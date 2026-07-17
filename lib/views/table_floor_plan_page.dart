import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/guest_model.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';
import '../widgets/language_toggle_button.dart';
import '../widgets/table_form_dialog.dart';

class _SeatDropPayload {
  final Guest? guest;
  final bool createEmptyChair;

  const _SeatDropPayload.guest(this.guest) : createEmptyChair = false;

  const _SeatDropPayload.emptyChair()
      : guest = null,
        createEmptyChair = true;
}

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
  List<Guest> _allGuests = [];
  Map<String, List<Guest>> _guestsByTable = {};
  Set<String> _selectedTableIds = <String>{};
  String? _hoveredGuestId;
  bool _isDragging = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
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
      _allGuests = loadedGuests;
      _guestsByTable = guestsByTable;
      _showGuests = widget.readOnly ? true : (savedShowGuests ?? true);
      _isLoading = false;
      _hasUnsavedChanges = false;
    });
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
    late final Size baseSize;
    switch (shape) {
      case 'cirkel':
        baseSize = Size(132 + capacityBoost, 132 + capacityBoost);
        break;
      case 'oval':
        baseSize = Size(186 + capacityBoost, 118 + (capacityBoost * 0.4));
        break;
      case 'kvadrat':
        baseSize = Size(140 + capacityBoost, 140 + capacityBoost);
        break;
      default:
        baseSize = Size(180 + capacityBoost, 112 + (capacityBoost * 0.35));
        break;
    }
    return baseSize;
  }

  int _normalizedRotationDegrees(dynamic value) {
    final rawValue = value is num ? value.round() : int.tryParse('$value') ?? 0;
    final normalized = rawValue % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  int _tableRotationDegrees(Map<String, dynamic> table) {
    return _normalizedRotationDegrees(table['rotation_degrees']);
  }

  double _tableRotationRadians(Map<String, dynamic> table) {
    return _tableRotationDegrees(table) * math.pi / 180;
  }

  bool _usesShortSidePlacement(Map<String, dynamic> table) {
    return table['short_side_placement_enabled'] != false;
  }

  List<Guest> _tableGuests(String tableId) {
    return _guestsByTable.putIfAbsent(tableId, () => <Guest>[]);
  }

  String? _tableIdForGuest(Guest guest) {
    for (final entry in _guestsByTable.entries) {
      if (entry.value.any((item) => item.id == guest.id)) {
        return entry.key;
      }
    }
    return null;
  }

  Map<String, dynamic>? _tableById(String tableId) {
    for (final table in _tables) {
      if ((table['id'] ?? '').toString() == tableId) {
        return table;
      }
    }
    return null;
  }

  void _reindexGuestsForTable(Map<String, dynamic> table) {
    final tableId = (table['id'] ?? '').toString();
    if (tableId.isEmpty) return;
    final assigned = List<Guest>.from(_tableGuests(tableId));
    final seatLimit = (table['seats'] as int?) ?? assigned.length;
    final lockedBySeat = <int, Guest>{};
    final floatingGuests = <Guest>[];
    for (final guest in assigned) {
      final seatNumber = guest.seatNumber;
      if (guest.isLocked && seatNumber != null && seatNumber > 0) {
        lockedBySeat[seatNumber] = guest;
      } else {
        floatingGuests.add(guest);
      }
    }
    // Do NOT sort floatingGuests — preserve insertion order so the position
    // the user chose determines the final seat number, not stale seatNumbers.
    final reordered = <Guest>[];
    var floatingIndex = 0;
    final totalSeats = math.max(seatLimit, assigned.length);
    for (var seatNumber = 1; seatNumber <= totalSeats; seatNumber++) {
      final lockedGuest = lockedBySeat[seatNumber];
      if (lockedGuest != null) {
        lockedGuest.tableId = tableId;
        lockedGuest.seatNumber = seatNumber;
        reordered.add(lockedGuest);
        continue;
      }
      if (floatingIndex >= floatingGuests.length) continue;
      final guest = floatingGuests[floatingIndex++];
      guest.tableId = tableId;
      guest.seatNumber = seatNumber;
      reordered.add(guest);
    }
    _guestsByTable[tableId] = reordered;
  }

  void _markFloorPlanDirty() {
    setState(() {
      _hasUnsavedChanges = true;
      // A successful drop causes the LongPressDraggable to be removed from
      // the tree before its onDragEnd fires, so reset dragging state here.
      _isDragging = false;
      _hoveredGuestId = null;
    });
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
    final assignedGuests = List<Guest>.from(_tableGuests(tableId));
    final seatCountForLayout = math.max(seats, assignedGuests.length);
    if (seatCountForLayout <= 0) {
      return const <Widget>[];
    }

    final tableCenter = Offset(
      position.dx + (size.width / 2),
      position.dy + (size.height / 2),
    );
    final textScaler = MediaQuery.textScalerOf(context);
    const seatRadius = 12.0;
    final bubbleOffset = math.max(size.shortestSide * 0.22, 34.0);
    final placedChipRects = <Rect>[];
    final widgets = <Widget>[];

    final guestBySeat = <int, Guest>{
      for (final g in assignedGuests)
        if (g.seatNumber != null) g.seatNumber!: g,
    };

    for (var index = 0; index < seatCountForLayout; index++) {
      final guest = guestBySeat[index + 1];
      if (guest == null && !_isDragging) continue;
      final seatCenter = _seatCenterForShape(
        shape: shape,
        tableCenter: tableCenter,
        tableSize: size,
        seatIndex: index,
        seatCount: seatCountForLayout,
        seatRadius: seatRadius,
        shortSidePlacementEnabled: _usesShortSidePlacement(table),
        rotationRadians: _tableRotationRadians(table),
      );

      final vector = seatCenter - tableCenter;
      final vectorLength = vector.distance;
      final direction = vectorLength == 0
          ? const Offset(0, -1)
          : Offset(vector.dx / vectorLength, vector.dy / vectorLength);

      final seatTargetSize = seatRadius * 2.8;
      widgets.add(
        Positioned(
          left: seatCenter.dx - (seatTargetSize / 2),
          top: seatCenter.dy - (seatTargetSize / 2),
          child: DragTarget<_SeatDropPayload>(
            onWillAcceptWithDetails: (_) => !widget.readOnly,
            onAcceptWithDetails: (details) {
              final payload = details.data;
              if (payload.createEmptyChair) {
                final emptyChair = _createEmptyChairGuest();
                _placeGuestOnTable(table, emptyChair, index, createIfMissing: true);
                return;
              }

              final draggedGuest = payload.guest;
              if (draggedGuest == null) return;
              _placeGuestOnTable(table, draggedGuest, index, createIfMissing: false);
            },
            builder: (context, candidateData, rejectedData) {
              final hasDropTarget = candidateData.isNotEmpty;
              final Color dotColor;
              final Color dotBorder;
              final String dotLabel;
              if (hasDropTarget) {
                dotColor = const Color(0x334B6BFB);
                dotBorder = const Color(0xFF4B6BFB);
                dotLabel = '';
              } else if (guest == null) {
                dotColor = const Color(0xFFE8E8E8);
                dotBorder = const Color(0xFFBBBBBB);
                dotLabel = '';
              } else if (guest.isPlaceholder) {
                dotColor = const Color(0xFFF0F0F0);
                dotBorder = const Color(0xFF9E9E9E);
                dotLabel = '';
              } else if (guest.isLocked) {
                dotColor = const Color(0xFFFFD8A8);
                dotBorder = const Color(0xFFE39B3A);
                dotLabel = '${guest.seatNumber ?? (index + 1)}';
              } else {
                dotColor = const Color(0xFFDDE7FF);
                dotBorder = const Color(0xFF90A9E8);
                dotLabel = '${guest.seatNumber ?? (index + 1)}';
              }
              final dotDiameter = seatRadius * 2;
              return SizedBox(
                width: seatTargetSize,
                height: seatTargetSize,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: hasDropTarget ? seatTargetSize : dotDiameter,
                    height: hasDropTarget ? seatTargetSize : dotDiameter,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      border: Border.all(color: dotBorder, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        dotLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      if (guest == null) {
        continue;
      }

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
      final isHovered = _hoveredGuestId == guest.id;

      widgets.addAll([
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
          left: chipRect.left,
          top: chipRect.top,
          child: LongPressDraggable<_SeatDropPayload>(
            data: _SeatDropPayload.guest(guest),
            feedback: Material(
              color: Colors.transparent,
              child: _guestChipCard(
                guest: guest,
                width: chipSize.width,
                height: chipSize.height,
                highlighted: true,
                text: hasDietaryText ? '${guest.displayName}\n$dietaryText' : guest.displayName,
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.25,
              child: _guestChipCard(
                guest: guest,
                width: chipSize.width,
                height: chipSize.height,
                highlighted: false,
                text: hasDietaryText ? '${guest.displayName}\n$dietaryText' : guest.displayName,
              ),
            ),
            onDragStarted: () => setState(() {
              _hoveredGuestId = guest.id;
              _isDragging = true;
            }),
            onDragEnd: (_) => setState(() {
              _hoveredGuestId = null;
              _isDragging = false;
            }),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hoveredGuestId = guest.id),
              onExit: (_) {
                if (_hoveredGuestId == guest.id) {
                  setState(() => _hoveredGuestId = null);
                }
              },
              child: AnimatedScale(
                scale: isHovered ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: _guestChipCard(
                  guest: guest,
                  width: chipSize.width,
                  height: chipSize.height,
                  highlighted: guest.isLocked || guest.isPlaceholder,
                  text: hasDietaryText ? '${guest.displayName}\n$dietaryText' : guest.displayName,
                ),
              ),
            ),
          ),
        ),
      ]);
    }

    return widgets;
  }

  Guest _createEmptyChairGuest() {
    return Guest(
      id: 'empty-chair-${DateTime.now().microsecondsSinceEpoch}',
      firstName: 'Empty',
      lastName: 'chair',
      createdAt: DateTime.now().toUtc(),
      title: GuestTitle.none,
      isLocked: true,
      isPlaceholder: true,
    );
  }

  bool _placeGuestOnTable(
    Map<String, dynamic> table,
    Guest guest,
    int targetSeatIndex, {
    bool createIfMissing = false,
  }) {
    final tableId = (table['id'] ?? '').toString();
    if (tableId.isEmpty) {
      return false;
    }

    final sourceTableId = _tableIdForGuest(guest);
    final movingWithinSameTable = sourceTableId == tableId;
    final targetSeatCount = (table['seats'] as int?) ?? 0;

    // Capacity check for cross-table moves only.
    if (!movingWithinSameTable &&
        sourceTableId != null &&
        _tableGuests(tableId).length >= targetSeatCount) {
      return false;
    }

    // Remove from source and reindex it first, before we touch the target.
    if (sourceTableId != null) {
      final sourceGuests = _guestsByTable[sourceTableId];
      if (sourceGuests != null) {
        sourceGuests.removeWhere((item) => item.id == guest.id);
      }
      final sourceTable = _tableById(sourceTableId);
      if (sourceTable != null) {
        _reindexGuestsForTable(sourceTable);
      }
    } else if (!createIfMissing) {
      return false;
    }

    // Get a FRESH reference to the target list AFTER source reindex.
    // For within-table moves, _reindexGuestsForTable above replaces
    // _guestsByTable[tableId] with a new list; we must use that new list.
    final targetTable = _tableGuests(tableId);
    final insertionIndex = targetSeatIndex.clamp(0, targetTable.length);
    // Any locked guest that is explicitly dragged to a new position gets their
    // seatNumber updated to that position; this covers both regular locked
    // guests moving to another table and placeholder empty chairs.
    if (guest.isLocked) {
      if (guest.isPlaceholder) guest.isLocked = true;
      guest.seatNumber = targetSeatIndex + 1;
    }
    if (!_allGuests.any((item) => item.id == guest.id)) {
      _allGuests.add(guest);
    }
    targetTable.insert(insertionIndex, guest);
    guest.tableId = tableId;
    _reindexGuestsForTable(table);
    _markFloorPlanDirty();
    return true;
  }

  bool _isRectangularPlacementShape(String shape) {
    return shape == 'kvadrat' || shape == 'rektangel' || shape == 'oval';
  }

  void _toggleTableSelection(String tableId) {
    setState(() {
      if (_selectedTableIds.contains(tableId)) {
        _selectedTableIds.remove(tableId);
      } else {
        _selectedTableIds.add(tableId);
      }
    });
  }

  void _clearTableSelection() {
    if (_selectedTableIds.isEmpty) {
      return;
    }

    setState(() {
      _selectedTableIds.clear();
    });
  }

  void _selectAllTables() {
    setState(() {
      _selectedTableIds = _tables
          .map((table) => (table['id'] ?? '').toString())
          .where((tableId) => tableId.isNotEmpty)
          .toSet();
    });
  }

  Future<void> _applyFloorPlanSettingsToSelection({
    int rotationDegreesDelta = 0,
    bool? shortSidePlacementEnabled,
  }) async {
    if (_selectedTableIds.isEmpty) {
      return;
    }

    final selectedIds = Set<String>.from(_selectedTableIds);

    setState(() {
      _tables = _tables.map((table) {
        final tableId = (table['id'] ?? '').toString();
        if (!selectedIds.contains(tableId)) {
          return table;
        }

        final nextRotation = _normalizedRotationDegrees(
          _tableRotationDegrees(table) + rotationDegreesDelta,
        );
        final updated = Map<String, dynamic>.from(table)
          ..['rotation_degrees'] = nextRotation
          ..['short_side_placement_enabled'] =
              shortSidePlacementEnabled ?? _usesShortSidePlacement(table);

        final currentPosition = _tablePositions[tableId] ?? const Offset(0, 0);
        _tablePositions[tableId] = _clampPosition(
          currentPosition,
          _tableVisualSize(updated),
        );

        return updated;
      }).toList();
      _hasUnsavedChanges = true;
    });
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

  Future<void> _saveFloorPlanChanges({bool showFeedback = false}) async {
    if (_isSaving || !_hasUnsavedChanges) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final localizations = AppLocalizationsScope.of(context);
      final updateFutures = <Future<void>>[];

      for (final table in _tables) {
        final tableId = (table['id'] ?? '').toString();
        if (tableId.isEmpty) {
          continue;
        }

        updateFutures.add(
          StorageService.updateTableFloorPlanSettings(
            tableId,
            rotationDegrees: table['rotation_degrees'] as int?,
            shortSidePlacementEnabled:
                table['short_side_placement_enabled'] as bool?,
          ),
        );
      }

      await Future.wait(updateFutures);
      await StorageService.saveTableLayout(widget.weddingId, _tablePositions);
      await StorageService.saveGuests(widget.weddingId, _allGuests);
      if (!mounted) return;

      setState(() {
        _hasUnsavedChanges = false;
      });

      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.text('save_success'))),
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
          Future<void> submitTableForm() async {
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
              _hasUnsavedChanges = true;
            });
          }

          return TableFormDialog(
            titleText: localizations.text('create_table'),
            nameLabelText: localizations.text('table_name'),
            seatsLabelText: localizations.text('table_seats'),
            shapeLabelText: localizations.text('table_shape'),
            saveLabelText: localizations.text('save'),
            nameController: nameCtrl,
            seatsController: seatsCtrl,
            selectedShape: selectedShape,
            shapeItems: shapes
                .map(
                  (shape) => DropdownMenuItem(
                    value: shape['value'] as String,
                    child: Text(localizations.text(shape['labelKey'] as String)),
                  ),
                )
                .toList(),
            onShapeChanged: (value) => setDialogState(() => selectedShape = value),
            onSubmit: submitTableForm,
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
      ..setEntry(0, 0, targetScale)
      ..setEntry(1, 1, targetScale)
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
      _hasUnsavedChanges = true;
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

  Widget _guestChipCard({
    required Guest guest,
    required double width,
    required double height,
    required bool highlighted,
    required String text,
  }) {
    final isPlaceholder = guest.isPlaceholder;
    final isLocked = guest.isLocked || isPlaceholder;
    final baseColor = isPlaceholder
        ? const Color(0xFFF2F2F2)
        : isLocked
            ? const Color(0xFFFFF0D6)
            : const Color(0xFFFFFFFF);
    final borderColor = isPlaceholder
        ? const Color(0xFF9E9E9E)
        : isLocked
            ? const Color(0xFFE39B3A)
            : const Color(0xFFDADADA);

    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted ? baseColor.withValues(alpha: 0.96) : baseColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPlaceholder ? Icons.chair_alt_outlined : (isLocked ? Icons.lock : Icons.person),
            size: 14,
            color: isPlaceholder
                ? const Color(0xFF666666)
                : isLocked
                    ? const Color(0xFFC27814)
                    : const Color(0xFF666666),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10.8,
                fontWeight: FontWeight.w600,
                color: isPlaceholder ? const Color(0xFF666666) : Colors.black87,
                height: 1.0,
              ),
              maxLines: text.contains('\n') ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyChairControl(
    AppLocalizationsController localizations, {
    bool dragging = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: dragging ? const Color(0xFFF2F2F2) : const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6DDEB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chair_alt_outlined,
            size: 18,
            color: dragging ? const Color(0xFF666666) : const Color(0xFF4B6BFB),
          ),
          const SizedBox(width: 8),
          Text(
            localizations.text('empty_chair'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
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

  List<int> _twoSideSeatDistribution(int seatCount) {
    if (seatCount <= 0) return const [0, 0, 0, 0];

    final frontCount = (seatCount / 2).ceil();
    final backCount = seatCount - frontCount;
    return [frontCount, 0, backCount, 0];
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
    required bool shortSidePlacementEnabled,
    required double rotationRadians,
  }) {
    if (seatCount <= 0) return tableCenter;

    final normalizedShape = shape.toLowerCase();
    final progress = ((seatIndex + 0.5) / seatCount).clamp(0.0, 1.0);

    if (normalizedShape == 'cirkel' ||
        (normalizedShape == 'oval' && shortSidePlacementEnabled)) {
      final angle = (-math.pi / 2) + (2 * math.pi * progress);
      final orbitRadiusX = (tableSize.width / 2) + seatRadius;
      final orbitRadiusY = (tableSize.height / 2) + seatRadius;
      return _rotatePointAroundCenter(
        Offset(
          tableCenter.dx + orbitRadiusX * math.cos(angle),
          tableCenter.dy + orbitRadiusY * math.sin(angle),
        ),
        center: tableCenter,
        angleRadians: rotationRadians,
      );
    }

    final seatsPerSide = shortSidePlacementEnabled
      ? _rectangularSeatDistribution(seatCount, tableSize)
      : _twoSideSeatDistribution(seatCount);

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
      return _rotatePointAroundCenter(
        Offset(x, tableCenter.dy - halfHeight - sideOffset),
        center: tableCenter,
        angleRadians: rotationRadians,
      );
    }
    resolvedSeatIndex -= seatsPerSide[0];

    if (resolvedSeatIndex < seatsPerSide[1]) {
      final count = seatsPerSide[1];
      final offsets = _centeredSideOffsets(count, leftRightAvailable);
      final y = (tableCenter.dy + offsets[resolvedSeatIndex]).clamp(
        tableCenter.dy - halfHeight + sideVerticalInset,
        tableCenter.dy + halfHeight - sideVerticalInset,
      );
      return _rotatePointAroundCenter(
        Offset(tableCenter.dx + halfWidth + sideOffset, y),
        center: tableCenter,
        angleRadians: rotationRadians,
      );
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
      return _rotatePointAroundCenter(
        Offset(x, tableCenter.dy + halfHeight + sideOffset),
        center: tableCenter,
        angleRadians: rotationRadians,
      );
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
    return _rotatePointAroundCenter(
      Offset(tableCenter.dx - halfWidth - sideOffset, y),
      center: tableCenter,
      angleRadians: rotationRadians,
    );
  }

  Offset _rotatePointAroundCenter(
    Offset point, {
    required Offset center,
    required double angleRadians,
  }) {
    if (angleRadians == 0) {
      return point;
    }

    final translated = point - center;
    final rotated = Offset(
      translated.dx * math.cos(angleRadians) - translated.dy * math.sin(angleRadians),
      translated.dx * math.sin(angleRadians) + translated.dy * math.cos(angleRadians),
    );
    return center + rotated;
  }

  Widget _buildHeader() {
    final localizations = AppLocalizationsScope.of(context);
    final hasSelection = _selectedTableIds.isNotEmpty;
    final selectedTables = _tables
        .where((table) => _selectedTableIds.contains((table['id'] ?? '').toString()))
        .toList();
    final allSelectedShortSidesEnabled =
        selectedTables.isNotEmpty && selectedTables.every(_usesShortSidePlacement);
    final canToggleShortSides = selectedTables.any((table) {
      final shape = (table['shape']?.toString() ?? '').toLowerCase();
      return _isRectangularPlacementShape(shape);
    });
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 760;

          final controls = <Widget>[
            const LanguageToggleButton(),
            TextButton.icon(
              onPressed: _resetZoom,
              icon: const Icon(Icons.center_focus_strong),
              label: Text(localizations.text('center_view')),
            ),
            TextButton.icon(
              onPressed: _exportFloorPlanAsPng,
              icon: const Icon(Icons.image_outlined),
              label: Text(localizations.text('seating_chart_export_png')),
            ),
            if (!widget.readOnly)
              Draggable<_SeatDropPayload>(
                data: const _SeatDropPayload.emptyChair(),
                onDragStarted: () => setState(() => _isDragging = true),
                onDragEnd: (_) => setState(() => _isDragging = false),
                feedback: Material(
                  color: Colors.transparent,
                  child: _emptyChairControl(localizations, dragging: true),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: _emptyChairControl(localizations),
                ),
                child: _emptyChairControl(localizations),
              ),
            if (!widget.readOnly)
              TextButton.icon(
                onPressed:
                    (_hasUnsavedChanges && !_isSaving)
                        ? () => _saveFloorPlanChanges(showFeedback: true)
                        : null,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(localizations.text('save')),
              ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isCompact) ...[
                Text(
                  localizations.text('floor_plan_header'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: controls,
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        localizations.text('floor_plan_header'),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                    ...controls,
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                widget.readOnly
                    ? localizations.text('floor_plan_read_only_hint')
                    : hasSelection
                        ? localizations.text(
                            'floor_plan_selected_count',
                            values: {'count': '${_selectedTableIds.length}'},
                          )
                        : localizations.text('floor_plan_select_hint'),
                style: TextStyle(color: Colors.grey.shade700),
              ),
              if (!widget.readOnly) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _tables.isEmpty
                          ? null
                          : (hasSelection ? _clearTableSelection : _selectAllTables),
                      icon: Icon(hasSelection ? Icons.deselect : Icons.select_all),
                      label: Text(
                        localizations.text(
                          hasSelection
                              ? 'floor_plan_clear_selection'
                              : 'floor_plan_select_all',
                        ),
                      ),
                    ),
                    if (hasSelection) ...[
                      OutlinedButton.icon(
                        onPressed: () => _applyFloorPlanSettingsToSelection(
                          rotationDegreesDelta: -15,
                        ),
                        icon: const Icon(Icons.rotate_left),
                        label: Text(
                          '${localizations.text('floor_plan_rotate_left')} ${localizations.text('floor_plan_rotate_15')}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _applyFloorPlanSettingsToSelection(
                          rotationDegreesDelta: -45,
                        ),
                        icon: const Icon(Icons.rotate_left),
                        label: Text(
                          '${localizations.text('floor_plan_rotate_left')} ${localizations.text('floor_plan_rotate_45')}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _applyFloorPlanSettingsToSelection(
                          rotationDegreesDelta: -90,
                        ),
                        icon: const Icon(Icons.rotate_left),
                        label: Text(
                          '${localizations.text('floor_plan_rotate_left')} ${localizations.text('floor_plan_rotate_90')}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _applyFloorPlanSettingsToSelection(
                          rotationDegreesDelta: 15,
                        ),
                        icon: const Icon(Icons.rotate_right),
                        label: Text(
                          '${localizations.text('floor_plan_rotate_right')} ${localizations.text('floor_plan_rotate_15')}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _applyFloorPlanSettingsToSelection(
                          rotationDegreesDelta: 45,
                        ),
                        icon: const Icon(Icons.rotate_right),
                        label: Text(
                          '${localizations.text('floor_plan_rotate_right')} ${localizations.text('floor_plan_rotate_45')}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _applyFloorPlanSettingsToSelection(
                          rotationDegreesDelta: 90,
                        ),
                        icon: const Icon(Icons.rotate_right),
                        label: Text(
                          '${localizations.text('floor_plan_rotate_right')} ${localizations.text('floor_plan_rotate_90')}',
                        ),
                      ),
                      Opacity(
                        opacity: canToggleShortSides ? 1 : 0.55,
                        child: IgnorePointer(
                          ignoring: !canToggleShortSides,
                          child: Container(
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
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.swap_horiz, size: 18),
                                const SizedBox(width: 6),
                                Text(localizations.text('floor_plan_short_sides')),
                                const SizedBox(width: 6),
                                Switch.adaptive(
                                  value: allSelectedShortSidesEnabled,
                                  onChanged: (value) => _applyFloorPlanSettingsToSelection(
                                    shortSidePlacementEnabled: value,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  localizations.text('floor_plan_help'),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildFloorCanvas() {
    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: _minScale,
      maxScale: _maxScale,
      panEnabled: !_isDragging,
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

  Widget _buildTableNode(Map<String, dynamic> table) {
    final localizations = AppLocalizationsScope.of(context);
    final tableId = (table['id'] ?? '').toString();
    final tableName = (table['name'] ?? 'Bord').toString();
    final shape = (table['shape']?.toString() ?? 'Rektangel').toLowerCase();
    final position = _tablePositions[tableId] ?? const Offset(0, 0);
    final size = _tableVisualSize(table);
    final seats = (table['seats'] as int?) ?? 0;
    final isSelected = _selectedTableIds.contains(tableId);
    final decoration = switch (shape) {
      'cirkel' => BoxDecoration(
        color: const Color(0xFFFFF5EA),
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? const Color(0xFF4B6BFB) : const Color(0xFFE3B56B),
          width: isSelected ? 3.2 : 2.2,
        ),
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
        border: Border.all(
          color: isSelected ? const Color(0xFF4B6BFB) : const Color(0xFFE3B56B),
          width: isSelected ? 3.2 : 2.2,
        ),
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
        border: Border.all(
          color: isSelected ? const Color(0xFF4B6BFB) : const Color(0xFFC7A4F0),
          width: isSelected ? 3.2 : 2.2,
        ),
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
        border: Border.all(
          color: isSelected ? const Color(0xFF4B6BFB) : const Color(0xFFE7AAB9),
          width: isSelected ? 3.2 : 2.2,
        ),
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
        onTap: widget.readOnly ? null : () => _toggleTableSelection(tableId),
        onPanUpdate: widget.readOnly
            ? null
            : (details) => _moveTable(tableId, details.delta),
        onPanEnd: null,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Transform.rotate(
                  angle: _tableRotationRadians(table),
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
                          if (!widget.readOnly) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 18,
                                  color: isSelected
                                      ? const Color(0xFF4B6BFB)
                                      : Colors.grey.shade600,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
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
    final isCompact = MediaQuery.of(context).size.width < 760;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.text('table_floor_plan_title'))),
      floatingActionButton: widget.readOnly
          ? null
          : SafeArea(
              child: isCompact
                  ? FloatingActionButton.small(
                      onPressed: () => _openTableFormDialog(),
                      tooltip: localizations.text('add_table'),
                      child: const Icon(Icons.add),
                    )
                  : FloatingActionButton(
                      onPressed: () => _openTableFormDialog(),
                      tooltip: localizations.text('add_table'),
                      child: const Icon(Icons.add),
                    ),
            ),
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
