import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/place.dart';

/// Fully offline search service using local places.json file.
class OfflinePlacesService {
  static const String _assetPath = 'assets/data/gujarat_places.json';

  /// In-memory store of all places for fast searching
  final List<_PlaceData> _places = [];

  /// Pre-computed lowercase names for faster search
  final List<String> _searchableNames = [];

  bool _isInitialized = false;
  String? _error;

  /// Whether the service has been initialized
  bool get isInitialized => _isInitialized;

  /// Error message if initialization failed
  String? get error => _error;

  /// Total number of places loaded
  int get placeCount => _places.length;

  /// Initialize the service by loading places from assets or storage.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final localFile = File('${docDir.path}/data/gujarat_places.json');
      
      final stopwatch = Stopwatch()..start();
      String jsonString;
      if (await localFile.exists()) {
        debugPrint('[OfflinePlaces] Loading places from documents storage...');
        jsonString = await localFile.readAsString();
      } else {
        debugPrint('[OfflinePlaces] Loading places from bundled assets...');
        // Load JSON from assets
        jsonString = await rootBundle.loadString(_assetPath);
      }
      
      final Map<String, dynamic> geoJson = json.decode(jsonString);

      // Parse features
      final features = geoJson['features'] as List<dynamic>? ?? [];

      for (final feature in features) {
        final place = _PlaceData.fromGeoJsonFeature(feature);
        if (place != null) {
          _places.add(place);
          // Pre-compute lowercase name for faster search
          _searchableNames.add(place.name.toLowerCase());
        }
      }

