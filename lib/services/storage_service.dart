import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wedding_model.dart';
import '../models/guest_model.dart';

final supabase = Supabase.instance.client;

class CoverUploadResult {
  final String? publicUrl;
  final String? errorMessage;

  const CoverUploadResult({this.publicUrl, this.errorMessage});

  bool get isSuccess => publicUrl != null && publicUrl!.isNotEmpty;
}

class StorageService {
  static const String _weddingKey = 'active_wedding_code';
  static const String _coverBucket = 'wedding-covers';
  static const String _coverBgPrefix = 'cover_bg_';
  static const String _placementRulesPrefix = 'placement_rules_';
  static const String _floorPlanShowGuestsPrefix = 'floor_plan_show_guests_';
  static const String _adminCodeCachePrefix = 'admin_code_cache_';
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

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

  static Future<void> bootstrapAdminForLogin(
    Wedding wedding, {
    required bool joinedExistingWedding,
  }) async {
    // Creator device cache is set during wedding creation in saveNewWeddingToList.
    // Existing wedding joins should default to guest until admin code is entered.
  }

  static Future<bool> isAdminForWedding(Wedding wedding) async {
    final adminCodeHash = wedding.adminCode.trim();
    if (adminCodeHash.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('$_adminCodeCachePrefix${wedding.id}') ?? '';
    if (cached.trim().isEmpty) return false;

    return _hashAdminCode(cached.trim()) == adminCodeHash;
  }

  static Future<void> _cacheAdminCodeForWedding(
    String weddingId,
    String adminCode,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_adminCodeCachePrefix$weddingId', adminCode.trim());
  }

  static Future<void> clearAdminForWedding(String weddingId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_adminCodeCachePrefix$weddingId');
  }

  static String getAdminCode(Wedding wedding) {
    return wedding.adminCode.trim();
  }

  static Future<String?> getCachedAdminCode(String weddingId) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('$_adminCodeCachePrefix$weddingId') ?? '';
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String generateAdminCode() {
    final random = Random.secure();
    final codeNumber = random.nextInt(900000) + 100000;
    return codeNumber.toString();
  }

  static bool validateAdminCode(Wedding wedding, String input) {
    final cleaned = input.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(cleaned)) {
      return false;
    }
    final adminCodeHash = wedding.adminCode.trim();
    if (adminCodeHash.isEmpty) return false;
    return _hashAdminCode(cleaned) == adminCodeHash;
  }

  static Future<bool> unlockAdminForWedding(
    Wedding wedding,
    String input,
  ) async {
    final isValid = validateAdminCode(wedding, input);
    if (!isValid) {
      return false;
    }

    await _cacheAdminCodeForWedding(wedding.id, input);
    return true;
  }

