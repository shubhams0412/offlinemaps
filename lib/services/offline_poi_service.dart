import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// POI category for filtering
enum PoiCategory {
  all,
  city,
  town,
  village,
  airport,
  railway,
  bus,
  hospital,
  pharmacy,
  fuel,
  restaurant,
  cafe,
  hotel,
  atm,
  bank,
  temple,
  mosque,
  church,
  school,
  college,
  university,
  police,
  postOffice,
  supermarket,
  mall,
  park,
  beach,
  monument,
  museum,
  cinema,
  parking,
}

/// Represents a Point of Interest
class OfflinePoi {
  final int? id;
  final String name;
  final String? alternateName;
  final String displayAddress;
  final double latitude;
  final double longitude;
  final PoiCategory category;
  final String? phone;
  final String? website;
  final String? openingHours;
  final Map<String, dynamic>? metadata;

  OfflinePoi({
    this.id,
    required this.name,
    this.alternateName,
    required this.displayAddress,
    required this.latitude,
    required this.longitude,
    required this.category,
    this.phone,
    this.website,
    this.openingHours,
    this.metadata,
  });

  LatLng get location => LatLng(latitude, longitude);

  String get categoryIcon {
    switch (category) {
      case PoiCategory.city:
        return '🏙️';
      case PoiCategory.town:
        return '🏘️';
      case PoiCategory.village:
        return '🏡';
      case PoiCategory.airport:
        return '✈️';
      case PoiCategory.railway:
        return '🚂';
      case PoiCategory.bus:
        return '🚌';
      case PoiCategory.hospital:
        return '🏥';
      case PoiCategory.pharmacy:
        return '💊';
      case PoiCategory.fuel:
        return '⛽';
      case PoiCategory.restaurant:
        return '🍽️';
      case PoiCategory.cafe:
        return '☕';
      case PoiCategory.hotel:
        return '🏨';
      case PoiCategory.atm:
        return '🏧';
      case PoiCategory.bank:
        return '🏦';
      case PoiCategory.temple:
        return '🛕';
      case PoiCategory.mosque:
        return '🕌';
      case PoiCategory.church:
        return '⛪';
      case PoiCategory.school:
        return '🏫';
      case PoiCategory.college:
      case PoiCategory.university:
        return '🎓';
      case PoiCategory.police:
        return '🚔';
      case PoiCategory.postOffice:
        return '📮';
      case PoiCategory.supermarket:
        return '🛒';
      case PoiCategory.mall:
        return '🛍️';
      case PoiCategory.park:
        return '🌳';
      case PoiCategory.beach:
        return '🏖️';
      case PoiCategory.monument:
        return '🗿';
      case PoiCategory.museum:
        return '🏛️';
      case PoiCategory.cinema:
        return '🎬';
      case PoiCategory.parking:
        return '🅿️';
      default:
        return '📍';
    }
  }

  String get categoryName {
    switch (category) {
      case PoiCategory.city:
        return 'City';
      case PoiCategory.town:
        return 'Town';
      case PoiCategory.village:
        return 'Village';
      case PoiCategory.airport:
        return 'Airport';
      case PoiCategory.railway:
        return 'Railway Station';
      case PoiCategory.bus:
        return 'Bus Station';
      case PoiCategory.hospital:
        return 'Hospital';
      case PoiCategory.pharmacy:
        return 'Pharmacy';
      case PoiCategory.fuel:
        return 'Fuel Station';
      case PoiCategory.restaurant:
        return 'Restaurant';
      case PoiCategory.cafe:
        return 'Cafe';
      case PoiCategory.hotel:
        return 'Hotel';
      case PoiCategory.atm:
        return 'ATM';
      case PoiCategory.bank:
        return 'Bank';
      case PoiCategory.temple:
        return 'Temple';
      case PoiCategory.mosque:
        return 'Mosque';
      case PoiCategory.church:
        return 'Church';
      case PoiCategory.school:
        return 'School';
      case PoiCategory.college:
        return 'College';
      case PoiCategory.university:
        return 'University';
      case PoiCategory.police:
        return 'Police Station';
      case PoiCategory.postOffice:
        return 'Post Office';
      case PoiCategory.supermarket:
        return 'Supermarket';
      case PoiCategory.mall:
        return 'Shopping Mall';
      case PoiCategory.park:
        return 'Park';
      case PoiCategory.beach:
        return 'Beach';
      case PoiCategory.monument:
        return 'Monument';
      case PoiCategory.museum:
        return 'Museum';
      case PoiCategory.cinema:
        return 'Cinema';
      case PoiCategory.parking:
        return 'Parking';
      default:
        return 'Place';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'alternate_name': alternateName,
      'display_address': displayAddress,
      'latitude': latitude,
      'longitude': longitude,
      'category': category.index,
      'phone': phone,
      'website': website,
      'opening_hours': openingHours,
      'metadata': metadata != null ? json.encode(metadata) : null,
    };
  }

