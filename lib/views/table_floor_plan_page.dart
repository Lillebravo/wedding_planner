import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/guest_model.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';
import '../widgets/app_dropdown_form_field.dart';
import '../widgets/app_labeled_text_field.dart';
import '../widgets/dialog_action_buttons.dart';
import '../widgets/dialog_title_with_close.dart';
import '../widgets/language_toggle_button.dart';

class TableFloorPlanPage extends StatefulWidget {
  final String weddingId;
  final bool readOnly;

  const TableFloorPlanPage({
    super.key,
    required this.weddingId,
    this.readOnly = false,
  });

  @override
  State<TableFloorPlanPage> createState() => _TableFloorPlanPageState();
}

class _TableFloorPlanPageState extends State<TableFloorPlanPage> {
  static const Size _canvasSize = Size(1800, 1200);
  static const double _minScale = 0.35;
  static const double _maxScale = 2.6;

  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _floorPlanExportKey = GlobalKey();
  final GlobalKey _floorViewportKey = GlobalKey();

  List<Map<String, dynamic>> _tables = [];
  Map<String, Offset> _tablePositions = {};
  Map<String, List<Guest>> _guestsByTable = {};
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showGuests = true;
  double _currentScale = 1.0;

  static const TextStyle _guestNameTextStyle = TextStyle(
    fontSize: 10.8,
    fontWeight: FontWeight.w600,
    height: 1.0,
  );

