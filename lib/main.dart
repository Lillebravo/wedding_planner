import 'package:flutter/material.dart';
import 'models/wedding_model.dart';
import 'services/storage_service.dart';
import 'views/onboarding_page.dart';
import 'views/landing_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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