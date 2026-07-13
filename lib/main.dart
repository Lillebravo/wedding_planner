import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'models/wedding_model.dart';
import 'services/storage_service.dart';
import 'views/onboarding_page.dart';
import 'views/landing_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initiera Supabase live mot molnet
  await Supabase.initialize(
    url: 'https://lutrlyzmmzjujoaybfjg.supabase.co/',
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx1dHJseXptbXpqdWpvYXliZmpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3NjU0MDAsImV4cCI6MjA5OTM0MTQwMH0.JnVqtW-mk_o9nM2XEfIJYddq_uAmyBE-fhC0m7V4dOY',
  );

  final localizationController = AppLocalizationsController();
  await localizationController.load();
  
  // Hämtar hela bröllopsobjektet för att se om vi är inloggade
  Wedding? activeWedding = await StorageService.getActiveWedding();

  runApp(
    WeddingApp(
      isLoggedIn: activeWedding != null,
      localizationController: localizationController,
    ),
  );
}

class WeddingApp extends StatelessWidget {
  final bool isLoggedIn;
  final AppLocalizationsController localizationController;

  const WeddingApp({
    super.key,
    required this.isLoggedIn,
    required this.localizationController,
  });

  @override
  Widget build(BuildContext context) {
    return AppLocalizationsScope(
      controller: localizationController,
      child: AnimatedBuilder(
        animation: localizationController,
        builder: (context, _) {
          return MaterialApp(
            locale: localizationController.locale,
            supportedLocales: const [Locale('sv'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            title: localizationController.text('app_title'),
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              primarySwatch: Colors.pink,
              scaffoldBackgroundColor: Colors.white,
            ),
            home: isLoggedIn ? const LandingPage() : const OnboardingPage(),
          );
        },
      ),
    );
  }
}