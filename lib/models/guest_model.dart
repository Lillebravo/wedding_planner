// Uppdaterad med brud, brudgum, brudtärna och marskalk
enum GuestTitle { none, bride, groom, maidOfHonor, groomsman, bestMan, parent, sibling, child }
enum RelationType { none, partner, friend, avoid }

class Guest {
  String id;
  String firstName;
  String lastName;
  String? email;
  String? phoneNumber;
  DateTime? createdAt;
  List<String> dietaryRestrictions;
  GuestTitle title;
  bool isLocked;
  bool isPlaceholder;
  String? tableId;
  int? seatNumber;
  
  Map<String, RelationType> relations;

  Guest({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phoneNumber,
    this.createdAt,
    List<String>? dietaryRestrictions,
    this.title = GuestTitle.none,
    this.isLocked = false,
    this.isPlaceholder = false,
    this.tableId,
    this.seatNumber,
    Map<String, RelationType>? relations,
  })  : dietaryRestrictions = dietaryRestrictions ?? <String>[],
        relations = relations ?? {};

  String get fullName => '$firstName $lastName';

  String get displayName => isPlaceholder ? 'Empty chair' : fullName;
}