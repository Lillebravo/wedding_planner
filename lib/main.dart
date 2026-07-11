import 'package:flutter/material.dart';
import 'models/wedding_model.dart';
import 'services/storage_service.dart';
import 'views/onboarding_page.dart';
import 'views/landing_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initiera Supabase live mot molnet
  await Supabase.initialize(
    url: 'https://lutrlyzmmzjujoaybfjg.supabase.co/',
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx1dHJseXptbXpqdWpvYXliZmpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3NjU0MDAsImV4cCI6MjA5OTM0MTQwMH0.JnVqtW-mk_o9nM2XEfIJYddq_uAmyBE-fhC0m7V4dOY',
  );
  
  // Hämtar hela bröllopsobjektet för att se om vi är inloggade
  Wedding? activeWedding = await StorageService.getActiveWedding();

  runApp(WeddingApp(isLoggedIn: activeWedding != null));
}

class WeddingApp extends StatelessWidget {
  final bool isLoggedIn;

  const WeddingApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bröllopsplanerare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.pink,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: isLoggedIn ? const LandingPage() : const OnboardingPage(),
    );
  }
}