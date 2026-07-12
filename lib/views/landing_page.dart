import 'package:flutter/material.dart';
import '../models/wedding_model.dart';
import '../services/storage_service.dart';
import 'guest_list_page.dart';
import 'onboarding_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  Wedding? _wedding;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWeddingData();
  }

  void _loadWeddingData() async {
    Wedding? w = await StorageService.getActiveWedding();
    setState(() {
      _wedding = w;
      _isLoading = false;
    });
  }

  void _logout() async {
    await StorageService.clearActiveWedding();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const OnboardingPage()));
  }

  void _openSettingsDialog() {
    if (_wedding == null) return;
    final p1Ctrl = TextEditingController(text: _wedding!.partner1);
    final p2Ctrl = TextEditingController(text: _wedding!.partner2);
    final churchCtrl = TextEditingController(text: _wedding!.churchAddress);
    final venueCtrl = TextEditingController(text: _wedding!.venueAddress);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Redigera Bröllopsdetaljer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: p1Ctrl, decoration: const InputDecoration(labelText: 'Partner 1')),
            TextField(controller: p2Ctrl, decoration: const InputDecoration(labelText: 'Partner 2')),
            TextField(controller: churchCtrl, decoration: const InputDecoration(labelText: 'Vigseladress')),
            TextField(controller: venueCtrl, decoration: const InputDecoration(labelText: 'Festlokalsadress')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Avbryt')),
          ElevatedButton(
            onPressed: () async {
              final updatedWedding = Wedding(
                id: _wedding!.id,
                partner1: p1Ctrl.text.trim(),
                partner2: p2Ctrl.text.trim(),
                dateStr: _wedding!.dateStr,
                timeStr: _wedding!.timeStr,
                code: _wedding!.code,
                churchAddress: churchCtrl.text.trim(),
                venueAddress: venueCtrl.text.trim(),
                coverImageUrl: _wedding!.coverImageUrl,
              );
              Navigator.pop(dialogContext);
              await StorageService.updateWedding(updatedWedding);
              await StorageService.saveActiveWedding(updatedWedding);
              _loadWeddingData();
            },
            child: const Text('Spara'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_wedding == null) return const OnboardingPage();

    return Scaffold(
      appBar: AppBar(
        title: Text('${_wedding!.partner1} & ${_wedding!.partner2}'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettingsDialog),
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GuestListPage())),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Center(child: Text("Välkommen till ${_wedding!.partner1} & ${_wedding!.partner2}'s bröllopsportal!")),
    );
  }
}