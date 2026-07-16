import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/wedding_model.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';
import '../widgets/app_labeled_text_field.dart';
import '../widgets/date_time_picker_buttons.dart';
import '../widgets/dialog_action_buttons.dart';
import '../widgets/dialog_title_with_close.dart';
import '../widgets/language_toggle_button.dart';
import '../widgets/preset_options_input.dart';
import 'guest_list_page.dart';
import 'onboarding_page.dart';
import 'table_floor_plan_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  static const String _defaultHeroImage =
      'https://images.unsplash.com/photo-1511285560929-80b456fea0bc?auto=format&fit=crop&w=1600&q=80';
  Wedding? _wedding;
  bool _isAdmin = false;
  bool _isLoading = true;
  Color _coverBackgroundColor = const Color(0xFFFCE4EC);
  bool _showHero = false;
  int _staggerStep = -1;
  Timer? _countdownTimer;

  static const List<String> _itineraryCategoryKeys = [
    'landing_category_welcome_drink',
    'landing_category_guest_arrival',
    'landing_category_ceremony',
    'landing_category_confetti',
    'landing_category_group_photo',
    'landing_category_couple_photo',
    'landing_category_reception',
    'landing_category_mingle',
    'landing_category_canapes',
    'landing_category_toastmaster_intro',
    'landing_category_starter',
    'landing_category_interlude',
    'landing_category_main_course',
    'landing_category_dessert',
    'landing_category_cake',
    'landing_category_coffee',
    'landing_category_open_bar',
    'landing_category_toast',
    'landing_category_speech',
    'landing_category_quiz',
    'landing_category_games',
    'landing_category_live_music',
    'landing_category_first_dance',
    'landing_category_dance',
    'landing_category_dj_set',
    'landing_category_late_night_snack',
    'landing_category_afterparty',
    'landing_category_farewell',
  ];

  @override
  void initState() {
    super.initState();
    _loadWeddingData();
  }

  void _loadWeddingData() async {
    Wedding? w = await StorageService.getActiveWedding();
    Color bgColor = const Color(0xFFFCE4EC);
    bool isAdmin = false;
    if (w != null) {
      final savedBg = await StorageService.getCoverBackgroundColorValue(w.id);
      if (savedBg != null) {
        bgColor = Color(savedBg);
      }
      isAdmin = await StorageService.isAdminForWedding(w);
    }

    setState(() {
      _wedding = w;
      _isAdmin = isAdmin;
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

  bool _isNotSetValue(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized.isEmpty || normalized == 'ej satt' || normalized == 'not set';
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

  String _itineraryEventTitle(
    Map<String, dynamic> event,
    AppLocalizationsController localizations,
  ) {
    final categoryKey = event['categoryKey']?.toString();
    if (categoryKey != null && categoryKey.isNotEmpty) {
      return localizations.text(categoryKey);
    }

    final rawTitle = (event['title'] ?? '').toString();
    final localizedFromRawKey = localizations.text(rawTitle);
    if (localizedFromRawKey != rawTitle) {
      return localizedFromRawKey;
    }

    final resolvedCategoryKey = localizations.keyForValue(
      rawTitle,
      candidateKeys: _itineraryCategoryKeys,
    );
    if (resolvedCategoryKey != null) {
      return localizations.text(resolvedCategoryKey);
    }

    return rawTitle;
  }

  Widget _buildScheduleItem(
    Map<String, dynamic> event,
    AppLocalizationsController localizations,
  ) {
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
              _itineraryEventTitle(event, localizations),
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
    final localizations = AppLocalizationsScope.of(context);

    setState(() => _isLoading = true);

    try {
      final updatedWedding = Wedding(
        id: _wedding!.id,
        partner1: _wedding!.partner1,
        partner2: _wedding!.partner2,
        dateStr: _wedding!.dateStr,
        timeStr: _wedding!.timeStr,
        code: _wedding!.code,
        adminCode: _wedding!.adminCode,
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
          content: Text(
            localizations.text(
              'landing_cover_settings_update_failed',
              values: {'error': '$e'},
            ),
          ),
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

  Future<void> _copyAdminCode() async {
    final localizations = AppLocalizationsScope.of(context);
    if (_wedding == null) return;

    final adminCode = await StorageService.getCachedAdminCode(_wedding!.id);
    if (adminCode == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.text('admin_code_not_cached'))),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: adminCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.text('admin_code_copied'))),
    );
  }

  Future<void> _showAdminCodeDialog() async {
    if (_wedding == null) return;
    final adminCode = await StorageService.getCachedAdminCode(_wedding!.id);
    if (!mounted) return;
    final localizations = AppLocalizationsScope.of(context);

    if (adminCode == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.text('admin_code_not_cached'))),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: DialogTitleWithClose(
          titleText: localizations.text('admin_code_title'),
          onClose: () => Navigator.pop(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.text('admin_code_hint')),
            const SizedBox(height: 12),
            SelectableText(
              adminCode,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              _copyAdminCode();
              Navigator.pop(dialogContext);
            },
            icon: const Icon(Icons.copy),
            label: Text(localizations.text('copy_admin_code')),
          ),
        ],
      ),
    );
  }

  Future<void> _openAdminUnlockDialog() async {
    if (_wedding == null) return;
    final localizations = AppLocalizationsScope.of(context);
    final codeController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: DialogTitleWithClose(
          titleText: localizations.text('admin_unlock_title'),
          onClose: () => Navigator.pop(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.text('admin_unlock_hint')),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: InputDecoration(
                labelText: localizations.text('admin_code_label'),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          DialogConfirmButton(
            label: localizations.text('unlock_admin_mode'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(dialogContext);
              final unlocked = await StorageService.unlockAdminForWedding(
                _wedding!,
                codeController.text,
              );
              if (!mounted) return;

              if (!unlocked) {
                messenger.showSnackBar(
                  SnackBar(content: Text(localizations.text('admin_unlock_failed'))),
                );
                return;
              }

              setState(() => _isAdmin = true);
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text(localizations.text('admin_unlock_success'))),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _leaveAdminMode() async {
    if (_wedding == null) return;
    final localizations = AppLocalizationsScope.of(context);
    await StorageService.clearAdminForWedding(_wedding!.id);
    if (!mounted) return;
    setState(() => _isAdmin = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.text('admin_mode_disabled'))),
    );
  }

  void _openSettingsEntry() {
    if (_isAdmin) {
      _openSettingsDialog();
      return;
    }

    _openAdminUnlockDialog();
  }

  // Ny funktion för att öppna kartor
  Future<void> _openMap(String address) async {
    final localizations = AppLocalizationsScope.of(context);
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
            SnackBar(content: Text(localizations.text('landing_map_open_failed'))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.text('landing_map_open_error'))),
        );
      }
    }
  }

  Future<void> _uploadNewCover() async {
    final localizations = AppLocalizationsScope.of(context);
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
        SnackBar(content: Text(localizations.text('landing_cover_read_failed'))),
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
            uploadResult.errorMessage ?? localizations.text('landing_cover_upload_failed'),
          ),
        ),
      );
      return;
    }

    await _saveWeddingWithCover(coverImageUrl: uploadResult.publicUrl);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.text('landing_cover_updated'))),
    );
  }

  Future<void> _openCoverSettingsMenu() async {
    if (_wedding == null) return;
    final localizations = AppLocalizationsScope.of(context);

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
                title: Text(localizations.text('landing_cover_pick_uploaded')),
                onTap: () => Navigator.pop(context, 'pick_existing'),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: Text(localizations.text('landing_cover_upload_new')),
                onTap: () => Navigator.pop(context, 'upload_new'),
              ),
              ListTile(
                leading: const Icon(Icons.color_lens_outlined),
                title: Text(localizations.text('landing_cover_pick_background')),
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
    final localizations = AppLocalizationsScope.of(context);

    final imageUrls = await StorageService.listCoverImageUrls(_wedding!.id);
    if (!mounted) return;

    if (imageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.text('landing_cover_no_uploaded_images'))),
      );
      return;
    }

    final selectedUrl = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final mutableImageUrls = List<String>.from(imageUrls);

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: DialogTitleWithClose(
              titleText: localizations.text('landing_cover_select'),
              onClose: () => Navigator.pop(dialogContext),
            ),
            content: SizedBox(
              width: 520,
              height: 380,
              child: mutableImageUrls.isEmpty
                  ? Center(child: Text(localizations.text('landing_cover_no_images_left')))
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
                                          title: DialogTitleWithClose(
                                            titleText: localizations.text('landing_cover_delete_title'),
                                            onClose: () => Navigator.pop(confirmContext),
                                          ),
                                          content: Text(localizations.text('landing_cover_delete_confirm')),
                                          actions: [
                                            DialogConfirmButton(
                                              label: localizations.text('yes'),
                                              onPressed: () => Navigator.pop(confirmContext, true),
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
                                          SnackBar(content: Text(localizations.text('landing_cover_deleted'))),
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(this.context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              localizations.text(
                                                'landing_cover_delete_failed',
                                                values: {'error': '$e'},
                                              ),
                                            ),
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
          ),
        );
      },
    );

    if (selectedUrl == null || !mounted) return;
    await _saveWeddingWithCover(coverImageUrl: selectedUrl);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.text('landing_cover_selected_uploaded'))),
    );
  }

  Future<void> _openCoverColorPicker() async {
    final localizations = AppLocalizationsScope.of(context);
    Color pickedColor = _coverBackgroundColor;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: DialogTitleWithClose(
          titleText: localizations.text('landing_cover_color_title'),
          onClose: () => Navigator.pop(dialogContext),
        ),
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
          DialogConfirmButton(
            label: localizations.text('save'),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );

    if (shouldSave != true || !mounted) return;
    await _saveWeddingWithCover(coverBackgroundColor: pickedColor);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.text('landing_background_updated'))),
    );
  }

  // Den stora inställningsmenyn för Bröllopet
  void _openSettingsDialog() {
    final localizations = AppLocalizationsScope.of(context);
    final p1Ctrl = TextEditingController(text: _wedding!.partner1);
    final p2Ctrl = TextEditingController(text: _wedding!.partner2);
    final churchCtrl = TextEditingController(text: _wedding!.churchAddress);
    final venueCtrl = TextEditingController(text: _wedding!.venueAddress);

    DateTime? selectedDate = DateTime.tryParse(_wedding!.dateStr);
    TimeOfDay? selectedTime;
    if (!_isNotSetValue(_wedding!.timeStr) && _wedding!.timeStr.contains(':')) {
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
            title: DialogTitleWithClose(
              titleText: localizations.text('landing_wedding_details_edit_title'),
              onClose: () => Navigator.pop(ctx),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F3F4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizations.text('admin_settings_title'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                localizations.text('admin_settings_hint'),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _showAdminCodeDialog,
                              icon: const Icon(Icons.visibility_outlined),
                              label: Text(localizations.text('show_admin_code')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AppLabeledTextField(
                    controller: p1Ctrl,
                    labelText: localizations.text('landing_partner_1'),
                  ),
                  AppLabeledTextField(
                    controller: p2Ctrl,
                    labelText: localizations.text('landing_partner_2'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DatePickerOutlinedButton(
                          selectedDate: selectedDate,
                          pickDateLabel: localizations.text('pick_date'),
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          onPicked: (picked) {
                            setDialogState(() => selectedDate = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TimePickerOutlinedButton(
                          selectedTime: selectedTime,
                          pickTimeLabel: localizations.text('pick_time'),
                          initialTime: const TimeOfDay(hour: 15, minute: 0),
                          onPicked: (picked) {
                            setDialogState(() => selectedTime = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppLabeledTextField(
                    controller: churchCtrl,
                    labelText: localizations.text('landing_ceremony_address'),
                  ),
                  AppLabeledTextField(
                    controller: venueCtrl,
                    labelText: localizations.text('landing_venue_address'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _leaveAdminMode();
                },
                child: Text(localizations.text('leave_admin_mode')),
              ),
              DialogConfirmButton(
                label: localizations.text('save'),
                onPressed: () async {
                  final navigator = Navigator.of(ctx);
                  final messenger = ScaffoldMessenger.of(context);

                  final updatedWedding = Wedding(
                    id: _wedding!.id,
                    partner1: p1Ctrl.text.trim(),
                    partner2: p2Ctrl.text.trim(),
                    dateStr: selectedDate != null
                        ? formatIsoDate(selectedDate!)
                      : localizations.text('not_set'),
                    timeStr: selectedTime != null
                        ? formatHHmm(selectedTime!)
                      : localizations.text('not_set'),
                    code: _wedding!.code,
                    adminCode: _wedding!.adminCode,
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
                      SnackBar(content: Text(localizations.text('landing_details_updated'))),
                    );
                  } catch (e) {
                    setState(() => _isLoading = false);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          localizations.text('error_with_message', values: {'error': '$e'}),
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyWeddingCode() async {
    final localizations = AppLocalizationsScope.of(context);
    final code = _wedding?.code.trim() ?? '';
    if (code.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.text('landing_wedding_code_copied'))),
    );
  }

  // Schema (Itinerary) hanteraren
  void _openItineraryDialog() {
    final localizations = AppLocalizationsScope.of(context);
    List<Map<String, dynamic>> tempItinerary = List<Map<String, dynamic>>.from(
      _wedding!.itinerary,
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> openEditEventDialog(int index) async {
            final existingEvent = tempItinerary[index];
            List<String> selectedTitle = <String>[
              _itineraryEventTitle(existingEvent, localizations),
            ];

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
                  title: DialogTitleWithClose(
                    titleText: localizations.text('landing_event_edit_title'),
                    onClose: () => Navigator.pop(editCtx),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TimePickerOutlinedButton(
                        selectedTime: selectedTime,
                        pickTimeLabel: localizations.text('pick_time'),
                        initialTime: selectedTime,
                        onPicked: (picked) {
                          setEditState(() => selectedTime = picked);
                        },
                      ),
                      const SizedBox(height: 12),
                      PresetOptionsInput(
                        labelText: localizations.text('landing_event_label'),
                        hintText: localizations.text('preset_custom_hint'),
                        options: _itineraryCategoryKeys
                            .map((key) => localizations.text(key))
                            .toList(),
                        selectedValues: selectedTitle,
                        onChanged: (values) {
                          setEditState(() {
                            selectedTitle = values;
                          });
                        },
                        multiSelect: false,
                      ),
                    ],
                  ),
                  actions: [
                    DialogConfirmButton(
                      label: localizations.text('save'),
                      onPressed: () => Navigator.pop(editCtx, true),
                    ),
                  ],
                ),
              ),
            );

            if (shouldSave != true) {
              return;
            }

            final updatedTitle =
                selectedTitle.isEmpty ? '' : selectedTitle.first.trim();
            if (updatedTitle.isNotEmpty) {
              setDialogState(() {
                final mappedKey =
                    localizations.keyForValue(
                      updatedTitle,
                      candidateKeys: _itineraryCategoryKeys,
                    ) ??
                    '';
                tempItinerary[index] = {
                  'time': formatHHmm(selectedTime),
                  if (mappedKey.isNotEmpty) 'categoryKey': mappedKey,
                  'title': mappedKey.isEmpty ? updatedTitle : '',
                };
                tempItinerary.sort(
                  (a, b) =>
                      a['time'].toString().compareTo(b['time'].toString()),
                );
              });
            }
          }

          void openAddEventDialog() {
            TimeOfDay? eventTime;
            List<String> selectedCategory = <String>[];

            showDialog(
              context: ctx,
              builder: (addCtx) => StatefulBuilder(
                builder: (context, setAddState) {
                  return AlertDialog(
                    title: DialogTitleWithClose(
                      titleText: localizations.text('landing_event_add_title'),
                      onClose: () => Navigator.pop(addCtx),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                          TimePickerOutlinedButton(
                            selectedTime: eventTime,
                            pickTimeLabel: localizations.text('pick_time'),
                            required: true,
                            initialTime: const TimeOfDay(hour: 15, minute: 0),
                            onPicked: (picked) {
                              setAddState(() => eventTime = picked);
                            },
                        ),
                        const SizedBox(height: 16),
                        PresetOptionsInput(
                          labelText: localizations.text('landing_event_category'),
                          hintText: localizations.text('preset_custom_hint'),
                          options: _itineraryCategoryKeys
                              .map((key) => localizations.text(key))
                              .toList(),
                          selectedValues: selectedCategory,
                          onChanged: (values) {
                            setAddState(() {
                              if (values.isEmpty) {
                                selectedCategory = <String>[];
                                return;
                              }
                              selectedCategory = <String>[values.first];
                            });
                          },
                          multiSelect: false,
                        ),
                      ],
                    ),
                    actions: [
                      DialogConfirmButton(
                        label: localizations.text('add'),
                        onPressed: eventTime == null || selectedCategory.isEmpty
                            ? null
                            : () {
                                final rawChoice =
                                    selectedCategory.isEmpty ? '' : selectedCategory.first;
                                if (rawChoice.isNotEmpty) {
                                  final mappedKey =
                                      localizations.keyForValue(
                                        rawChoice,
                                        candidateKeys: _itineraryCategoryKeys,
                                      ) ??
                                      '';
                                  final isPreset = mappedKey.isNotEmpty;
                                  setDialogState(() {
                                    tempItinerary.add({
                                      'time': formatHHmm(eventTime!),
                                      if (isPreset) 'categoryKey': mappedKey,
                                      'title': isPreset ? '' : rawChoice,
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
                      ),
                    ],
                  );
                },
              ),
            );
          }

          return AlertDialog(
            title: DialogTitleWithClose(
              titleText: localizations.text('landing_itinerary_manage_title'),
              onClose: () => Navigator.pop(ctx),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: tempItinerary.isEmpty
                  ? Center(
                      child: Text(
                        localizations.text('landing_itinerary_empty'),
                        style: const TextStyle(color: Colors.grey),
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
                          title: Text(_itineraryEventTitle(event, localizations)),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blueGrey),
                                tooltip: localizations.text('edit'),
                                onPressed: () => openEditEventDialog(i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: localizations.text('delete'),
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
                child: Text(localizations.text('landing_event_new')),
              ),
              DialogConfirmButton(
                label: localizations.text('save'),
                onPressed: () async {
                  final nav = Navigator.of(ctx);
                  final updatedWedding = Wedding(
                    id: _wedding!.id,
                    partner1: _wedding!.partner1,
                    partner2: _wedding!.partner2,
                    dateStr: _wedding!.dateStr,
                    timeStr: _wedding!.timeStr,
                    code: _wedding!.code,
                    adminCode: _wedding!.adminCode,
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
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizationsScope.of(context);
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
              const LanguageToggleButton(),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: localizations.text('landing_settings'),
                onPressed: _openSettingsEntry,
              ),
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.people),
                  tooltip: localizations.text('landing_guest_list'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GuestListPage(),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: localizations.text('landing_logout'),
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
                                localizations.text('landing_hero_invitation_text'),
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
                                  '${_wedding!.dateStr} ${_isNotSetValue(_wedding!.timeStr) ? '' : '• ${_wedding!.timeStr}'}'
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
                                  _buildHeroStat('${countdown['days']}', localizations.text('countdown_days')),
                                  _buildHeroStat('${countdown['hours']}', localizations.text('countdown_hours')),
                                  _buildHeroStat('${countdown['minutes']}', localizations.text('countdown_minutes')),
                                  _buildHeroStat('${countdown['seconds']}', localizations.text('countdown_seconds')),
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
                            localizations.text('landing_partner1_line1'),
                            localizations.text('landing_partner1_line2'),
                          ],
                        ),
                        _buildCoupleCard(
                          name: _wedding!.partner2,
                          icon: Icons.favorite,
                          accent: const Color(0xFFD6A35D),
                          lines: [
                            localizations.text('landing_partner2_line1'),
                            localizations.text('landing_partner2_line2'),
                          ],
                        ),
                      ],
                    );

                    final detailTiles = <Widget>[
                      if (_isAdmin)
                        _buildInfoTile(
                          icon: Icons.groups_2_outlined,
                          title: localizations.text('landing_share_code_title'),
                          subtitle: _wedding!.code,
                          accent: Colors.pink.shade400,
                          trailing: IconButton.filledTonal(
                            icon: const Icon(Icons.copy),
                            tooltip: localizations.text('landing_copy_code'),
                            onPressed: _copyWeddingCode,
                          ),
                        ),
                      _buildInfoTile(
                        icon: Icons.calendar_month,
                        title: localizations.text('landing_wedding_day_title'),
                        subtitle:
                            '${_wedding!.dateStr}\n${localizations.text('landing_time_prefix')}: ${_wedding!.timeStr}',
                        accent: Colors.pink.shade400,
                      ),
                      _buildInfoTile(
                        icon: Icons.grid_view_rounded,
                        title: localizations.text('landing_floor_plan_title'),
                        subtitle: localizations.text('landing_floor_plan_subtitle'),
                        accent: Colors.teal.shade400,
                        trailing: const Icon(
                          Icons.open_in_new,
                          color: Colors.grey,
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TableFloorPlanPage(
                              weddingId: _wedding!.id,
                              readOnly: !_isAdmin,
                            ),
                          ),
                        ),
                      ),
                    ];

                    if (_wedding!.churchAddress.isNotEmpty) {
                      detailTiles.add(
                        _buildInfoTile(
                          icon: Icons.church,
                          title: localizations.text('landing_ceremony_title'),
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
                          title: localizations.text('landing_reception_title'),
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
                        title: localizations.text('landing_meet_couple_title'),
                        subtitle: localizations.text('landing_meet_couple_subtitle'),
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
                              localizations.text('landing_our_wedding_day'),
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
                                      localizations.text('countdown_days'),
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
                                      localizations.text('countdown_hours'),
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
                                      localizations.text('countdown_minutes'),
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
                                      localizations.text('countdown_seconds'),
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
                            localizations.text('landing_itinerary_title'),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2B1F26),
                            ),
                          ),
                          if (_isAdmin)
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
                            localizations.text('landing_itinerary_none_yet'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      );
                    } else {
                      for (final event in _wedding!.itinerary) {
                        sectionWidgets.add(_buildScheduleItem(event, localizations));
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
