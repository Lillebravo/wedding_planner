// Tests for the SeatingAlgorithm round-robin engine.
//
// Mock data: 30 guests with a variety of partner, friend, and avoid
// relations placed across 4 tables with 8 seats each (32 total, 2 spare).
//
// Hard constraints asserted in every scenario:
//   1. All 30 guests receive a tableId (nobody left unassigned).
//   2. No two guests who share an "avoid" relation are at the same table.
//   3. No table contains exactly 1 guest after placement.
//
// Additional constraint asserted when the partner rule is active:
//   4. Every partner pair sits at the same table.

import 'package:flutter_test/flutter_test.dart';
import 'package:wedding_planner/models/guest_model.dart';
import 'package:wedding_planner/services/seating_algorithm.dart';

// ─────────────────────────────── mock data ────────────────────────────────────

/// Builds a fresh list of 30 [Guest] instances.
///
/// Relations:
///   Partners (5 pairs):   g01↔g02, g03↔g04, g05↔g06, g07↔g08, g09↔g10
///   Friends:              see implementation below
///   Avoid (2 pairs):      g09↔g15 (Grace / Mia), g19↔g20 (Quinn / Rose)
List<Guest> buildGuests() {
  Guest g(String id, String first, {GuestTitle title = GuestTitle.none}) =>
      Guest(id: id, firstName: first, lastName: 'Test', title: title);

  final guests = [
    // Hosts
    g('g01', 'Anna', title: GuestTitle.bride),
    g('g02', 'Erik', title: GuestTitle.groom),
    // Couple group A
    g('g03', 'Alice'),
    g('g04', 'Bob'),
    g('g05', 'Carol'),
    g('g06', 'David'),
    // Couple group B
    g('g07', 'Eve'),
    g('g08', 'Frank'),
    g('g09', 'Grace'),
    g('g10', 'Henry'),
    // Friend cluster A
    g('g11', 'Iris'),
    g('g12', 'Jack'),
    g('g13', 'Kate'),
    // Friend cluster B
    g('g14', 'Leo'),
    g('g15', 'Mia'),
    g('g16', 'Noah'),
    // Friend pairs
    g('g17', 'Olivia'),
    g('g18', 'Peter'),
    g('g19', 'Quinn'),
    g('g20', 'Rose'),
    g('g21', 'Sam'),
    g('g22', 'Tina'),
    // Additional guests
    g('g23', 'Uma'),
    g('g24', 'Victor'),
    g('g25', 'Wendy'),
    g('g26', 'Xavier'),
    g('g27', 'Yara'),
    g('g28', 'Zara'),
    g('g29', 'Adam'),
    g('g30', 'Beth'),
  ];

  final byId = {for (final g in guests) g.id: g};

  void partner(String a, String b) {
    byId[a]!.relations[b] = RelationType.partner;
    byId[b]!.relations[a] = RelationType.partner;
  }

  void friend(String a, String b) {
    byId[a]!.relations[b] = RelationType.friend;
    byId[b]!.relations[a] = RelationType.friend;
  }

  void avoid(String a, String b) {
    byId[a]!.relations[b] = RelationType.avoid;
    byId[b]!.relations[a] = RelationType.avoid;
  }

  // ── partners ──
  partner('g01', 'g02'); // Anna ↔ Erik  (bride / groom)
  partner('g03', 'g04'); // Alice ↔ Bob
  partner('g05', 'g06'); // Carol ↔ David
  partner('g07', 'g08'); // Eve ↔ Frank
  partner('g09', 'g10'); // Grace ↔ Henry

  // ── friends ──
  friend('g03', 'g05'); // Alice ↔ Carol
  friend('g03', 'g06'); // Alice ↔ David
  friend('g04', 'g07'); // Bob ↔ Eve
  friend('g11', 'g12'); // Iris ↔ Jack
  friend('g11', 'g13'); // Iris ↔ Kate
  friend('g14', 'g15'); // Leo ↔ Mia
  friend('g14', 'g16'); // Leo ↔ Noah
  friend('g17', 'g18'); // Olivia ↔ Peter
  friend('g21', 'g22'); // Sam ↔ Tina
  friend('g25', 'g26'); // Wendy ↔ Xavier
  friend('g29', 'g30'); // Adam ↔ Beth

  // ── avoids ──
  avoid('g09', 'g15'); // Grace avoids Mia  (and partner↔friend clash risk)
  avoid('g19', 'g20'); // Quinn avoids Rose

  return guests;
}

/// Builds 4 fresh tables with 8 seats each (32 seats total).
List<Map<String, dynamic>> buildTables() => [
      {'id': 'table-1', 'name': 'Table 1', 'seats': 8, 'assigned': <Guest>[]},
      {'id': 'table-2', 'name': 'Table 2', 'seats': 8, 'assigned': <Guest>[]},
      {'id': 'table-3', 'name': 'Table 3', 'seats': 8, 'assigned': <Guest>[]},
      {'id': 'table-4', 'name': 'Table 4', 'seats': 8, 'assigned': <Guest>[]},
    ];

