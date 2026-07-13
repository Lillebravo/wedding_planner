import 'package:flutter/material.dart';
import '../models/wedding_model.dart';
import '../models/guest_model.dart';
import '../services/storage_service.dart';
import 'landing_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const String _rsvpBackgroundImage =
      'https://images.unsplash.com/photo-1460978812857-470ed1c77af0?auto=format&fit=crop&w=1600&q=80';
  final _formKey = GlobalKey<FormState>();
  bool _isConnecting = false;
  bool _isLoading = false;

  final _codeController = TextEditingController();
  final _p1Controller = TextEditingController();
  final _p2Controller = TextEditingController();
  final _churchController = TextEditingController();
  final _venueController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    _isConnecting = true;
  }

  String _buildRandomCode() {
    final randomDigits = (DateTime.now().microsecondsSinceEpoch % 9000) + 1000;
    return 'brollop-$randomDigits';
  }

  void _generateRandomCode() {
    setState(() {
      _codeController.text = _buildRandomCode();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 15, minute: 0),
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      Wedding activeWedding;

      try {
        if (_isConnecting) {
          final enteredCode = _codeController.text.trim();
          final fetched = await StorageService.getWeddingFromCloud(enteredCode);
          if (fetched == null) {
            setState(() => _isLoading = false);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Koden matchar inget aktivt bröllop.'),
              ),
            );
            return;
          }
          activeWedding = fetched;
        } else {
          final dateString = _selectedDate != null
              ? _selectedDate!.toIso8601String().split(
                  'T',
                )[0] // Använd korrekt metod
              : 'Ej satt';

          final timeString = _selectedTime != null
              ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
              : 'Ej satt';

          final enteredCode = _codeController.text.trim().isEmpty
              ? _buildRandomCode()
              : _codeController.text.trim();
          _codeController.text = enteredCode;

          final tempWedding = Wedding(
            id: '',
            partner1: _p1Controller.text.trim(),
            partner2: _p2Controller.text.trim(),
            dateStr: dateString,
            timeStr: timeString,
            code: enteredCode,
            churchAddress: _churchController.text.trim(),
            venueAddress: _venueController.text
                .trim(), //venueAddress istället för trendAddress
          );

          activeWedding = await StorageService.saveNewWeddingToList(
            tempWedding,
          );

          final String honorTableUuid =
              await StorageService.createOnboardingTable(
                activeWedding.id,
                'Honnörsbord',
                8,
              );

          final brideId = 'bride-${activeWedding.id}';
          final groomId = 'groom-${activeWedding.id}';

          List<Guest> defaultPair = [
            Guest(
              id: brideId,
              firstName: activeWedding.partner1,
              lastName: '(Värd)',
              title: GuestTitle.bride,
              isLocked: true,
              tableId: honorTableUuid,
              seatNumber: 1,
            )..relations[groomId] = RelationType.partner,
            Guest(
              id: groomId,
              firstName: activeWedding.partner2,
              lastName: '(Värd)',
              title: GuestTitle.groom,
              isLocked: true,
              tableId: honorTableUuid,
              seatNumber: 2,
            )..relations[brideId] = RelationType.partner,
          ];

          await StorageService.saveGuests(activeWedding.id, defaultPair);
        }

        await StorageService.saveActiveWedding(activeWedding);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LandingPage()),
        );
      } catch (e) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ett fel uppstod: $e')));
      }
    }
  }

  Widget _buildConfettiDivider() {
    final colors = [
      Colors.pink.shade100,
      const Color(0xFFF5D9AA),
      const Color(0xFFD9E8C2),
      Colors.pink.shade100,
      const Color(0xFFF5D9AA),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: colors
          .map(
            (color) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.change_history, size: 14, color: color),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _rsvpBackgroundImage,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: const Color(0xFFF9F1F2),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66FFF8F2), Color(0xAAFFFFFF)],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Align(
                  alignment: screenWidth > 900
                      ? const Alignment(-0.2, 0)
                      : Alignment.center,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x24000000),
                          blurRadius: 32,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isConnecting ? 'R.S.V.P.' : 'Create Your Wedding',
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w400,
                              color: Colors.pink.shade200,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isConnecting
                                ? 'Please enter your wedding code to continue.'
                                : 'Fill in the details below to start planning your day.',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade700,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Center(child: _buildConfettiDivider()),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _codeController,
                            decoration: InputDecoration(
                              labelText: 'Bröllopskod',
                              border: const UnderlineInputBorder(),
                              suffixIcon: _isConnecting
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.auto_awesome_outlined),
                                      color: Theme.of(context).colorScheme.primary,
                                      tooltip: 'Generera kod automatiskt',
                                      onPressed: _generateRandomCode,
                                    ),
                            ),
                            validator: (v) =>
                                _isConnecting && (v == null || v.trim().isEmpty)
                                    ? 'Ange kod'
                                    : null,
                          ),
                          const SizedBox(height: 24),
                          if (!_isConnecting) ...[
                            TextFormField(
                              controller: _p1Controller,
                              decoration: const InputDecoration(
                                labelText: 'Partner 1 Namn *',
                                border: UnderlineInputBorder(),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Obligatoriskt fält'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _p2Controller,
                              decoration: const InputDecoration(
                                labelText: 'Partner 2 Namn *',
                                border: UnderlineInputBorder(),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Obligatoriskt fält'
                                  : null,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.calendar_month),
                                    label: Text(
                                      _selectedDate == null
                                          ? 'Välj Datum'
                                          : _selectedDate!.toIso8601String().split('T')[0],
                                    ),
                                    onPressed: _pickDate,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      side: BorderSide(color: Colors.grey.shade300),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.access_time),
                                    label: Text(
                                      _selectedTime == null
                                          ? 'Välj Tid'
                                          : '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}',
                                    ),
                                    onPressed: _pickTime,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      side: BorderSide(color: Colors.grey.shade300),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _churchController,
                              decoration: const InputDecoration(
                                labelText: 'Adress för vigsel/ceremoni (Frivilligt)',
                                border: UnderlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _venueController,
                              decoration: const InputDecoration(
                                labelText: 'Adress för festen (Frivilligt)',
                                border: UnderlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: const Color(0xFFE7B8C3),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(_isConnecting ? 'Logga in' : 'Skapa Bröllop'),
                          ),
                          const SizedBox(height: 12),
                          if (_isConnecting)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isConnecting = false;
                                });
                              },
                              child: const Text('Har du ingen kod? Skapa nytt bröllop här'),
                            )
                          else
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isConnecting = true;
                                });
                              },
                              child: const Text('Har du redan en kod? Logga in här'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
