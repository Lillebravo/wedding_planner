// Uppdaterad med brud, brudgum, brudtärna och marskalk
enum GuestTitle { none, bride, groom, maidOfHonor, groomsman, bestMan, parent, sibling, child }
enum RelationType { none, partner, friend, avoid }

class Guest {
  String id;
  String firstName;
  String lastName;
  String? email;
  String? phoneNumber;
  List<String> dietaryRestrictions;
  GuestTitle title;
  bool isLocked;
  String? tableId;
  int? seatNumber;
  
  Map<String, RelationType> relations;

  Guest({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phoneNumber,
    List<String>? dietaryRestrictions,
    this.title = GuestTitle.none,
    this.isLocked = false,
    this.tableId,
    this.seatNumber,
    Map<String, RelationType>? relations,
  })  : dietaryRestrictions = dietaryRestrictions ?? <String>[],
        relations = relations ?? {};

  String get fullName => '$firstName $lastName';
}