  static String _hashAdminCode(String adminCode) {
    final bytes = utf8.encode(adminCode.trim());
    return crypto.sha256.convert(bytes).toString();
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
      debugPrint('Fel vid hämtning av bröllop: $e');
      return null;
    }
  }

  static Future<Wedding> updateWedding(Wedding wedding) async {
    final response = await supabase
        .from('weddings')
        .update({
          'partner1_name': wedding.partner1,
          'partner2_name': wedding.partner2,
          'date': wedding.dateStr == 'Ej satt' ? null : wedding.dateStr,
          'time': wedding.timeStr,
          'admin_code': wedding.adminCode,
          'ceremony_address': wedding.churchAddress,
          'party_address': wedding.venueAddress,
          'cover_image_url': wedding.coverImageUrl,
          'itinerary': wedding.itinerary,
        })
        .eq('id', wedding.id)
        .select()
        .single();

    return Wedding.fromJson(response);
  }

  static Future<Wedding> saveNewWeddingToList(Wedding wedding) async {
    final adminCode = wedding.adminCode.trim().isEmpty
        ? generateAdminCode()
        : wedding.adminCode.trim();
    final adminCodeHash = _hashAdminCode(adminCode);

    final response = await supabase
        .from('weddings')
        .insert({
          'partner1_name': wedding.partner1,
          'partner2_name': wedding.partner2,
          'date': wedding.dateStr == 'Ej satt' ? null : wedding.dateStr,
          'time': wedding.timeStr,
          'wedding_code': wedding.code,
          'admin_code': adminCodeHash,
          'ceremony_address': wedding.churchAddress,
          'party_address': wedding.venueAddress,
          'cover_image_url': wedding.coverImageUrl,
          'itinerary': wedding.itinerary,
        })
        .select()
        .single();
    final createdWedding = Wedding.fromJson(response);
    await _cacheAdminCodeForWedding(createdWedding.id, adminCode);
    return createdWedding;
  }

  static Future<CoverUploadResult> uploadCoverImage(
    String weddingId,
    String fileName,
    Uint8List fileBytes,
  ) async {
    try {
      final safeFileName = _sanitizeStorageFileName(fileName);
      final path = '$weddingId/$safeFileName';

      await supabase.storage
          .from(_coverBucket)
          .uploadBinary(
            path,
            fileBytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _getContentType(safeFileName),
            ),
          );

      final publicUrl = supabase.storage.from(_coverBucket).getPublicUrl(path);
      if (publicUrl.isEmpty) {
        return const CoverUploadResult(
          errorMessage: 'Supabase returnerade ingen publik URL för bilden.',
        );
      }

      return CoverUploadResult(publicUrl: publicUrl);
    } on StorageException catch (e) {
      debugPrint('Storage error while uploading image: ${e.message}');
      return CoverUploadResult(
        errorMessage:
            'Kunde inte ladda upp bilden till bucketen $_coverBucket: ${e.message}',
      );
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return CoverUploadResult(
        errorMessage: 'Ett oväntat fel uppstod vid bilduppladdning: $e',
      );
    }
  }

  static Future<List<String>> listCoverImageUrls(String weddingId) async {
    try {
      final files = await supabase.storage
          .from(_coverBucket)
          .list(path: weddingId);

      final filtered = files
          .where((item) {
            final name = item.name.toLowerCase();
            return name.endsWith('.jpg') ||
                name.endsWith('.jpeg') ||
                name.endsWith('.png') ||
                name.endsWith('.webp') ||
                name.endsWith('.gif');
          })
          .toList()
        ..sort((a, b) => b.name.compareTo(a.name));

      return filtered
          .map(
            (item) => supabase.storage
                .from(_coverBucket)
                .getPublicUrl('$weddingId/${item.name}'),
          )
          .where((url) => url.isNotEmpty)
          .toList();
    } on StorageException catch (e) {
      debugPrint('Storage error while listing cover images: ${e.message}');
      return <String>[];
    } catch (e) {
      debugPrint('Error listing cover images: $e');
      return <String>[];
    }
  }

  static Future<void> deleteCoverImageByUrl(String imageUrl) async {
    final path = _extractCoverPathFromPublicUrl(imageUrl);
    if (path == null || path.isEmpty) {
      throw Exception('Kunde inte tolka filens sökväg från bildens URL.');
    }

    try {
      await supabase.storage.from(_coverBucket).remove([path]);
    } on StorageException catch (e) {
      debugPrint('Storage error while deleting cover image: ${e.message}');
      throw Exception('Kunde inte radera bilden: ${e.message}');
    } catch (e) {
      debugPrint('Error deleting cover image: $e');
      throw Exception('Ett oväntat fel uppstod vid radering av bilden.');
    }
  }

  static String? _extractCoverPathFromPublicUrl(String imageUrl) {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) return null;

    const marker = '/object/public/$_coverBucket/';
    final markerIndex = uri.path.indexOf(marker);
    if (markerIndex == -1) return null;

    final encodedPath = uri.path.substring(markerIndex + marker.length);
    if (encodedPath.isEmpty) return null;

    return Uri.decodeComponent(encodedPath);
  }

  static Future<void> saveCoverBackgroundColorValue(
    String weddingId,
    int colorValue,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_coverBgPrefix$weddingId', colorValue);
  }

  static Future<int?> getCoverBackgroundColorValue(String weddingId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_coverBgPrefix$weddingId');
  }

  static String _sanitizeStorageFileName(String fileName) {
    final sanitized = fileName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    return sanitized.isEmpty ? 'cover_image' : sanitized;
  }

  static String _getContentType(String fileName) {
    final lowerCaseFileName = fileName.toLowerCase();

    if (lowerCaseFileName.endsWith('.png')) return 'image/png';
    if (lowerCaseFileName.endsWith('.gif')) return 'image/gif';
    if (lowerCaseFileName.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  static Future<String> createOnboardingTable(
    String weddingId,
    String name,
    int seats,
  ) async {
    final response = await supabase
        .from('tables')
        .insert({
          'wedding_id': weddingId,
          'name': name,
          'seats': seats,
          'shape': 'Rektangel',
          'position_x': null,
          'position_y': null,
        })
        .select()
        .single();
    return response['id'] ?? '';
  }

  static Future<String> addTable(
    String weddingId,
    String name,
    int seats,
    String shape,
  ) async {
    final response = await supabase
        .from('tables')
        .insert({
          'wedding_id': weddingId,
          'name': name,
          'seats': seats,
          'shape': shape,
          'position_x': null,
          'position_y': null,
        })
        .select('id')
        .single();

    return (response['id'] ?? '').toString();
  }

  static Future<void> updateTable(
    String tableId,
    String name,
    int seats,
    String shape,
  ) async {
    final normalizedTableId = _normalizeUuidOrNull(tableId);
    if (normalizedTableId == null) {
      debugPrint('Skipping updateTable for non-UUID id: $tableId');
      return;
    }

    await supabase
      .from('tables')
      .update({'name': name, 'seats': seats, 'shape': shape})
        .eq('id', normalizedTableId);
  }

  static Future<void> deleteTable(String tableId) async {
    final normalizedTableId = _normalizeUuidOrNull(tableId);
    if (normalizedTableId == null) {
      debugPrint('Skipping deleteTable for non-UUID id: $tableId');
      return;
    }

    await supabase
        .from('guests')
        .update({'table_id': null, 'seat_number': null})
        .eq('table_id', normalizedTableId);

    await supabase.from('tables').delete().eq('id', normalizedTableId);
  }

  static Future<List<Map<String, dynamic>>> getTables(String weddingId) async {
    final response = await supabase
        .from('tables')
      .select('id, name, seats, shape, position_x, position_y')
        .eq('wedding_id', weddingId)
        .order('created_at', ascending: true);

    return response
        .map<Map<String, dynamic>>(
          (item) => {
            'id': (item['id'] ?? '').toString(),
            'name': (item['name'] ?? '').toString(),
            'seats': item['seats'] ?? 0,
            'shape': (item['shape'] ?? 'Rektangel').toString(),
            'position_x': item['position_x'],
            'position_y': item['position_y'],
          },
        )
        .toList();
  }

  static Future<void> saveGuests(String weddingId, List<Guest> guests) async {
    Map<String, String> idMapping = {};

    // 1. Spara gästerna och få tillbaka riktiga UUIDs
    for (var g in guests) {
      final isTempId =
          g.id.startsWith('bride-') ||
          g.id.startsWith('groom-') ||
          !g.id.contains('-');
      final normalizedTableId = _normalizeUuidOrNull(g.tableId);

      final data = {
        'wedding_id': weddingId,
        'first_name': g.firstName,
        'last_name': g.lastName,
        'title': g.title.name,
        'is_locked': g.isLocked,
        'table_id': normalizedTableId,
        'seat_number': g.seatNumber,
        'phone': g.phoneNumber,
        'email': g.email,
        'dietary_restrictions': g.dietaryRestrictions,
      };

      g.tableId = normalizedTableId;

      if (!isTempId) {
        data['id'] = g.id;
      }

      final response = await supabase
          .from('guests')
          .upsert(data)
          .select()
          .single();
      final String realUuid = response['id'] ?? '';

      if (g.id != realUuid) {
        idMapping[g.id] = realUuid;
        g.id = realUuid;
      }
    }

    // 2. Mappa om alla relationer i minnet så att inga temporära strängar spökar
    if (idMapping.isNotEmpty) {
      for (var g in guests) {
        final oldRelations = Map<String, RelationType>.from(g.relations);
        g.relations.clear();
        oldRelations.forEach((targetId, type) {
          final realTargetId = idMapping[targetId] ?? targetId;
          g.relations[realTargetId] = type;
        });
      }
    }

    // 3. Nu när minnet är 100% rensat från temp-ID:n, skjut upp relationerna
    for (var g in guests) {
      await supabase.from('guest_relations').delete().eq('guest_id_1', g.id);

      for (var entry in g.relations.entries) {
        if (entry.value == RelationType.none) continue;

        await supabase.from('guest_relations').upsert({
          'guest_id_1': g.id,
          'guest_id_2': entry.key,
          'type': entry.value.name,
        });
      }
    }
  }

  static Future<List<Guest>> getGuests(String weddingId) async {
    final response = await supabase
        .from('guests')
        .select()
        .eq('wedding_id', weddingId);
    List<Guest> guestsList = [];

    for (var item in response) {
      guestsList.add(
        Guest(
          id: item['id'] ?? '',
          firstName: item['first_name'] ?? '',
          lastName: item['last_name'] ?? '',
          title: GuestTitle.values.firstWhere(
            (e) => e.name == item['title'],
            orElse: () => GuestTitle.none,
          ),
          isLocked: item['is_locked'] ?? false,
          tableId: item['table_id'],
          seatNumber: item['seat_number'],
          phoneNumber: item['phone'],
          email: item['email'],
          dietaryRestrictions: _parseDietaryRestrictions(item['dietary_restrictions']),
        ),
      );
    }

    for (var g in guestsList) {
      final rels = await supabase
          .from('guest_relations')
          .select()
          .eq('guest_id_1', g.id);
      for (var r in rels) {
        final targetId = r['guest_id_2'];
        final typeStr = r['type'];
        final type = RelationType.values.firstWhere(
          (e) => e.name == typeStr,
          orElse: () => RelationType.friend,
        );
        g.relations[targetId] = type;
      }
    }
    return guestsList;
  }

  static Future<String> exportWeddingToClipboard(String weddingId) async {
    final wedding = await getActiveWedding();
    final guests = await getGuests(weddingId);

    final data = {
      'wedding': wedding?.toJson(),
      'guests': guests
          .map(
            (g) => {
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
            },
          )
          .toList(),
    };
    return jsonEncode(data); // Nu används dart:convert!
  }

  static Future<void> importWeddingFromJson(String jsonStr) async {
    try {
      final data = jsonDecode(jsonStr);
      debugPrint('Importera data: $data');
      // TODO: Lägg till logik för att skriva JSON-datan till Supabase i framtiden
    } catch (e) {
      throw Exception('Ogiltig JSON-kod');
    }
  }

  static String? normalizeUuidOrNull(String? value) {
    return _normalizeUuidOrNull(value);
  }

  static Future<void> savePlacementRules(
    String weddingId,
    List<Map<String, dynamic>> rules,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_placementRulesPrefix$weddingId';
    final payload = jsonEncode(rules);
    await prefs.setString(key, payload);
  }

  static Future<List<Map<String, dynamic>>?> getPlacementRules(String weddingId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_placementRulesPrefix$weddingId';
    final payload = prefs.getString(key);
    if (payload == null || payload.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! List) return null;

      return decoded
          .whereType<Map>()
          .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      debugPrint('Could not decode placement rules: $e');
      return null;
    }
  }

  static Future<Map<String, ui.Offset>> getTableLayout(String weddingId) async {
    try {
      final result = <String, ui.Offset>{};
      final response = await supabase
          .from('tables')
          .select('id, position_x, position_y')
          .eq('wedding_id', weddingId);

      for (final item in response) {
        final tableId = (item['id'] ?? '').toString();
        final x = item['position_x'];
        final y = item['position_y'];

        if (tableId.isEmpty || x is! num || y is! num) {
          continue;
        }

        result[tableId] = ui.Offset(x.toDouble(), y.toDouble());
      }

      return result;
    } catch (e) {
      debugPrint('Could not decode table layout: $e');
      return <String, ui.Offset>{};
    }
  }

  static Future<void> saveTableLayout(
    String weddingId,
    Map<String, ui.Offset> layout,
  ) async {
    for (final entry in layout.entries) {
      final normalizedTableId = _normalizeUuidOrNull(entry.key);
      if (normalizedTableId == null) {
        continue;
      }

      await supabase.from('tables').update({
        'position_x': entry.value.dx,
        'position_y': entry.value.dy,
      }).eq('id', normalizedTableId);
    }
  }

  static Future<void> saveFloorPlanShowGuests(
    String weddingId,
    bool showGuests,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_floorPlanShowGuestsPrefix$weddingId', showGuests);
  }

  static Future<bool?> getFloorPlanShowGuests(String weddingId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_floorPlanShowGuestsPrefix$weddingId');
  }

  static String? _normalizeUuidOrNull(String? value) {
    if (value == null) return null;

    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) return null;
    if (_uuidPattern.hasMatch(trimmedValue)) return trimmedValue;

    debugPrint('Ignoring non-UUID table_id while saving guest: $trimmedValue');
    return null;
  }

  static List<String> _parseDietaryRestrictions(dynamic rawValue) {
    if (rawValue == null) return <String>[];

    if (rawValue is List) {
      return rawValue
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    final asString = rawValue.toString().trim();
    if (asString.isEmpty) return <String>[];

    // Backward compatibility for old text storage (single value or comma-separated).
    return asString
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
