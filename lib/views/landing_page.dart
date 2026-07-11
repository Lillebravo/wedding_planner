import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final dateCtrl = TextEditingController(text: _wedding!.dateStr);
    final timeCtrl = TextEditingController(text: _wedding!.timeStr);
    final churchCtrl = TextEditingController(text: _wedding!.churchAddress);
    final venueCtrl = TextEditingController(text: _wedding!.venueAddress);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Redigera Bröllopsdetaljer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: p1Ctrl, decoration: const InputDecoration(labelText: 'Partner 1')),
              TextField(controller: p2Ctrl, decoration: const InputDecoration(labelText: 'Partner 2')),
              TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: 'Datum')),
              TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'Tid')),
              TextField(controller: churchCtrl, decoration: const InputDecoration(labelText: 'Vigseladress')),
              TextField(controller: venueCtrl, decoration: const InputDecoration(labelText: 'Festlokalsadress')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Avbryt')),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _wedding!.partner1 = p1Ctrl.text.trim();
                _wedding!.partner2 = p2Ctrl.text.trim();
                _wedding!.dateStr = dateCtrl.text.trim();
                _wedding!.timeStr = timeCtrl.text.trim();
                _wedding!.churchAddress = churchCtrl.text.trim();
                _wedding!.venueAddress = venueCtrl.text.trim();
              });

              Navigator.pop(dialogContext);

              // Skriv ändringarna live till Supabase
              await StorageService.saveNewWeddingToList(_wedding!);
              await StorageService.saveActiveWedding(_wedding!);
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
          IconButton(icon: const Icon(Icons.settings), tooltip: 'Inställningar', onPressed: _openSettingsDialog),
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'Hantera gäster',
            onPressed: () {
              Navigator.push(
                context, 
                MaterialPageRoute(
                  builder: (context) => const GuestListPage(),
                )
              );
            },
          ),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Logga ut från eventet', onPressed: _logout),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 220,
              width: double.infinity,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage('https://images.unsplash.com/photo-1519741497674-611481863552?q=80&w=600'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                alignment: Alignment.center,
                child: Text(
                  '${_wedding!.partner1} ♥ ${_wedding!.partner2}',
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.pink[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.key, color: Colors.pink),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Er bröllopskod för gäster:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(_wedding!.code, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.pink),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _wedding!.code));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Koden kopierad! 📋')));
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Information – ${_wedding!.dateStr} kl. ${_wedding!.timeStr}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (_wedding!.estimatedGuests != null && _wedding!.estimatedGuests!.isNotEmpty)
                    Text('Beräknat antal gäster: ${_wedding!.estimatedGuests}', style: const TextStyle(color: Colors.grey)),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.church, color: Colors.pink),
                    title: const Text('Vigselplats'),
                    subtitle: Text(_wedding!.churchAddress?.isEmpty ?? true ? 'Ingen adress angiven' : _wedding!.churchAddress!),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restaurant, color: Colors.pink),
                    title: const Text('Festlokal'),
                    subtitle: Text(_wedding!.venueAddress?.isEmpty ?? true ? 'Ingen adress angiven' : _wedding!.venueAddress!),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}