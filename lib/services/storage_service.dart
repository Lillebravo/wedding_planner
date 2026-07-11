import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wedding_model.dart';
import '../models/guest_model.dart';

class StorageService {
  static const String _activeWeddingKey = 'active_wedding_data';
  static const String _allWeddingsKey = 'all_local_weddings';
  static const String _guestsKeyPrefix = 'wedding_guests_';

  static Future<void> saveActiveWedding(Wedding wedding) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeWeddingKey, jsonEncode(wedding.toJson()));
  }

  static Future<Wedding?> getActiveWedding() async {
    final prefs = await SharedPreferences.getInstance();
    final String? weddingJson = prefs.getString(_activeWeddingKey);
    if (weddingJson == null) return null;
    return Wedding.fromJson(jsonDecode(weddingJson));
  }

  static Future<void> clearActiveWedding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeWeddingKey);
  }

  static Future<List<Wedding>> getAllLocalWeddings() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? storedList = prefs.getStringList(_allWeddingsKey);
    if (storedList == null) return [];
    return storedList.map((item) => Wedding.fromJson(jsonDecode(item))).toList();
  }

  static Future<void> saveNewWeddingToList(Wedding newWedding) async {
    final prefs = await SharedPreferences.getInstance();
    final weddings = await getAllLocalWeddings();
    weddings.removeWhere((w) => w.code == newWedding.code);
    weddings.add(newWedding);
    final List<String> stringList = weddings.map((w) => jsonEncode(w.toJson())).toList();
    await prefs.setStringList(_allWeddingsKey, stringList);
  }

  // Hämta gäster för ett specifikt bröllop
  static Future<List<Guest>> getGuests(String weddingId) async {
    final prefs = await SharedPreferences.getInstance();
    // FIX: Ändrat från '${_guestsKeyPrefix}$weddingId' till '$_guestsKeyPrefix$weddingId'
    final String? guestsJson = prefs.getString('$_guestsKeyPrefix$weddingId');
    if (guestsJson == null) return [];
    
    final List<dynamic> decoded = jsonDecode(guestsJson);
    return decoded.map((item) => Guest(
      id: item['id'],
      firstName: item['firstName'],
      lastName: item['lastName'],
      email: item['email'],
      phoneNumber: item['phoneNumber'],
      dietaryRestrictions: item['dietaryRestrictions'],
      title: GuestTitle.values.firstWhere((e) => e.name == item['title'], orElse: () => GuestTitle.none),
      isLocked: item['isLocked'] ?? false,
      tableId: item['tableId'],
      seatNumber: item['seatNumber'],
    )).toList();
  }

  // Spara gäster för ett specifikt bröllop
  static Future<void> saveGuests(String weddingId, List<Guest> guests) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> encoded = guests.map((g) => {
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
    }).toList();
    // FIX: Ändrat från '${_guestsKeyPrefix}$weddingId' till '$_guestsKeyPrefix$weddingId'
    await prefs.setString('$_guestsKeyPrefix$weddingId', jsonEncode(encoded));
  }

  // NYTT: Exportera hela bröllopet till ett komplett JSON-objekt
  static Future<String> exportWeddingToClipboard(String weddingId) async {
    final activeWedding = await getActiveWedding();
    if (activeWedding == null) return '';

    final guestsList = await getGuests(weddingId);
    
    // Mappa gästerna inklusive deras relations-map
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
      'relations': g.relations.map((key, value) => MapEntry(key, value.name)), // Sparar relationer!
    }).toList();

    final Map<String, dynamic> fullPackage = {
      'version': '1.0',
      'wedding': activeWedding.toJson(),
      'guests': guestsEncoded,
    };

    return jsonEncode(fullPackage);
  }

  // NYTT: Importera ett komplett bröllop från en JSON-sträng
  static Future<void> importWeddingFromJson(String jsonString) async {
    final Map<String, dynamic> package = jsonDecode(jsonString);
    
    // 1. Återställ bröllopsdatan
    final wedding = Wedding.fromJson(package['wedding']);
    await saveActiveWedding(wedding);
    await saveNewWeddingToList(wedding);

    // 2. Återställ gästerna och deras relationer
    final List<dynamic> guestsRaw = package['guests'];
    final List<Guest> importedGuests = guestsRaw.map((item) {
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
        seatNumber: item['seatNumber'],
      );
      
      // Läs in relationerna om de finns med i JSON-paketet
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