  factory OfflinePoi.fromMap(Map<String, dynamic> map) {
    return OfflinePoi(
      id: map['id'],
      name: map['name'],
      alternateName: map['alternate_name'],
      displayAddress: map['display_address'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      category: PoiCategory.values[map['category'] ?? 0],
      phone: map['phone'],
      website: map['website'],
      openingHours: map['opening_hours'],
      metadata: map['metadata'] != null
          ? json.decode(map['metadata'])
          : null,
    );
  }
}

/// Offline POI search and database service
class OfflinePoiService {
  static const String _dbName = 'offline_pois.db';
  static const int _dbVersion = 1;

  Database? _database;
  bool _isInitialized = false;

  /// Singleton pattern
  static final OfflinePoiService _instance = OfflinePoiService._internal();
  factory OfflinePoiService() => _instance;
  OfflinePoiService._internal();

  /// Initialize the database
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = path.join(documentsDir.path, _dbName);

      _database = await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
      );

      // Populate with bundled data if empty
      final count = Sqflite.firstIntValue(
        await _database!.rawQuery('SELECT COUNT(*) FROM pois'),
      );
      if (count == 0) {
        await _populateDefaultData();
      }

      _isInitialized = true;
      debugPrint('[OfflinePoiService] Initialized with ${count ?? 0} POIs');
    } catch (e) {
      debugPrint('[OfflinePoiService] Init error: $e');
    }
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pois (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        alternate_name TEXT,
        display_address TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        category INTEGER NOT NULL,
        phone TEXT,
        website TEXT,
        opening_hours TEXT,
        metadata TEXT
      )
    ''');

    // Create spatial index using R-tree
    await db.execute('''
      CREATE VIRTUAL TABLE pois_rtree USING rtree(
        id,
        min_lat, max_lat,
        min_lon, max_lon
      )
    ''');

    // Create text search index
    await db.execute('''
      CREATE VIRTUAL TABLE pois_fts USING fts5(
        name,
        alternate_name,
        display_address,
        content='pois',
        content_rowid='id'
      )
    ''');

    // Triggers to keep FTS and R-tree in sync
    await db.execute('''
      CREATE TRIGGER pois_ai AFTER INSERT ON pois BEGIN
        INSERT INTO pois_fts(rowid, name, alternate_name, display_address)
        VALUES (new.id, new.name, new.alternate_name, new.display_address);
        INSERT INTO pois_rtree(id, min_lat, max_lat, min_lon, max_lon)
        VALUES (new.id, new.latitude, new.latitude, new.longitude, new.longitude);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER pois_ad AFTER DELETE ON pois BEGIN
        INSERT INTO pois_fts(pois_fts, rowid, name, alternate_name, display_address)
        VALUES ('delete', old.id, old.name, old.alternate_name, old.display_address);
        DELETE FROM pois_rtree WHERE id = old.id;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER pois_au AFTER UPDATE ON pois BEGIN
        INSERT INTO pois_fts(pois_fts, rowid, name, alternate_name, display_address)
        VALUES ('delete', old.id, old.name, old.alternate_name, old.display_address);
        INSERT INTO pois_fts(rowid, name, alternate_name, display_address)
        VALUES (new.id, new.name, new.alternate_name, new.display_address);
        UPDATE pois_rtree SET
          min_lat = new.latitude, max_lat = new.latitude,
          min_lon = new.longitude, max_lon = new.longitude
        WHERE id = new.id;
      END
    ''');
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    // Handle migrations here
  }

  Future<void> _populateDefaultData() async {
    final pois = _getDefaultPois();
    final batch = _database!.batch();

    for (final poi in pois) {
      batch.insert('pois', poi.toMap());
    }

    await batch.commit(noResult: true);
    debugPrint('[OfflinePoiService] Populated ${pois.length} default POIs');
  }

  /// Search POIs by text query
  Future<List<OfflinePoi>> search(
    String query, {
    PoiCategory? category,
    LatLng? nearLocation,
    double radiusKm = 50.0,
    int limit = 20,
  }) async {
    if (!_isInitialized) await initialize();

    if (query.isEmpty && category == null && nearLocation == null) {
      return [];
    }

    // Check for coordinate input
    final coordMatch = RegExp(r'^([-+]?\d*\.?\d+)\s*,\s*([-+]?\d*\.?\d+)$')
        .firstMatch(query.trim());
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lon = double.tryParse(coordMatch.group(2)!);
      if (lat != null && lon != null) {
        return [
          OfflinePoi(
            name: 'Coordinates',
            displayAddress: '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
            latitude: lat,
            longitude: lon,
            category: PoiCategory.all,
          ),
        ];
      }
    }

    String sql;
    List<dynamic> args = [];

    if (query.isNotEmpty) {
      // Full-text search
      sql = '''
        SELECT pois.* FROM pois
        JOIN pois_fts ON pois.id = pois_fts.rowid
        WHERE pois_fts MATCH ?
      ''';
      args.add('$query*');

      if (category != null && category != PoiCategory.all) {
        sql += ' AND pois.category = ?';
        args.add(category.index);
      }
    } else if (nearLocation != null) {
      // Spatial search within bounding box
      final latDelta = radiusKm / 111.0;
      final lonDelta = radiusKm / (111.0 * math.cos(nearLocation.latitude * math.pi / 180));

      sql = '''
        SELECT pois.* FROM pois
        JOIN pois_rtree ON pois.id = pois_rtree.id
        WHERE pois_rtree.min_lat >= ? AND pois_rtree.max_lat <= ?
          AND pois_rtree.min_lon >= ? AND pois_rtree.max_lon <= ?
      ''';
      args.addAll([
        nearLocation.latitude - latDelta,
        nearLocation.latitude + latDelta,
        nearLocation.longitude - lonDelta,
        nearLocation.longitude + lonDelta,
      ]);

      if (category != null && category != PoiCategory.all) {
        sql += ' AND pois.category = ?';
        args.add(category.index);
      }
    } else if (category != null && category != PoiCategory.all) {
      sql = 'SELECT * FROM pois WHERE category = ?';
      args.add(category.index);
    } else {
      return [];
    }

    sql += ' LIMIT ?';
    args.add(limit);

    final results = await _database!.rawQuery(sql, args);
    var pois = results.map((r) => OfflinePoi.fromMap(r)).toList();

    // Sort by distance if location provided
    if (nearLocation != null) {
      pois.sort((a, b) {
        final distA = _haversineDistance(nearLocation, a.location);
        final distB = _haversineDistance(nearLocation, b.location);
        return distA.compareTo(distB);
      });
    }

    return pois;
  }

  /// Search POIs near a location
  Future<List<OfflinePoi>> searchNearby(
    LatLng location, {
    PoiCategory? category,
    double radiusKm = 10.0,
    int limit = 20,
  }) async {
    return search(
      '',
      category: category,
      nearLocation: location,
      radiusKm: radiusKm,
      limit: limit,
    );
  }

  /// Get POI by ID
  Future<OfflinePoi?> getById(int id) async {
    if (!_isInitialized) await initialize();

    final results = await _database!.query(
      'pois',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return OfflinePoi.fromMap(results.first);
  }

  /// Add a new POI
  Future<int> addPoi(OfflinePoi poi) async {
    if (!_isInitialized) await initialize();
    return await _database!.insert('pois', poi.toMap());
  }

  /// Add multiple POIs
  Future<void> addPois(List<OfflinePoi> pois) async {
    if (!_isInitialized) await initialize();

    final batch = _database!.batch();
    for (final poi in pois) {
      batch.insert('pois', poi.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Delete a POI
  Future<void> deletePoi(int id) async {
    if (!_isInitialized) await initialize();
    await _database!.delete('pois', where: 'id = ?', whereArgs: [id]);
  }

  /// Clear all POIs
  Future<void> clearAll() async {
    if (!_isInitialized) await initialize();
    await _database!.delete('pois');
  }

  /// Import POIs from JSON
  Future<int> importFromJson(String jsonData) async {
    if (!_isInitialized) await initialize();

    final List<dynamic> data = json.decode(jsonData);
    final pois = data.map((item) {
      return OfflinePoi(
        name: item['name'] ?? '',
        alternateName: item['alternate_name'],
        displayAddress: item['address'] ?? item['display_address'] ?? '',
        latitude: (item['lat'] ?? item['latitude'])?.toDouble() ?? 0.0,
        longitude: (item['lon'] ?? item['longitude'])?.toDouble() ?? 0.0,
        category: _parseCategory(item['category'] ?? item['type']),
        phone: item['phone'],
        website: item['website'],
        openingHours: item['opening_hours'],
        metadata: item['metadata'],
      );
    }).toList();

    await addPois(pois);
    return pois.length;
  }

  PoiCategory _parseCategory(String? categoryStr) {
    if (categoryStr == null) return PoiCategory.all;

    switch (categoryStr.toLowerCase()) {
      case 'city':
        return PoiCategory.city;
      case 'town':
        return PoiCategory.town;
      case 'village':
        return PoiCategory.village;
      case 'airport':
      case 'aerodrome':
        return PoiCategory.airport;
      case 'railway':
      case 'station':
      case 'train_station':
        return PoiCategory.railway;
      case 'bus':
      case 'bus_station':
        return PoiCategory.bus;
      case 'hospital':
        return PoiCategory.hospital;
      case 'pharmacy':
        return PoiCategory.pharmacy;
      case 'fuel':
      case 'petrol':
      case 'gas_station':
        return PoiCategory.fuel;
      case 'restaurant':
        return PoiCategory.restaurant;
      case 'cafe':
        return PoiCategory.cafe;
      case 'hotel':
      case 'motel':
        return PoiCategory.hotel;
      case 'atm':
        return PoiCategory.atm;
      case 'bank':
        return PoiCategory.bank;
      case 'temple':
      case 'hindu':
        return PoiCategory.temple;
      case 'mosque':
      case 'muslim':
        return PoiCategory.mosque;
      case 'church':
      case 'christian':
        return PoiCategory.church;
      case 'school':
        return PoiCategory.school;
      case 'college':
        return PoiCategory.college;
      case 'university':
        return PoiCategory.university;
      case 'police':
        return PoiCategory.police;
      case 'post_office':
        return PoiCategory.postOffice;
      case 'supermarket':
        return PoiCategory.supermarket;
      case 'mall':
      case 'shopping':
        return PoiCategory.mall;
      case 'park':
        return PoiCategory.park;
      case 'beach':
        return PoiCategory.beach;
      case 'monument':
        return PoiCategory.monument;
      case 'museum':
        return PoiCategory.museum;
      case 'cinema':
        return PoiCategory.cinema;
      case 'parking':
        return PoiCategory.parking;
      default:
        return PoiCategory.all;
    }
  }

  double _haversineDistance(LatLng start, LatLng end) {
    const R = 6371.0;
    final dLat = _toRadians(end.latitude - start.latitude);
    final dLon = _toRadians(end.longitude - start.longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(start.latitude)) *
            math.cos(_toRadians(end.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180.0;

  /// Get POI count
  Future<int> getCount() async {
    if (!_isInitialized) await initialize();
    return Sqflite.firstIntValue(
      await _database!.rawQuery('SELECT COUNT(*) FROM pois'),
    ) ?? 0;
  }

  List<OfflinePoi> _getDefaultPois() {
    return [
      // Major Indian Cities
      OfflinePoi(name: 'Mumbai', displayAddress: 'Mumbai, Maharashtra, India', latitude: 19.0760, longitude: 72.8777, category: PoiCategory.city),
      OfflinePoi(name: 'Delhi', displayAddress: 'New Delhi, India', latitude: 28.6139, longitude: 77.2090, category: PoiCategory.city),
      OfflinePoi(name: 'Bangalore', alternateName: 'Bengaluru', displayAddress: 'Bangalore, Karnataka, India', latitude: 12.9716, longitude: 77.5946, category: PoiCategory.city),
      OfflinePoi(name: 'Chennai', displayAddress: 'Chennai, Tamil Nadu, India', latitude: 13.0827, longitude: 80.2707, category: PoiCategory.city),
      OfflinePoi(name: 'Kolkata', displayAddress: 'Kolkata, West Bengal, India', latitude: 22.5726, longitude: 88.3639, category: PoiCategory.city),
      OfflinePoi(name: 'Hyderabad', displayAddress: 'Hyderabad, Telangana, India', latitude: 17.3850, longitude: 78.4867, category: PoiCategory.city),

      // Gujarat Cities
      OfflinePoi(name: 'Ahmedabad', displayAddress: 'Ahmedabad, Gujarat, India', latitude: 23.0225, longitude: 72.5714, category: PoiCategory.city),
      OfflinePoi(name: 'Surat', displayAddress: 'Surat, Gujarat, India', latitude: 21.1702, longitude: 72.8311, category: PoiCategory.city),
      OfflinePoi(name: 'Vadodara', alternateName: 'Baroda', displayAddress: 'Vadodara, Gujarat, India', latitude: 22.3072, longitude: 73.1812, category: PoiCategory.city),
      OfflinePoi(name: 'Rajkot', displayAddress: 'Rajkot, Gujarat, India', latitude: 22.3039, longitude: 70.8022, category: PoiCategory.city),
      OfflinePoi(name: 'Gandhinagar', displayAddress: 'Gandhinagar, Gujarat, India', latitude: 23.2156, longitude: 72.6369, category: PoiCategory.city),
      OfflinePoi(name: 'Bhavnagar', displayAddress: 'Bhavnagar, Gujarat, India', latitude: 21.7645, longitude: 72.1519, category: PoiCategory.city),
      OfflinePoi(name: 'Jamnagar', displayAddress: 'Jamnagar, Gujarat, India', latitude: 22.4707, longitude: 70.0577, category: PoiCategory.city),
      OfflinePoi(name: 'Junagadh', displayAddress: 'Junagadh, Gujarat, India', latitude: 21.5222, longitude: 70.4579, category: PoiCategory.city),

      // Gujarat Airports
      OfflinePoi(name: 'Sardar Vallabhbhai Patel International Airport', displayAddress: 'Ahmedabad Airport (AMD), Gujarat', latitude: 23.0734, longitude: 72.6266, category: PoiCategory.airport),
      OfflinePoi(name: 'Surat International Airport', displayAddress: 'Surat Airport (STV), Gujarat', latitude: 21.1139, longitude: 72.7410, category: PoiCategory.airport),
      OfflinePoi(name: 'Vadodara Airport', displayAddress: 'Vadodara Airport (BDQ), Gujarat', latitude: 22.3362, longitude: 73.2263, category: PoiCategory.airport),
      OfflinePoi(name: 'Rajkot International Airport', displayAddress: 'Hirasar Airport (HSR), Gujarat', latitude: 22.3644, longitude: 71.0116, category: PoiCategory.airport),

      // Railway Stations
      OfflinePoi(name: 'Ahmedabad Junction', displayAddress: 'Kalupur, Ahmedabad, Gujarat', latitude: 23.0266, longitude: 72.6007, category: PoiCategory.railway),
      OfflinePoi(name: 'Surat Railway Station', displayAddress: 'Surat, Gujarat', latitude: 21.2060, longitude: 72.8403, category: PoiCategory.railway),
      OfflinePoi(name: 'Vadodara Junction', displayAddress: 'Vadodara, Gujarat', latitude: 22.3098, longitude: 73.1880, category: PoiCategory.railway),

      // Landmarks & Monuments
      OfflinePoi(name: 'Statue of Unity', displayAddress: 'Kevadia, Narmada District, Gujarat', latitude: 21.8380, longitude: 73.7191, category: PoiCategory.monument),
      OfflinePoi(name: 'Sabarmati Ashram', displayAddress: 'Ashram Road, Ahmedabad', latitude: 23.0592, longitude: 72.5801, category: PoiCategory.museum),
      OfflinePoi(name: 'Gir National Park', displayAddress: 'Sasan Gir, Junagadh, Gujarat', latitude: 21.1243, longitude: 70.8242, category: PoiCategory.park),
      OfflinePoi(name: 'Somnath Temple', displayAddress: 'Somnath, Gujarat', latitude: 20.8880, longitude: 70.4010, category: PoiCategory.temple),
      OfflinePoi(name: 'Dwarkadhish Temple', displayAddress: 'Dwarka, Gujarat', latitude: 22.2376, longitude: 68.9674, category: PoiCategory.temple),
      OfflinePoi(name: 'Akshardham Temple', displayAddress: 'Gandhinagar, Gujarat', latitude: 23.2258, longitude: 72.6715, category: PoiCategory.temple),
      OfflinePoi(name: 'Rann of Kutch', displayAddress: 'White Desert, Kutch, Gujarat', latitude: 23.7337, longitude: 69.8597, category: PoiCategory.park),
      OfflinePoi(name: 'Laxmi Vilas Palace', displayAddress: 'Vadodara, Gujarat', latitude: 22.2930, longitude: 73.1863, category: PoiCategory.monument),

      // Hospitals
      OfflinePoi(name: 'Civil Hospital Ahmedabad', displayAddress: 'Asarwa, Ahmedabad', latitude: 23.0464, longitude: 72.6104, category: PoiCategory.hospital),
      OfflinePoi(name: 'Apollo Hospital Ahmedabad', displayAddress: 'Gandhinagar Highway, Ahmedabad', latitude: 23.0718, longitude: 72.5171, category: PoiCategory.hospital),
      OfflinePoi(name: 'Sterling Hospital', displayAddress: 'Gurukul Road, Ahmedabad', latitude: 23.0363, longitude: 72.5256, category: PoiCategory.hospital),
      OfflinePoi(name: 'Zydus Hospital', displayAddress: 'Thaltej, Ahmedabad', latitude: 23.0519, longitude: 72.5204, category: PoiCategory.hospital),

      // Shopping
      OfflinePoi(name: 'Iscon Mega Mall', displayAddress: 'S.G. Highway, Ahmedabad', latitude: 23.0329, longitude: 72.5068, category: PoiCategory.mall),
      OfflinePoi(name: 'Ahmedabad One Mall', displayAddress: 'Vastrapur, Ahmedabad', latitude: 23.0365, longitude: 72.5287, category: PoiCategory.mall),
      OfflinePoi(name: 'AlphaOne Mall', displayAddress: 'Vastrapur, Ahmedabad', latitude: 23.0382, longitude: 72.5276, category: PoiCategory.mall),
    ];
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _isInitialized = false;
  }
}