// ────────────────────────────── shared assertions ─────────────────────────────

void assertAllSeated(List<Guest> guests) {
  for (final g in guests) {
    expect(
      g.tableId,
      isNotNull,
      reason: '${g.fullName} must be assigned to a table after run()',
    );
  }
}

void assertNoAvoidConflicts(List<Map<String, dynamic>> tables) {
  for (final table in tables) {
    final assigned = table['assigned'] as List<Guest>;
    for (int i = 0; i < assigned.length; i++) {
      for (int j = i + 1; j < assigned.length; j++) {
        final a = assigned[i];
        final b = assigned[j];
        final conflict = a.relations[b.id] == RelationType.avoid ||
            b.relations[a.id] == RelationType.avoid;
        expect(
          conflict,
          isFalse,
          reason:
              '${a.fullName} and ${b.fullName} both have "avoid" but share '
              '${table['name']}',
        );
      }
    }
  }
}

void assertNoLonelyTables(List<Map<String, dynamic>> tables) {
  for (final table in tables) {
    final count = (table['assigned'] as List<Guest>).length;
    expect(
      count,
      isNot(equals(1)),
      reason: '${table['name']} has exactly 1 guest – lonely table forbidden',
    );
  }
}

void assertPartnersAtSameTable(
  List<Guest> guests,
  List<Map<String, dynamic>> tables,
) {
  final tableForGuest = <String, String>{};
  for (final table in tables) {
    for (final g in (table['assigned'] as List<Guest>)) {
      tableForGuest[g.id] = table['id'] as String;
    }
  }

  for (final guest in guests) {
    for (final entry in guest.relations.entries) {
      if (entry.value != RelationType.partner) continue;
      final partnerId = entry.key;
      if (!guests.any((g) => g.id == partnerId)) continue; // partner not in list

      expect(
        tableForGuest[guest.id],
        equals(tableForGuest[partnerId]),
        reason: '${guest.fullName} (${guest.id}) should sit at the same table '
            'as partner $partnerId, but '
            '${guest.id}→${tableForGuest[guest.id]} vs '
            '$partnerId→${tableForGuest[partnerId]}',
      );
    }
  }
}

void assertTotalAssigned(
    List<Guest> guests, List<Map<String, dynamic>> tables) {
  final total = tables.fold<int>(
      0, (sum, t) => sum + (t['assigned'] as List<Guest>).length);
  expect(
    total,
    equals(guests.length),
    reason: 'Total assigned ($total) should equal guest count (${guests.length})',
  );
}

void assertSeatNumbersContiguous(List<Map<String, dynamic>> tables) {
  for (final table in tables) {
    final assigned = table['assigned'] as List<Guest>;
    for (int i = 0; i < assigned.length; i++) {
      expect(
        assigned[i].seatNumber,
        equals(i + 1),
        reason:
            '${table['name']} seat ${i + 1}: expected seatNumber ${i + 1}, '
            'got ${assigned[i].seatNumber}',
      );
    }
  }
}

// ──────────────────────────────────── tests ───────────────────────────────────

