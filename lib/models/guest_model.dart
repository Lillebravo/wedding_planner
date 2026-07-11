// Uppdaterad med brud, brudgum, brudtärna och marskalk
enum GuestTitle { none, bride, groom, maidOfHonor, groomsman, bestMan, parent, sibling, child }
enum RelationType { partner, friend, avoid }

class Guest {
  String id;
  String firstName;
  String lastName;
  String? email;
  String? phoneNumber;
  String? dietaryRestrictions;
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
    this.dietaryRestrictions,
    this.title = GuestTitle.none,
    this.isLocked = false,
    this.tableId,
    this.seatNumber,
    Map<String, RelationType>? relations,
  }) : relations = relations ?? {};

  String get fullName => '$firstName $lastName';
}