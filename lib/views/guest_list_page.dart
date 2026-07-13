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

enum GuestSortOption {
  nameAscending,
  nameDescending,
  createdNewest,
  createdOldest,
}

class _GuestListPageState extends State<GuestListPage> {
  Wedding? _activeWedding;
  List<Guest> guests = [];
  bool _isLoading = true;

  String _searchQuery = '';
  GuestTitle? _selectedTitleFilter;
  bool _filterOnlyDiet = false;
  GuestSortOption _selectedSort = GuestSortOption.nameAscending;

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

  bool _isHost(Guest guest) {
    return guest.title == GuestTitle.bride || guest.title == GuestTitle.groom;
  }

  int _hostPriority(Guest guest) {
    if (guest.title == GuestTitle.bride) return 0;
    if (guest.title == GuestTitle.groom) return 1;
    return 2;
  }

  int _createdTimestamp(Guest guest) {
    return int.tryParse(guest.id) ?? -1;
  }

  bool _matchesActiveFilters(Guest guest) {
    final matchesSearch = guest.fullName.toLowerCase().contains(
      _searchQuery.toLowerCase(),
    );
    final matchesTitle =
        _selectedTitleFilter == null || guest.title == _selectedTitleFilter;
    final matchesDiet =
        !_filterOnlyDiet ||
        (guest.dietaryRestrictions != null &&
            guest.dietaryRestrictions!.trim().isNotEmpty);

    return matchesSearch && matchesTitle && matchesDiet;
  }

