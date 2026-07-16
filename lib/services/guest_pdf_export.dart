import '../l10n/app_localizations.dart';
import '../models/guest_model.dart';

String guestPdfLine(
  Guest guest,
  AppLocalizationsController localizations, {
  bool includeRole = false,
  bool includeDietary = false,
}) {
  final details = guestPdfDetails(
    guest,
    localizations,
    includeRole: includeRole,
    includeDietary: includeDietary,
  );

  if (details.isEmpty) {
    return guest.fullName;
  }

  return '${guest.fullName} | $details';
}

String guestPdfDetails(
  Guest guest,
  AppLocalizationsController localizations, {
  bool includeRole = false,
  bool includeDietary = false,
}) {
  final parts = <String>[];

  if (includeRole && guest.title != GuestTitle.none) {
    parts.add(localizations.guestTitle(guest.title));
  }

  if (includeDietary && guest.dietaryRestrictions.isNotEmpty) {
    parts.add(guest.dietaryRestrictions.join(', '));
  }

  return parts.join(' | ');
}