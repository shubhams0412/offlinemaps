
/// Represents a geographic place in the offline map system.
class Place {
  final String id;
  final String name;
  final String displayName;
  final String type;
  final double lat;
  final double lon;
  final String? icon;
  final String? address;
  final String? phone;
  final String? website;
  final Map<String, dynamic>? metadata;

  Place({
    required this.id,
    required this.name,
    required this.displayName,
    required this.type,
    required this.lat,
    required this.lon,
    this.icon,
    this.address,
    this.phone,
    this.website,
    this.metadata,
  });

  /// Get the location type icon emoji
  String get typeIcon {
    if (icon != null && icon!.isNotEmpty) return icon!;
    
    switch (type.toLowerCase()) {
      case 'city':
        return '🏙️';
      case 'town':
        return '🏘️';
      case 'village':
        return '🏡';
      case 'suburb':
      case 'neighbourhood':
        return '🏠';
      case 'restaurant':
      case 'cafe':
        return '🍽️';
      case 'hospital':
      case 'clinic':
        return '🏥';
      case 'school':
      case 'university':
      case 'college':
        return '🎓';
      case 'bank':
      case 'atm':
        return '🏦';
      case 'fuel':
        return '⛽';
      case 'pharmacy':
        return '💊';
      case 'railway':
      case 'station':
        return '🚂';
      case 'airport':
      case 'aerodrome':
        return '✈️';
      default:
        return '📍';
    }
  }

  @override
  String toString() => 'Place($name, $lat, $lon)';
}
