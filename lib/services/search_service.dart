import 'dart:async';
import '../models/place.dart';
import 'offline_places_service.dart';

/// Fully offline replacement for the old online SearchService.
/// This class now wraps OfflinePlacesService to provide search results
/// without any internet dependency.
class SearchService {
  final OfflinePlacesService _offlinePlaces = OfflinePlacesService();

  /// Initialize the underlying offline search engine.
  /// Should be called on app startup.
  Future<void> initialize() async {
    await _offlinePlaces.initialize();
  }

  /// Searches for places fully offline using the local JSON database.
  /// Returns top results (default 15).
  Future<List<Map<String, dynamic>>> searchPlaces(String query, {String? category, double? userLat, double? userLon, int limit = 15}) async {
    try {
      if (!_offlinePlaces.isInitialized) {
        await initialize();
      }

      final List<Place> results = _offlinePlaces.search(query, limit: limit, category: category, userLat: userLat, userLon: userLon);
      
      // Convert to Map for compatibility with existing UI code
      return results.map((place) => {
        'display_name': place.displayName,
        'lat': place.lat.toString(), // UI expects string like Nominatim
        'lon': place.lon.toString(),
        'name': place.name,
        'type': place.type,
      }).toList();
    } catch (e) {
      throw Exception('Offline search error: $e');
    }
  }
}
