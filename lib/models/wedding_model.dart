class Wedding {
  final String id;
  final String partner1;
  final String partner2;
  final String dateStr; 
  final String timeStr; 
  final String code;
  final String adminCode;
  final String churchAddress;
  final String venueAddress; // Säkerställd till venueAddress
  final String? coverImageUrl;
  final List<Map<String, dynamic>> itinerary; 

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
    'party_address': venueAddress, // Mappar mot party_address i Supabase
    'cover_image_url': coverImageUrl,
    'itinerary': itinerary, 
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
    venueAddress: json['party_address'] ?? '', // Läser från party_address
    coverImageUrl: json['cover_image_url'],
    itinerary: json['itinerary'] != null 
        ? List<Map<String, dynamic>>.from(json['itinerary'])
        : [],
  );
}