import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wedding_model.dart';
import '../models/guest_model.dart';

final supabase = Supabase.instance.client;

class StorageService {
  static const String _weddingKey = 'active_wedding_code';

  static Future<void> saveActiveWedding(Wedding wedding) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_weddingKey, wedding.code);
  }

  static Future<Wedding?> getActiveWedding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_weddingKey);
      if (code == null) return null;
      return await getWeddingFromCloud(code);
    } catch (e) {
      return null;
    }
  }

  static Future<void> clearActiveWedding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_weddingKey);
  }

  static Future<Wedding?> getWeddingFromCloud(String code) async {
    try {
      final response = await supabase
          .from('weddings')
          .select()
          .eq('wedding_code', code)
          .maybeSingle();

      if (response == null) return null;
      return Wedding.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  static Future<void> updateWedding(Wedding wedding) async {
    await supabase.from('weddings').update({
      'partner1_name': wedding.partner1,
      'partner2_name': wedding.partner2,
      'date': wedding.dateStr == 'Ej satt' ? null : wedding.dateStr,
      'time': wedding.timeStr,
      'ceremony_address': wedding.churchAddress,
      'party_address': wedding.venueAddress, // Korrigerat från trendAddress
      'cover_image_url': wedding.coverImageUrl,
      'itinerary': wedding.itinerary,
    }).eq('id', wedding.id);
  }

  static Future<Wedding> saveNewWeddingToList(Wedding wedding) async {
    final response = await supabase.from('weddings').insert({
      'partner1_name': wedding.partner1,
      'partner2_name': wedding.partner2,
      'date': wedding.dateStr == 'Ej satt' ? null : wedding.dateStr,
      'time': wedding.timeStr,
      'wedding_code': wedding.code,
      'ceremony_address': wedding.churchAddress,
      'party_address': wedding.venueAddress, // Korrigerat från trendAddress
      'cover_image_url': wedding.coverImageUrl,
      'itinerary': wedding.itinerary,
    }).select().single();

    return Wedding.fromJson(response);
  }

  static Future<String?> uploadCoverImage(String weddingId, String fileName, Uint8List fileBytes) async {
    try {
      final path = '$weddingId/$fileName';
      
      await supabase.storage.from('wedding-covers').uploadBinary(
            path,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final String publicUrl = supabase.storage.from('wedding-covers').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  static Future<String> createOnboardingTable(String weddingId, String name, int seats) async {
    final response = await supabase.from('tables').insert({
      'wedding_id': weddingId,
      'name': name,
      'seats': seats,
      'shape': 'Rektangel',
    }).select().single();
    return response['id'] ?? '';
  }

  static Future<void> saveGuests(String weddingId, List<Guest> guests) async {
    Map<String, String> idMapping = {};

    for (var g in guests) {
      final isTempId = g.id.startsWith('bride-') || g.id.startsWith('groom-') || !g.id.contains('-');
      
      final data = {
        'wedding_id': weddingId,
        'first_name': g.firstName,
        'last_name': g.lastName,
        'title': g.title.name,
        'is_locked': g.isLocked,
        'table_id': g.tableId,
        'seat_number': g.seatNumber,
        'phone': g.phoneNumber,
        'email': g.email,
        'dietary_restrictions': g.dietaryRestrictions,
      };

      if (!isTempId) {
        data['id'] = g.id;
      }

      final response = await supabase.from('guests').upsert(data).select().single();
      final String realUuid = response['id'] ?? '';
      idMapping[g.id] = realUuid;
      g.id = realUuid; 
    }

    for (var g in guests) {
      final realGuestId1 = idMapping[g.id] ?? g.id;
      await supabase.from('guest_relations').delete().eq('guest_id_1', realGuestId1);

      final targetIds = g.relations.keys.toList(); 
      for (var tempTargetId in targetIds) {
        final type = g.relations[tempTargetId];
        if (type == RelationType.none) continue;

        final realGuestId2 = idMapping[tempTargetId] ?? tempTargetId;

        await supabase.from('guest_relations').upsert({
          'guest_id_1': realGuestId1,
          'guest_id_2': realGuestId2,
          'type': type!.name,
        });
      }
    }
  }

  static Future<List<Guest>> getGuests(String weddingId) async {
    final response = await supabase.from('guests').select().eq('wedding_id', weddingId);
    List<Guest> guestsList = [];

    for (var item in response) {
      guestsList.add(Guest(
        id: item['id'] ?? '',
        firstName: item['first_name'] ?? '',
        lastName: item['last_name'] ?? '',
        title: GuestTitle.values.firstWhere((e) => e.name == item['title'], orElse: () => GuestTitle.none),
        isLocked: item['is_locked'] ?? false,
        tableId: item['table_id'],
        seatNumber: item['seat_number'],
        phoneNumber: item['phone'],
        email: item['email'],
        dietaryRestrictions: item['dietary_restrictions'],
      ));
    }

    for (var g in guestsList) {
      final rels = await supabase.from('guest_relations').select().eq('guest_id_1', g.id);
      for (var r in rels) {
        final targetId = r['guest_id_2'];
        final typeStr = r['type'];
        final type = RelationType.values.firstWhere((e) => e.name == typeStr, orElse: () => RelationType.friend);
        g.relations[targetId] = type;
      }
    }
    return guestsList;
  }

  static Future<String> exportWeddingToClipboard(String weddingId) async {
    final weddingResponse = await supabase.from('weddings').select().eq('id', weddingId).single();
    final guestsList = await getGuests(weddingId);
    final tablesResponse = await supabase.from('tables').select().eq('wedding_id', weddingId);

    final Map<String, dynamic> fullPackage = {
      'wedding': weddingResponse,
      'tables': tablesResponse,
      'guests': guestsList.map((g) => {
        'id': g.id,
        'first_name': g.firstName,
        'last_name': g.lastName,
        'title': g.title.name,
        'is_locked': g.isLocked,
        'table_id': g.tableId,
        'seat_number': g.seatNumber,
        'phone': g.phoneNumber,
        'email': g.email,
        'dietary_restrictions': g.dietaryRestrictions,
        'relations': g.relations.map((key, value) => MapEntry(key, value.name)),
      }).toList(),
    };

    return jsonEncode(fullPackage);
  }

  static Future<void> importWeddingFromJson(String jsonStr) async {
    final data = jsonDecode(jsonStr);
    final weddingData = data['wedding'];
    
    await supabase.from('weddings').upsert(weddingData);
    final String weddingId = weddingData['id'];

    if (data['tables'] != null) {
      for (var t in data['tables']) {
        await supabase.from('tables').upsert(t);
      }
    }

    if (data['guests'] != null) {
      List<Guest> importedGuests = [];
      for (var g in data['guests']) {
        final guest = Guest(
          id: g['id'],
          firstName: g['first_name'] ?? '',
          lastName: g['last_name'] ?? '',
          title: GuestTitle.values.firstWhere((e) => e.name == g['title'], orElse: () => GuestTitle.none),
          isLocked: g['is_locked'] ?? false,
          tableId: g['table_id'],
          seatNumber: g['seat_number'],
          phoneNumber: g['phone'],
          email: g['email'],
          dietaryRestrictions: g['dietary_restrictions'],
        );
        
        if (g['relations'] != null) {
          final relMap = g['relations'] as Map<String, dynamic>;
          relMap.forEach((targetId, typeStr) {
            guest.relations[targetId] = RelationType.values.firstWhere((e) => e.name == typeStr, orElse: () => RelationType.friend);
          });
        }
        importedGuests.add(guest);
      }
      await saveGuests(weddingId, importedGuests);
    }
  }
}