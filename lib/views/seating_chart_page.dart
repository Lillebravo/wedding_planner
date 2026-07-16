// ignore_for_file: unused_element

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/guest_model.dart';
import '../l10n/app_localizations.dart';
import '../services/guest_pdf_export.dart';
import '../services/seating_algorithm.dart';
import '../services/storage_service.dart';
import '../widgets/app_dropdown_form_field.dart';
import '../widgets/app_labeled_text_field.dart';
import '../widgets/app_search_field.dart';
import '../widgets/dialog_action_buttons.dart';
import '../widgets/dialog_title_with_close.dart';
import '../widgets/language_toggle_button.dart';
import 'table_floor_plan_page.dart';

enum PlacementRuleId { friendAtTable, partnerAdjacent }

class PlacementRuleSetting {
  final PlacementRuleId id;
  final String title;
  bool enabled;

  PlacementRuleSetting({
    required this.id,
    required this.title,
    required this.enabled,
  });
}

class SeatingChartPage extends StatefulWidget {
  final List<Guest> guests;
  final String weddingId;

  const SeatingChartPage({
    super.key,
    required this.guests,
    required this.weddingId,
  });

  @override
  State<SeatingChartPage> createState() => _SeatingChartPageState();
}

class _SeatingChartPageState extends State<SeatingChartPage> {
  String _chartSearchQuery = '';
  GuestTitle? _chartTitleFilter;
  bool _chartOnlyDietary = false;
  bool _isLoadingTables = true;
  final GlobalKey _visualLayoutKey = GlobalKey();

  List<Map<String, dynamic>> tables = [];

  final List<PlacementRuleSetting> _placementRules = [
    PlacementRuleSetting(
      id: PlacementRuleId.partnerAdjacent,
      title: 'Partner bredvid',
      enabled: true,
    ),
    PlacementRuleSetting(
      id: PlacementRuleId.friendAtTable,
      title: 'Minst en vän vid samma bord',
      enabled: true,
    ),
  ];

  String _placementRuleTitle(AppLocalizationsController localizations, PlacementRuleId id) {
    return switch (id) {
      PlacementRuleId.friendAtTable => localizations.text('auto_rule_friend'),
      PlacementRuleId.partnerAdjacent => localizations.text('auto_rule_partner'),
    };
  }

  String _shapeLabel(AppLocalizationsController localizations, String shape) {
    switch (shape.toLowerCase()) {
      case 'cirkel':
      case 'circle':
        return localizations.text('table_round');
      case 'oval':
        return localizations.text('table_oval');
      case 'kvadrat':
      case 'square':
        return localizations.text('table_square');
      default:
        return localizations.text('table_rectangle');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPlacementRules();
    _loadTables();
  }

  Future<void> _loadPlacementRules() async {
    final storedRules = await StorageService.getPlacementRules(widget.weddingId);
    if (storedRules == null || !mounted) return;

    final Map<PlacementRuleId, PlacementRuleSetting> defaultRules = {
      for (final rule in _placementRules)
        rule.id: PlacementRuleSetting(id: rule.id, title: rule.title, enabled: rule.enabled),
    };

    final List<PlacementRuleSetting> orderedRules = [];
    for (final entry in storedRules) {
      final idString = entry['id']?.toString();
      if (idString == null) continue;

      final PlacementRuleId? ruleId = PlacementRuleId.values
          .where((id) => id.name == idString)
          .cast<PlacementRuleId?>()
          .firstWhere((id) => id != null, orElse: () => null);
      if (ruleId == null) continue;

      final existing = defaultRules.remove(ruleId);
      if (existing == null) continue;

      final bool? enabledValue = entry['enabled'] as bool?;
      existing.enabled = enabledValue ?? existing.enabled;
      orderedRules.add(existing);
    }

    orderedRules.addAll(defaultRules.values);

    setState(() {
      _placementRules
        ..clear()
        ..addAll(orderedRules);
    });
  }

  Future<void> _persistPlacementRules() async {
    final payload = _placementRules
        .map(
          (rule) => {
            'id': rule.id.name,
            'enabled': rule.enabled,
          },
        )
        .toList();

    await StorageService.savePlacementRules(widget.weddingId, payload);
  }

  Future<void> _exportSeatingAsPdf() async {
    final localizations = AppLocalizationsScope.of(context);
    try {
      final pdf = pw.Document();
      final baseFont = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();

      final sortedTables = [...tables]..sort(
        (a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''),
      );

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
          build: (context) {
            final content = <pw.Widget>[
              pw.Text(
                localizations.text('seating_chart_title'),
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text('${DateTime.now()}'),
              pw.SizedBox(height: 20),
            ];

            for (final table in sortedTables) {
              final assignedGuests = List<Guest>.from(table['assigned'] as List<Guest>);
              _sortAssignedBySeat(assignedGuests);

              content.add(
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 14),
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 1),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '${table['name']} (${assignedGuests.length}/${table['seats']} ${localizations.text('table_plural')})',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 6),
                      if (assignedGuests.isEmpty)
                        pw.Text(localizations.text('no_seated_guests'))
                      else
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: assignedGuests
                              .map(
                                (g) => pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                                  child: pw.Text(
                                    '${g.seatNumber ?? '-'} ${guestPdfLine(g, localizations, includeRole: true, includeDietary: true)}',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),
              );
            }

            final unassignedGuests = widget.guests
                .where((g) => !tables.any((t) => (t['assigned'] as List<Guest>).contains(g)));

            if (unassignedGuests.isNotEmpty) {
              content
                ..add(pw.SizedBox(height: 8))
                ..add(
                  pw.Text(
                    localizations.text('seating_chart_unassigned'),
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                  ),
                )
                ..add(pw.SizedBox(height: 6));

              content.addAll(
                unassignedGuests.map(
                  (g) => pw.Text(
                    guestPdfLine(
                      g,
                      localizations,
                      includeRole: true,
                      includeDietary: true,
                    ),
                  ),
                ),
              );
            }

            return content;
          },
        ),
      );

