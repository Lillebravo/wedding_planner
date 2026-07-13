import 'package:flutter/material.dart';
import '../models/guest_model.dart';
import '../services/storage_service.dart';

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
  bool _isLoadingTables = true;

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

  Future<void> _loadTables() async {
    try {
      final dbTables = await StorageService.getTables(widget.weddingId);

      if (dbTables.isEmpty) {
        // Om inga tabeller finns (edge case), skapa honnörsbordet lokalt
        if (!mounted) return;
        setState(() {
          tables = [
            {
              'id': 'local-honor-table-new',
              'name': 'Honnörsbord',
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

      // Ladda alla tabeller från Supabase
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

  int _knownGuestsAtTableCount(Guest guest, List<Guest> assigned) {
    return assigned.where((seated) => _isFriendOrPartner(guest, seated)).length;
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

  bool _matchesPlacementRule(
    PlacementRuleId rule,
    Guest guest,
    List<Guest> assigned,
    int candidateSeat,
    bool isCircularTable,
  ) {
    switch (rule) {
      case PlacementRuleId.friendAtTable:
        return assigned.any((seated) => _isFriendOrPartner(guest, seated));
      case PlacementRuleId.partnerAdjacent:
        final totalSeatsAfterPlacement = assigned.length + 1;
        for (int i = 0; i < assigned.length; i++) {
          final seated = assigned[i];
          final isPartner = _isPartnerRelation(guest, seated);
          if (!isPartner) continue;

          final seatedSeat = i + 1;
          if ((seatedSeat - candidateSeat).abs() == 1) {
            return true;
          }

          if (isCircularTable && totalSeatsAfterPlacement > 2) {
            final wrapsAround =
                (candidateSeat == 1 && seatedSeat == totalSeatsAfterPlacement) ||
                (candidateSeat == totalSeatsAfterPlacement && seatedSeat == 1);
            if (wrapsAround) {
              return true;
            }
          }
        }
        return false;
    }
  }

  int _placementScore(
    Guest guest,
    List<Guest> assigned,
    int candidateSeat,
    bool isCircularTable,
  ) {
    final enabledRules = _placementRules.where((r) => r.enabled).toList();
    if (enabledRules.isEmpty) return 0;

    int score = 0;
    for (int i = 0; i < enabledRules.length; i++) {
      final rule = enabledRules[i];
      final weight = (enabledRules.length - i) * 100;
      if (_matchesPlacementRule(rule.id, guest, assigned, candidateSeat, isCircularTable)) {
        score += weight;
      }
    }

    return score;
  }

  Future<void> _showPlacementSettingsDialog() async {
    final updatedRules = _placementRules
        .map(
          (rule) => PlacementRuleSetting(
            id: rule.id,
            title: rule.title,
            enabled: rule.enabled,
          ),
        )
        .toList();

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Inställningar för autoplacering'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Slå av/på regler och dra för att välja vilken regel som är viktigast.',
                  ),
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
                            subtitle: Text('Prioritet ${index + 1}'),
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
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Avbryt'),
              ),
              ElevatedButton(
                onPressed: () async {
                  setState(() {
                    _placementRules
                      ..clear()
                      ..addAll(updatedRules);
                  });
                  Navigator.pop(dialogContext);
                  await _persistPlacementRules();
                },
                child: const Text('Spara'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Nu är metoden async och uppdaterar sätesnummer & databasen!
  Future<void> _runPlacementAlgorithm() async {
    setState(() {
      final hosts = widget.guests
          .where((g) => g.title == GuestTitle.bride || g.title == GuestTitle.groom)
          .toList();
      final standardGuests = widget.guests
          .where((g) => g.title != GuestTitle.bride && g.title != GuestTitle.groom)
          .toList();

      for (var host in hosts) {
        for (var guest in standardGuests) {
          if (!host.relations.containsKey(guest.id)) {
            host.relations[guest.id] = RelationType.friend;
          }
          if (!guest.relations.containsKey(host.id)) {
            guest.relations[host.id] = RelationType.friend;
          }
        }
      }

      List<Guest> unassigned = widget.guests.where((g) {
        if (g.isLocked && g.tableId != null) return false;
        return true;
      }).toList();

      for (final guest in unassigned) {
        guest.tableId = null;
        guest.seatNumber = null;
      }

      for (var table in tables) {
        List<Guest> assigned = table['assigned'] as List<Guest>;
        assigned.removeWhere((g) => !g.isLocked);
        _sortAssignedBySeat(assigned);
        _reindexSeats(assigned, table);
      }

      int totalAvailableSeats = 0;
      for (var t in tables) {
        totalAvailableSeats += (t['seats'] as int) - (t['assigned'] as List<Guest>).length;
      }

      if (unassigned.length > totalAvailableSeats) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red[700],
            content: Text(
              '⚠️ Det finns inte tillräckligt med bord! Det saknas ${unassigned.length - totalAvailableSeats} platser.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      unassigned.sort((a, b) => b.relations.length.compareTo(a.relations.length));

      bool changesMade = true;
      while (unassigned.isNotEmpty && changesMade) {
        changesMade = false;

        Guest? bestGuest;
        int bestTableIndex = -1;
        int bestSeat = -1;
        int bestScore = -1;
        int bestKnownCount = -1;

        for (int tableIndex = 0; tableIndex < tables.length; tableIndex++) {
          final table = tables[tableIndex];
          final List<Guest> assigned = table['assigned'] as List<Guest>;
          final int maxSeats = table['seats'] as int;
          final bool isCircularTable = (table['shape']?.toString().toLowerCase() ?? '') == 'cirkel';

          if (assigned.length >= maxSeats) continue;

          for (final guest in unassigned) {
            if (_hasAvoidConflict(guest, assigned)) continue;

            final knownCount = _knownGuestsAtTableCount(guest, assigned);

            for (int candidateSeat = 1; candidateSeat <= assigned.length + 1; candidateSeat++) {
              final score = _placementScore(guest, assigned, candidateSeat, isCircularTable);
              final isBetter =
                  score > bestScore ||
                  (score == bestScore && knownCount > bestKnownCount) ||
                  (score == bestScore &&
                      knownCount == bestKnownCount &&
                      bestGuest != null &&
                      guest.relations.length > bestGuest.relations.length) ||
                  (bestGuest == null);

              if (isBetter) {
                bestScore = score;
                bestKnownCount = knownCount;
                bestGuest = guest;
                bestTableIndex = tableIndex;
                bestSeat = candidateSeat;
              }
            }
          }
        }

        if (bestGuest != null && bestTableIndex >= 0 && bestSeat > 0) {
          final List<Guest> assigned = tables[bestTableIndex]['assigned'] as List<Guest>;
          assigned.insert(bestSeat - 1, bestGuest);
          unassigned.remove(bestGuest);
          changesMade = true;
        }
      }

      // Fördela om ensamma gäster
      for (var table in tables) {
        List<Guest> assigned = table['assigned'] as List<Guest>;
        if (assigned.length == 1 && widget.guests.length > 1) {
          Guest loneWolf = assigned.first;
          if (!loneWolf.isLocked) {
            for (var otherTable in tables) {
              if (otherTable['id'] == table['id']) continue;
              List<Guest> otherAssigned = otherTable['assigned'] as List<Guest>;
              if (otherAssigned.length < (otherTable['seats'] as int)) {
                assigned.clear();
                otherAssigned.add(loneWolf);
                break;
              }
            }
          }
        }
      }

      // Ge alla gäster korrekta sätesnummer och tableId
      for (var table in tables) {
        List<Guest> assigned = table['assigned'] as List<Guest>;
        _sortAssignedBySeat(assigned);
        _reindexSeats(assigned, table);
      }
    });

    // Synka hela den nya placeringen live mot Supabase
    final messenger = ScaffoldMessenger.of(context);
    try {
      await StorageService.saveGuests(widget.weddingId, widget.guests);
      messenger.showSnackBar(
        const SnackBar(content: Text('✅ Autoplacering slutförd och sparad i molnet!')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Ett fel uppstod: $e')),
      );
    }
  }

  void _openTableFormDialog({Map<String, dynamic>? tableToEdit}) {
    final isEditing = tableToEdit != null;
    final nameCtrl = TextEditingController(
      text: isEditing ? tableToEdit['name'] : 'Bord ${tables.length + 1}',
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
            title: Text(isEditing ? 'Redigera bord' : 'Skapa nytt bord'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Bordsnamn *'),
                  ),
                  TextField(
                    controller: seatsCtrl,
                    decoration: const InputDecoration(labelText: 'Antal sittplatser *'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: selectedShape,
                    decoration: const InputDecoration(labelText: 'Bordsform'),
                    items: ['Kvadrat', 'Rektangel', 'Cirkel', 'Oval']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => selectedShape = val!),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Placerade gäster (${currentAssigned.length} / $maxSeatsAllowed)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOverflown ? Colors.red : Colors.black,
                    ),
                  ),
                  if (isOverflown) ...[
                    const Text(
                      '⚠️ För många gäster! Ta bort gäster nedan innan du sparar.',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  SizedBox(
                    width: double.maxFinite,
                    height: 120,
                    child: currentAssigned.isEmpty
                        ? const Center(
                            child: Text('Bordet är tomt.', style: TextStyle(color: Colors.grey)),
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
                      hint: const Text('Sätt direkt vid bordet...'),
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
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Avbryt'),
              ),
              ElevatedButton(
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
                child: const Text('Spara'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteTable(Map<String, dynamic> table) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ta bort bord?'),
        content: Text('Är du säker på att du vill ta bort ${table['name']}? Alla gäster blir oplacerade.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Avbryt'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
            child: const Text('Ta bort', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildTablesPane() {
    return Container(
      color: Colors.grey[200],
      child: tables.isEmpty
          ? const Center(child: Text('Inga bord skapade.'))
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
                        const SnackBar(content: Text('Bordet är fullt!')),
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
                                    '${table['name']} (${table['shape']} - ${assignedGuests.length}/${table['seats']} stolar)',
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
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text('Dra gäster hit...', style: TextStyle(color: Colors.grey)),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Oplacerade personer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Sök efter namn...',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _chartSearchQuery = val),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: DropdownButtonFormField<GuestTitle>(
              initialValue: _chartTitleFilter,
              decoration: const InputDecoration(labelText: 'Filtrera efter roll'),
              isExpanded: true,
              isDense: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('Alla roller')),
                ...GuestTitle.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))),
              ],
              onChanged: (val) => setState(() => _chartTitleFilter = val),
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: Builder(
              builder: (context) {
                final menuList = unassignedGuests.where((g) {
                  final matchesSearch = g.fullName.toLowerCase().contains(_chartSearchQuery.toLowerCase());
                  final matchesTitle = _chartTitleFilter == null || g.title == _chartTitleFilter;
                  return matchesSearch && matchesTitle;
                }).toList();

                if (menuList.isEmpty) {
                  return const Center(
                    child: Text('Inga personer matchar.', style: TextStyle(color: Colors.grey)),
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
                          subtitle: Text(guest.title.name),
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
        title: const Text('Bordsplacering'),
        actions: [
          if (isCompact)
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'Autoplacera',
              onPressed: _runPlacementAlgorithm,
            )
          else
            ElevatedButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Autoplacera'),
              onPressed: _runPlacementAlgorithm,
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Inställningar för autoplacering',
            onPressed: _showPlacementSettingsDialog,
          ),
          if (!isCompact)
            const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add_box),
            tooltip: 'Skapa nytt bord',
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
                Expanded(flex: 3, child: _buildTablesPane()),
                Expanded(
                  flex: 1,
                  child: _buildUnassignedPane(unassignedGuests, isCompact: false),
                ),
              ],
            ),
    );
  }
}