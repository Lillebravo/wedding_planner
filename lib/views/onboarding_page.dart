import 'dart:math';
import 'package:flutter/material.dart';
import '../models/wedding_model.dart';
import '../models/guest_model.dart'; // FIX: Importera gästmodellen för att ta bort typfelen
import '../services/storage_service.dart';
import 'landing_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _p1Controller = TextEditingController();
  final _p2Controller = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  final _guestsController = TextEditingController();
  final _churchController = TextEditingController();
  final _venueController = TextEditingController();
  
  bool _isConnecting = false;
  List<Wedding> _localWeddings = [];

  @override
  void initState() {
    super.initState();
    _loadLocalWeddings();
  }

  void _loadLocalWeddings() async {
    final weddings = await StorageService.getAllLocalWeddings();
    setState(() {
      _localWeddings = weddings;
    });
  }

  void _generateRandomCode() {
    final random = Random();
    const characters = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final randomString = List.generate(5, (index) => characters[random.nextInt(characters.length)]).join();
    setState(() {
      _codeController.text = 'brollop-$randomString';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Välkommen till Bröllopsplaneraren')),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_isConnecting ? 'Logga in till bröllop' : 'Skapa nytt bröllop', 
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: 'Bröllopskod', 
                      border: const OutlineInputBorder(),
                      // FIX: Linter-safe måsvingar blockerar 'curly_braces_in_flow_control_structures'
                      suffixIcon: !_isConnecting 
                        ? IconButton(
                            icon: const Icon(Icons.flash_on, color: Colors.amber),
                            tooltip: 'Generera automatisk kod',
                            onPressed: _generateRandomCode,
                          )
                        : null,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Ange eller generera en kod.';
                      final cleanCode = value.trim();
                      
                      if (_isConnecting && !_localWeddings.any((w) => w.code == cleanCode)) {
                        return 'Koden matchar inga aktiva bröllop.';
                      }
                      if (!_isConnecting && _localWeddings.any((w) => w.code == cleanCode)) {
                        return 'Koden är upptagen. Detta bröllop finns redan!';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  ToggleButtons(
                    isSelected: [!_isConnecting, _isConnecting],
                    onPressed: (index) {
                      setState(() { _isConnecting = index == 1; });
                      _formKey.currentState?.validate();
                    },
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Skapa Nytt')), 
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Logga in med kod'))
                    ],
                  ),
                  if (!_isConnecting) ...[
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _p1Controller, 
                      decoration: const InputDecoration(labelText: 'Partner 1 Namn *', border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? 'Ange namn' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _p2Controller, 
                      decoration: const InputDecoration(labelText: 'Partner 2 Namn *', border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? 'Ange namn' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _dateController, 
                            decoration: const InputDecoration(labelText: 'Datum (Frivilligt)', border: OutlineInputBorder(), hintText: 'YYYY-MM-DD'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _timeController, 
                            decoration: const InputDecoration(labelText: 'Tid (Frivilligt)', border: OutlineInputBorder(), hintText: 'HH:MM'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _guestsController, 
                      decoration: const InputDecoration(labelText: 'Beräknat antal gäster (Frivilligt)', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _churchController, 
                      decoration: const InputDecoration(labelText: 'Adress för vigsel/ceremoni (Frivilligt)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _venueController, 
                      decoration: const InputDecoration(labelText: 'Adress för festen (Frivilligt)', border: OutlineInputBorder()),
                    ),
                  ],
                  const SizedBox(height: 30),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: _submit,
                    child: Text(_isConnecting ? 'Anslut till Bröllop' : 'Skapa Bröllop'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      final enteredCode = _codeController.text.trim();
      Wedding activeWedding;

      if (_isConnecting) {
        activeWedding = _localWeddings.firstWhere((w) => w.code == enteredCode);
      } else {
        activeWedding = Wedding(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          partner1: _p1Controller.text.trim(),
          partner2: _p2Controller.text.trim(),
          dateStr: _dateController.text.isEmpty ? 'Ej satt' : _dateController.text.trim(),
          timeStr: _timeController.text.isEmpty ? 'Ej satt' : _timeController.text.trim(),
          code: enteredCode,
          estimatedGuests: _guestsController.text,
          churchAddress: _churchController.text,
          venueAddress: _venueController.text,
        );
        await StorageService.saveNewWeddingToList(activeWedding);

        final brideId = 'bride-${activeWedding.id}';
        final groomId = 'groom-${activeWedding.id}';

        // Skapa brudparet med en inbördes partner-relation direkt!
        List<Guest> defaultPair = [
          Guest(
            id: brideId,
            firstName: _p1Controller.text.trim(),
            lastName: '(Värd)',
            title: GuestTitle.bride,
            isLocked: true,
            tableId: '1',
          )..relations[groomId] = RelationType.partner, // Bruden är partner med brudgummen
          Guest(
            id: groomId,
            firstName: _p2Controller.text.trim(),
            lastName: '(Värd)',
            title: GuestTitle.groom,
            isLocked: true,
            tableId: '1',
          )..relations[brideId] = RelationType.partner, // Brudgummen är partner med bruden
        ];
        
        await StorageService.saveGuests(activeWedding.id, defaultPair);
      }

      await StorageService.saveActiveWedding(activeWedding);
      
      if (!mounted) return;
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (context) => const LandingPage()),
      );
    }
  }
}