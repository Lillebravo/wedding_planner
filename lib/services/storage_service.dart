import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wedding_model.dart';
import '../models/guest_model.dart';

// Global referens till Supabase-klienten
final supabase = Supabase.instance.client;

class StorageService {
  static const String _activeWeddingCodeKey = 'active_wedding_code';

  // --- AUTO-INLOGGNING (LOKAL HÄMTNING AV ENBART KOD) ---
  static Future<void> saveActiveWedding(Wedding wedding) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeWeddingCodeKey, wedding.code);
  }

  static Future<Wedding?> getActiveWedding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? code = prefs.getString(_activeWeddingCodeKey);
      if (code == null) return null;
      
      // Hämta bröllopet live från molnet via koden
      return await getWeddingFromCloud(code);
    } catch (e) {
      // Om databasen svajar eller kastar PGRST125 vid uppstart, 
      // fångar vi felet här så att appen inte kraschar.
      debugPrint('Auto-inloggning misslyckades på grund av nätverks/databasfel: $e');
      return null; 
    }
  }

  static Future<void> clearActiveWedding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeWeddingCodeKey);
  }

  // --- SUPABASE LIVE-ANROP: BRÖLLOP (WEDDINGS) ---
  static Future<Wedding?> getWeddingFromCloud(String code) async {
    try {
      final response = await supabase
          .from('weddings')
          .select()
          .eq('wedding_code', code)
          .maybeSingle();
      
      if (response == null) return null;
      
      return Wedding(
        id: response['id'],
        partner1: response['bride_name'], // Mappat mot SQL-schemat
        partner2: response['groom_name'],
        dateStr: response['wedding_date'] ?? 'Ej satt',
        timeStr: response['wedding_time'] ?? 'Ej satt',
        code: response['wedding_code'],
        estimatedGuests: response['max_guests']?.toString(),
        churchAddress: response['church_address'],
        venueAddress: response['party_address'],
      );
    } catch (e) {
      debugPrint('Fel vid hämtning av bröllop: $e'); // FIX: Använder debugPrint istället för print
      return null;
    }
  }

  static Future<Wedding> saveNewWeddingToList(Wedding newWedding) async {
    final Map<String, dynamic> weddingData = {
      'wedding_code': newWedding.code,
      'bride_name': newWedding.partner1,
      'groom_name': newWedding.partner2,
      'wedding_date': newWedding.dateStr == 'Ej satt' ? null : newWedding.dateStr,
      'wedding_time': newWedding.timeStr == 'Ej satt' ? null : newWedding.timeStr,
      'max_guests': int.tryParse(newWedding.estimatedGuests ?? ''),
      'church_address': newWedding.churchAddress,
      'party_address': newWedding.venueAddress,
    };

    if (newWedding.id.contains('-')) {
      weddingData['id'] = newWedding.id;
    }

    // Kör upsert och kräv att få tillbaka den sparade raden direkt från databasen
    final response = await supabase
        .from('weddings')
        .upsert(weddingData)
        .select()
        .single();
    
    // Returnera ett nytt Wedding-objekt som har databasens RIKTIGA UUID som id!
    return Wedding(
      id: response['id'], 
      partner1: response['bride_name'],
      partner2: response['groom_name'],
      dateStr: response['wedding_date'] ?? 'Ej satt',
      timeStr: response['wedding_time'] ?? 'Ej satt',
      code: response['wedding_code'],
      estimatedGuests: response['max_guests']?.toString(),
      churchAddress: response['church_address'],
      venueAddress: response['party_address'],
    );
  }

  static Future<List<Wedding>> getAllLocalWeddings() async {
    // Används för dubblettkontroll vid skapande av nya koder
    final response = await supabase.from('weddings').select('wedding_code');
    return response.map((w) => Wedding(
      id: '', 
      partner1: '', 
      partner2: '', 
      code: w['wedding_code'],
      dateStr: 'Ej satt', // FIX: Skickar med de saknade krävda parametrarna
      timeStr: 'Ej satt', // FIX: Skickar med de saknade krävda parametrarna
    )).toList();
  }

  // --- SUPABASE LIVE-ANROP: GÄSTER & RELATIONER ---
  static Future<List<Guest>> getGuests(String weddingId) async {
    // 1. Hämta alla gäster tillhörande bröllopet
    final guestsResponse = await supabase
        .from('guests')
        .select()
        .eq('wedding_id', weddingId);

    if (guestsResponse.isEmpty) return [];

    // 2. Hämta alla relationer för detta bröllops gäster
    final relationsResponse = await supabase
        .from('guest_relations')
        .select('*, guest_id_1!inner(wedding_id)')
        .eq('guest_id_1.wedding_id', weddingId);

    // 3. Bygg gästlistan från databasrader
    List<Guest> guestsList = guestsResponse.map((item) {
      return Guest(
        id: item['id'],
        firstName: item['first_name'],
        lastName: item['last_name'],
        email: item['email'],
        phoneNumber: item['phone'],
        dietaryRestrictions: item['dietary_restrictions'],
        title: GuestTitle.values.firstWhere((e) => e.name == item['title'], orElse: () => GuestTitle.none),
        isLocked: item['is_locked'] ?? false,
        tableId: item['table_id'],
        seatNumber: item['seat_number'],
      );
    }).toList();

    // 4. Mappa in sparade relationer i objekten
    for (var rel in relationsResponse) {
      final g1Id = rel['guest_id_1'];
      final g2Id = rel['guest_id_2'];
      final typeStr = rel['relation_type'];
      
      final type = RelationType.values.firstWhere((e) => e.name == typeStr, orElse: () => RelationType.friend);
      
      final guest = guestsList.firstWhere((g) => g.id == g1Id, orElse: () => guestsList.first);
      guest.relations[g2Id] = type;
    }

    return guestsList;
  }

  static Future<void> saveGuests(String weddingId, List<Guest> guests) async {
    // Vi bygger en karta (Map) för att hålla reda på kopplingen mellan
    // gamla minnes-ID:n (t.ex. 'bride-XXX') och nya äkta UUID:n från databasen.
    final Map<String, String> idMapping = {};
    final List<Map<String, dynamic>> savedGuestsRows = [];

    // --- STEG 1: Spara alla gäster först för att få deras äkta UUID ---
    for (var g in guests) {
      final Map<String, dynamic> guestData = {
        'wedding_id': weddingId,
        'first_name': g.firstName,
        'last_name': g.lastName,
        'email': g.email,
        'phone': g.phoneNumber,
        'dietary_restrictions': g.dietaryRestrictions,
        'title': g.title.name,
        'is_locked': g.isLocked,
        'seat_number': g.seatNumber,
      };

      // Om gästens bord inte är ett giltigt UUID, skicka null
      if (g.tableId != null && g.tableId!.contains('-')) {
        guestData['table_id'] = g.tableId;
      }

      // Om gästens ID redan är ett äkta UUID, behåll det
      if (g.id.contains('-') && !g.id.startsWith('bride-') && !g.id.startsWith('groom-')) {
        guestData['id'] = g.id;
      }

      // Skicka till databasen och hämta tillbaka raden
      final response = await supabase
          .from('guests')
          .upsert(guestData)
          .select()
          .single();

      final String realUuid = response['id'];
      
      // Spara mappningen! (T.ex. 'bride-123' -> 'd3b07384d-...')
      idMapping[g.id] = realUuid;
      savedGuestsRows.add(response);
    }

    // --- STEG 2: Spara alla relationer med de nya äkta UUID-strängarna ---
    for (var g in guests) {
      final String realGuestId1 = idMapping[g.id] ?? g.id;

      // Rensa gamla relationer i DB för denna gäst innan vi skriver nya
      if (realGuestId1.contains('-')) {
        await supabase.from('guest_relations').delete().eq('guest_id_1', realGuestId1);
      }

      if (g.relations.isNotEmpty) {
        for (var entry in g.relations.entries) {
          // Översätt det gamla ID:t till det nya äkta UUID:t via vår karta
          final String realGuestId2 = idMapping[entry.key] ?? entry.key;

          // Om något ID fortfarande inte är ett giltigt UUID, hoppa över (förhindrar 22P02 krasch)
          if (!realGuestId1.contains('-') || !realGuestId2.contains('-')) {
            continue;
          }

          await supabase.from('guest_relations').upsert({
            'guest_id_1': realGuestId1,
            'guest_id_2': realGuestId2,
            'relation_type': entry.value.name,
          });
        }
      }
    }
  }

  // --- IMPORT / EXPORT VIA MOLNET ---
  static Future<String> exportWeddingToClipboard(String weddingId) async {
    final activeWedding = await getActiveWedding();
    if (activeWedding == null) return '';

    final guestsList = await getGuests(weddingId);
    
    final guestsEncoded = guestsList.map((g) => {
      'id': g.id,
      'firstName': g.firstName,
      'lastName': g.lastName,
      'email': g.email,
      'phoneNumber': g.phoneNumber,
      'dietaryRestrictions': g.dietaryRestrictions,
      'title': g.title.name,
      'isLocked': g.isLocked,
      'tableId': g.tableId,
      'seatNumber': g.seatNumber,
      'relations': g.relations.map((key, value) => MapEntry(key, value.name)),
    }).toList();

    final Map<String, dynamic> fullPackage = {
      'version': '1.0',
      'wedding': activeWedding.toJson(),
      'guests': guestsEncoded,
    };

    return jsonEncode(fullPackage);
  }

  static Future<void> importWeddingFromJson(String jsonString) async {
    final Map<String, dynamic> package = jsonDecode(jsonString);
    final wedding = Wedding.fromJson(package['wedding']);
    
    // Spara i databasen
    await saveNewWeddingToList(wedding);
    await saveActiveWedding(wedding);

    final List<dynamic> guestsRaw = package['guests'];
    List<Guest> importedGuests = guestsRaw.map((item) {
      final guest = Guest(
        id: item['id'],
        firstName: item['firstName'],
        lastName: item['lastName'],
        email: item['email'],
        phoneNumber: item['phoneNumber'],
        dietaryRestrictions: item['dietaryRestrictions'],
        title: GuestTitle.values.firstWhere((e) => e.name == item['title'], orElse: () => GuestTitle.none),
        isLocked: item['isLocked'] ?? false,
        tableId: item['tableId'],
        seatNumber: item['seat_number'],
      );
      
      if (item['relations'] != null) {
        final Map<String, dynamic> relsRaw = item['relations'];
        guest.relations = relsRaw.map((key, value) => MapEntry(
          key, 
          RelationType.values.firstWhere((e) => e.name == value, orElse: () => RelationType.friend)
        ));
      }
      return guest;
    }).toList();

    await saveGuests(wedding.id, importedGuests);
  }
}