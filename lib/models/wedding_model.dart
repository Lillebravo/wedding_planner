class Wedding {
  String id;
  String partner1;
  String partner2;
  String dateStr; // Sparas som text för enkelhetens skull i utkastet
  String timeStr;
  String code;
  String? estimatedGuests;
  String? churchAddress;
  String? venueAddress;

  Wedding({
    required this.id,
    required this.partner1,
    required this.partner2,
    required this.dateStr,
    required this.timeStr,
    required this.code,
    this.estimatedGuests,
    this.churchAddress,
    this.venueAddress,
  });

  // Konvertera till Map för att spara som JSON-sträng
  Map<String, dynamic> toJson() => {
    'id': id,
    'partner1': partner1,
    'partner2': partner2,
    'dateStr': dateStr,
    'timeStr': timeStr,
    'code': code,
    'estimatedGuests': estimatedGuests,
    'churchAddress': churchAddress,
    'venueAddress': venueAddress,
  };

  // Skapa objekt från Map
  factory Wedding.fromJson(Map<String, dynamic> json) => Wedding(
    id: json['id'],
    partner1: json['partner1'],
    partner2: json['partner2'],
    dateStr: json['dateStr'],
    timeStr: json['timeStr'],
    code: json['code'],
    estimatedGuests: json['estimatedGuests'],
    churchAddress: json['churchAddress'],
    venueAddress: json['venueAddress'],
  );
}