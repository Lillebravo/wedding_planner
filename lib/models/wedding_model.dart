class Wedding {
  final String id;
  final String partner1;
  final String partner2;
  final String dateStr;
  final String timeStr;
  final String code;
  final String adminCode;
  final String churchAddress;
  final String venueAddress;
  final String? coverImageUrl;
  final List<Map<String, dynamic>> itinerary;
  final bool showMeetCouple;
  final bool showCountdown;
  final bool showDetails;
  final bool showItinerary;
  final bool showHeroText;
  final String partner1Description;
  final String partner2Description;
  final String? partner1ImageUrl;
  final String? partner2ImageUrl;

  Wedding({
    required this.id,
    required this.partner1,
    required this.partner2,
    required this.dateStr,
    required this.timeStr,
    required this.code,
    this.adminCode = '',
    required this.churchAddress,
    required this.venueAddress,
    this.coverImageUrl,
    this.itinerary = const [],
    this.showMeetCouple = true,
    this.showCountdown = true,
    this.showDetails = true,
    this.showItinerary = true,
    this.showHeroText = true,
    this.partner1Description = '',
    this.partner2Description = '',
    this.partner1ImageUrl,
    this.partner2ImageUrl,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'partner1_name': partner1,
    'partner2_name': partner2,
    'date': dateStr == 'Ej satt' ? null : dateStr,
    'time': timeStr,
    'wedding_code': code,
    'admin_code': adminCode,
    'ceremony_address': churchAddress,
    'party_address': venueAddress,
    'cover_image_url': coverImageUrl,
    'itinerary': itinerary,
    'show_meet_couple': showMeetCouple,
    'show_countdown': showCountdown,
    'show_details': showDetails,
    'show_itinerary': showItinerary,
    'show_hero_text': showHeroText,
    'partner1_description': partner1Description,
    'partner2_description': partner2Description,
    'partner1_image_url': partner1ImageUrl,
    'partner2_image_url': partner2ImageUrl,
  };

  factory Wedding.fromJson(Map<String, dynamic> json) => Wedding(
    id: json['id'] ?? '',
    partner1: json['partner1_name'] ?? '',
    partner2: json['partner2_name'] ?? '',
    dateStr: json['date'] ?? 'Ej satt',
    timeStr: json['time'] ?? 'Ej satt',
    code: json['wedding_code'] ?? '',
    adminCode: (json['admin_code'] ?? '').toString(),
    churchAddress: json['ceremony_address'] ?? '',
    venueAddress: json['party_address'] ?? '',
    coverImageUrl: json['cover_image_url'],
    itinerary: json['itinerary'] != null
        ? List<Map<String, dynamic>>.from(json['itinerary'])
        : [],
    showMeetCouple: json['show_meet_couple'] ?? true,
    showCountdown: json['show_countdown'] ?? true,
    showDetails: json['show_details'] ?? true,
    showItinerary: json['show_itinerary'] ?? true,
    showHeroText: json['show_hero_text'] ?? true,
    partner1Description: (json['partner1_description'] ?? '').toString(),
    partner2Description: (json['partner2_description'] ?? '').toString(),
    partner1ImageUrl: json['partner1_image_url'],
    partner2ImageUrl: json['partner2_image_url'],
  );
}