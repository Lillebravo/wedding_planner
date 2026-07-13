import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/guest_model.dart';

enum AppLanguage { swedish, english }

extension AppLanguageCode on AppLanguage {
  String get code => switch (this) {
    AppLanguage.swedish => 'sv',
    AppLanguage.english => 'en',
  };

  static AppLanguage fromCode(String? code) {
    return switch (code?.toLowerCase()) {
      'en' => AppLanguage.english,
      _ => AppLanguage.swedish,
    };
  }
}

class AppLocalizationsController extends ChangeNotifier {
  static const String _prefsKey = 'app_language_code';

  AppLanguage _language = AppLanguage.swedish;
  final Map<String, Map<String, String>> _translations = {};

  AppLanguage get language => _language;
  Locale get locale => Locale(_language.code);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _language = AppLanguageCode.fromCode(prefs.getString(_prefsKey));

    _translations['sv'] = await _loadTranslationFile('assets/l10n/sv.json');
    _translations['en'] = await _loadTranslationFile('assets/l10n/en.json');
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;

    _language = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, language.code);
    notifyListeners();
  }

  Future<void> toggleLanguage() {
    return setLanguage(
      _language == AppLanguage.swedish ? AppLanguage.english : AppLanguage.swedish,
    );
  }

  String? keyForValue(String value, {Iterable<String>? candidateKeys}) {
    final normalizedValue = _normalizeLookup(value);
    if (normalizedValue.isEmpty) {
      return null;
    }

    final allowedKeys = candidateKeys == null ? null : Set<String>.from(candidateKeys);

    for (final translationSet in _translations.values) {
      for (final entry in translationSet.entries) {
        if (allowedKeys != null && !allowedKeys.contains(entry.key)) {
          continue;
        }

        if (_normalizeLookup(entry.value) == normalizedValue) {
          return entry.key;
        }
      }
    }

    return null;
  }

  String text(String key, {Map<String, String> values = const {}}) {
    final fallback = _translations['en'] ?? const <String, String>{};
    final current = _translations[_language.code] ?? fallback;
    final raw = current[key] ?? fallback[key] ?? key;

    var result = raw;
    values.forEach((placeholder, value) {
      result = result.replaceAll('{$placeholder}', value);
    });

    return result;
  }

  String guestTitle(GuestTitle title) {
    return switch (title) {
      GuestTitle.none => text('guest_title_none'),
      GuestTitle.bride => text('guest_title_bride'),
      GuestTitle.groom => text('guest_title_groom'),
      GuestTitle.maidOfHonor => text('guest_title_maid_of_honor'),
      GuestTitle.groomsman => text('guest_title_groomsman'),
      GuestTitle.bestMan => text('guest_title_best_man'),
      GuestTitle.parent => text('guest_title_parent'),
      GuestTitle.sibling => text('guest_title_sibling'),
      GuestTitle.child => text('guest_title_child'),
    };
  }

  String relationLabel(RelationType relationType) {
    return switch (relationType) {
      RelationType.none => text('relation_none'),
      RelationType.partner => text('relation_partner'),
      RelationType.friend => text('relation_friend'),
      RelationType.avoid => text('relation_avoid'),
    };
  }

  String languageLabel(AppLanguage language) {
    return switch (language) {
      AppLanguage.swedish => text('language_swedish'),
      AppLanguage.english => text('language_english'),
    };
  }

  Future<Map<String, String>> _loadTranslationFile(String assetPath) async {
    final jsonString = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(jsonString);
    return Map<String, String>.from(decoded as Map);
  }

  String _normalizeLookup(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class AppLocalizationsScope extends InheritedNotifier<AppLocalizationsController> {
  const AppLocalizationsScope({
    super.key,
    required AppLocalizationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLocalizationsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLocalizationsScope>();
    assert(scope != null, 'AppLocalizationsScope not found in widget tree.');
    return scope!.notifier!;
  }
}