void main() {
  group('SeatingAlgorithm – 30-guest scenario', () {
    // ── no rules ──────────────────────────────────────────────────────────────
    test('no rules: all guests seated, no avoid conflicts, no lonely tables',
        () {
      final guests = buildGuests();
      final tables = buildTables();
      SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: false,
        friendRuleEnabled: false,
      ).run();

      assertAllSeated(guests);
      assertTotalAssigned(guests, tables);
      assertNoAvoidConflicts(tables);
      assertNoLonelyTables(tables);
      assertSeatNumbersContiguous(tables);
    });

    // ── partner rule only ─────────────────────────────────────────────────────
    test(
        'partner rule only: partners at same table, no avoid conflicts, '
        'no lonely tables', () {
      final guests = buildGuests();
      final tables = buildTables();
      SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: true,
        friendRuleEnabled: false,
      ).run();

      assertAllSeated(guests);
      assertTotalAssigned(guests, tables);
      assertNoAvoidConflicts(tables);
      assertNoLonelyTables(tables);
      assertPartnersAtSameTable(guests, tables);
      assertSeatNumbersContiguous(tables);
    });

    // ── friend rule only ──────────────────────────────────────────────────────
    test(
        'friend rule only: all guests seated, no avoid conflicts, '
        'no lonely tables', () {
      final guests = buildGuests();
      final tables = buildTables();
      SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: false,
        friendRuleEnabled: true,
      ).run();

      assertAllSeated(guests);
      assertTotalAssigned(guests, tables);
      assertNoAvoidConflicts(tables);
      assertNoLonelyTables(tables);
      assertSeatNumbersContiguous(tables);
    });

    // ── both rules, partner priority (default) ────────────────────────────────
    test(
        'both rules + partner priority: partners together, no avoid conflicts, '
        'no lonely tables', () {
      final guests = buildGuests();
      final tables = buildTables();
      SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: true,
        friendRuleEnabled: true,
        partnerHigherPriority: true,
      ).run();

      assertAllSeated(guests);
      assertTotalAssigned(guests, tables);
      assertNoAvoidConflicts(tables);
      assertNoLonelyTables(tables);
      assertPartnersAtSameTable(guests, tables);
      assertSeatNumbersContiguous(tables);
    });

    // ── both rules, friend priority ───────────────────────────────────────────
    test(
        'both rules + friend priority: partners together (via colocate), '
        'no avoid conflicts, no lonely tables', () {
      final guests = buildGuests();
      final tables = buildTables();
      SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: true,
        friendRuleEnabled: true,
        partnerHigherPriority: false,
      ).run();

      assertAllSeated(guests);
      assertTotalAssigned(guests, tables);
      assertNoAvoidConflicts(tables);
      assertNoLonelyTables(tables);
      assertPartnersAtSameTable(guests, tables);
      assertSeatNumbersContiguous(tables);
    });

    // ── avoid enforcement ─────────────────────────────────────────────────────
    test('avoid pairs never share a table in any rule combination', () {
      // Run with every combination and verify avoid is always respected.
      for (final pr in [true, false]) {
        for (final fr in [true, false]) {
          for (final php in [true, false]) {
            final guests = buildGuests();
            final tables = buildTables();
            SeatingAlgorithm(
              tables: tables,
              guests: guests,
              partnerRuleEnabled: pr,
              friendRuleEnabled: fr,
              partnerHigherPriority: php,
            ).run();
            assertNoAvoidConflicts(tables);
          }
        }
      }
    });

    // ── locked guest preservation ─────────────────────────────────────────────
    test('locked guest stays at pre-assigned table', () {
      final guests = buildGuests();
      final tables = buildTables();

      // Lock Iris (g11) to table-3.
      final iris = guests.firstWhere((g) => g.id == 'g11');
      iris.isLocked = true;
      iris.tableId = 'table-3';
      (tables[2]['assigned'] as List<Guest>).add(iris);

      SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: true,
        friendRuleEnabled: true,
      ).run();

      assertAllSeated(guests);
      assertTotalAssigned(guests, tables);
      assertNoAvoidConflicts(tables);
      assertNoLonelyTables(tables);
      expect(iris.tableId, equals('table-3'),
          reason: 'Locked guest Iris must remain at table-3');
    });

    // ── avoid pair with partner rule: partner table must not contain avoider ──
    test(
        'Grace (partner of Henry) and Mia never share a table '
        'regardless of partner rule', () {
      for (final pr in [true, false]) {
        final guests = buildGuests();
        final tables = buildTables();
        SeatingAlgorithm(
          tables: tables,
          guests: guests,
          partnerRuleEnabled: pr,
          friendRuleEnabled: true,
        ).run();

        final tableForGuest = <String, String>{};
        for (final table in tables) {
          for (final g in (table['assigned'] as List<Guest>)) {
            tableForGuest[g.id] = table['id'] as String;
          }
        }

        expect(
          tableForGuest['g09'],
          isNot(equals(tableForGuest['g15'])),
          reason:
              'Grace (g09) and Mia (g15) have an avoid relation and must not '
              'share a table (partnerRule=$pr)',
        );
      }
    });

    // ── Quinn & Rose avoid each other ─────────────────────────────────────────
    test('Quinn and Rose (avoid pair) are never at the same table', () {
      final guests = buildGuests();
      final tables = buildTables();
      SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: true,
        friendRuleEnabled: true,
      ).run();

      final tableForGuest = <String, String>{};
      for (final table in tables) {
        for (final g in (table['assigned'] as List<Guest>)) {
          tableForGuest[g.id] = table['id'] as String;
        }
      }

      expect(
        tableForGuest['g19'],
        isNot(equals(tableForGuest['g20'])),
        reason: 'Quinn (g19) and Rose (g20) have an avoid relation',
      );
    });

    // ── re-run idempotency ────────────────────────────────────────────────────
    test('running algorithm twice on the same data produces a valid placement',
        () {
      final guests = buildGuests();
      final tables = buildTables();
      final algo = SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: true,
        friendRuleEnabled: true,
      );

      algo.run();
      // Second run should re-place everything cleanly.
      algo.run();

      assertAllSeated(guests);
      assertTotalAssigned(guests, tables);
      assertNoAvoidConflicts(tables);
      assertNoLonelyTables(tables);
      assertPartnersAtSameTable(guests, tables);
    });
  });
}
