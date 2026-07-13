import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class LanguageToggleButton extends StatelessWidget {
  const LanguageToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizationsScope.of(context);
    final label = localizations.language == AppLanguage.swedish ? 'SV' : 'EN';

    return PopupMenuButton<AppLanguage>(
      tooltip: localizations.text('switch_language'),
      onSelected: localizations.setLanguage,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: AppLanguage.swedish,
          child: Text(localizations.languageLabel(AppLanguage.swedish)),
        ),
        PopupMenuItem(
          value: AppLanguage.english,
          child: Text(localizations.languageLabel(AppLanguage.english)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}