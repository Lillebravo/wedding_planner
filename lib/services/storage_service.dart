import 'dart:convert';
import 'package:flutter/foundation.dart';
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
    final response = await supabase
        .from('weddings')
        .insert({
          'partner1_name': wedding.partner1,
          'partner2_name': wedding.partner2,
          'date': wedding.dateStr == 'Ej satt' ? null : wedding.dateStr,
          'time': wedding.timeStr,
          'wedding_code': wedding.code,
          'ceremony_address': wedding.churchAddress,
          'party_address': wedding.venueAddress,
          'cover_image_url': wedding.coverImageUrl,
          'itinerary': wedding.itinerary,
        })
        .select()
        .single();

    return Wedding.fromJson(response);
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
          dietaryRestrictions: item['dietary_restrictions'],
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

  static String? _normalizeUuidOrNull(String? value) {
    if (value == null) return null;

    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) return null;
    if (_uuidPattern.hasMatch(trimmedValue)) return trimmedValue;

    debugPrint('Ignoring non-UUID table_id while saving guest: $trimmedValue');
    return null;
  }
}
