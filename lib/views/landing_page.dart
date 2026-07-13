import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
  static const String _defaultHeroImage =
      'https://images.unsplash.com/photo-1511285560929-80b456fea0bc?auto=format&fit=crop&w=1600&q=80';
  Wedding? _wedding;
  bool _isLoading = true;
  Color _coverBackgroundColor = const Color(0xFFFCE4EC);
  bool _showHero = false;
  int _staggerStep = -1;
  Timer? _countdownTimer;

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
      _showHero = false;
      _staggerStep = -1;
    });

    _runIntroAnimation();
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _runIntroAnimation() async {
    if (!mounted) return;

    // Omslagsbilden fade:ar in först, därefter domino-in för innehållet.
    setState(() => _showHero = true);
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    for (int i = 0; i < 36; i++) {
      if (!mounted) return;
      setState(() => _staggerStep = i);
      await Future.delayed(const Duration(milliseconds: 115));
    }
  }

  Widget _buildStaggerItem({required int step, required Widget child}) {
    final isVisible = _staggerStep >= step;

    return AnimatedOpacity(
      opacity: isVisible ? 1 : 0,
      duration: const Duration(milliseconds: 940),
      curve: Curves.easeOutQuart,
      child: AnimatedSlide(
        offset: isVisible ? Offset.zero : const Offset(0, 0.085),
        duration: const Duration(milliseconds: 940),
        curve: Curves.easeOutQuart,
        child: child,
      ),
    );
  }

  DateTime? _weddingDateTime() {
    final date = DateTime.tryParse(_wedding?.dateStr ?? '');
    if (date == null) return null;

    final timeParts = (_wedding?.timeStr ?? '').split(':');
    if (timeParts.length != 2) {
      return date;
    }

    final hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = int.tryParse(timeParts[1]) ?? 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  Map<String, int> _countdownParts() {
    final weddingDate = _weddingDateTime();
    if (weddingDate == null) {
      return {
        'days': 0,
        'hours': 0,
        'minutes': 0,
        'seconds': 0,
      };
    }

    var remaining = weddingDate.difference(DateTime.now());
    if (remaining.isNegative) {
      remaining = Duration.zero;
    }

    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);

    return {
      'days': days,
      'hours': hours,
      'minutes': minutes,
      'seconds': seconds,
    };
  }

  Widget _buildHeroStat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w300,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFF6EAEA),
            fontSize: 11,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildConfettiDivider({Color? color}) {
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
            (dividerColor) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.change_history,
                size: 14,
                color: color ?? dividerColor,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSectionTitle({
    required String title,
    required String subtitle,
  }) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w400,
            color: Color(0xFF24191D),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            color: Colors.grey.shade700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        _buildConfettiDivider(),
      ],
    );
  }

  Widget _buildCoupleCard({
    required String name,
    required IconData icon,
    required List<String> lines,
    required Color accent,
  }) {
    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent.withValues(alpha: 0.18), accent],
              ),
            ),
            child: Icon(icon, size: 68, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF24191D),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            lines.join('\n'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.favorite_border, size: 18, color: Color(0xFFE9B2BC)),
              SizedBox(width: 12),
              Icon(Icons.auto_awesome, size: 18, color: Color(0xFFE9B2BC)),
              SizedBox(width: 12),
              Icon(Icons.celebration_outlined, size: 18, color: Color(0xFFE9B2BC)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF24191D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleItem(Map<String, dynamic> event) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.pink.shade50,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              event['time'] ?? '',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.pink.shade700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              event['title'] ?? '',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF24191D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveWeddingWithCover({
    String? coverImageUrl,
    Color? coverBackgroundColor,
    bool clearCoverImage = false,
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
        coverImageUrl: clearCoverImage
            ? null
            : (coverImageUrl ?? _wedding!.coverImageUrl),
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
        SnackBar(
          content: Text('Kunde inte uppdatera omslagsinställningar: $e'),
        ),
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
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kunde inte öppna kartan.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ett fel uppstod vid öppning av karta.'),
          ),
        );
      }
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
      builder: (dialogContext) {
        final mutableImageUrls = List<String>.from(imageUrls);

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Välj omslagsbild'),
            content: SizedBox(
              width: 520,
              height: 380,
              child: mutableImageUrls.isEmpty
                  ? const Center(
                      child: Text('Inga bilder kvar.'),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: mutableImageUrls.length,
                      itemBuilder: (context, index) {
                        final imageUrl = mutableImageUrls[index];
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
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Material(
                                  color: Colors.black54,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () async {
                                      final shouldDelete = await showDialog<bool>(
                                        context: dialogContext,
                                        builder: (confirmContext) => AlertDialog(
                                          title: const Text('Ta bort bild?'),
                                          content: const Text(
                                            'Är du säker på att du vill ta bort den här bilden?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(confirmContext, false),
                                              child: const Text('Nej'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(confirmContext, true),
                                              child: const Text('Ja'),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (shouldDelete != true || !mounted) return;

                                      try {
                                        await StorageService.deleteCoverImageByUrl(imageUrl);

                                        if (!mounted) return;

                                        final remainingUrls = List<String>.from(mutableImageUrls)
                                          ..remove(imageUrl);

                                        final wasCurrentCover =
                                            imageUrl == _wedding!.coverImageUrl;
                                        if (wasCurrentCover) {
                                          if (remainingUrls.isNotEmpty) {
                                            await _saveWeddingWithCover(
                                              coverImageUrl: remainingUrls.first,
                                            );
                                          } else {
                                            await _saveWeddingWithCover(
                                              clearCoverImage: true,
                                            );
                                          }
                                        }

                                        if (!mounted) return;

                                        setDialogState(() {
                                          mutableImageUrls.remove(imageUrl);
                                        });

                                        ScaffoldMessenger.of(this.context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Bilden har tagits bort.'),
                                          ),
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(this.context).showSnackBar(
                                          SnackBar(
                                            content: Text('Kunde inte ta bort bilden: $e'),
                                          ),
                                        );
                                      }
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (isCurrent)
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white, width: 3),
                                  ),
                                  child: const Align(
                                    alignment: Alignment.bottomRight,
                                    child: Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.check_circle,
                                        color: Colors.white,
                                      ),
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
      },
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
      selectedTime = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
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
                  TextField(
                    controller: p1Ctrl,
                    decoration: const InputDecoration(labelText: 'Partner 1'),
                  ),
                  TextField(
                    controller: p2Ctrl,
                    decoration: const InputDecoration(labelText: 'Partner 2'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            selectedDate == null
                                ? 'Välj Datum'
                                : selectedDate!.toIso8601String().split('T')[0],
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedDate = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time),
                          label: Text(
                            selectedTime == null
                                ? 'Välj Tid'
                                : '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}',
                          ),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime:
                                  selectedTime ??
                                  const TimeOfDay(hour: 15, minute: 0),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedTime = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: churchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Adress för ceremoni',
                    ),
                  ),
                  TextField(
                    controller: venueCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Adress för festlokal',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Avbryt'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final navigator = Navigator.of(ctx);
                  final messenger = ScaffoldMessenger.of(context);

                  final updatedWedding = Wedding(
                    id: _wedding!.id,
                    partner1: p1Ctrl.text.trim(),
                    partner2: p2Ctrl.text.trim(),
                    dateStr: selectedDate != null
                        ? selectedDate!.toIso8601String().split('T')[0]
                        : 'Ej satt',
                    timeStr: selectedTime != null
                        ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                        : 'Ej satt',
                    code: _wedding!.code,
                    churchAddress: churchCtrl.text.trim(),
                    venueAddress: venueCtrl.text.trim(),
                    coverImageUrl: _wedding!.coverImageUrl,
                    itinerary: _wedding!.itinerary,
                  );

                  setState(() => _isLoading = true);
                  navigator.pop();

                  try {
                    final saved = await StorageService.updateWedding(
                      updatedWedding,
                    );
                    await StorageService.saveActiveWedding(saved);
                    setState(() {
                      _wedding = saved;
                      _isLoading = false;
                    });
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Detaljerna har uppdaterats!'),
                      ),
                    );
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
      const SnackBar(
        content: Text('Bröllopskoden kopierades till klippbordet.'),
      ),
    );
  }

  // Schema (Itinerary) hanteraren
  void _openItineraryDialog() {
    List<Map<String, dynamic>> tempItinerary = List<Map<String, dynamic>>.from(
      _wedding!.itinerary,
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> openEditEventDialog(int index) async {
            final existingEvent = tempItinerary[index];
            final titleController = TextEditingController(
              text: (existingEvent['title'] ?? '').toString(),
            );

            final timeString = (existingEvent['time'] ?? '').toString();
            final parts = timeString.split(':');
            TimeOfDay selectedTime = TimeOfDay(
              hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0,
              minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
            );

            final shouldSave = await showDialog<bool>(
              context: ctx,
              builder: (editCtx) => StatefulBuilder(
                builder: (context, setEditState) => AlertDialog(
                  title: const Text('Redigera händelse'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.access_time),
                        label: Text(
                          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setEditState(() => selectedTime = picked);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Händelse',
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(editCtx, false),
                      child: const Text('Avbryt'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(editCtx, true),
                      child: const Text('Spara'),
                    ),
                  ],
                ),
              ),
            );

            if (shouldSave != true) {
              titleController.dispose();
              return;
            }

            final updatedTitle = titleController.text.trim();
            if (updatedTitle.isNotEmpty) {
              setDialogState(() {
                tempItinerary[index] = {
                  'time':
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                  'title': updatedTitle,
                };
                tempItinerary.sort(
                  (a, b) =>
                      a['time'].toString().compareTo(b['time'].toString()),
                );
              });
            }

            titleController.dispose();
          }

          void openAddEventDialog() {
            TimeOfDay? eventTime;
            String selectedCategory = 'Ceremoni';
            final customCtrl = TextEditingController();
            final categories = [
              'Ceremoni',
              'Mottagning',
              'Förrätt',
              'Varmrätt',
              'Efterrätt',
              'Brudskål',
              'Tal',
              'Dans',
              'Annat (Fritext)',
            ];

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
                          label: Text(
                            eventTime == null
                                ? 'Välj Tid *'
                                : '${eventTime!.hour.toString().padLeft(2, '0')}:${eventTime!.minute.toString().padLeft(2, '0')}',
                          ),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: const TimeOfDay(hour: 15, minute: 0),
                            );
                            if (picked != null) {
                              setAddState(() => eventTime = picked);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory,
                          items: categories
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setAddState(() => selectedCategory = val!),
                          decoration: const InputDecoration(
                            labelText: 'Kategori',
                          ),
                        ),
                        if (selectedCategory == 'Annat (Fritext)') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: customCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Egen händelse',
                            ),
                          ),
                        ],
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(addCtx),
                        child: const Text('Avbryt'),
                      ),
                      ElevatedButton(
                        onPressed: eventTime == null
                            ? null
                            : () {
                                final title =
                                    selectedCategory == 'Annat (Fritext)'
                                    ? customCtrl.text.trim()
                                    : selectedCategory;
                                if (title.isNotEmpty) {
                                  setDialogState(() {
                                    tempItinerary.add({
                                      'time':
                                          '${eventTime!.hour.toString().padLeft(2, '0')}:${eventTime!.minute.toString().padLeft(2, '0')}',
                                      'title': title,
                                    });
                                    // Sortera listan på tid (sträng-sortering funkar bra på HH:MM)
                                    tempItinerary.sort(
                                      (a, b) => a['time'].toString().compareTo(
                                        b['time'].toString(),
                                      ),
                                    );
                                  });
                                  Navigator.pop(addCtx);
                                }
                              },
                        child: const Text('Lägg till'),
                      ),
                    ],
                  );
                },
              ),
            );
          }

          return AlertDialog(
            title: const Text('Hantera Schema'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: tempItinerary.isEmpty
                  ? const Center(
                      child: Text(
                        'Schemat är tomt.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: tempItinerary.length,
                      itemBuilder: (context, i) {
                        final event = tempItinerary[i];
                        return ListTile(
                          leading: Text(
                            event['time'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          title: Text(event['title'] ?? ''),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blueGrey),
                                tooltip: 'Redigera',
                                onPressed: () => openEditEventDialog(i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Ta bort',
                                onPressed: () => setDialogState(
                                  () => tempItinerary.removeAt(i),
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
                onPressed: () => openAddEventDialog(),
                child: const Text('Ny Händelse'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Avbryt'),
              ),
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
                    final saved = await StorageService.updateWedding(
                      updatedWedding,
                    );
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

    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final expandedHeight = screenWidth < 420
      ? 520.0
      : screenWidth < 700
      ? 600.0
      : screenWidth < 1200
      ? 660.0
      : 720.0;
    final countdown = _countdownParts();
    final heroImageUrl = _wedding!.coverImageUrl ?? _defaultHeroImage;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F9),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: expandedHeight,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Inställningar',
                onPressed: _openSettingsDialog,
              ),
              IconButton(
                icon: const Icon(Icons.people),
                tooltip: 'Gästlista',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GuestListPage(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logga ut',
                onPressed: _logout,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: _showHero ? 1 : 0),
                    duration: const Duration(milliseconds: 1350),
                    curve: Curves.easeOutQuart,
                    builder: (context, progress, child) {
                      final eased = Curves.easeOutQuart.transform(progress);
                      return Opacity(opacity: eased, child: child);
                    },
                    child: Image.network(
                      heroImageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _coverBackgroundColor.withValues(alpha: 0.95),
                                const Color(0xFFF3D8E6),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x33000000), Color(0xB5000000)],
                        stops: [0.15, 1],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      kToolbarHeight + MediaQuery.of(context).padding.top + 28,
                      24,
                      48,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildStaggerItem(
                              step: 0,
                              child: Text(
                                '${_wedding!.partner1} & ${_wedding!.partner2}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: screenWidth < 600 ? 42 : 68,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white,
                                  height: 1,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black38,
                                      blurRadius: 18,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _buildStaggerItem(
                              step: 1,
                              child: Text(
                                'We joyfully invite you to share in our\nhappiness as we unite in marriage.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: screenWidth < 600 ? 17 : 22,
                                  color: const Color(0xFFF7EEEE),
                                  height: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildStaggerItem(
                              step: 2,
                              child: _buildConfettiDivider(color: Colors.white70),
                            ),
                            const SizedBox(height: 24),
                            _buildStaggerItem(
                              step: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.28),
                                  ),
                                ),
                                child: Text(
                                  '${_wedding!.dateStr} ${_wedding!.timeStr == 'Ej satt' ? '' : '• ${_wedding!.timeStr}'}'
                                      .trim(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 34),
                            _buildStaggerItem(
                              step: 4,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 30,
                                runSpacing: 18,
                                children: [
                                  _buildHeroStat('${countdown['days']}', 'DAYS'),
                                  _buildHeroStat('${countdown['hours']}', 'HOURS'),
                                  _buildHeroStat('${countdown['minutes']}', 'MINUTES'),
                                  _buildHeroStat('${countdown['seconds']}', 'SECONDS'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: AnimatedOpacity(
                      opacity: _staggerStep >= 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 780),
                      curve: Curves.easeOut,
                      child: FloatingActionButton.small(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.pink.shade500,
                        heroTag: 'upload_btn',
                        onPressed: _openCoverSettingsMenu,
                        child: const Icon(Icons.camera_alt),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                child: Builder(
                  builder: (context) {
                    final coupleCards = Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 28,
                      runSpacing: 28,
                      children: [
                        _buildCoupleCard(
                          name: _wedding!.partner1,
                          icon: Icons.local_florist,
                          accent: const Color(0xFFE4A7B6),
                          lines: [
                            'Ser fram emot att dela denna dag',
                            'med familj och vänner.',
                          ],
                        ),
                        _buildCoupleCard(
                          name: _wedding!.partner2,
                          icon: Icons.favorite,
                          accent: const Color(0xFFD6A35D),
                          lines: [
                            'Tack för att ni är med och gör',
                            'firandet ännu mer minnesvärt.',
                          ],
                        ),
                      ],
                    );

                    final detailTiles = <Widget>[
                      _buildInfoTile(
                        icon: Icons.groups_2_outlined,
                        title: 'Dela koden med gäster',
                        subtitle: _wedding!.code,
                        accent: Colors.pink.shade400,
                        trailing: IconButton.filledTonal(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Kopiera kod',
                          onPressed: _copyWeddingCode,
                        ),
                      ),
                      _buildInfoTile(
                        icon: Icons.calendar_month,
                        title: 'Vår bröllopsdag',
                        subtitle: '${_wedding!.dateStr}\nTid: ${_wedding!.timeStr}',
                        accent: Colors.pink.shade400,
                      ),
                    ];

                    if (_wedding!.churchAddress.isNotEmpty) {
                      detailTiles.add(
                        _buildInfoTile(
                          icon: Icons.church,
                          title: 'Ceremoni',
                          subtitle: _wedding!.churchAddress,
                          accent: Colors.blue.shade400,
                          trailing: const Icon(
                            Icons.open_in_new,
                            color: Colors.grey,
                          ),
                          onTap: () => _openMap(_wedding!.churchAddress),
                        ),
                      );
                    }

                    if (_wedding!.venueAddress.isNotEmpty) {
                      detailTiles.add(
                        _buildInfoTile(
                          icon: Icons.celebration,
                          title: 'Mottagning / Festlokal',
                          subtitle: _wedding!.venueAddress,
                          accent: Colors.orange.shade400,
                          trailing: const Icon(
                            Icons.open_in_new,
                            color: Colors.grey,
                          ),
                          onTap: () => _openMap(_wedding!.venueAddress),
                        ),
                      );
                    }

                    final sectionWidgets = <Widget>[
                      _buildSectionTitle(
                        title: 'Meet The Happy Couple',
                        subtitle: 'Get to know them even better.',
                      ),
                      const SizedBox(height: 18),
                      coupleCards,
                      const SizedBox(height: 40),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 28,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEC6D3),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x12B57C8C),
                              blurRadius: 30,
                              offset: Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Our Wedding Day',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _wedding!.dateStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildConfettiDivider(color: Colors.white70),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 14,
                              runSpacing: 14,
                              children: [
                                Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white70,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: _buildHeroStat(
                                      '${countdown['days']}',
                                      'DAYS',
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white70,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: _buildHeroStat(
                                      '${countdown['hours']}',
                                      'HOURS',
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white70,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: _buildHeroStat(
                                      '${countdown['minutes']}',
                                      'MINUTES',
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white70,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: _buildHeroStat(
                                      '${countdown['seconds']}',
                                      'SECONDS',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      ...detailTiles,
                      const SizedBox(height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Itinerary',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2B1F26),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.edit_calendar,
                              color: Colors.pink,
                            ),
                            onPressed: _openItineraryDialog,
                          ),
                        ],
                      ),
                    ];

                    if (_wedding!.itinerary.isEmpty) {
                      sectionWidgets.add(
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Inget schema är satt ännu.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      );
                    } else {
                      for (final event in _wedding!.itinerary) {
                        sectionWidgets.add(_buildScheduleItem(event));
                      }
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < sectionWidgets.length; i++) ...[
                          _buildStaggerItem(step: i, child: sectionWidgets[i]),
                          if (i == 0)
                            const SizedBox(height: 10)
                          else if (i == sectionWidgets.length - 1)
                            const SizedBox.shrink()
                          else
                            const SizedBox(height: 8),
                          if (i == sectionWidgets.length - 3 &&
                              sectionWidgets.length > 4)
                            const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
