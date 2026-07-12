import 'package:flutter/material.dart';
import '../models/guest_model.dart';
import '../services/storage_service.dart';

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

  List<Map<String, dynamic>> tables = [
    {
      'id': 'local-honor-table',
      'name': 'Honnörsbord',
      'seats': 8,
      'shape': 'Rektangel',
      'assigned': <Guest>[],
    },
  ];

  @override
  void initState() {
    super.initState();
    _syncHonorTableIdFromGuests();
    _prePlaceLockedGuests();
  }

  void _syncHonorTableIdFromGuests() {
    for (final guest in widget.guests) {
      final normalizedTableId = StorageService.normalizeUuidOrNull(guest.tableId);
      if (normalizedTableId != null) {
        tables[0]['id'] = normalizedTableId;
        return;
      }
    }
  }

  void _assignGuestToTable(Guest guest, Map<String, dynamic> table, int seatIndex) {
    guest.tableId = StorageService.normalizeUuidOrNull(table['id']?.toString());
    guest.seatNumber = seatIndex;
  }

  void _prePlaceLockedGuests() {
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

      for (var table in tables) {
        List<Guest> assigned = table['assigned'] as List<Guest>;
        assigned.removeWhere((g) => !g.isLocked);
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

        for (var table in tables) {
          if (unassigned.isEmpty) break;

          List<Guest> assigned = table['assigned'] as List<Guest>;
          int maxSeats = table['seats'] as int;

          if (assigned.length >= maxSeats) continue;

          Guest? bestCandidate;

          for (var guest in unassigned) {
            bool hasConflict = false;
            for (var seated in assigned) {
              if (guest.relations[seated.id] == RelationType.avoid ||
                  seated.relations[guest.id] == RelationType.avoid) {
                hasConflict = true;
                break;
              }
            }

            if (hasConflict) continue;

            bool hasFriendHere = assigned.any(
              (seated) =>
                  guest.relations[seated.id] == RelationType.friend ||
                  guest.relations[seated.id] == RelationType.partner,
            );

            if (hasFriendHere || bestCandidate == null) {
              bestCandidate = guest;
              if (hasFriendHere) break;
            }
          }

          if (bestCandidate != null) {
            unassigned.remove(bestCandidate);
            assigned.add(bestCandidate);
            changesMade = true;
          }
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
        for (int i = 0; i < assigned.length; i++) {
          _assignGuestToTable(assigned[i], table, i + 1);
        }
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
                        final nav = Navigator.of(dialogContext);
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
                        nav.pop();
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
              final nav = Navigator.of(dialogContext);
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
              nav.pop();
            },
            child: const Text('Ta bort', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Guest> unassignedGuests = widget.guests.where((g) {
      return !tables.any((t) => (t['assigned'] as List<Guest>).contains(g));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bordsplacering'),
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Autoplacera'),
            onPressed: _runPlacementAlgorithm,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add_box),
            tooltip: 'Skapa nytt bord',
            onPressed: () => _openTableFormDialog(),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.grey[200],
              child: tables.isEmpty
                  ? const Center(child: Text('Inga bord skapade.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: tables.length,
                      itemBuilder: (context, index) {
                        final table = tables[index];
                        final List<Guest> assignedGuests = table['assigned'];

                        return DragTarget<Guest>(
                          onAcceptWithDetails: (details) async {
                            if (assignedGuests.length >= table['seats']) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Bordet är fullt!')),
                              );
                              return;
                            }
                            setState(() {
                              for (var t in tables) {
                                (t['assigned'] as List<Guest>).remove(details.data);
                              }
                              assignedGuests.add(details.data);
                              // Sätt seatNumber till det nya indexet
                              _assignGuestToTable(details.data, table, assignedGuests.length);
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
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${table['name']} (${table['shape']} - ${assignedGuests.length}/${table['seats']} stolar)',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        Row(
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
                                    Wrap(
                                      spacing: 8,
                                      children: assignedGuests.map((guest) {
                                        return FilterChip(
                                          avatar: Icon(guest.isLocked ? Icons.lock : Icons.lock_open, size: 16),
                                          label: Text('${guest.seatNumber}. ${guest.fullName}'),
                                          selected: guest.isLocked,
                                          selectedColor: Colors.amber[100],
                                          backgroundColor: Colors.blue[50],
                                          showCheckmark: false,
                                          onSelected: (bool selected) async {
                                            setState(() => guest.isLocked = selected);
                                            await StorageService.saveGuests(widget.weddingId, widget.guests);
                                          },
                                          onDeleted: () async {
                                            setState(() {
                                              assignedGuests.remove(guest);
                                              guest.tableId = null;
                                              guest.seatNumber = null;
                                              // Packa om sätesnumren för de som sitter kvar
                                              for (int i = 0; i < assignedGuests.length; i++) {
                                                assignedGuests[i].seatNumber = i + 1;
                                              }
                                            });
                                            await StorageService.saveGuests(widget.weddingId, widget.guests);
                                          },
                                        );
                                      }).toList(),
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
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(left: BorderSide(color: Colors.grey[300]!)),
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
            ),
          ),
        ],
      ),
    );
  }
}