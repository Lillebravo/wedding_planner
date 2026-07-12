import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const OnboardingPage()),
    );
  }

  // Ny funktion för att öppna kartor
  Future<void> _openMap(String address) async {
    if (address.isEmpty) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kunde inte öppna kartan.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ett fel uppstod vid öppning av karta.')));
    }
  }

  Future<void> _uploadNewCover() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final selectedFile = result?.files.single;

    if (selectedFile == null || _wedding == null) {
      return;
    }

    if (!mounted) return;

    if (selectedFile.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kunde inte lasa den valda bilden. Testa en annan fil.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final uploadResult = await StorageService.uploadCoverImage(
      _wedding!.id,
      selectedFile.name,
      selectedFile.bytes!,
    );

    if (!mounted) return;

    if (!uploadResult.isSuccess) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploadResult.errorMessage ?? 'Bilduppladdningen misslyckades.',
          ),
        ),
      );
      return;
    }

    try {
      final updatedWedding = Wedding(
        id: _wedding!.id,
        partner1: _wedding!.partner1,
        partner2: _wedding!.partner2,
        dateStr: _wedding!.dateStr,
        timeStr: _wedding!.timeStr,
        code: _wedding!.code,
        churchAddress: _wedding!.churchAddress,
        venueAddress: _wedding!.venueAddress,
        coverImageUrl: uploadResult.publicUrl,
        itinerary: _wedding!.itinerary,
      );

      final savedWedding = await StorageService.updateWedding(updatedWedding);
      await StorageService.saveActiveWedding(savedWedding);

      setState(() {
        _wedding = savedWedding;
        _isLoading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Omslagsbilden uppdaterades.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bilden laddades upp men URL kunde inte sparas i weddings: $e',
          ),
        ),
      );
    }
  }

  // Den stora inställningsmenyn för Bröllopet
  void _openSettingsDialog() {
    final p1Ctrl = TextEditingController(text: _wedding!.partner1);
    final p2Ctrl = TextEditingController(text: _wedding!.partner2);
    final churchCtrl = TextEditingController(text: _wedding!.churchAddress);
    final venueCtrl = TextEditingController(text: _wedding!.venueAddress);
    
    DateTime? selectedDate = DateTime.tryParse(_wedding!.dateStr);
    TimeOfDay? selectedTime;
    if (_wedding!.timeStr != 'Ej satt' && _wedding!.timeStr.contains(':')) {
      final parts = _wedding!.timeStr.split(':');
      selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Redigera Bröllopsdetaljer'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: p1Ctrl, decoration: const InputDecoration(labelText: 'Partner 1')),
                  TextField(controller: p2Ctrl, decoration: const InputDecoration(labelText: 'Partner 2')),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month),
                          label: Text(selectedDate == null ? 'Välj Datum' : selectedDate!.toIso8601String().split('T')[0]),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setDialogState(() => selectedDate = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time),
                          label: Text(selectedTime == null ? 'Välj Tid' : '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: selectedTime ?? const TimeOfDay(hour: 15, minute: 0),
                            );
                            if (picked != null) setDialogState(() => selectedTime = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: churchCtrl, decoration: const InputDecoration(labelText: 'Adress för ceremoni')),
                  TextField(controller: venueCtrl, decoration: const InputDecoration(labelText: 'Adress för festlokal')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
              ElevatedButton(
                onPressed: () async {
                  final navigator = Navigator.of(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  
                  final updatedWedding = Wedding(
                    id: _wedding!.id,
                    partner1: p1Ctrl.text.trim(),
                    partner2: p2Ctrl.text.trim(),
                    dateStr: selectedDate != null ? selectedDate!.toIso8601String().split('T')[0] : 'Ej satt',
                    timeStr: selectedTime != null ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}' : 'Ej satt',
                    code: _wedding!.code,
                    churchAddress: churchCtrl.text.trim(),
                    venueAddress: venueCtrl.text.trim(),
                    coverImageUrl: _wedding!.coverImageUrl,
                    itinerary: _wedding!.itinerary,
                  );

                  setState(() => _isLoading = true);
                  navigator.pop();

                  try {
                    final saved = await StorageService.updateWedding(updatedWedding);
                    await StorageService.saveActiveWedding(saved);
                    setState(() {
                      _wedding = saved;
                      _isLoading = false;
                    });
                    messenger.showSnackBar(const SnackBar(content: Text('Detaljerna har uppdaterats!')));
                  } catch (e) {
                    setState(() => _isLoading = false);
                    messenger.showSnackBar(SnackBar(content: Text('Fel: $e')));
                  }
                },
                child: const Text('Spara'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Schema (Itinerary) hanteraren
  void _openItineraryDialog() {
    List<Map<String, dynamic>> tempItinerary = List<Map<String, dynamic>>.from(_wedding!.itinerary);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void openAddEventDialog() {
            TimeOfDay? eventTime;
            String selectedCategory = 'Ceremoni';
            final customCtrl = TextEditingController();
            final categories = ['Ceremoni', 'Mottagning', 'Förrätt', 'Varmrätt', 'Efterrätt', 'Brudskål', 'Tal', 'Dans', 'Annat (Fritext)'];

            showDialog(
              context: ctx,
              builder: (addCtx) => StatefulBuilder(
                builder: (context, setAddState) {
                  return AlertDialog(
                    title: const Text('Lägg till händelse'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.access_time),
                          label: Text(eventTime == null ? 'Välj Tid *' : '${eventTime!.hour.toString().padLeft(2, '0')}:${eventTime!.minute.toString().padLeft(2, '0')}'),
                          onPressed: () async {
                            final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 15, minute: 0));
                            if (picked != null) setAddState(() => eventTime = picked);
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory,
                          items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (val) => setAddState(() => selectedCategory = val!),
                          decoration: const InputDecoration(labelText: 'Kategori'),
                        ),
                        if (selectedCategory == 'Annat (Fritext)') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: customCtrl,
                            decoration: const InputDecoration(labelText: 'Egen händelse'),
                          ),
                        ]
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(addCtx), child: const Text('Avbryt')),
                      ElevatedButton(
                        onPressed: eventTime == null ? null : () {
                          final title = selectedCategory == 'Annat (Fritext)' ? customCtrl.text.trim() : selectedCategory;
                          if (title.isNotEmpty) {
                            setDialogState(() {
                              tempItinerary.add({
                                'time': '${eventTime!.hour.toString().padLeft(2, '0')}:${eventTime!.minute.toString().padLeft(2, '0')}',
                                'title': title,
                              });
                              // Sortera listan på tid (sträng-sortering funkar bra på HH:MM)
                              tempItinerary.sort((a, b) => a['time'].toString().compareTo(b['time'].toString()));
                            });
                            Navigator.pop(addCtx);
                          }
                        },
                        child: const Text('Lägg till'),
                      )
                    ],
                  );
                }
              )
            );
          }

          return AlertDialog(
            title: const Text('Hantera Schema'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: tempItinerary.isEmpty
                  ? const Center(child: Text('Schemat är tomt.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: tempItinerary.length,
                      itemBuilder: (context, i) {
                        final event = tempItinerary[i];
                        return ListTile(
                          leading: Text(event['time'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          title: Text(event['title'] ?? ''),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => setDialogState(() => tempItinerary.removeAt(i)),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(onPressed: () => openAddEventDialog(), child: const Text('Ny Händelse')),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
              ElevatedButton(
                onPressed: () async {
                  final nav = Navigator.of(ctx);
                  final updatedWedding = Wedding(
                    id: _wedding!.id,
                    partner1: _wedding!.partner1,
                    partner2: _wedding!.partner2,
                    dateStr: _wedding!.dateStr,
                    timeStr: _wedding!.timeStr,
                    code: _wedding!.code,
                    churchAddress: _wedding!.churchAddress,
                    venueAddress: _wedding!.venueAddress,
                    coverImageUrl: _wedding!.coverImageUrl,
                    itinerary: tempItinerary,
                  );

                  setState(() => _isLoading = true);
                  nav.pop();

                  try {
                    final saved = await StorageService.updateWedding(updatedWedding);
                    await StorageService.saveActiveWedding(saved);
                    setState(() {
                      _wedding = saved;
                      _isLoading = false;
                    });
                  } catch (e) {
                    setState(() => _isLoading = false);
                  }
                },
                child: const Text('Spara'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_wedding == null) {
      return const OnboardingPage();
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250.0,
            floating: false,
            pinned: true,
            actions: [
              IconButton(icon: const Icon(Icons.settings), onPressed: _openSettingsDialog),
              IconButton(
                icon: const Icon(Icons.people),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GuestListPage()),
                ),
              ),
              IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '${_wedding!.partner1} & ${_wedding!.partner2}',
                style: const TextStyle(color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 10)]),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _wedding!.coverImageUrl != null
                      ? Image.network(_wedding!.coverImageUrl!, fit: BoxFit.cover)
                      : Container(color: Colors.pink[100], child: const Icon(Icons.favorite, size: 80, color: Colors.white)),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54]),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'upload_btn',
                      onPressed: _uploadNewCover,
                      child: const Icon(Icons.camera_alt),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Detaljer för dagen', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.calendar_month, color: Colors.pink),
                        title: Text('Datum: ${_wedding!.dateStr}'),
                        subtitle: Text('Tid: ${_wedding!.timeStr}'),
                      ),
                    ),
                    if (_wedding!.churchAddress.isNotEmpty)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.church, color: Colors.blue),
                          title: const Text('Ceremoni'),
                          subtitle: Text(_wedding!.churchAddress),
                          trailing: const Icon(Icons.open_in_new, color: Colors.grey),
                          onTap: () => _openMap(_wedding!.churchAddress),
                        ),
                      ),
                    if (_wedding!.venueAddress.isNotEmpty)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.celebration, color: Colors.orange),
                          title: const Text('Mottagning / Festlokal'),
                          subtitle: Text(_wedding!.venueAddress),
                          trailing: const Icon(Icons.open_in_new, color: Colors.grey),
                          onTap: () => _openMap(_wedding!.venueAddress),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tidslinje / Schema', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.edit_calendar, color: Colors.pink),
                          onPressed: _openItineraryDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _wedding!.itinerary.isEmpty
                        ? const Text('Inget schema är satt ännu.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _wedding!.itinerary.length,
                            itemBuilder: (context, index) {
                              final event = _wedding!.itinerary[index];
                              return ListTile(
                                leading: Text(event['time'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                title: Text(event['title'] ?? ''),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}