      stopwatch.stop();
      _isInitialized = true;
      debugPrint(
        '[OfflinePlaces] Loaded ${_places.length} places in ${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      _error = 'Failed to load places: $e';
      debugPrint('[OfflinePlaces] Error: $_error');
    }
  }

  /// Search for places matching the query.
  /// If [category] is provided, only results matching that category will be returned.
  /// [userLat] and [userLon] can be provided to prioritize nearby results.
  List<Place> search(String query, {int limit = 15, String? category, double? userLat, double? userLon}) {
    if (!_isInitialized) return [];

    final hasQuery = query.trim().isNotEmpty;
    final queryLower = hasQuery ? query.toLowerCase().trim() : '';
    final List<_ScoredPlace> scored = [];

    // Filter and score matches
    for (int i = 0; i < _places.length; i++) {
      final place = _places[i];

      // 1. Category Filter (Mandatory if provided)
      if (category != null) {
        if (!_matchesCategory(place, category)) continue;
      }

      // 2. Name search (Optional - if no query, just return category matches)
      int score = 0;
      if (hasQuery) {
        final nameLower = _searchableNames[i];
        if (!nameLower.contains(queryLower)) continue;

        if (nameLower == queryLower) {
          score = 1000;
        } else if (nameLower.startsWith(queryLower)) {
          score = 500;
        } else if (nameLower.contains(' $queryLower') || nameLower.contains('-$queryLower')) {
          score = 200;
        } else {
          score = 100;
        }
      } else if (category == null) {
        // No query and no category? Return nothing.
        continue;
      } else {
        // Category search with no query - base score
        score = 10;
      }

      // 3. Proximity Boost (Closer = Higher Score)
      if (userLat != null && userLon != null) {
        final distance = _haversineDistance(userLat, userLon, place.lat, place.lon);
        // Add a significant boost for proximity (up to 300 points for very close places)
        // This ensures a slightly worse name match will win if it's much closer
        final distanceBoost = (300 / (1 + distance)).round();
        score += distanceBoost;
      }

      if (place.placeType == 'city') score += 50;
      if (place.placeType == 'town') score += 30;

      scored.add(_ScoredPlace(place, score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.take(limit).map((s) => s.place.toPlace()).toList();
  }

  /// Helper to check if a place matches a category
  bool _matchesCategory(_PlaceData place, String category) {
    final amenity = place.properties['amenity']?.toString().toLowerCase();
    
    switch (category.toLowerCase()) {
      case 'hospital':
        return amenity == 'hospital' || amenity == 'clinic';
      case 'petrol_pump':
      case 'fuel':
        return amenity == 'fuel';
      default:
        // Broad check for other potential categories in properties
        return place.properties.values.any((v) => v.toString().toLowerCase().contains(category.toLowerCase()));
    }
  }

  Timer? _debounceTimer;
  String? _lastQuery;
  String? _lastCategory;

  void searchDebounced(
    String query, {
    required void Function(List<Place> results) onResults,
    String? category,
    double? userLat,
    double? userLon,
    int limit = 15,
    Duration debounce = const Duration(milliseconds: 200),
  }) {
    _debounceTimer?.cancel();
    
    if (query.trim().isEmpty && category == null) {
      onResults([]);
      return;
    }
    
    if (query == _lastQuery && category == _lastCategory) return;
    _lastQuery = query;
    _lastCategory = category;

    _debounceTimer = Timer(debounce, () {
      final results = search(query, limit: limit, category: category, userLat: userLat, userLon: userLon);
      onResults(results);
    });
  }

  /// Reverse geocode - find nearest place to coordinates.
  Place? reverseGeocode(double lat, double lon, {double radiusKm = 10}) {
    if (!_isInitialized || _places.isEmpty) return null;

    _PlaceData? closest;
    double closestDistance = double.infinity;

    for (final place in _places) {
      final distance = _haversineDistance(lat, lon, place.lat, place.lon);
      if (distance < closestDistance && distance <= radiusKm) {
        closestDistance = distance;
        closest = place;
      }
    }

    return closest?.toPlace();
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }

  double _toRadians(double deg) => deg * math.pi / 180;

  void cancelPendingSearch() {
    _debounceTimer?.cancel();
    _lastQuery = null;
  }

  void dispose() {
    _debounceTimer?.cancel();
    _places.clear();
    _searchableNames.clear();
    _isInitialized = false;
    _error = null;
  }
}

class _PlaceData {
  final String name;
  final double lat;
  final double lon;
  final String placeType;
  final String? displayName;
  final Map<String, dynamic> properties;

  _PlaceData({
    required this.name,
    required this.lat,
    required this.lon,
    required this.placeType,
    this.displayName,
    required this.properties,
  });

  static _PlaceData? fromGeoJsonFeature(Map<String, dynamic> feature) {
    try {
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      final properties = feature['properties'] as Map<String, dynamic>? ?? {};

      if (geometry == null) return null;
      final String geomType = geometry['type'] ?? 'Point';
      final dynamic coordsData = geometry['coordinates'];

      double? lat;
      double? lon;

      if (geomType == 'Point' && coordsData is List && coordsData.length >= 2) {
        lon = (coordsData[0] as num).toDouble();
        lat = (coordsData[1] as num).toDouble();
      } else if (geomType == 'LineString' && coordsData is List && coordsData.isNotEmpty) {
        final firstPair = coordsData[0] as List;
        lon = (firstPair[0] as num).toDouble();
        lat = (firstPair[1] as num).toDouble();
      } else if (geomType == 'Polygon' && coordsData is List && coordsData.isNotEmpty) {
        final outerRing = coordsData[0] as List;
        if (outerRing.isNotEmpty) {
          final firstPair = outerRing[0] as List;
          lon = (firstPair[0] as num).toDouble();
          lat = (firstPair[1] as num).toDouble();
        }
      }

      if (lat == null || lon == null) return null;

      final name = properties['name'] ?? properties['name:en'];
      if (name == null || name.toString().trim().isEmpty) return null;

      final placeType = properties['place']?.toString() ?? properties['type']?.toString() ?? 'place';

      return _PlaceData(
        name: name.toString(),
        lat: lat,
        lon: lon,
        placeType: placeType,
        displayName: properties['display_name'] ?? properties['label'],
        properties: properties,
      );
    } catch (e) {
      return null;
    }
  }

  Place toPlace() {
    return Place(
      id: 'off_${name.hashCode}_$lat',
      name: name,
      displayName: displayName ?? _buildDisplayName(),
      type: placeType,
      lat: lat,
      lon: lon,
      icon: _getIcon(),
      address: properties['addr:full']?.toString() ?? properties['address']?.toString(),
      phone: properties['phone']?.toString(),
      website: properties['website']?.toString(),
      metadata: properties,
    );
  }

  String _buildDisplayName() {
    final parts = <String>[name];
    if (properties['addr:city'] != null) parts.add(properties['addr:city'].toString());
    if (properties['addr:state'] != null) parts.add(properties['addr:state'].toString());
    return parts.join(', ');
  }

  String _getIcon() {
    switch (placeType.toLowerCase()) {
      case 'city': return '🏙️';
      case 'town': return '🏘️';
      case 'village': return '🏡';
      case 'hospital': return '🏥';
      case 'school': return '🎓';
      case 'restaurant': return '🍽️';
      case 'bank': return '🏦';
      case 'fuel': return '⛽';
      default: return '📍';
    }
  }
}

class _ScoredPlace {
  final _PlaceData place;
  final int score;
  _ScoredPlace(this.place, this.score);
}
