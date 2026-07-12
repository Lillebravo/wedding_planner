import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/guest_model.dart';
import '../models/wedding_model.dart';
import '../services/storage_service.dart';
import 'seating_chart_page.dart';

class GuestListPage extends StatefulWidget {
  const GuestListPage({super.key});

  @override
  State<GuestListPage> createState() => _GuestListPageState();
}

class _GuestListPageState extends State<GuestListPage> {
  Wedding? _activeWedding;
  List<Guest> guests = [];
  bool _isLoading = true;

  String _searchQuery = '';
  GuestTitle? _selectedTitleFilter;
  bool _filterOnlyDiet = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final wedding = await StorageService.getActiveWedding();
    if (wedding != null) {
      final loadedGuests = await StorageService.getGuests(wedding.id);
      setState(() {
        _activeWedding = wedding;
        guests = loadedGuests;
        _isLoading = false;
      });
    }
  }

  void _syncToStorage() async {
    if (_activeWedding != null) {
      await StorageService.saveGuests(_activeWedding!.id, guests);
    }
  }

  void _openGuestFormDialog({Guest? guestToEdit}) {
    final isEditing = guestToEdit != null;

    final firstNameCtrl = TextEditingController(
      text: isEditing ? guestToEdit.firstName : '',
    );
    final lastNameCtrl = TextEditingController(
      text: isEditing ? guestToEdit.lastName : '',
    );
    final emailCtrl = TextEditingController(
      text: isEditing ? guestToEdit.email : '',
    );
    final phoneCtrl = TextEditingController(
      text: isEditing ? guestToEdit.phoneNumber : '',
    );
    final dietCtrl = TextEditingController(
      text: isEditing ? guestToEdit.dietaryRestrictions : '',
    );
    GuestTitle selectedTitle = isEditing ? guestToEdit.title : GuestTitle.none;

    bool isDuplicate = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void checkDuplicate() {
              final newFullName =
                  '${firstNameCtrl.text.trim().toLowerCase()} ${lastNameCtrl.text.trim().toLowerCase()}';
              bool duplicateFound = guests.any((g) {
                if (isEditing && g.id == guestToEdit.id) return false;
                return '${g.firstName.toLowerCase()} ${g.lastName.toLowerCase()}' ==
                    newFullName;
              });
              setDialogState(() => isDuplicate = duplicateFound);
            }

            final bool isFieldsEmpty =
                firstNameCtrl.text.trim().isEmpty ||
                lastNameCtrl.text.trim().isEmpty;

            return AlertDialog(
              title: Text(isEditing ? 'Redigera person' : 'Lägg till gäst'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: firstNameCtrl,
                      decoration: const InputDecoration(labelText: 'Förnamn *'),
                      onChanged: (_) => checkDuplicate(),
                    ),
                    TextField(
                      controller: lastNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Efternamn *',
                      ),
                      onChanged: (_) => checkDuplicate(),
                    ),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'E-post (Frivilligt)',
                      ),
                    ),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Telefonnummer (Frivilligt)',
                      ),
                    ),
                    TextField(
                      controller: dietCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Specialkost/Allergier (Frivilligt)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<GuestTitle>(
                      initialValue: selectedTitle,
                      decoration: const InputDecoration(
                        labelText: 'Titel/Roll',
                      ),
                      items: GuestTitle.values
                          .map(
                            (title) => DropdownMenuItem(
                              value: title,
                              child: Text(title.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedTitle = value);
                        }
                      },
                    ),
                    if (isDuplicate) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Denna person finns redan i listan.',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
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
                  onPressed: (isDuplicate || isFieldsEmpty)
                      ? null
                      : () {
                          setState(() {
                            if (isEditing) {
                              guestToEdit.firstName = firstNameCtrl.text.trim();
                              guestToEdit.lastName = lastNameCtrl.text.trim();
                              guestToEdit.email = emailCtrl.text.trim().isEmpty
                                  ? null
                                  : emailCtrl.text.trim();
                              guestToEdit.phoneNumber =
                                  phoneCtrl.text.trim().isEmpty
                                  ? null
                                  : phoneCtrl.text.trim();
                              guestToEdit.dietaryRestrictions =
                                  dietCtrl.text.trim().isEmpty
                                  ? null
                                  : dietCtrl.text.trim();
                              guestToEdit.title = selectedTitle;
                            } else {
                              final newGuest = Guest(
                                id: DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                                firstName: firstNameCtrl.text.trim(),
                                lastName: lastNameCtrl.text.trim(),
                                email: emailCtrl.text.trim().isEmpty
                                    ? null
                                    : emailCtrl.text.trim(),
                                phoneNumber: phoneCtrl.text.trim().isEmpty
                                    ? null
                                    : phoneCtrl.text.trim(),
                                dietaryRestrictions:
                                    dietCtrl.text.trim().isEmpty
                                    ? null
                                    : dietCtrl.text.trim(),
                                title: selectedTitle,
                              );

                              final hosts = guests
                                  .where(
                                    (g) =>
                                        g.title == GuestTitle.bride ||
                                        g.title == GuestTitle.groom,
                                  )
                                  .toList();
                              for (var host in hosts) {
                                newGuest.relations[host.id] =
                                    RelationType.friend;
                                host.relations[newGuest.id] =
                                    RelationType.friend;
                              }

                              guests.add(newGuest);
                            }
                          });
                          _syncToStorage();
                          Navigator.pop(dialogContext);
                        },
                  child: Text(isEditing ? 'Spara' : 'Lägg till'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteDialog(Guest guest) {
    if (guest.title == GuestTitle.bride || guest.title == GuestTitle.groom) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Värdarna (Brudparet) kan inte raderas från sitt eget bröllop!',
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ta bort gäst?'),
        content: Text('Är du säker på att du vill ta bort ${guest.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Avbryt'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                guests.removeWhere((g) => g.id == guest.id);
                for (var other in guests) {
                  other.relations.remove(guest.id);
                }
              });
              _syncToStorage();
              Navigator.pop(dialogContext);
            },
            child: const Text('Ta bort', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hostCount = guests
        .where(
          (g) => g.title == GuestTitle.bride || g.title == GuestTitle.groom,
        )
        .length;
    final guestCount = guests.length - hostCount;

    final filteredGuests = guests.where((guest) {
      final matchesSearch = guest.fullName.toLowerCase().contains(
        _searchQuery.toLowerCase(),
      );
      final matchesTitle =
          _selectedTitleFilter == null || guest.title == _selectedTitleFilter;
      final matchesDiet =
          !_filterOnlyDiet ||
          (guest.dietaryRestrictions != null &&
              guest.dietaryRestrictions!.isNotEmpty);
      return matchesSearch && matchesTitle && matchesDiet;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Värdar: $hostCount | Gäster: $guestCount'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Exportera allt (Kopiera JSON)',
            onPressed: () async {
              if (_activeWedding != null) {
                // Spara undan ScaffoldMessengerState synkront innan det asynkrona gapet
                final messenger = ScaffoldMessenger.of(context);
                final jsonStr = await StorageService.exportWeddingToClipboard(
                  _activeWedding!.id,
                );
                await Clipboard.setData(ClipboardData(text: jsonStr));

                // Använd den sparade referensen istället för att läsa BuildContext efter await
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      '🚀 Hela bröllopsdatan har kopierats till urklipp! Skicka texten till din partner.',
                    ),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Importera från JSON-text',
            onPressed: () {
              final importController = TextEditingController();
              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Importera data'),
                  content: TextField(
                    controller: importController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText:
                          'Klistra in JSON-koden du fick från din partner här...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Avbryt'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final text = importController.text.trim();
                        if (text.isEmpty) return;

                        // Spara undan navigeringstillsyner och meddelandepaneler synkront
                        final navigator = Navigator.of(dialogContext);
                        final messenger = ScaffoldMessenger.of(context);

                        try {
                          await StorageService.importWeddingFromJson(text);

                          // Stäng dialogen direkt via den sparade synkrona referensen
                          navigator.pop();

                          // Ladda om statet för komponenten
                          _loadData();

                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                '🎉 Lyckad import! Allt är synkat.',
                              ),
                            ),
                          );
                        } catch (e) {
                          // Om importen kraschar stänger vi inte dialogrutan utan visar bara felmeddelande
                          messenger.showSnackBar(
                            const SnackBar(
                              backgroundColor: Colors.red,
                              content: Text(
                                '⚠️ Felaktig kod. Kunde inte läsa datan.',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Importera'),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.chair_alt),
            onPressed: () {
              if (_activeWedding != null) {
                // Säkerställ att bröllopet är laddat
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SeatingChartPage(
                      guests: guests,
                      weddingId: _activeWedding!.id, // ✅ Skicka med ID:t här!
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Sök i listan...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<GuestTitle>(
                            hint: const Text('Filtrera på titel'),
                            value: _selectedTitleFilter,
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Alla roller'),
                              ),
                              ...GuestTitle.values.map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.name),
                                ),
                              ),
                            ],
                            onChanged: (val) =>
                                setState(() => _selectedTitleFilter = val),
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilterChip(
                          label: const Text('Bara specialkost'),
                          selected: _filterOnlyDiet,
                          onSelected: (val) =>
                              setState(() => _filterOnlyDiet = val),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredGuests.isEmpty
                ? const Center(child: Text('Inga träffar.'))
                : ListView.builder(
                    itemCount: filteredGuests.length,
                    itemBuilder: (context, index) {
                      final guest = filteredGuests[index];
                      final isHost =
                          guest.title == GuestTitle.bride ||
                          guest.title == GuestTitle.groom;

                      return Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          tileColor: isHost ? Colors.pink[50] : null,
                          title: Text(
                            guest.fullName,
                            style: TextStyle(
                              fontWeight: isHost
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            'Roll: ${guest.title.name} • Kost: ${guest.dietaryRestrictions ?? "Ingen"} • Relationer: ${guest.relations.length}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.people_alt_outlined,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _manageRelationsDialog(guest),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.orange,
                                ),
                                onPressed: () =>
                                    _openGuestFormDialog(guestToEdit: guest),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _confirmDeleteDialog(guest),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openGuestFormDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _manageRelationsDialog(Guest currentGuest) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final otherGuests = guests
                .where((g) => g.id != currentGuest.id)
                .toList();
            return AlertDialog(
              title: Text('Vem känner ${currentGuest.firstName}?'),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: otherGuests.isEmpty
                    ? const Center(child: Text('Här var det tomt.'))
                    : ListView.builder(
                        itemCount: otherGuests.length,
                        itemBuilder: (context, i) {
                          final other = otherGuests[i];
                          final currentRelationType =
                              currentGuest.relations[other.id];

                          return ListTile(
                            title: Text(other.fullName),
                            trailing: DropdownButton<RelationType>(
                              hint: const Text('Välj relation'),
                              value: currentRelationType,
                              items: RelationType.values.map((type) {
                                String label = type.name;
                                if (type == RelationType.none) {
                                  label = 'Ingen relation (Rensa)';
                                }
                                if (type == RelationType.partner) {
                                  label = 'Partner (+1)';
                                }
                                if (type == RelationType.friend) {
                                  label = 'Vän';
                                }
                                if (type == RelationType.avoid) {
                                  label = 'Undvik placering';
                                }

                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(label),
                                );
                              }).toList(),
                              onChanged: (type) {
                                setState(() {
                                  setDialogState(() {
                                    if (type != null) {
                                      if (type == RelationType.none) {
                                        // Om man väljer "Ingen relation", ta bort nycklarna helt ur minnet
                                        currentGuest.relations.remove(other.id);
                                        other.relations.remove(currentGuest.id);
                                      } else {
                                        // Annars sparar vi den valda relationen
                                        currentGuest.relations[other.id] = type;
                                        other.relations[currentGuest.id] = type;
                                      }
                                    }
                                  });
                                });
                                _syncToStorage();
                              },
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Klar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
