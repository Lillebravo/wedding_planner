// Tests for the SeatingAlgorithm round-robin engine.
//
// Mock data: 100 guests with a variety of partner, friend, and avoid
// relations placed across tables with different seat counts.
//
// Hard constraints asserted in every scenario (when capacity ≥ guest count):
//   1. All 100 guests receive a tableId (nobody left unassigned).
//   2. No two guests who share an "avoid" relation are at the same table.
//   3. No table contains exactly 1 guest after placement.
//
// Additional constraint asserted when the partner rule is active:
//   4. Every partner pair sits at the same table.
//
// Edge-case groups also cover:
//   • More seats than guests  – capacity > 100, all guests seated.
//   • Fewer seats than guests – capacity < 100, capacity respected, no
//     avoid conflicts, no lonely tables.

import 'package:flutter_test/flutter_test.dart';
import 'package:wedding_planner/models/guest_model.dart';
import 'package:wedding_planner/services/seating_algorithm.dart';

// ─────────────────────────────── mock data ────────────────────────────────────

/// Builds a fresh list of 100 [Guest] instances.
///
/// Relations:
///   Partners (15 pairs): g01↔g02 (bride/groom), g03↔g04, g05↔g06,
///                        g07↔g08, g09↔g10, g31↔g32 … g49↔g50
///   Friends:             multiple clusters and pairs (see implementation)
///   Avoids (4 pairs):    g09↔g15 (Grace/Mia), g19↔g20 (Quinn/Rose),
///                        g31↔g60 (Carl/Jonas), g70↔g80 (Ulric/Elise)
List<Guest> buildGuests() {
  Guest g(String id, String first, {GuestTitle title = GuestTitle.none}) =>
      Guest(id: id, firstName: first, lastName: 'Test', title: title);

  final guests = [
    // Hosts
    g('g01', 'Anna', title: GuestTitle.bride),
    g('g02', 'Erik', title: GuestTitle.groom),
    // Original partner couples
    g('g03', 'Alice'),   g('g04', 'Bob'),
    g('g05', 'Carol'),   g('g06', 'David'),
    g('g07', 'Eve'),     g('g08', 'Frank'),
    g('g09', 'Grace'),   g('g10', 'Henry'),
    // Original singles with friend/avoid relations
    g('g11', 'Iris'),    g('g12', 'Jack'),    g('g13', 'Kate'),
    g('g14', 'Leo'),     g('g15', 'Mia'),     g('g16', 'Noah'),
    g('g17', 'Olivia'),  g('g18', 'Peter'),
    g('g19', 'Quinn'),   g('g20', 'Rose'),
    g('g21', 'Sam'),     g('g22', 'Tina'),
    g('g23', 'Uma'),     g('g24', 'Victor'),
    g('g25', 'Wendy'),   g('g26', 'Xavier'),
    g('g27', 'Yara'),    g('g28', 'Zara'),
    g('g29', 'Aaron'),   g('g30', 'Beth'),
    // New partner couples
    g('g31', 'Carl'),    g('g32', 'Dana'),
    g('g33', 'Elias'),   g('g34', 'Fiona'),
    g('g35', 'George'),  g('g36', 'Hannah'),
    g('g37', 'Ivan'),    g('g38', 'Julia'),
    g('g39', 'Karl'),    g('g40', 'Laura'),
    g('g41', 'Mark'),    g('g42', 'Nancy'),
    g('g43', 'Oscar'),   g('g44', 'Paula'),
    g('g45', 'Ralph'),   g('g46', 'Sofia'),
    g('g47', 'Tom'),     g('g48', 'Ursula'),
    g('g49', 'Vera'),    g('g50', 'Will'),
    // Additional singles
    g('g51', 'Alexis'),  g('g52', 'Brian'),   g('g53', 'Claire'),  g('g54', 'Derek'),
    g('g55', 'Elena'),   g('g56', 'Felix'),   g('g57', 'Gina'),
    g('g58', 'Hugo'),    g('g59', 'Isla'),    g('g60', 'Jonas'),   g('g61', 'Karen'),
    g('g62', 'Liam'),    g('g63', 'Maria'),   g('g64', 'Nate'),    g('g65', 'Penny'),
    g('g66', 'Owen'),    g('g67', 'Rachel'),  g('g68', 'Steve'),   g('g69', 'Tara'),
    g('g70', 'Ulric'),   g('g71', 'Violet'),  g('g72', 'Wayne'),   g('g73', 'Xena'),
    g('g74', 'Yvonne'),  g('g75', 'Zane'),    g('g76', 'Abby'),    g('g77', 'Brad'),
    g('g78', 'Cate'),    g('g79', 'Diego'),   g('g80', 'Elise'),   g('g81', 'Fred'),
    g('g82', 'Heidi'),   g('g83', 'Igor'),    g('g84', 'Jade'),    g('g85', 'Kyle'),
    g('g86', 'Luna'),    g('g87', 'Max'),     g('g88', 'Nina'),    g('g89', 'Orin'),
    g('g90', 'Piper'),   g('g91', 'Rex'),     g('g92', 'Sara'),    g('g93', 'Todd'),
    g('g94', 'Una'),     g('g95', 'Vince'),   g('g96', 'Wren'),    g('g97', 'Xander'),
    g('g98', 'Yasmin'),  g('g99', 'Zoe'),     g('g100', 'Alex'),
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
  partner('g31', 'g32'); // Carl ↔ Dana
  partner('g33', 'g34'); // Elias ↔ Fiona
  partner('g35', 'g36'); // George ↔ Hannah
  partner('g37', 'g38'); // Ivan ↔ Julia
  partner('g39', 'g40'); // Karl ↔ Laura
  partner('g41', 'g42'); // Mark ↔ Nancy
  partner('g43', 'g44'); // Oscar ↔ Paula
  partner('g45', 'g46'); // Ralph ↔ Sofia
  partner('g47', 'g48'); // Tom ↔ Ursula
  partner('g49', 'g50'); // Vera ↔ Will

  // ── friends (original guests) ──
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
  friend('g29', 'g30'); // Aaron ↔ Beth

  // ── friends (new guests) ──
  // Cluster A: Alexis, Brian, Claire, Derek
  friend('g51', 'g52'); friend('g51', 'g53'); friend('g51', 'g54');
  friend('g52', 'g53'); friend('g52', 'g54'); friend('g53', 'g54');
  // Cluster B: Elena, Felix, Gina
  friend('g55', 'g56'); friend('g55', 'g57'); friend('g56', 'g57');
  // Cluster C: Hugo, Isla, Jonas, Karen
  friend('g58', 'g59'); friend('g58', 'g60'); friend('g58', 'g61');
  friend('g59', 'g60'); friend('g59', 'g61'); friend('g60', 'g61');
  // Pairs
  friend('g62', 'g63'); // Liam ↔ Maria
  friend('g64', 'g65'); // Nate ↔ Penny
  friend('g66', 'g67'); // Owen ↔ Rachel
  friend('g68', 'g69'); // Steve ↔ Tara
  friend('g71', 'g72'); // Violet ↔ Wayne
  friend('g73', 'g74'); // Xena ↔ Yvonne
  friend('g75', 'g76'); // Zane ↔ Abby
  friend('g77', 'g78'); // Brad ↔ Cate
  friend('g79', 'g80'); // Diego ↔ Elise  (Elise also in avoid pair)
  friend('g81', 'g82'); // Fred ↔ Heidi
  friend('g83', 'g84'); // Igor ↔ Jade
  friend('g85', 'g86'); // Kyle ↔ Luna
  friend('g87', 'g88'); // Max ↔ Nina
  friend('g89', 'g90'); // Orin ↔ Piper
  friend('g91', 'g92'); // Rex ↔ Sara
  friend('g93', 'g94'); // Todd ↔ Una
  friend('g95', 'g96'); // Vince ↔ Wren
  friend('g97', 'g98'); // Xander ↔ Yasmin
  friend('g99', 'g100'); // Zoe ↔ Alex

  // ── avoids ──
  avoid('g09', 'g15'); // Grace avoids Mia  (partner↔friend clash)
  avoid('g19', 'g20'); // Quinn avoids Rose
  avoid('g31', 'g60'); // Carl avoids Jonas (partner vs friend-cluster clash)
  avoid('g70', 'g80'); // Ulric avoids Elise

  return guests;
}

/// Builds 9 tables with different seat counts (110 seats total).
/// 110 > 100 guests, so this is the standard "more seats than guests" setup.
List<Map<String, dynamic>> buildTables() => [
      {'id': 'table-1', 'name': 'Table 1', 'seats': 14, 'assigned': <Guest>[]},
      {'id': 'table-2', 'name': 'Table 2', 'seats': 10, 'assigned': <Guest>[]},
      {'id': 'table-3', 'name': 'Table 3', 'seats': 12, 'assigned': <Guest>[]},
      {'id': 'table-4', 'name': 'Table 4', 'seats': 15, 'assigned': <Guest>[]},
      {'id': 'table-5', 'name': 'Table 5', 'seats': 11, 'assigned': <Guest>[]},
      {'id': 'table-6', 'name': 'Table 6', 'seats': 13, 'assigned': <Guest>[]},
      {'id': 'table-7', 'name': 'Table 7', 'seats': 10, 'assigned': <Guest>[]},
      {'id': 'table-8', 'name': 'Table 8', 'seats': 14, 'assigned': <Guest>[]},
      {'id': 'table-9', 'name': 'Table 9', 'seats': 11, 'assigned': <Guest>[]},
    ];

/// 6 tables with large varied seat counts (150 seats total) — used to
/// explicitly test ample over-capacity (50 spare seats for 100 guests).
List<Map<String, dynamic>> buildTablesAmple() => [
      {'id': 'table-1', 'name': 'Table 1', 'seats': 20, 'assigned': <Guest>[]},
      {'id': 'table-2', 'name': 'Table 2', 'seats': 18, 'assigned': <Guest>[]},
      {'id': 'table-3', 'name': 'Table 3', 'seats': 25, 'assigned': <Guest>[]},
      {'id': 'table-4', 'name': 'Table 4', 'seats': 22, 'assigned': <Guest>[]},
      {'id': 'table-5', 'name': 'Table 5', 'seats': 30, 'assigned': <Guest>[]},
      {'id': 'table-6', 'name': 'Table 6', 'seats': 35, 'assigned': <Guest>[]},
    ];

/// 5 tables with small varied seat counts (50 seats total) — used to test
/// "fewer seats than guests" (only 50 of 100 guests can be seated).
List<Map<String, dynamic>> buildTablesFewerSeats() => [
      {'id': 'table-1', 'name': 'Table 1', 'seats': 12, 'assigned': <Guest>[]},
      {'id': 'table-2', 'name': 'Table 2', 'seats': 10, 'assigned': <Guest>[]},
      {'id': 'table-3', 'name': 'Table 3', 'seats': 15, 'assigned': <Guest>[]},
      {'id': 'table-4', 'name': 'Table 4', 'seats':  8, 'assigned': <Guest>[]},
      {'id': 'table-5', 'name': 'Table 5', 'seats':  5, 'assigned': <Guest>[]},
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

/// Asserts that no table holds more guests than its declared seat count.
void assertCapacityRespected(List<Map<String, dynamic>> tables) {
  for (final table in tables) {
    final count = (table['assigned'] as List<Guest>).length;
    final seats = table['seats'] as int;
    expect(
      count,
      lessThanOrEqualTo(seats),
      reason: '${table['name']} has $count guests but only $seats seats',
    );
  }
}

/// Like [assertPartnersAtSameTable] but skips partners that were left
/// unassigned — expected when total capacity < guest count.
void assertSeatedPartnersAtSameTable(
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
    final myTable = tableForGuest[guest.id];
    if (myTable == null) continue; // guest was not seated — skip
    for (final entry in guest.relations.entries) {
      if (entry.value != RelationType.partner) continue;
      final partnerId = entry.key;
      if (!guests.any((g) => g.id == partnerId)) continue;
      final partnerTable = tableForGuest[partnerId];
      if (partnerTable == null) continue; // partner not seated — skip
      expect(
        myTable,
        equals(partnerTable),
        reason: '${guest.fullName} (${guest.id}) is seated but not at the '
            'same table as seated partner $partnerId',
      );
    }
  }
}

// ──────────────────────────────────── tests ───────────────────────────────────

void main() {
  group('SeatingAlgorithm – 100-guest scenario', () {
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

  // ── seat count edge cases ──────────────────────────────────────────────────

  group('SeatingAlgorithm – seat count edge cases', () {
    // ── ample capacity (significantly more seats than guests) ─────────────────
    test(
        'ample capacity (150 seats / 100 guests): all guests seated, '
        'no avoid conflicts, no lonely tables', () {
      final guests = buildGuests();
      final tables = buildTablesAmple();
      SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: true,
        friendRuleEnabled: true,
      ).run();

      assertAllSeated(guests);
      assertTotalAssigned(guests, tables);
      assertCapacityRespected(tables);
      assertNoAvoidConflicts(tables);
      assertNoLonelyTables(tables);
      assertPartnersAtSameTable(guests, tables);
      assertSeatNumbersContiguous(tables);
    });

    test(
        'ample capacity: avoid pairs respected across all rule combinations',
        () {
      for (final pr in [true, false]) {
        for (final fr in [true, false]) {
          final guests = buildGuests();
          final tables = buildTablesAmple();
          SeatingAlgorithm(
            tables: tables,
            guests: guests,
            partnerRuleEnabled: pr,
            friendRuleEnabled: fr,
          ).run();
          assertAllSeated(guests);
          assertCapacityRespected(tables);
          assertNoAvoidConflicts(tables);
          assertNoLonelyTables(tables);
        }
      }
    });

    // ── insufficient capacity (fewer seats than guests) ───────────────────────
    test(
        'insufficient capacity (50 seats / 100 guests): capacity respected, '
        'no avoid conflicts, no lonely tables', () {
      final guests = buildGuests();
      final tables = buildTablesFewerSeats();
      SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: false,
        friendRuleEnabled: false,
      ).run();

      assertCapacityRespected(tables);
      assertNoAvoidConflicts(tables);
      assertNoLonelyTables(tables);
      assertSeatNumbersContiguous(tables);
      // Not all guests can be seated — total must not exceed capacity.
      final totalSeated = tables.fold<int>(
          0, (sum, t) => sum + (t['assigned'] as List<Guest>).length);
      expect(totalSeated, lessThanOrEqualTo(50),
          reason: 'At most 50 guests can sit when capacity is 50');
    });

    test(
        'insufficient capacity + partner rule: seated partners share a table, '
        'no avoid conflicts, no lonely tables', () {
      final guests = buildGuests();
      final tables = buildTablesFewerSeats();
      SeatingAlgorithm(
        tables: tables,
        guests: guests,
        partnerRuleEnabled: true,
        friendRuleEnabled: true,
      ).run();

      assertCapacityRespected(tables);
      assertNoAvoidConflicts(tables);
      assertNoLonelyTables(tables);
      assertSeatedPartnersAtSameTable(guests, tables);
    });

    test(
        'insufficient capacity: avoid pairs never share a table in any '
        'rule combination', () {
      for (final pr in [true, false]) {
        for (final fr in [true, false]) {
          final guests = buildGuests();
          final tables = buildTablesFewerSeats();
          SeatingAlgorithm(
            tables: tables,
            guests: guests,
            partnerRuleEnabled: pr,
            friendRuleEnabled: fr,
          ).run();
          assertCapacityRespected(tables);
          assertNoAvoidConflicts(tables);
          assertNoLonelyTables(tables);
        }
      }
    });
  });
}