      final pdfBytes = await pdf.save();
      final fileName = 'bordsplacering_${DateTime.now().millisecondsSinceEpoch}';
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(pdfBytes),
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.text('exported_pdf'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${localizations.text('seating_chart_export_pdf')}: $e')),
      );
    }
  }

  Future<void> _loadTables() async {
    try {
      final dbTables = await StorageService.getTables(widget.weddingId);

      if (dbTables.isEmpty) {
        // Om inga tabeller finns (edge case), skapa honn├Ârsbordet lokalt
        if (!mounted) return;
        setState(() {
          tables = [
            {
              'id': 'local-honor-table-new',
              'name': 'Honn├Ârsbord',
              'seats': 8,
              'shape': 'Rektangel',
              'assigned': <Guest>[],
            }
          ];
          _prePlaceLockedGuests();
          _isLoadingTables = false;
        });
        return;
      }

      // Ladda alla tabeller fr├Ñn Supabase
      final loadedTables = dbTables
          .map(
            (t) => {
              'id': t['id'],
              'name': t['name'],
              'seats': t['seats'],
              'shape': t['shape'],
              'assigned': <Guest>[],
            },
          )
          .toList();

      if (!mounted) return;
      setState(() {
        tables = loadedTables;
        _prePlaceLockedGuests();
        _isLoadingTables = false;
      });
    } catch (e) {
      debugPrint('Error loading tables: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingTables = false;
      });
    }
  }

  void _assignGuestToTable(Guest guest, Map<String, dynamic> table, int seatIndex) {
    guest.tableId = StorageService.normalizeUuidOrNull(table['id']?.toString());
    guest.seatNumber = seatIndex;
  }

  void _prePlaceLockedGuests() {
    for (final table in tables) {
      (table['assigned'] as List<Guest>).clear();
    }

    for (var guest in widget.guests) {
      if (guest.tableId != null) {
        final table = tables.firstWhere(
          (t) => t['id'] == guest.tableId,
          orElse: () => tables.first,
        );
        final List<Guest> assigned = table['assigned'];
        if (!assigned.contains(guest)) {
          assigned.add(guest);
        }
      }
    }

    for (final table in tables) {
      _sortAssignedBySeat(table['assigned'] as List<Guest>);
      _reindexSeats(table['assigned'] as List<Guest>, table);
    }
  }

  void _sortAssignedBySeat(List<Guest> assignedGuests) {
    assignedGuests.sort((a, b) {
      final aSeat = a.seatNumber ?? 9999;
      final bSeat = b.seatNumber ?? 9999;
      return aSeat.compareTo(bSeat);
    });
  }

  void _reindexSeats(List<Guest> assignedGuests, Map<String, dynamic> table) {
    for (int i = 0; i < assignedGuests.length; i++) {
      _assignGuestToTable(assignedGuests[i], table, i + 1);
    }
  }

  bool _isPartnerRelation(Guest a, Guest b) {
    return a.relations[b.id] == RelationType.partner || b.relations[a.id] == RelationType.partner;
  }

  bool _isFriendOrPartner(Guest a, Guest b) {
    final forward = a.relations[b.id];
    final reverse = b.relations[a.id];
    return forward == RelationType.friend ||
        forward == RelationType.partner ||
        reverse == RelationType.friend ||
        reverse == RelationType.partner;
  }

  bool _hasAvoidConflict(Guest guest, List<Guest> assigned) {
    for (final seated in assigned) {
      if (guest.relations[seated.id] == RelationType.avoid ||
          seated.relations[guest.id] == RelationType.avoid) {
        return true;
      }
    }
    return false;
  }

  bool _isHostGuest(Guest guest) {
    return guest.title == GuestTitle.bride || guest.title == GuestTitle.groom;
  }

  List<List<Guest>> _collectPartnerPairs(
    List<Guest> candidates, {
    required bool includeAllPartnerRelations,
  }) {
    final byId = {for (final guest in candidates) guest.id: guest};
    final used = <String>{};
    final pairs = <List<Guest>>[];

    void addPair(Guest a, Guest b) {
      if (a.id == b.id) return;
      if (used.contains(a.id) || used.contains(b.id)) return;
      used.add(a.id);
      used.add(b.id);
      pairs.add([a, b]);
    }

    final bride = candidates.where((g) => g.title == GuestTitle.bride).firstOrNull;
    final groom = candidates.where((g) => g.title == GuestTitle.groom).firstOrNull;
    if (bride != null && groom != null) {
      addPair(bride, groom);
    }

    if (!includeAllPartnerRelations) {
      return pairs;
    }

    for (final guest in candidates) {
      if (used.contains(guest.id)) continue;

      for (final relation in guest.relations.entries) {
        if (relation.value != RelationType.partner) continue;
        final partner = byId[relation.key];
        if (partner == null) continue;
        addPair(guest, partner);
        break;
      }
    }

    return pairs;
  }

  // --- ROUND-ROBIN PLACEMENT ENGINE ---

  /// Attempts to seat [group] starting from [rrPointer], cycling through tables.
  ///
  /// Skips tables that are full, have avoid conflicts, or (when [requireFriend]
  /// is true) have no known friend/partner of any group member.
  /// Falls back to the first valid table (capacity + no avoid) when no
  /// preferred match exists. Returns the new rrPointer on success, -1 on total
  /// failure (no table can accommodate the group at all).
  int _rrSeatGroup(
    List<Guest> group,
    int rrPointer, {
    bool requireFriend = false,
  }) {
    final n = tables.length;
    if (n == 0 || group.isEmpty) return -1;
    int fallbackIdx = -1;

    for (int attempt = 0; attempt < n; attempt++) {
      final idx = (rrPointer + attempt) % n;
      final assigned = tables[idx]['assigned'] as List<Guest>;
      final maxSeats = tables[idx]['seats'] as int;

      if (maxSeats - assigned.length < group.length) continue;
      if (group.any((g) => _hasAvoidConflict(g, assigned))) continue;

      // Track first valid table as fallback (capacity + no avoid, ignoring friend rule)
      if (fallbackIdx < 0) fallbackIdx = idx;

      if (requireFriend) {
        final hasLink = assigned.isNotEmpty &&
            group.any((g) => assigned.any((s) => _isFriendOrPartner(g, s)));
        if (!hasLink) continue;
      }

      assigned.addAll(group);
      return (idx + 1) % n;
    }

    // Fallback: seat at first valid table, ignoring friend rule
    if (fallbackIdx >= 0) {
      (tables[fallbackIdx]['assigned'] as List<Guest>).addAll(group);
      return (fallbackIdx + 1) % n;
    }

    return -1; // no table can accommodate the group
  }

  /// Phase: seat all partner couples from [unassigned] via round-robin.
  /// Pairs that cannot be seated together remain in [unassigned].
  int _rrPhaseCouple(List<Guest> unassigned, int rrPointer,
      {bool requireFriend = false}) {
    final pairs =
        _collectPartnerPairs(unassigned, includeAllPartnerRelations: true);
    for (final pair in pairs) {
      final newPtr =
          _rrSeatGroup(pair, rrPointer, requireFriend: requireFriend);
      if (newPtr >= 0) {
        rrPointer = newPtr;
        unassigned.removeWhere((g) => pair.any((p) => p.id == g.id));
      }
    }
    return rrPointer;
  }

  /// Phase: seat every guest in [unassigned] one at a time via round-robin.
  int _rrPhaseByGuest(List<Guest> unassigned, int rrPointer,
      {bool requireFriend = false}) {
    for (final guest in List<Guest>.from(unassigned)) {
      final newPtr =
          _rrSeatGroup([guest], rrPointer, requireFriend: requireFriend);
      if (newPtr >= 0) {
        rrPointer = newPtr;
        unassigned.remove(guest);
      }
    }
    return rrPointer;
  }

  /// Friend-priority Phase B: after each guest has been seated individually,
  /// try to move one partner to the other's table where capacity and avoid
  /// rules permit. Skips locked guests and avoids leaving a table lonely.
  void _rrTryColocatePartners() {
    final guestTableIdx = <String, int>{};
    for (int ti = 0; ti < tables.length; ti++) {
      for (final g in (tables[ti]['assigned'] as List<Guest>)) {
        guestTableIdx[g.id] = ti;
      }
    }

    for (int ti = 0; ti < tables.length; ti++) {
      for (final guest
          in List<Guest>.from(tables[ti]['assigned'] as List<Guest>)) {
        if (guest.isLocked) continue;
        String? partnerId;
        for (final entry in guest.relations.entries) {
          if (entry.value == RelationType.partner) {
            partnerId = entry.key;
            break;
          }
        }
        if (partnerId == null) continue;

        final partnerTi = guestTableIdx[partnerId];
        if (partnerTi == null || partnerTi == ti) continue;

        final partnerAssigned = tables[partnerTi]['assigned'] as List<Guest>;
        final partnerMax = tables[partnerTi]['seats'] as int;
        if (partnerAssigned.length >= partnerMax) continue;
        if (_hasAvoidConflict(guest, partnerAssigned)) continue;

        final sourceAssigned = tables[ti]['assigned'] as List<Guest>;
        // Don't leave the source table lonely (1 guest) after the move
        if (sourceAssigned.length <= 2) continue;

        sourceAssigned.remove(guest);
        partnerAssigned.add(guest);
        guestTableIdx[guest.id] = partnerTi;
      }
    }
  }

  /// Post-placement constraint: no table may have exactly 1 guest.
  ///
  /// Option A – move the lone guest to any table with ≥2 guests and free space.
  /// Option B – bring a non-locked guest from a table with ≥3 guests here.
  void _fixLonelyGuests() {
    for (int ti = 0; ti < tables.length; ti++) {
      final assigned = tables[ti]['assigned'] as List<Guest>;
      if (assigned.length != 1) continue;
      final loneGuest = assigned.first;

      // Option A: move lone guest out
      bool moved = false;
      for (int oi = 0; oi < tables.length; oi++) {
        if (oi == ti) continue;
        final otherAssigned = tables[oi]['assigned'] as List<Guest>;
        final otherMax = tables[oi]['seats'] as int;
        if (otherAssigned.length < 2) continue;
        if (otherAssigned.length >= otherMax) continue;
        if (_hasAvoidConflict(loneGuest, otherAssigned)) continue;
        assigned.remove(loneGuest);
        otherAssigned.add(loneGuest);
        moved = true;
        break;
      }
      if (moved) continue;

      // Option B: bring a guest in from a table with ≥3 guests
      for (int oi = 0; oi < tables.length; oi++) {
        if (oi == ti) continue;
        final otherAssigned = tables[oi]['assigned'] as List<Guest>;
        if (otherAssigned.length < 3) continue;
        final thisMax = tables[ti]['seats'] as int;
        if (assigned.length >= thisMax) continue;

        final movable = otherAssigned
            .where((g) => !g.isLocked && !_hasAvoidConflict(g, assigned))
            .firstOrNull;
        if (movable == null) continue;

        otherAssigned.remove(movable);
        assigned.add(movable);
        break;
      }
    }
  }

  Future<void> _showPlacementSettingsDialog() async {
    final localizations = AppLocalizationsScope.of(context);
    final updatedRules = _placementRules
        .map(
          (rule) => PlacementRuleSetting(
            id: rule.id,
            title: _placementRuleTitle(localizations, rule.id),
            enabled: rule.enabled,
          ),
        )
        .toList();

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: DialogTitleWithClose(
              titleText: localizations.text('auto_placement_settings'),
              onClose: () => Navigator.pop(dialogContext),
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.text('auto_placement_hint')),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: ReorderableListView.builder(
                      itemCount: updatedRules.length,
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) {
                        setDialogState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final moved = updatedRules.removeAt(oldIndex);
                          updatedRules.insert(newIndex, moved);
                        });
                      },
                      itemBuilder: (context, index) {
                        final rule = updatedRules[index];
                        return Card(
                          key: ValueKey(rule.id),
                          child: SwitchListTile(
                            value: rule.enabled,
                            title: Text(rule.title),
                            subtitle: Text(
                              localizations.text('priority', values: {'index': '${index + 1}'}),
                            ),
                            secondary: const Icon(Icons.drag_indicator),
                            onChanged: (val) => setDialogState(() => rule.enabled = val),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              DialogConfirmButton(
                label: localizations.text('save'),
                onPressed: () async {
                  setState(() {
                    _placementRules
                      ..clear()
                      ..addAll(updatedRules);
                  });
                  Navigator.pop(dialogContext);
                  await _persistPlacementRules();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // Nu är metoden async och uppdaterar sätesnummer & databasen!
  Future<void> _runPlacementAlgorithm() async {
    final localizations = AppLocalizationsScope.of(context);
    setState(() {
      final enabledRuleIds = _placementRules
          .where((rule) => rule.enabled)
          .map((rule) => rule.id)
          .toSet();
      final friendRuleEnabled =
          enabledRuleIds.contains(PlacementRuleId.friendAtTable);
      final partnerRuleEnabled =
          enabledRuleIds.contains(PlacementRuleId.partnerAdjacent);

      // Capacity check for snackbar warning.
      final lockedCount =
          widget.guests.where((g) => g.isLocked && g.tableId != null).length;
      final totalSeats =
          tables.fold(0, (s, t) => s + (t['seats'] as int));
      final unassignedCount = widget.guests.length - lockedCount;
      final availableSeats = totalSeats - lockedCount;
      if (unassignedCount > availableSeats) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red[700],
            content: Text(
              localizations.text(
                'placement_not_enough_seats',
                values: {'count': '${unassignedCount - availableSeats}'},
              ),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // Priority: lower index in _placementRules = higher priority.
      final int partnerPriIdx = _placementRules
          .indexWhere((r) => r.id == PlacementRuleId.partnerAdjacent);
      final int friendPriIdx = _placementRules
          .indexWhere((r) => r.id == PlacementRuleId.friendAtTable);

      SeatingAlgorithm(
        tables: tables,
        guests: widget.guests,
        partnerRuleEnabled: partnerRuleEnabled,
        friendRuleEnabled: friendRuleEnabled,
        partnerHigherPriority: partnerPriIdx < friendPriIdx,
      ).run();

      // Re-normalise tableIds to valid UUIDs (Supabase requirement).
      for (final table in tables) {
        _reindexSeats(table['assigned'] as List<Guest>, table);
      }
    });

    // Synka hela den nya placeringen live mot Supabase
    final messenger = ScaffoldMessenger.of(context);
    try {
      await StorageService.saveGuests(widget.weddingId, widget.guests);
      messenger.showSnackBar(
        SnackBar(content: Text(localizations.text('placement_running'))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(localizations.text('error_with_message', values: {'error': '$e'})),
        ),
      );
    }
  }

  void _openTableFormDialog({Map<String, dynamic>? tableToEdit}) {
    final localizations = AppLocalizationsScope.of(context);
    final isEditing = tableToEdit != null;
    final nameCtrl = TextEditingController(
      text: isEditing
          ? tableToEdit['name']
          : '${localizations.text('table_default_name_prefix')} ${tables.length + 1}',
    );
    final seatsCtrl = TextEditingController(
      text: isEditing ? tableToEdit['seats'].toString() : '8',
    );
    String selectedShape = isEditing ? tableToEdit['shape'] : 'Cirkel';
    List<Guest> currentAssigned = isEditing ? List<Guest>.from(tableToEdit['assigned']) : [];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final int maxSeatsAllowed = int.tryParse(seatsCtrl.text) ?? 0;
          final bool isOverflown = currentAssigned.length > maxSeatsAllowed;

          List<Guest> availableGuests = widget.guests.where((g) {
            return !currentAssigned.contains(g) &&
                !tables.any(
                  (t) =>
                      t['id'] != (isEditing ? tableToEdit['id'] : '') &&
                      (t['assigned'] as List<Guest>).contains(g),
                );
          }).toList();

          return AlertDialog(
            title: DialogTitleWithClose(
              titleText: localizations.text(isEditing ? 'edit_table' : 'create_table'),
              onClose: () => Navigator.pop(dialogContext),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppLabeledTextField(
                    controller: nameCtrl,
                    labelText: '${localizations.text('table_name')} *',
                  ),
                  AppLabeledTextField(
                    controller: seatsCtrl,
                    labelText: '${localizations.text('table_seats')} *',
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  AppDropdownFormField<String>(
                    initialValue: selectedShape,
                    labelText: localizations.text('table_shape'),
                    items: ['Kvadrat', 'Rektangel', 'Cirkel', 'Oval']
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(_shapeLabel(localizations, s)),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setDialogState(() => selectedShape = val!),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${localizations.text('seating_chart_assigned_guests')} (${currentAssigned.length} / $maxSeatsAllowed)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOverflown ? Colors.red : Colors.black,
                    ),
                  ),
                  if (isOverflown) ...[
                    Text(
                      localizations.text('seating_chart_too_many_guests_warning'),
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  SizedBox(
                    width: double.maxFinite,
                    height: 120,
                    child: currentAssigned.isEmpty
                        ? Center(
                            child: Text(
                              localizations.text('table_empty'),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: currentAssigned.length,
                            itemBuilder: (context, idx) {
                              final g = currentAssigned[idx];
                              return Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListTile(
                                  title: Text(g.fullName),
                                  dense: true,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                                    onPressed: () => setDialogState(() => currentAssigned.remove(g)),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  if (currentAssigned.length < maxSeatsAllowed) ...[
                    DropdownButton<Guest>(
                      hint: Text(localizations.text('seating_chart_assign_directly')),
                      isExpanded: true,
                      items: availableGuests
                          .map((g) => DropdownMenuItem(value: g, child: Text(g.fullName)))
                          .toList(),
                      onChanged: (guest) {
                        if (guest != null) {
                          setDialogState(() => currentAssigned.add(guest));
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              DialogConfirmButton(
                label: localizations.text('save'),
                onPressed: (isOverflown || nameCtrl.text.isEmpty || maxSeatsAllowed <= 0)
                    ? null
                    : () async {
                        Navigator.of(dialogContext).pop();
                        if (isEditing) {
                          setState(() {
                            tableToEdit['name'] = nameCtrl.text.trim();
                            tableToEdit['seats'] = maxSeatsAllowed;
                            tableToEdit['shape'] = selectedShape;
                            tableToEdit['assigned'] = currentAssigned;
                            for (int i = 0; i < currentAssigned.length; i++) {
                              _assignGuestToTable(currentAssigned[i], tableToEdit, i + 1);
                            }
                          });
                          await StorageService.updateTable(
                            tableToEdit['id'],
                            nameCtrl.text.trim(),
                            maxSeatsAllowed,
                            selectedShape,
                          );
                        } else {
                          final newId = await StorageService.addTable(
                            widget.weddingId,
                            nameCtrl.text.trim(),
                            maxSeatsAllowed,
                            selectedShape,
                          );
                          setState(() {
                            final newTable = {
                              'id': newId,
                              'name': nameCtrl.text.trim(),
                              'seats': maxSeatsAllowed,
                              'shape': selectedShape,
                              'assigned': currentAssigned,
                            };
                            tables.add(newTable);
                            for (int i = 0; i < currentAssigned.length; i++) {
                              _assignGuestToTable(currentAssigned[i], newTable, i + 1);
                            }
                          });
                        }
                        await StorageService.saveGuests(widget.weddingId, widget.guests);
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteTable(Map<String, dynamic> table) {
    final localizations = AppLocalizationsScope.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: DialogTitleWithClose(
          titleText: localizations.text('delete_table'),
          onClose: () => Navigator.pop(dialogContext),
        ),
        content: Text(
          localizations.text(
            'seating_chart_delete_table_confirm',
            values: {'name': '${table['name']}'},
          ),
        ),
        actions: [
          DialogConfirmButton(
            label: localizations.text('delete'),
            destructive: true,
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              setState(() {
                List<Guest> assigned = table['assigned'] as List<Guest>;
                for (var g in assigned) {
                  g.tableId = null;
                  g.seatNumber = null;
                }
                tables.removeWhere((t) => t['id'] == table['id']);
              });
              await StorageService.deleteTable(table['id']);
              await StorageService.saveGuests(widget.weddingId, widget.guests);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTablesPane() {
    final localizations = AppLocalizationsScope.of(context);
    return Container(
      color: Colors.grey[200],
      child: tables.isEmpty
          ? Center(child: Text(localizations.text('no_tables')))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tables.length,
              itemBuilder: (context, index) {
                final table = tables[index];
                final List<Guest> assignedGuests = table['assigned'];
                _sortAssignedBySeat(assignedGuests);

                return DragTarget<Guest>(
                  onAcceptWithDetails: (details) async {
                    if (assignedGuests.length >= table['seats']) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(localizations.text('table_full'))),
                      );
                      return;
                    }
                    setState(() {
                      Map<String, dynamic>? oldTable;
                      for (var t in tables) {
                        final assigned = t['assigned'] as List<Guest>;
                        if (assigned.remove(details.data)) {
                          oldTable = t;
                        }
                      }
                      if (oldTable != null) {
                        final fromTable = oldTable;
                        _reindexSeats(fromTable['assigned'] as List<Guest>, fromTable);
                      }
                      assignedGuests.add(details.data);
                      _reindexSeats(assignedGuests, table);
                    });
                    await StorageService.saveGuests(widget.weddingId, widget.guests);
                  },
                  builder: (context, candidateData, rejectedData) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      color: candidateData.isNotEmpty ? Colors.green[100] : Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${table['name']} (${_shapeLabel(localizations, '${table['shape']}')} - ${assignedGuests.length}/${table['seats']} ${localizations.text('table_plural')})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.orange, size: 20),
                                      onPressed: () => _openTableFormDialog(tableToEdit: table),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                      onPressed: () => _confirmDeleteTable(table),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(),
                            if (assignedGuests.isNotEmpty)
                              SizedBox(
                                height: assignedGuests.length * 62.0,
                                child: ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: assignedGuests.length,
                                  buildDefaultDragHandles: false,
                                  // ignore: deprecated_member_use
                                  onReorder: (oldIndex, newIndex) async {
                                    setState(() {
                                      if (newIndex > oldIndex) newIndex -= 1;
                                      final moved = assignedGuests.removeAt(oldIndex);
                                      assignedGuests.insert(newIndex, moved);
                                      _reindexSeats(assignedGuests, table);
                                    });
                                    await StorageService.saveGuests(widget.weddingId, widget.guests);
                                  },
                                  itemBuilder: (context, guestIndex) {
                                    final guest = assignedGuests[guestIndex];
                                    return Container(
                                      key: ValueKey('${table['id']}-${guest.id}'),
                                      margin: const EdgeInsets.symmetric(vertical: 2),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.transparent,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: ReorderableDelayedDragStartListener(
                                              index: guestIndex,
                                              child: ListTile(
                                                dense: true,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                                leading: const Icon(Icons.drag_indicator),
                                                title: Text('${guest.seatNumber}. ${guest.fullName}'),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              guest.isLocked ? Icons.lock : Icons.lock_open,
                                            ),
                                            onPressed: () async {
                                              setState(() => guest.isLocked = !guest.isLocked);
                                              await StorageService.saveGuests(
                                                widget.weddingId,
                                                widget.guests,
                                              );
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                                            onPressed: () async {
                                              setState(() {
                                                assignedGuests.remove(guest);
                                                guest.tableId = null;
                                                guest.seatNumber = null;
                                                _reindexSeats(assignedGuests, table);
                                              });
                                              await StorageService.saveGuests(
                                                widget.weddingId,
                                                widget.guests,
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            if (assignedGuests.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  localizations.text('seating_chart_drag_guests_here'),
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildUnassignedPane(List<Guest> unassignedGuests, {required bool isCompact}) {
    final localizations = AppLocalizationsScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: isCompact
            ? Border(bottom: BorderSide(color: Colors.grey[300]!))
            : Border(left: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              localizations.text('seating_chart_unassigned_people'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: AppSearchField(
              hintText: localizations.text('search_placeholder'),
              dense: true,
              onChanged: (val) => setState(() => _chartSearchQuery = val),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: AppDropdownFormField<GuestTitle?>(
              initialValue: _chartTitleFilter,
              labelText: localizations.text('filter_role_label'),
              isExpanded: true,
              isDense: true,
              items: [
                DropdownMenuItem(value: null, child: Text(localizations.text('all_roles'))),
                ...GuestTitle.values.map(
                  (t) => DropdownMenuItem(value: t, child: Text(localizations.guestTitle(t))),
                ),
              ],
              onChanged: (val) => setState(() => _chartTitleFilter = val),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: Text(localizations.text('only_dietary')),
                selected: _chartOnlyDietary,
                onSelected: (selected) => setState(() => _chartOnlyDietary = selected),
              ),
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: Builder(
              builder: (context) {
                final menuList = unassignedGuests.where((g) {
                  final matchesSearch = g.fullName.toLowerCase().contains(_chartSearchQuery.toLowerCase());
                  final matchesTitle = _chartTitleFilter == null || g.title == _chartTitleFilter;
                  final matchesDietary = !_chartOnlyDietary || g.dietaryRestrictions.isNotEmpty;
                  return matchesSearch && matchesTitle && matchesDietary;
                }).toList();

                if (menuList.isEmpty) {
                  return Center(
                    child: Text(
                      localizations.text('no_matches'),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: menuList.length,
                  itemBuilder: (context, index) {
                    final guest = menuList[index];
                    final isHost = guest.title == GuestTitle.bride || guest.title == GuestTitle.groom;

                    return Draggable<Guest>(
                      data: guest,
                      feedback: Material(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          color: isHost ? Colors.pink[100] : Colors.blue[100],
                          child: Text(guest.fullName),
                        ),
                      ),
                      childWhenDragging: ListTile(
                        title: Text(guest.fullName, style: const TextStyle(color: Colors.grey)),
                        leading: const Icon(Icons.person, color: Colors.grey),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          tileColor: isHost ? Colors.pink[50] : null,
                          title: Text(
                            guest.fullName,
                            style: TextStyle(fontWeight: isHost ? FontWeight.bold : FontWeight.normal),
                          ),
                          subtitle: Text(localizations.guestTitle(guest.title)),
                          leading: const Icon(Icons.drag_indicator),
                          trailing: IconButton(
                            icon: Icon(guest.isLocked ? Icons.lock : Icons.lock_open),
                            onPressed: () async {
                              setState(() => guest.isLocked = !guest.isLocked);
                              await StorageService.saveGuests(widget.weddingId, widget.guests);
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeechBubble(String text, {required bool alignRight}) {
    return Column(
      crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDADADA)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Size _visualTableSizeForShape(String shape, int seatCount) {
    final capacityScale = (0.92 + (seatCount * 0.03)).clamp(0.92, 1.42);
    switch (shape) {
      case 'cirkel':
        return Size(150 * capacityScale, 150 * capacityScale);
      case 'oval':
        return Size(210 * capacityScale, 135 * capacityScale);
      case 'kvadrat':
        return Size(150 * capacityScale, 150 * capacityScale);
      default:
        return Size(220 * capacityScale, 130 * capacityScale);
    }
  }

  List<int> _rectangularSeatDistribution(int seatCount, Size tableSize) {
    if (seatCount <= 0) return const [0, 0, 0, 0];

    final weights = [tableSize.width, tableSize.height, tableSize.width, tableSize.height];
    final totalWeight = weights.fold<double>(0.0, (sum, weight) => sum + weight);
    final rawCounts = weights.map((weight) => seatCount * weight / totalWeight).toList();
    final counts = rawCounts.map((value) => value.floor()).toList();

    int remainder = seatCount - counts.fold<int>(0, (sum, value) => sum + value);
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

    // För kantiga bord fördelas platserna efter sidornas längd så att långsidor får fler platser.
    final seatsPerSide = _rectangularSeatDistribution(seatCount, tableSize);

    final halfWidth = tableSize.width / 2;
    final halfHeight = tableSize.height / 2;
    final sideOffset = seatRadius;

    final sideHorizontalInset = math.min(tableSize.width * 0.28, 40.0);
    final sideVerticalInset = math.min(tableSize.height * 0.28, 34.0);
    final topBottomAvailable = math.max(0.0, tableSize.width - (2 * sideHorizontalInset));
    final leftRightAvailable = math.max(0.0, tableSize.height - (2 * sideVerticalInset));

    int resolvedSeatIndex = seatIndex.clamp(0, seatCount - 1);

    // Top (vänster -> höger)
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

    // Höger (topp -> botten)
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

    // Botten (höger -> vänster)
    if (resolvedSeatIndex < seatsPerSide[2]) {
      final count = seatsPerSide[2];
      final offsets = _centeredSideOffsets(count, topBottomAvailable).reversed.toList();
      final x = (tableCenter.dx + offsets[resolvedSeatIndex]).clamp(
        tableCenter.dx - halfWidth + sideHorizontalInset,
        tableCenter.dx + halfWidth - sideHorizontalInset,
      );
      return Offset(x, tableCenter.dy + halfHeight + sideOffset);
    }
    resolvedSeatIndex -= seatsPerSide[2];

    // Vänster (botten -> topp)
    final count = seatsPerSide[3];
    final offsets = _centeredSideOffsets(count, leftRightAvailable).reversed.toList();
    final y = (tableCenter.dy + offsets[resolvedSeatIndex]).clamp(
      tableCenter.dy - halfHeight + sideVerticalInset,
      tableCenter.dy + halfHeight - sideVerticalInset,
    );
    return Offset(tableCenter.dx - halfWidth - sideOffset, y);
  }

  Widget _buildVisualTableCard(Map<String, dynamic> table) {
    final localizations = AppLocalizationsScope.of(context);
    final assignedGuests = List<Guest>.from(table['assigned'] as List<Guest>);
    _sortAssignedBySeat(assignedGuests);
    final shape = (table['shape']?.toString() ?? 'Rektangel').toLowerCase();
    final seatCapacity = (table['seats'] as int?) ?? assignedGuests.length;
    final centerShapeSize = _visualTableSizeForShape(shape, seatCapacity);
    final borderRadius = switch (shape) {
      'cirkel' => BorderRadius.circular(200),
      'oval' => BorderRadius.circular(999),
      'kvadrat' => BorderRadius.circular(16),
      _ => BorderRadius.circular(16),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 520.0;
        final canvasWidth = math.min(availableWidth - 24, 560.0).clamp(340.0, 560.0);

        final center = Offset(canvasWidth / 2, canvasWidth * 0.42);
        final scale = canvasWidth / 520;
        final scaledShapeSize = Size(
          centerShapeSize.width * scale,
          centerShapeSize.height * scale,
        );
        final seatDiameter = (30 * scale).clamp(20.0, 32.0);
        final seatRadius = seatDiameter / 2;
        final bubbleWidth = (160 * scale).clamp(120.0, 180.0);
        final bubbleHeight = (58 * scale).clamp(44.0, 64.0);
        final bubbleOffset = math.max((scaledShapeSize.shortestSide * 0.18), 28.0);
        final canvasHeight = math.max(
          (canvasWidth * 0.88).clamp(300.0, 500.0),
          scaledShapeSize.height + bubbleHeight + (bubbleOffset * 2.8),
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6E6E6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${table['name']} (${_shapeLabel(localizations, '${table['shape']}')})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                '${assignedGuests.length}/${table['seats']} ${localizations.text('table_plural')}',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: center.dx - scaledShapeSize.width / 2,
                      top: center.dy - scaledShapeSize.height / 2,
                      child: Container(
                        width: scaledShapeSize.width,
                        height: scaledShapeSize.height,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBF0F3),
                          borderRadius: borderRadius,
                          border: Border.all(color: const Color(0xFFE8C4D0), width: 2),
                        ),
                        child: Center(
                          child: Text(
                            table['name']?.toString() ?? localizations.text('add_table'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    if (assignedGuests.isEmpty)
                      Positioned(
                        left: center.dx - 56,
                        top: center.dy - 10,
                        child: Text(
                          localizations.text('no_seated_guests'),
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ...List.generate(assignedGuests.length, (index) {
                      final guest = assignedGuests[index];
                      final seatCenter = _seatCenterForShape(
                        shape: shape,
                        tableCenter: center,
                        tableSize: scaledShapeSize,
                        seatIndex: index,
                        seatCount: math.max(seatCapacity, 1),
                        seatRadius: seatRadius,
                      );

                      final seatVector = seatCenter - center;
                      final seatVectorLength = seatVector.distance;
                      final direction = seatVectorLength == 0
                          ? const Offset(0, -1)
                          : Offset(seatVector.dx / seatVectorLength, seatVector.dy / seatVectorLength);

                      final bubbleCenter = seatCenter + direction * (seatRadius + bubbleOffset);
                      final alignRight = direction.dx < 0;
                      final clampedBubbleLeft = (bubbleCenter.dx - (alignRight ? bubbleWidth : 0))
                          .clamp(0.0, canvasWidth - bubbleWidth);
                      final clampedBubbleTop = (bubbleCenter.dy - bubbleHeight / 2)
                          .clamp(0.0, canvasHeight - bubbleHeight);

                      final bubbleEdgePoint = alignRight
                          ? Offset(clampedBubbleLeft + bubbleWidth, clampedBubbleTop + bubbleHeight / 2)
                          : Offset(clampedBubbleLeft, clampedBubbleTop + bubbleHeight / 2);

                      final connectorLength = math.max(
                        0.0,
                        (seatCenter - bubbleEdgePoint).distance - seatRadius,
                      );
                      final connectorAngle = math.atan2(
                        bubbleEdgePoint.dy - seatCenter.dy,
                        bubbleEdgePoint.dx - seatCenter.dx,
                      );

                      return Stack(
                        children: [
                          Positioned(
                            left: seatCenter.dx,
                            top: seatCenter.dy - 1,
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
                            left: seatCenter.dx - seatDiameter / 2,
                            top: seatCenter.dy - seatDiameter / 2,
                            child: Container(
                              width: seatDiameter,
                              height: seatDiameter,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: guest.isLocked ? const Color(0xFFFFD8A8) : const Color(0xFFDDE7FF),
                                border: Border.all(
                                  color: guest.isLocked
                                      ? const Color(0xFFE39B3A)
                                      : const Color(0xFF90A9E8),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${guest.seatNumber ?? index + 1}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: clampedBubbleLeft,
                            top: clampedBubbleTop,
                            child: _buildSpeechBubble(
                              guest.dietaryRestrictions.isEmpty
                                  ? guest.fullName
                                  : '${guest.fullName}\n${guest.dietaryRestrictions.join(', ')}',
                              alignRight: alignRight,
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVisualSeatingLayout() {
    final localizations = AppLocalizationsScope.of(context);
    final sortedTables = [...tables]..sort(
      (a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''),
    );

    return RepaintBoundary(
      key: _visualLayoutKey,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.text('seating_chart_visual_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    localizations.text('seating_chart_visual_description'),
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TableFloorPlanPage(weddingId: widget.weddingId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.grid_on),
                  label: Text(localizations.text('seating_chart_open_floor_plan')),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: sortedTables.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return _buildVisualTableCard(sortedTables[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingTables) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    List<Guest> unassignedGuests = widget.guests.where((g) {
      return !tables.any((t) => (t['assigned'] as List<Guest>).contains(g));
    }).toList();

    final isCompact = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizationsScope.of(context).text('seating_chart_title')),
        actions: [
          const LanguageToggleButton(),
          const SizedBox(width: 8),
          if (!isCompact)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: AppLocalizationsScope.of(context).text('seating_chart_export_pdf'),
              onPressed: _exportSeatingAsPdf,
            ),
          if (isCompact)
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: AppLocalizationsScope.of(context).text('auto_placement'),
              onPressed: _runPlacementAlgorithm,
            )
          else
            ElevatedButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: Text(AppLocalizationsScope.of(context).text('auto_placement')),
              onPressed: _runPlacementAlgorithm,
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: AppLocalizationsScope.of(context).text('auto_placement_settings'),
            onPressed: _showPlacementSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.grid_on),
            tooltip: AppLocalizationsScope.of(context).text('table_floor_plan_title'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TableFloorPlanPage(weddingId: widget.weddingId),
                ),
              );
            },
          ),
          if (!isCompact)
            const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add_box),
            tooltip: AppLocalizationsScope.of(context).text('add_table'),
            onPressed: () => _openTableFormDialog(),
          ),
          if (!isCompact) const SizedBox(width: 10),
        ],
      ),
      body: isCompact
          ? Column(
              children: [
                SizedBox(
                  height: 280,
                  child: _buildUnassignedPane(unassignedGuests, isCompact: true),
                ),
                Expanded(child: _buildTablesPane()),
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildTablesPane(),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 1,
                  child: _buildUnassignedPane(unassignedGuests, isCompact: false),
                ),
              ],
            ),
    );
  }
}
