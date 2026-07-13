import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:math' as math;
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
  Color _coverBackgroundColor = const Color(0xFFFCE4EC);

  @override
  void initState() {
    super.initState();
    _loadWeddingData();
  }

  void _loadWeddingData() async {
    Wedding? w = await StorageService.getActiveWedding();
    Color bgColor = const Color(0xFFFCE4EC);
    if (w != null) {
      final savedBg = await StorageService.getCoverBackgroundColorValue(w.id);
      if (savedBg != null) {
        bgColor = Color(savedBg);
      }
    }

    setState(() {
      _wedding = w;
      _coverBackgroundColor = bgColor;
      _isLoading = false;
    });
  }

  Future<void> _saveWeddingWithCover({
    String? coverImageUrl,
    Color? coverBackgroundColor,
  }) async {
    if (_wedding == null) return;

    setState(() => _isLoading = true);

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
        coverImageUrl: coverImageUrl ?? _wedding!.coverImageUrl,
        itinerary: _wedding!.itinerary,
      );

      final savedWedding = await StorageService.updateWedding(updatedWedding);
      await StorageService.saveActiveWedding(savedWedding);

      if (coverBackgroundColor != null) {
        await StorageService.saveCoverBackgroundColorValue(
          savedWedding.id,
          coverBackgroundColor.toARGB32(),
        );
      }

      if (!mounted) return;
      setState(() {
        _wedding = savedWedding;
        if (coverBackgroundColor != null) {
          _coverBackgroundColor = coverBackgroundColor;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte uppdatera omslagsinställningar: $e')),
      );
    }
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

    final uploadResult = await StorageService.uploadCoverImage(
      _wedding!.id,
      selectedFile.name,
      selectedFile.bytes!,
    );

    if (!mounted) return;

    if (!uploadResult.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploadResult.errorMessage ?? 'Bilduppladdningen misslyckades.',
          ),
        ),
      );
      return;
    }

    await _saveWeddingWithCover(coverImageUrl: uploadResult.publicUrl);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Omslagsbilden uppdaterades.')),
    );
  }

  Future<void> _openCoverSettingsMenu() async {
    if (_wedding == null) return;

    final selectedAction = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Välj bland uppladdade bilder'),
                onTap: () => Navigator.pop(context, 'pick_existing'),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Ladda upp ny bild'),
                onTap: () => Navigator.pop(context, 'upload_new'),
              ),
              ListTile(
                leading: const Icon(Icons.color_lens_outlined),
                title: const Text('Välj bakgrundsfärg (färghjul)'),
                onTap: () => Navigator.pop(context, 'pick_color'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || selectedAction == null) return;

    if (selectedAction == 'upload_new') {
      await _uploadNewCover();
      return;
    }

    if (selectedAction == 'pick_existing') {
      await _openUploadedCoverPicker();
      return;
    }

    if (selectedAction == 'pick_color') {
      await _openCoverColorPicker();
    }
  }

  Future<void> _openUploadedCoverPicker() async {
    if (_wedding == null) return;

    final imageUrls = await StorageService.listCoverImageUrls(_wedding!.id);
    if (!mounted) return;

    if (imageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inga uppladdade bilder hittades ännu.')),
      );
      return;
    }

    final selectedUrl = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Välj omslagsbild'),
        content: SizedBox(
          width: 520,
          height: 380,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: imageUrls.length,
            itemBuilder: (context, index) {
              final imageUrl = imageUrls[index];
              final isCurrent = imageUrl == _wedding!.coverImageUrl;

              return InkWell(
                onTap: () => Navigator.pop(dialogContext, imageUrl),
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.check_circle, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Stäng'),
          ),
        ],
      ),
    );

    if (selectedUrl == null || !mounted) return;
    await _saveWeddingWithCover(coverImageUrl: selectedUrl);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Omslagsbild vald från uppladdade bilder.')),
    );
  }

  Future<void> _openCoverColorPicker() async {
    Color pickedColor = _coverBackgroundColor;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Välj bakgrundsfärg'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickedColor,
            onColorChanged: (color) => pickedColor = color,
            colorPickerWidth: 300,
            pickerAreaHeightPercent: 0.7,
            enableAlpha: false,
            displayThumbColor: true,
            paletteType: PaletteType.hsvWithHue,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Avbryt'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Spara'),
          ),
        ],
      ),
    );

    if (shouldSave != true || !mounted) return;
    await _saveWeddingWithCover(coverBackgroundColor: pickedColor);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bakgrundsfärgen uppdaterades.')),
    );
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

  Future<void> _copyWeddingCode() async {
    final code = _wedding?.code.trim() ?? '';
    if (code.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bröllopskoden kopierades till klippbordet.')),
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

    final screenWidth = MediaQuery.of(context).size.width;
    final expandedHeight = screenWidth < 420
      ? 300.0
      : screenWidth < 700
        ? 350.0
        : screenWidth < 1200
          ? 360.0
          : 430.0;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: expandedHeight,
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
                  Container(color: _coverBackgroundColor),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final availableWidth = constraints.maxWidth;
                      final isSmallScreen = availableWidth < 700;
                      final isVeryLargeScreen = availableWidth >= 1900;

                      // On laptops we keep at least about half width.
                      // On very large displays we cap near one third.
                      final targetCoverWidth = isSmallScreen
                          ? availableWidth
                          : isVeryLargeScreen
                              ? availableWidth * 0.33
                              : math.max(availableWidth * 0.55, 560.0);

                      final horizontalPadding = isSmallScreen ? 0.0 : 12.0;
                      final verticalPadding = isSmallScreen ? 2.0 : 12.0;

                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: targetCoverWidth,
                            maxHeight: constraints.maxHeight,
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                              vertical: verticalPadding,
                            ),
                            child: _wedding!.coverImageUrl != null
                                ? ClipRect(
                                    child: Image.network(
                                      _wedding!.coverImageUrl!,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      filterQuality: FilterQuality.high,
                                      gaplessPlayback: true,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: Colors.pink[100],
                                          child: const Icon(
                                            Icons.favorite,
                                            size: 80,
                                            color: Colors.white,
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                : Container(
                                    color: Colors.pink[100],
                                    child: const Icon(Icons.favorite, size: 80, color: Colors.white),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
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
                      onPressed: _openCoverSettingsMenu,
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
                      elevation: 0,
                      color: Colors.pink[50],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.pink.shade100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.groups_2_outlined, color: Colors.pink.shade400),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Dela koden med gäster',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _wedding!.code,
                                    style: TextStyle(
                                      fontSize: 15,
                                      letterSpacing: 0.4,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              icon: const Icon(Icons.copy),
                              tooltip: 'Kopiera kod',
                              onPressed: _copyWeddingCode,
                            ),
                          ],
                        ),
                      ),
                    ),
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