import 'package:flutter/material.dart';
import '../models/guest_model.dart';
import '../models/wedding_model.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';
import 'seating_chart_page.dart';
import '../widgets/app_dropdown_form_field.dart';
import '../widgets/app_labeled_text_field.dart';
import '../widgets/app_search_field.dart';
import '../widgets/dialog_action_buttons.dart';
import '../widgets/dialog_title_with_close.dart';
import '../widgets/language_toggle_button.dart';
import '../widgets/preset_options_input.dart';

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
    final localizations = AppLocalizationsScope.of(context);
    final isEditing = guestToEdit != null;

    final commonDietOptions = [
      localizations.text('diet_option_vegetarian'),
      localizations.text('diet_option_vegan'),
      localizations.text('diet_option_pescetarian'),
      localizations.text('diet_option_gluten_free'),
      localizations.text('diet_option_lactose_free'),
      localizations.text('diet_option_nut_allergy'),
      localizations.text('diet_option_milk_protein_allergy'),
      localizations.text('diet_option_egg_allergy'),
      localizations.text('diet_option_shellfish_allergy'),
    ];

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
    List<String> dietValues = isEditing
        ? List<String>.from(guestToEdit.dietaryRestrictions)
        : <String>[];
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
              title: DialogTitleWithClose(
                titleText: isEditing
                    ? localizations.text('guest_edit_person')
                    : localizations.text('guest_add_guest'),
                onClose: () => Navigator.pop(dialogContext),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppLabeledTextField(
                      controller: firstNameCtrl,
                      labelText: '${localizations.text('first_name')} *',
                      onChanged: (_) => checkDuplicate(),
                    ),
                    AppLabeledTextField(
                      controller: lastNameCtrl,
                      labelText: '${localizations.text('last_name')} *',
                      onChanged: (_) => checkDuplicate(),
                    ),
                    AppLabeledTextField(
                      controller: emailCtrl,
                      labelText: localizations.text('email_optional'),
                    ),
                    AppLabeledTextField(
                      controller: phoneCtrl,
                      labelText: localizations.text('phone_optional'),
                    ),
                    const SizedBox(height: 12),
                    PresetOptionsInput(
                      labelText: localizations.text('special_diet_optional'),
                      hintText: localizations.text('preset_custom_hint'),
                      options: commonDietOptions,
                      selectedValues: dietValues,
                      onChanged: (values) {
                        setDialogState(() {
                          dietValues = values;
                        });
                      },
                      multiSelect: true,
                    ),
                    const SizedBox(height: 16),
                    AppDropdownFormField<GuestTitle>(
                      initialValue: selectedTitle,
                      labelText: localizations.text('guest_role_title'),
                      items: GuestTitle.values
                          .map(
                            (title) => DropdownMenuItem(
                              value: title,
                              child: Text(localizations.guestTitle(title)),
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
                      Text(
                        localizations.text('guest_already_exists'),
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
                DialogConfirmButton(
                  label: isEditing
                      ? localizations.text('save')
                      : localizations.text('add'),
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
                              guestToEdit.dietaryRestrictions = _normalizeDietValues(dietValues);
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
                                dietaryRestrictions: _normalizeDietValues(dietValues),
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
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteDialog(Guest guest) {
    final localizations = AppLocalizationsScope.of(context);
    if (guest.title == GuestTitle.bride || guest.title == GuestTitle.groom) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.text('hosts_cannot_be_deleted'))),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: DialogTitleWithClose(
          titleText: localizations.text('delete_guest_title'),
          onClose: () => Navigator.pop(dialogContext),
        ),
        content: Text(
          localizations.text('delete_guest_confirm', values: {'name': guest.fullName}),
        ),
        actions: [
          DialogConfirmButton(
            label: localizations.text('delete'),
            destructive: true,
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
          ),
        ],
      ),
    );
  }

  bool _isHost(Guest guest) {
    return guest.title == GuestTitle.bride || guest.title == GuestTitle.groom;
  }

  List<String> _normalizeDietValues(List<String> values) {
    final normalized = <String>[];
    for (final raw in values) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (!normalized.contains(trimmed)) {
        normalized.add(trimmed);
      }
    }
    return normalized;
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
      !_filterOnlyDiet || guest.dietaryRestrictions.isNotEmpty;

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
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
        break;
      case GuestSortOption.nameDescending:
        visibleGuests.sort(
          (a, b) =>
              b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase()),
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
    final localizations = AppLocalizationsScope.of(context);
    switch (sort) {
      case GuestSortOption.nameAscending:
        return localizations.text('sort_name_asc');
      case GuestSortOption.nameDescending:
        return localizations.text('sort_name_desc');
      case GuestSortOption.createdNewest:
        return localizations.text('sort_created_newest');
      case GuestSortOption.createdOldest:
        return localizations.text('sort_created_oldest');
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
    final localizations = AppLocalizationsScope.of(context);
    final isHost = _isHost(guest);
    final role = localizations.guestTitle(guest.title);
    final hasDiet = guest.dietaryRestrictions.isNotEmpty;
    final summaryParts = <String>[
      '${localizations.text('guest_role')}: $role',
      if (hasDiet) guest.dietaryRestrictions.join(', '),
      '${localizations.text('relations')}: ${guest.relations.length}',
    ];

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
                color: isHost
                    ? const Color(0xFFC46C84)
                    : const Color(0xFF77686D),
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
                          fontWeight: isHost
                              ? FontWeight.w700
                              : FontWeight.w600,
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
                          child: Text(
                            localizations.text('host_badge'),
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
                    summaryParts.join(' · '),
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
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'relations',
                        child: Text(localizations.text('manage_relations')),
                      ),
                      PopupMenuItem(value: 'edit', child: Text(localizations.text('edit'))),
                      PopupMenuItem(value: 'delete', child: Text(localizations.text('delete'))),
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
                        tooltip: localizations.text('manage_relations'),
                        onPressed: () => _manageRelationsDialog(guest),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Color(0xFFC1834D),
                        ),
                        tooltip: localizations.text('edit'),
                        onPressed: () =>
                            _openGuestFormDialog(guestToEdit: guest),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFC25353),
                        ),
                        tooltip: localizations.text('delete'),
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

    final localizations = AppLocalizationsScope.of(context);
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
        title: Text(localizations.text('hosts_and_guests', values: {
          'hosts': '$hostCount',
          'guests': '$guestCount',
        })),
        actions: [
          const LanguageToggleButton(),
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
                      Text(
                        localizations.text('guest_list_title'),
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
                  AppSearchField(
                    hintText: localizations.text('search_placeholder'),
                    filled: true,
                    fillColor: const Color(0xFFF7F3F4),
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
                        AppDropdownFormField<GuestSortOption>(
                          initialValue: _selectedSort,
                          labelText: localizations.text('sort_label'),
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
                          child: AppDropdownFormField<GuestSortOption>(
                            initialValue: _selectedSort,
                            labelText: localizations.text('sort_label'),
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
                        AppDropdownFormField<GuestTitle?>(
                          initialValue: _selectedTitleFilter,
                          labelText: localizations.text('filter_role_label'),
                          items: [
                            DropdownMenuItem<GuestTitle?>(
                              value: null,
                              child: Text(localizations.text('all_roles')),
                            ),
                            ...GuestTitle.values.map(
                              (title) => DropdownMenuItem<GuestTitle?>(
                                value: title,
                                child: Text(localizations.guestTitle(title)),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedTitleFilter = value);
                          },
                        )
                      else
                        Expanded(
                          child: AppDropdownFormField<GuestTitle?>(
                            initialValue: _selectedTitleFilter,
                            labelText: localizations.text('filter_role_label'),
                            items: [
                            DropdownMenuItem<GuestTitle?>(
                                value: null,
                                child: Text(localizations.text('all_roles')),
                              ),
                              ...GuestTitle.values.map(
                                (title) => DropdownMenuItem<GuestTitle?>(
                                  value: title,
                                  child: Text(localizations.guestTitle(title)),
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
                        label: Text(localizations.text('only_dietary')),
                        selected: _filterOnlyDiet,
                        onSelected: (val) =>
                            setState(() => _filterOnlyDiet = val),
                      ),
                      Chip(
                        avatar: Icon(Icons.push_pin_outlined, size: 16),
                        label: Text(localizations.text('hosts_pinned')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: visibleGuests.isEmpty
                ? Center(child: Text(localizations.text('no_matches')))
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
    final localizations = AppLocalizationsScope.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final otherGuests = guests
                .where((g) => g.id != currentGuest.id)
                .toList();
            return AlertDialog(
              title: DialogTitleWithClose(
                titleText: localizations.text('who_knows', values: {'name': currentGuest.firstName}),
                onClose: () => Navigator.pop(context),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: otherGuests.isEmpty
                    ? Center(child: Text(localizations.text('empty_list')))
                    : ListView.builder(
                        itemCount: otherGuests.length,
                        itemBuilder: (context, i) {
                          final other = otherGuests[i];
                          final currentRelationType =
                              currentGuest.relations[other.id];

                          return ListTile(
                            title: Text(other.fullName),
                            trailing: DropdownButton<RelationType>(
                              hint: Text(localizations.text('choose_relation')),
                              value: currentRelationType,
                              items: RelationType.values.map((type) {
                                String label = type.name;
                                if (type == RelationType.none) {
                                  label = localizations.text('relation_none_label');
                                }
                                if (type == RelationType.partner) {
                                  label = localizations.text('relation_partner_label');
                                }
                                if (type == RelationType.friend) {
                                  label = localizations.text('relation_friend_label');
                                }
                                if (type == RelationType.avoid) {
                                  label = localizations.text('relation_avoid_label');
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
            );
          },
        );
      },
    );
  }
}