  List<Guest> _buildVisibleGuests() {
    final hosts = guests.where(_isHost).toList()
      ..sort((a, b) => _hostPriority(a).compareTo(_hostPriority(b)));

    final visibleGuests = guests
        .where((g) => !_isHost(g))
        .where(_matchesActiveFilters)
        .toList();

    switch (_selectedSort) {
      case GuestSortOption.nameAscending:
        visibleGuests.sort(
          (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
        break;
      case GuestSortOption.nameDescending:
        visibleGuests.sort(
          (a, b) => b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase()),
        );
        break;
      case GuestSortOption.createdNewest:
        visibleGuests.sort(
          (a, b) => _createdTimestamp(b).compareTo(_createdTimestamp(a)),
        );
        break;
      case GuestSortOption.createdOldest:
        visibleGuests.sort(
          (a, b) => _createdTimestamp(a).compareTo(_createdTimestamp(b)),
        );
        break;
    }

    return [...hosts, ...visibleGuests];
  }

  String _sortLabel(GuestSortOption sort) {
    switch (sort) {
      case GuestSortOption.nameAscending:
        return 'Namn A-Ö';
      case GuestSortOption.nameDescending:
        return 'Namn Ö-A';
      case GuestSortOption.createdNewest:
        return 'Skapad senast';
      case GuestSortOption.createdOldest:
        return 'Skapad först';
    }
  }

  Widget _buildConfettiDivider() {
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
            (color) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.change_history, size: 13, color: color),
            ),
          )
          .toList(),
    );
  }

  Widget _buildGuestCard(Guest guest, bool isCompact) {
    final isHost = _isHost(guest);
    final role = guest.title.name;
    final diet = guest.dietaryRestrictions?.trim().isNotEmpty == true
        ? guest.dietaryRestrictions!
        : 'Ingen';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: isHost ? const Color(0xFFECC0CD) : const Color(0xFFF1ECEE),
          width: isHost ? 1.2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isHost
                    ? const Color(0xFFFCE7EE)
                    : const Color(0xFFF6F3F4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isHost ? Icons.favorite : Icons.person_outline,
                color: isHost ? const Color(0xFFC46C84) : const Color(0xFF77686D),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        guest.fullName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight:
                              isHost ? FontWeight.w700 : FontWeight.w600,
                          color: const Color(0xFF24191D),
                        ),
                      ),
                      if (isHost)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDEDF2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Värd',
                            style: TextStyle(
                              color: Color(0xFFC46C84),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Roll: $role · Kost: $diet · Relationer: ${guest.relations.length}',
                    style: const TextStyle(
                      color: Color(0xFF6E6166),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            isCompact
                ? PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'relations':
                          _manageRelationsDialog(guest);
                          break;
                        case 'edit':
                          _openGuestFormDialog(guestToEdit: guest);
                          break;
                        case 'delete':
                          _confirmDeleteDialog(guest);
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'relations',
                        child: Text('Hantera relationer'),
                      ),
                      PopupMenuItem(value: 'edit', child: Text('Redigera')),
                      PopupMenuItem(value: 'delete', child: Text('Ta bort')),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.people_alt_outlined,
                          color: Color(0xFF5778B1),
                        ),
                        tooltip: 'Relationer',
                        onPressed: () => _manageRelationsDialog(guest),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Color(0xFFC1834D),
                        ),
                        tooltip: 'Redigera',
                        onPressed: () => _openGuestFormDialog(guestToEdit: guest),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFC25353),
                        ),
                        tooltip: 'Ta bort',
                        onPressed: () => _confirmDeleteDialog(guest),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isCompact = MediaQuery.of(context).size.width < 700;

    final hostCount = guests
        .where(
          (g) => g.title == GuestTitle.bride || g.title == GuestTitle.groom,
        )
        .length;
    final guestCount = guests.length - hostCount;
    final visibleGuests = _buildVisibleGuests();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F4F6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF24191D),
        elevation: 0,
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
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Guest List',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF24191D),
                        ),
                      ),
                      const Spacer(),
                      _buildConfettiDivider(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Sök i listan...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFFF7F3F4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                  const SizedBox(height: 10),
                  Flex(
                    direction: isCompact ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: isCompact
                        ? CrossAxisAlignment.stretch
                        : CrossAxisAlignment.center,
                    children: [
                      if (isCompact)
                        DropdownButtonFormField<GuestSortOption>(
                          initialValue: _selectedSort,
                          decoration: const InputDecoration(
                            labelText: 'Sortera',
                          ),
                          items: GuestSortOption.values
                              .map(
                                (sort) => DropdownMenuItem(
                                  value: sort,
                                  child: Text(_sortLabel(sort)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedSort = value);
                            }
                          },
                        )
                      else
                        Expanded(
                          child: DropdownButtonFormField<GuestSortOption>(
                            initialValue: _selectedSort,
                            decoration: const InputDecoration(
                              labelText: 'Sortera',
                            ),
                            items: GuestSortOption.values
                                .map(
                                  (sort) => DropdownMenuItem(
                                    value: sort,
                                    child: Text(_sortLabel(sort)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedSort = value);
                              }
                            },
                          ),
                        ),
                      SizedBox(
                        width: isCompact ? 0 : 10,
                        height: isCompact ? 10 : 0,
                      ),
                      if (isCompact)
                        DropdownButtonFormField<GuestTitle?>(
                          initialValue: _selectedTitleFilter,
                          decoration: const InputDecoration(
                            labelText: 'Filtrera roll',
                          ),
                          items: [
                            const DropdownMenuItem<GuestTitle?>(
                              value: null,
                              child: Text('Alla roller'),
                            ),
                            ...GuestTitle.values.map(
                              (title) => DropdownMenuItem<GuestTitle?>(
                                value: title,
                                child: Text(title.name),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedTitleFilter = value);
                          },
                        )
                      else
                        Expanded(
                          child: DropdownButtonFormField<GuestTitle?>(
                            initialValue: _selectedTitleFilter,
                            decoration: const InputDecoration(
                              labelText: 'Filtrera roll',
                            ),
                            items: [
                              const DropdownMenuItem<GuestTitle?>(
                                value: null,
                                child: Text('Alla roller'),
                              ),
                              ...GuestTitle.values.map(
                                (title) => DropdownMenuItem<GuestTitle?>(
                                  value: title,
                                  child: Text(title.name),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedTitleFilter = value);
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Bara specialkost'),
                        selected: _filterOnlyDiet,
                        onSelected: (val) =>
                            setState(() => _filterOnlyDiet = val),
                      ),
                      const Chip(
                        avatar: Icon(Icons.push_pin_outlined, size: 16),
                        label: Text('Värdar är alltid pinnade överst'),
                      ),
                    ],
                  ),
                ],
              ),
              ),
          ),
          Expanded(
            child: visibleGuests.isEmpty
                ? const Center(child: Text('Inga träffar.'))
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      6,
                      14,
                      isCompact ? 88 : 72,
                    ),
                    itemCount: visibleGuests.length,
                    itemBuilder: (context, index) {
                      final guest = visibleGuests[index];
                      return _buildGuestCard(guest, isCompact);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: SafeArea(
        child: isCompact
            ? FloatingActionButton.small(
                onPressed: () => _openGuestFormDialog(),
                child: const Icon(Icons.add),
              )
            : FloatingActionButton(
                onPressed: () => _openGuestFormDialog(),
                child: const Icon(Icons.add),
              ),
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
