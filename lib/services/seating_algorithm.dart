import '../models/guest_model.dart';

/// Pure round-robin seating placement engine, decoupled from Flutter widgets.
///
/// Usage:
/// ```dart
/// SeatingAlgorithm(tables: tables, guests: guests).run();
/// ```
///
/// After [run] every non-locked [Guest] in [guests] has
/// [Guest.tableId] and [Guest.seatNumber] set.  Locked guests
/// with an existing [Guest.tableId] are left in place.
///
/// [tables] is a `List<Map<String, dynamic>>` where each map contains:
///   - `'id'`       : String  – unique table identifier
///   - `'seats'`    : int     – total seat capacity
///   - `'assigned'` : `List<Guest>` – mutable list; pre-populate with locked
///                    guests before calling [run] if any exist
class SeatingAlgorithm {
  final List<Map<String, dynamic>> tables;
  final List<Guest> guests;

  final bool partnerRuleEnabled;
  final bool friendRuleEnabled;

  /// When both rules are enabled, [true] means the partner rule is executed
  /// first (couple-phase before single-phase).  [false] means the friend rule
  /// takes priority (individual placement first, then partner co-location).
  final bool partnerHigherPriority;

  const SeatingAlgorithm({
    required this.tables,
    required this.guests,
    this.partnerRuleEnabled = true,
    this.friendRuleEnabled = true,
    this.partnerHigherPriority = true,
  });

  // ── entry point ────────────────────────────────────────────────────────────

  void run() {
    // 1. Give hosts (bride / groom) an implicit friend link to every standard
    //    guest so they act as social anchors for the friend rule.
    _expandHostFriendLinks();

    // 2. Collect guests that need to be (re-)placed.
    final unassigned = guests.where((g) {
      if (g.isLocked && g.tableId != null) return false;
      return true;
    }).toList();

    for (final g in unassigned) {
      g.tableId = null;
      g.seatNumber = null;
    }

    // 3. Clear unlocked guests from every table and reindex the locked ones.
    for (final table in tables) {
      final assigned = table['assigned'] as List<Guest>;
      assigned.removeWhere((g) => !g.isLocked);
      _sortAssignedBySeat(assigned);
      _reindexSeats(assigned, table);
    }

    // 4. Run the appropriate round-robin variant based on active rules.
    int rrPointer = 0;

    if (!partnerRuleEnabled && !friendRuleEnabled) {
      // No rules: pure round-robin, avoid-aware.
      _rrPhaseByGuest(unassigned, rrPointer);
    } else if (partnerRuleEnabled && !friendRuleEnabled) {
      // Partner rule only: seat couples first, then individuals.
      rrPointer = _rrPhaseCouple(unassigned, rrPointer);
      _rrPhaseByGuest(unassigned, rrPointer);
    } else if (!partnerRuleEnabled && friendRuleEnabled) {
      // Friend rule only: prefer tables with a known friend.
      _rrPhaseByGuest(unassigned, rrPointer, requireFriend: true);
    } else if (partnerHigherPriority) {
      // Both rules, partner has higher priority (default).
      rrPointer = _rrPhaseCouple(unassigned, rrPointer, requireFriend: true);
      _rrPhaseByGuest(unassigned, rrPointer, requireFriend: true);
    } else {
      // Both rules, friend has higher priority.
      rrPointer = _rrPhaseByGuest(unassigned, rrPointer, requireFriend: true);
      _rrTryColocatePartners();
      _rrPhaseByGuest(unassigned, rrPointer);
    }

    // 5. Guarantee: no table may end up with exactly 1 guest.
    _fixLonelyGuests();

    // 6. Write final seat numbers.
    for (final table in tables) {
      _reindexSeats(table['assigned'] as List<Guest>, table);
    }
  }

  // ── host-friend expansion ──────────────────────────────────────────────────

  void _expandHostFriendLinks() {
    final hosts = guests.where(_isHostGuest).toList();
    final standard = guests.where((g) => !_isHostGuest(g)).toList();
    for (final host in hosts) {
      for (final guest in standard) {
        host.relations.putIfAbsent(guest.id, () => RelationType.friend);
        guest.relations.putIfAbsent(host.id, () => RelationType.friend);
      }
    }
  }

  // ── seat indexing ──────────────────────────────────────────────────────────