  static const TextStyle _guestDietaryTextStyle = TextStyle(
    fontSize: 9.5,
    height: 1.0,
  );

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_handleTransformChanged);
    _loadData();
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if ((scale - _currentScale).abs() < 0.001) {
      return;
    }

    setState(() {
      _currentScale = scale;
    });
  }

  Future<void> _loadData() async {
    final loadedTables = await StorageService.getTables(widget.weddingId);
    final loadedGuests = await StorageService.getGuests(widget.weddingId);
    final savedLayout = await StorageService.getTableLayout(widget.weddingId);
    final savedShowGuests = await StorageService.getFloorPlanShowGuests(
      widget.weddingId,
    );
    final resolvedLayout = _resolveInitialLayout(loadedTables, savedLayout);
    final guestsByTable = _groupGuestsByTable(loadedGuests);

    if (!mounted) return;

    setState(() {
      _tables = loadedTables;
      _tablePositions = resolvedLayout;
      _guestsByTable = guestsByTable;
      _showGuests = widget.readOnly ? true : (savedShowGuests ?? true);
      _isLoading = false;
    });

    if (savedLayout.length != resolvedLayout.length &&
        resolvedLayout.isNotEmpty &&
        !widget.readOnly) {
      await StorageService.saveTableLayout(widget.weddingId, resolvedLayout);
    }
  }

  Map<String, List<Guest>> _groupGuestsByTable(List<Guest> guests) {
    final grouped = <String, List<Guest>>{};

    for (final guest in guests) {
      final tableId = guest.tableId?.trim();
      if (tableId == null || tableId.isEmpty) {
        continue;
      }

      grouped.putIfAbsent(tableId, () => <Guest>[]).add(guest);
    }

    for (final entry in grouped.entries) {
      entry.value.sort((a, b) {
        final aSeat = a.seatNumber ?? 9999;
        final bSeat = b.seatNumber ?? 9999;
        return aSeat.compareTo(bSeat);
      });
    }

    return grouped;
  }

  Map<String, Offset> _resolveInitialLayout(
    List<Map<String, dynamic>> tables,
    Map<String, Offset> savedLayout,
  ) {
    if (tables.isEmpty) {
      return <String, Offset>{};
    }

    final columns = math.max(2, math.min(4, math.sqrt(tables.length).ceil()));
    const horizontalSpacing = 360.0;
    const verticalSpacing = 250.0;
    const startX = 120.0;
    const startY = 120.0;

    final layout = <String, Offset>{};
    for (var index = 0; index < tables.length; index++) {
      final tableId = (tables[index]['id'] ?? '').toString();
      if (tableId.isEmpty) {
        continue;
      }

      final savedPosition = savedLayout[tableId];
      if (savedPosition != null) {
        layout[tableId] = savedPosition;
        continue;
      }

      final column = index % columns;
      final row = index ~/ columns;
      layout[tableId] = Offset(
        startX + (column * horizontalSpacing),
        startY + (row * verticalSpacing),
      );
    }

    return layout;
  }

  Size _tableVisualSize(Map<String, dynamic> table) {
    final seatCount = (table['seats'] as int?) ?? 8;
    final shape = (table['shape']?.toString() ?? 'rektangel').toLowerCase();
    final capacityBoost = (seatCount * 1.5).clamp(0.0, 36.0);

    switch (shape) {
      case 'cirkel':
        return Size(132 + capacityBoost, 132 + capacityBoost);
      case 'oval':
        return Size(186 + capacityBoost, 118 + (capacityBoost * 0.4));
      case 'kvadrat':
        return Size(140 + capacityBoost, 140 + capacityBoost);
      default:
        return Size(180 + capacityBoost, 112 + (capacityBoost * 0.35));
    }
  }

  Offset _clampPosition(Offset position, Size tableSize) {
    const padding = 24.0;
    final maxX = math.max(
      padding,
      _canvasSize.width - tableSize.width - padding,
    );
    final maxY = math.max(
      padding,
      _canvasSize.height - tableSize.height - padding,
    );

    return Offset(
      position.dx.clamp(padding, maxX),
      position.dy.clamp(padding, maxY),
    );
  }

  Future<void> _persistLayout({bool showFeedback = false}) async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await StorageService.saveTableLayout(widget.weddingId, _tablePositions);
      if (mounted && showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bordens placering sparad.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _exportFloorPlanAsPng() async {
    final localizations = AppLocalizationsScope.of(context);
    final boundary =
        _floorPlanExportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.text('export_png_failed'))),
      );
      return;
    }

    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Tom bilddata.');
      }

      final pngBytes = byteData.buffer.asUint8List();
      final fileName = 'golvvy_${DateTime.now().millisecondsSinceEpoch}';
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(pngBytes),
        fileExtension: 'png',
        mimeType: MimeType.png,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.text('exported_png'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${localizations.text('export_png_failed')}: $e')),
      );
    }
  }

  Future<void> _openTableFormDialog() async {
    final localizations = AppLocalizationsScope.of(context);
    final nameCtrl = TextEditingController(
      text: '${localizations.text('table_default_name_prefix')} ${_tables.length + 1}',
    );
    final seatsCtrl = TextEditingController(text: '8');
    const shapes = [
      {'value': 'Kvadrat', 'labelKey': 'table_square'},
      {'value': 'Rektangel', 'labelKey': 'table_rectangle'},
      {'value': 'Cirkel', 'labelKey': 'table_round'},
      {'value': 'Oval', 'labelKey': 'table_oval'},
    ];
    String selectedShape = 'Rektangel';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: DialogTitleWithClose(
              titleText: localizations.text('create_table'),
              onClose: () => Navigator.pop(dialogContext),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppLabeledTextField(
                  controller: nameCtrl,
                  labelText: localizations.text('table_name'),
                ),
                AppLabeledTextField(
                  controller: seatsCtrl,
                  labelText: localizations.text('table_seats'),
                  keyboardType: TextInputType.number,
                ),
                AppDropdownFormField<String>(
                  initialValue: selectedShape,
                  labelText: localizations.text('table_shape'),
                  items: shapes
                      .map(
                        (shape) => DropdownMenuItem(
                          value: shape['value'] as String,
                          child: Text(localizations.text(shape['labelKey'] as String)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => selectedShape = value ?? selectedShape),
                ),
              ],
            ),
            actions: [
              DialogConfirmButton(
                label: localizations.text('save'),
                onPressed: () async {
                  final seats = int.tryParse(seatsCtrl.text.trim()) ?? 0;
                  if (seats <= 0 || nameCtrl.text.trim().isEmpty) return;

                  Navigator.pop(dialogContext);
                  final newId = await StorageService.addTable(
                    widget.weddingId,
                    nameCtrl.text.trim(),
                    seats,
                    selectedShape,
                  );
                  if (newId.isEmpty) return;

                  final newTable = {
                    'id': newId,
                    'name': nameCtrl.text.trim(),
                    'seats': seats,
                    'shape': selectedShape,
                  };
                  final resolvedPosition = _clampPosition(
                    Offset(120 + (_tables.length * 40.0), 120 + (_tables.length * 28.0)),
                    _tableVisualSize(newTable),
                  );

                  setState(() {
                    _tables = [..._tables, newTable];
                    _tablePositions[newId] = resolvedPosition;
                  });
                  await StorageService.saveTableLayout(widget.weddingId, _tablePositions);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _resetZoom() {
    final renderObject = _floorViewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    final viewportSize = renderObject.size;
    if (viewportSize.isEmpty) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    final fitScale = math.min(
      viewportSize.width / _canvasSize.width,
      viewportSize.height / _canvasSize.height,
    );
    final targetScale = (fitScale * 0.94).clamp(_minScale, _maxScale);

    final dx = (viewportSize.width - (_canvasSize.width * targetScale)) / 2;
    final dy = (viewportSize.height - (_canvasSize.height * targetScale)) / 2;

    _transformationController.value = Matrix4.identity()
      ..scale(targetScale)
      ..setTranslationRaw(dx, dy, 0);
  }

  void _moveTable(String tableId, Offset delta) {
    final table = _tables.firstWhere(
      (item) => (item['id'] ?? '').toString() == tableId,
    );
    final currentPosition = _tablePositions[tableId] ?? const Offset(0, 0);
    final nextPosition = _clampPosition(
      currentPosition + (delta / _currentScale),
      _tableVisualSize(table),
    );

    setState(() {
      _tablePositions[tableId] = nextPosition;
    });
  }

  Rect _clampRectToCanvas(Rect rect) {
    final dx = rect.left < 0
        ? -rect.left
        : (rect.right > _canvasSize.width ? _canvasSize.width - rect.right : 0.0);
    final dy = rect.top < 0
        ? -rect.top
        : (rect.bottom > _canvasSize.height
              ? _canvasSize.height - rect.bottom
              : 0.0);
    return rect.shift(Offset(dx, dy));
  }

  double _rectOverlapArea(Rect a, Rect b) {
    final overlap = a.intersect(b);
    if (overlap.isEmpty) {
      return 0.0;
    }
    return overlap.width * overlap.height;
  }

  Rect _resolveGuestChipRect({
    required Offset seatCenter,
    required Offset direction,
    required bool alignRight,
    required double chipWidth,
    required double chipHeight,
    required double bubbleOffset,
    required List<Rect> placedRects,
  }) {
    final tangent = Offset(-direction.dy, direction.dx);
    final baseAnchor = seatCenter + direction * bubbleOffset;

    Rect buildRect(Offset anchor) {
      final left = alignRight ? anchor.dx - chipWidth : anchor.dx;
      final top = anchor.dy - (chipHeight / 2);
      return _clampRectToCanvas(Rect.fromLTWH(left, top, chipWidth, chipHeight));
    }

    final candidateShifts = <Offset>[const Offset(0, 0)];
    const lateralStep = 14.0;
    const radialStep = 10.0;
    for (int radial = 0; radial <= 4; radial++) {
      final radialShift = direction * (radial * radialStep);
      for (int lane = 1; lane <= 3; lane++) {
        final lateral = tangent * (lane * lateralStep);
        candidateShifts
          ..add(radialShift + lateral)
          ..add(radialShift - lateral);
      }
    }

    Rect? bestRect;
    double bestPenalty = double.infinity;

    for (final shift in candidateShifts) {
      final rect = buildRect(baseAnchor + shift);
      var penalty = 0.0;

      for (final placed in placedRects) {
        penalty += _rectOverlapArea(rect.inflate(4), placed.inflate(4));
      }

      if (penalty == 0) {
        return rect;
      }

      if (penalty < bestPenalty) {
        bestPenalty = penalty;
        bestRect = rect;
      }
    }

    return bestRect ?? buildRect(baseAnchor);
  }

  Size _measureGuestChipSize({
    required Guest guest,
    required TextScaler textScaler,
  }) {
    const horizontalPadding = 10.0;
    const verticalPadding = 5.0;
    const maxChipWidth = 420.0;

    final dietaryText = guest.dietaryRestrictions.join(', ').trim();
    final hasDietaryText = dietaryText.isNotEmpty;

    final namePainter = TextPainter(
      text: TextSpan(text: guest.fullName, style: _guestNameTextStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: maxChipWidth - (horizontalPadding * 2));

    final dietaryPainter = hasDietaryText
        ? (TextPainter(
            text: TextSpan(
              text: dietaryText,
              style: _guestDietaryTextStyle.copyWith(color: Colors.grey.shade700),
            ),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
            maxLines: 1,
          )..layout(maxWidth: maxChipWidth - (horizontalPadding * 2)))
        : null;

    final contentWidth = math.max(
      namePainter.width,
      dietaryPainter?.width ?? 0,
    );
    final width = (contentWidth + (horizontalPadding * 2)).clamp(120.0, maxChipWidth);

    final contentHeight = namePainter.height + (dietaryPainter?.height ?? 0);
    final spacingBetweenLines = hasDietaryText ? 2.0 : 0.0;
    final height = math.max(
      26.0,
      contentHeight + spacingBetweenLines + (verticalPadding * 2) + 2,
    );

    return Size(width, height);
  }

  List<int> _rectangularSeatDistribution(int seatCount, Size tableSize) {
    if (seatCount <= 0) return const [0, 0, 0, 0];

    final weights = [
      tableSize.width,
      tableSize.height,
      tableSize.width,
      tableSize.height,
    ];
    final totalWeight = weights.fold<double>(
      0.0,
      (sum, weight) => sum + weight,
    );
    final rawCounts = weights
        .map((weight) => seatCount * weight / totalWeight)
        .toList();
    final counts = rawCounts.map((value) => value.floor()).toList();

    int remainder =
        seatCount - counts.fold<int>(0, (sum, value) => sum + value);
    final remainderOrder = List<int>.generate(4, (index) => index)
      ..sort((a, b) {
        final aFraction = rawCounts[a] - counts[a];
        final bFraction = rawCounts[b] - counts[b];
        return bFraction.compareTo(aFraction);
      });

    for (final index in remainderOrder) {
      if (remainder <= 0) break;
      counts[index] += 1;
      remainder -= 1;
    }

    return counts;
  }

  List<double> _centeredSideOffsets(int count, double availableLength) {
    if (count <= 1) return const [0.0];

    final fillFactor = switch (count) {
      2 => 0.78,
      3 => 0.84,
      4 => 0.88,
      _ => 0.92,
    };
    final totalSpan = availableLength * fillFactor;
    final spacing = totalSpan / (count - 1);
    final start = -totalSpan / 2;

    return List<double>.generate(count, (index) => start + (index * spacing));
  }

  Offset _seatCenterForShape({
    required String shape,
    required Offset tableCenter,
    required Size tableSize,
    required int seatIndex,
    required int seatCount,
    required double seatRadius,
  }) {
    if (seatCount <= 0) return tableCenter;

    final normalizedShape = shape.toLowerCase();
    final progress = ((seatIndex + 0.5) / seatCount).clamp(0.0, 1.0);

    if (normalizedShape == 'cirkel' || normalizedShape == 'oval') {
      final angle = (-math.pi / 2) + (2 * math.pi * progress);
      final orbitRadiusX = (tableSize.width / 2) + seatRadius;
      final orbitRadiusY = (tableSize.height / 2) + seatRadius;
      return Offset(
        tableCenter.dx + orbitRadiusX * math.cos(angle),
        tableCenter.dy + orbitRadiusY * math.sin(angle),
      );
    }

    final seatsPerSide = _rectangularSeatDistribution(seatCount, tableSize);

    final halfWidth = tableSize.width / 2;
    final halfHeight = tableSize.height / 2;
    final sideOffset = seatRadius;

    final sideHorizontalInset = math.min(tableSize.width * 0.28, 40.0);
    final sideVerticalInset = math.min(tableSize.height * 0.28, 34.0);
    final topBottomAvailable = math.max(
      0.0,
      tableSize.width - (2 * sideHorizontalInset),
    );
    final leftRightAvailable = math.max(
      0.0,
      tableSize.height - (2 * sideVerticalInset),
    );

    int resolvedSeatIndex = seatIndex.clamp(0, seatCount - 1);

    if (resolvedSeatIndex < seatsPerSide[0]) {
      final count = seatsPerSide[0];
      final offsets = _centeredSideOffsets(count, topBottomAvailable);
      final x = (tableCenter.dx + offsets[resolvedSeatIndex]).clamp(
        tableCenter.dx - halfWidth + sideHorizontalInset,
        tableCenter.dx + halfWidth - sideHorizontalInset,
      );
      return Offset(x, tableCenter.dy - halfHeight - sideOffset);
    }
    resolvedSeatIndex -= seatsPerSide[0];

    if (resolvedSeatIndex < seatsPerSide[1]) {
      final count = seatsPerSide[1];
      final offsets = _centeredSideOffsets(count, leftRightAvailable);
      final y = (tableCenter.dy + offsets[resolvedSeatIndex]).clamp(
        tableCenter.dy - halfHeight + sideVerticalInset,
        tableCenter.dy + halfHeight - sideVerticalInset,
      );
      return Offset(tableCenter.dx + halfWidth + sideOffset, y);
    }
    resolvedSeatIndex -= seatsPerSide[1];

    if (resolvedSeatIndex < seatsPerSide[2]) {
      final count = seatsPerSide[2];
      final offsets = _centeredSideOffsets(
        count,
        topBottomAvailable,
      ).reversed.toList();
      final x = (tableCenter.dx + offsets[resolvedSeatIndex]).clamp(
        tableCenter.dx - halfWidth + sideHorizontalInset,
        tableCenter.dx + halfWidth - sideHorizontalInset,
      );
      return Offset(x, tableCenter.dy + halfHeight + sideOffset);
    }
    resolvedSeatIndex -= seatsPerSide[2];

    final count = seatsPerSide[3];
    final offsets = _centeredSideOffsets(
      count,
      leftRightAvailable,
    ).reversed.toList();
    final y = (tableCenter.dy + offsets[resolvedSeatIndex]).clamp(
      tableCenter.dy - halfHeight + sideVerticalInset,
      tableCenter.dy + halfHeight - sideVerticalInset,
    );
    return Offset(tableCenter.dx - halfWidth - sideOffset, y);
  }

  Widget _buildHeader() {
    final localizations = AppLocalizationsScope.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF6F8), Color(0xFFF5F7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9D7DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  localizations.text('floor_plan_header'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              const LanguageToggleButton(),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _resetZoom,
                icon: const Icon(Icons.center_focus_strong),
                label: Text(localizations.text('center_view')),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _exportFloorPlanAsPng,
                icon: const Icon(Icons.image_outlined),
                label: Text(localizations.text('seating_chart_export_png')),
              ),
              const SizedBox(width: 8),
              if (!widget.readOnly) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFD8CDD0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.people_outline, size: 18),
                      const SizedBox(width: 6),
                      Text(localizations.text('show_guests')),
                      const SizedBox(width: 6),
                      Switch.adaptive(
                        value: _showGuests,
                        onChanged: (value) async {
                          setState(() {
                            _showGuests = value;
                          });
                          await StorageService.saveFloorPlanShowGuests(
                            widget.weddingId,
                            value,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (!widget.readOnly) ...[
                ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => _persistLayout(showFeedback: true),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(localizations.text('save')),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _openTableFormDialog(),
                  icon: const Icon(Icons.add),
                  label: Text(localizations.text('add_table')),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.readOnly
                ? localizations.text('floor_plan_read_only_hint')
                : localizations.text('floor_plan_help'),
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildFloorCanvas() {
    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: _minScale,
      maxScale: _maxScale,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(520),
      child: RepaintBoundary(
        key: _floorPlanExportKey,
        child: SizedBox(
          width: _canvasSize.width,
          height: _canvasSize.height,
          child: Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: _FloorGridPainter()),
              ),
              ..._tables.map(_buildTableNode),
              if (_showGuests) ..._tables.expand(_buildGuestNodesForTable),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGuestNodesForTable(Map<String, dynamic> table) {
    final tableId = (table['id'] ?? '').toString();
    if (tableId.isEmpty) {
      return const <Widget>[];
    }

    final shape = (table['shape']?.toString() ?? 'Rektangel').toLowerCase();
    final position = _tablePositions[tableId] ?? const Offset(0, 0);
    final size = _tableVisualSize(table);
    final seats = (table['seats'] as int?) ?? 0;
    final assignedGuests = _guestsByTable[tableId] ?? <Guest>[];
    if (assignedGuests.isEmpty) {
      return const <Widget>[];
    }

    final seatCountForLayout = math.max(seats, assignedGuests.length);
    final tableCenter = Offset(
      position.dx + (size.width / 2),
      position.dy + (size.height / 2),
    );
    final textScaler = MediaQuery.textScalerOf(context);
    const seatRadius = 12.0;
    final bubbleOffset = math.max(size.shortestSide * 0.22, 34.0);
    final placedChipRects = <Rect>[];

    return List<Widget>.generate(assignedGuests.length, (index) {
      final guest = assignedGuests[index];
      final seatCenter = _seatCenterForShape(
        shape: shape,
        tableCenter: tableCenter,
        tableSize: size,
        seatIndex: index,
        seatCount: seatCountForLayout,
        seatRadius: seatRadius,
      );

      final vector = seatCenter - tableCenter;
      final vectorLength = vector.distance;
      final direction = vectorLength == 0
          ? const Offset(0, -1)
          : Offset(vector.dx / vectorLength, vector.dy / vectorLength);

      final alignRight = direction.dx < 0;
      final dietaryText = guest.dietaryRestrictions.join(', ').trim();
      final hasDietaryText = dietaryText.isNotEmpty;
      final chipSize = _measureGuestChipSize(guest: guest, textScaler: textScaler);
      final chipRect = _resolveGuestChipRect(
        seatCenter: seatCenter,
        direction: direction,
        alignRight: alignRight,
        chipWidth: chipSize.width,
        chipHeight: chipSize.height,
        bubbleOffset: seatRadius + bubbleOffset,
        placedRects: placedChipRects,
      );
      placedChipRects.add(chipRect);

      final edgePoint = Offset(
        seatCenter.dx.clamp(chipRect.left, chipRect.right),
        seatCenter.dy.clamp(chipRect.top, chipRect.bottom),
      );
      final connectorVector = edgePoint - seatCenter;
      final connectorDistance = connectorVector.distance;
      final connectorDirection = connectorDistance == 0
          ? direction
          : Offset(
              connectorVector.dx / connectorDistance,
              connectorVector.dy / connectorDistance,
            );
      final connectorStart = seatCenter + connectorDirection * seatRadius;
      final connectorLength = math.max(0.0, (edgePoint - connectorStart).distance);
      final connectorAngle = math.atan2(
        edgePoint.dy - connectorStart.dy,
        edgePoint.dx - connectorStart.dx,
      );

      return Stack(
        children: [
          Positioned(
            left: connectorStart.dx,
            top: connectorStart.dy - 1,
            child: Transform.rotate(
              angle: connectorAngle,
              alignment: Alignment.centerLeft,
              child: Container(
                width: connectorLength,
                height: 2,
                color: const Color(0xFFCFCFCF),
              ),
            ),
          ),
          Positioned(
            left: seatCenter.dx - seatRadius,
            top: seatCenter.dy - seatRadius,
            child: Container(
              width: seatRadius * 2,
              height: seatRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: guest.isLocked
                    ? const Color(0xFFFFD8A8)
                    : const Color(0xFFDDE7FF),
                border: Border.all(
                  color: guest.isLocked
                      ? const Color(0xFFE39B3A)
                      : const Color(0xFF90A9E8),
                ),
              ),
              child: Center(
                child: Text(
                  '${guest.seatNumber ?? index + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: chipRect.left,
            top: chipRect.top,
            child: Container(
              width: chipSize.width,
              constraints: BoxConstraints(minHeight: chipSize.height),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDADADA)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: hasDietaryText ? 2 : 1,
                    overflow: TextOverflow.visible,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: guest.fullName,
                          style: _guestNameTextStyle,
                        ),
                        if (hasDietaryText)
                          TextSpan(
                            text: '\n$dietaryText',
                            style: _guestDietaryTextStyle.copyWith(
                              color: Colors.grey.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildTableNode(Map<String, dynamic> table) {
    final localizations = AppLocalizationsScope.of(context);
    final tableId = (table['id'] ?? '').toString();
    final tableName = (table['name'] ?? 'Bord').toString();
    final shape = (table['shape']?.toString() ?? 'Rektangel').toLowerCase();
    final position = _tablePositions[tableId] ?? const Offset(0, 0);
    final size = _tableVisualSize(table);
    final seats = (table['seats'] as int?) ?? 0;
    final decoration = switch (shape) {
      'cirkel' => BoxDecoration(
        color: const Color(0xFFFFF5EA),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE3B56B), width: 2.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      'oval' => BoxDecoration(
        color: const Color(0xFFFFF7F0),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE3B56B), width: 2.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      'kvadrat' => BoxDecoration(
        color: const Color(0xFFF7F0FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC7A4F0), width: 2.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      _ => BoxDecoration(
        color: const Color(0xFFFFF2F4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7AAB9), width: 2.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
    };

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: widget.readOnly
            ? null
            : (details) => _moveTable(tableId, details.delta),
        onPanEnd: widget.readOnly ? null : (_) => _persistLayout(),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: decoration,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tableName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$seats ${seats == 1 ? localizations.text('table_singular') : localizations.text('table_plural')}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Icon(
                          widget.readOnly ? Icons.visibility : Icons.drag_indicator,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final localizations = AppLocalizationsScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(localizations.text('table_floor_plan_title'))),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF7F3F0), Color(0xFFFDFDFD)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    key: _floorViewportKey,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE7D7D0)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: _buildFloorCanvas(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloorGridPainter extends CustomPainter {
  const _FloorGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = const Color(0xFFF6F1EC);
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final finePaint = Paint()
      ..color = const Color(0x1A8B6F61)
      ..strokeWidth = 1;

    const gridStep = 48.0;
    for (double x = 0; x <= size.width; x += gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), finePaint);
    }
    for (double y = 0; y <= size.height; y += gridStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), finePaint);
    }

    final accentPaint = Paint()
      ..color = const Color(0x268B6F61)
      ..strokeWidth = 1.5;
    for (double x = 0; x <= size.width; x += gridStep * 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), accentPaint);
    }
    for (double y = 0; y <= size.height; y += gridStep * 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), accentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