  void _sortAssignedBySeat(List<Guest> guests) {
    guests.sort(
      (a, b) => (a.seatNumber ?? 9999).compareTo(b.seatNumber ?? 9999),
    );
  }

  void _reindexSeats(List<Guest> assignedGuests, Map<String, dynamic> table) {
    for (int i = 0; i < assignedGuests.length; i++) {
      assignedGuests[i].tableId = table['id'] as String?;
      assignedGuests[i].seatNumber = i + 1;
    }
  }

  // ── relation helpers ───────────────────────────────────────────────────────

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

  bool _isHostGuest(Guest g) =>
      g.title == GuestTitle.bride || g.title == GuestTitle.groom;

  // ── partner-pair collection ────────────────────────────────────────────────

  List<List<Guest>> _collectPartnerPairs(List<Guest> candidates) {
    final byId = {for (final g in candidates) g.id: g};
    final used = <String>{};
    final pairs = <List<Guest>>[];

    void addPair(Guest a, Guest b) {
      if (a.id == b.id) return;
      if (used.contains(a.id) || used.contains(b.id)) return;
      used.add(a.id);
      used.add(b.id);
      pairs.add([a, b]);
    }

    // Bride + groom always pair first.
    final bride =
        candidates.where((g) => g.title == GuestTitle.bride).firstOrNull;
    final groom =
        candidates.where((g) => g.title == GuestTitle.groom).firstOrNull;
    if (bride != null && groom != null) addPair(bride, groom);

    for (final guest in candidates) {
      if (used.contains(guest.id)) continue;
      for (final entry in guest.relations.entries) {
        if (entry.value != RelationType.partner) continue;
        final partner = byId[entry.key];
        if (partner == null) continue;
        addPair(guest, partner);
        break;
      }
    }

    return pairs;
  }

  // ── round-robin core ───────────────────────────────────────────────────────

  /// Tries to seat [group] starting from [rrPointer], cycling through tables.
  ///
  /// When [requireFriend] is true, prefers a table that already has a
  /// friend/partner of any group member; falls back to the first
  /// avoid-free table with room when no such table exists.
  ///
  /// Returns the new rrPointer on success, or -1 when no table can fit the
  /// group at all.
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

      // First valid table becomes fallback (capacity + no avoid).
      if (fallbackIdx < 0) fallbackIdx = idx;

      if (requireFriend) {
        final hasLink = assigned.isNotEmpty &&
            group.any((g) => assigned.any((s) => _isFriendOrPartner(g, s)));
        if (!hasLink) continue;
      }

      assigned.addAll(group);
      return (idx + 1) % n;
    }

    // Fallback: ignore friend rule, seat at first valid table.
    if (fallbackIdx >= 0) {
      (tables[fallbackIdx]['assigned'] as List<Guest>).addAll(group);
      return (fallbackIdx + 1) % n;
    }

    return -1; // no table can accommodate the group
  }

  /// Seats all partner pairs from [unassigned] via round-robin.
  int _rrPhaseCouple(
    List<Guest> unassigned,
    int rrPointer, {
    bool requireFriend = false,
  }) {
    final pairs = _collectPartnerPairs(unassigned);
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

  /// Seats every guest in [unassigned] one by one via round-robin.
  int _rrPhaseByGuest(
    List<Guest> unassigned,
    int rrPointer, {
    bool requireFriend = false,
  }) {
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

  /// After individual placement, tries to move one partner to the other's
  /// table wherever capacity and avoid rules permit.
  /// Skips locked guests and avoids leaving a source table with only 1 guest.
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
        // Do not leave the source table with only 1 guest after the move.
        if (sourceAssigned.length <= 2) continue;

        sourceAssigned.remove(guest);
        partnerAssigned.add(guest);
        guestTableIdx[guest.id] = partnerTi;
      }
    }
  }

  /// Post-placement safety pass: no table may have exactly 1 guest.
  ///
  /// Option A – move the lone guest to any table that has ≥2 guests and a
  ///            free seat (no avoid conflict).
  /// Option B – pull a non-locked, non-conflicting guest from a table
  ///            with ≥3 guests into the lonely table.
  void _fixLonelyGuests() {
    for (int ti = 0; ti < tables.length; ti++) {
      final assigned = tables[ti]['assigned'] as List<Guest>;
      if (assigned.length != 1) continue;
      final loneGuest = assigned.first;

      // Option A: move the lone guest out.
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

      // Option B: bring a guest in from a larger table.
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
}
