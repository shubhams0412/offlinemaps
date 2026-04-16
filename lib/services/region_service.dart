import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../models/map_download_models.dart';

/// Model representing a downloadable map region (legacy support)
class MapRegion {
  final String id;
  final String name;
  final String size;
  final String url;
  final String? description;
  final double? centerLat;
  final double? centerLng;
  final int? minZoom;
  final int? maxZoom;

  MapRegion({
    required this.id,
    required this.name,
    required this.size,
    required this.url,
    this.description,
    this.centerLat,
    this.centerLng,
    this.minZoom,
    this.maxZoom,
  });

  factory MapRegion.fromJson(Map<String, dynamic> json) {
    return MapRegion(
      id: json['id'] as String,
      name: json['name'] as String,
      size: json['size'] as String,
      url: json['url'] as String,
      description: json['description'] as String?,
      centerLat: (json['centerLat'] as num?)?.toDouble(),
      centerLng: (json['centerLng'] as num?)?.toDouble(),
      minZoom: json['minZoom'] as int?,
      maxZoom: json['maxZoom'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'url': url,
    'description': description,
    'centerLat': centerLat,
    'centerLng': centerLng,
    'minZoom': minZoom,
    'maxZoom': maxZoom,
  };
}

/// Service for managing map regions and MBTiles validation
class RegionService {
  static const String _regionsAssetPath = 'assets/regions.json';

  /// Load countries with hierarchical structure from bundled JSON asset
  static Future<List<MapCountry>> loadCountriesFromAsset() async {
    try {
      final String jsonString = await rootBundle.loadString(_regionsAssetPath);
      final Map<String, dynamic> data = json.decode(jsonString);
      final List<dynamic> countriesJson = data['countries'] as List<dynamic>? ?? [];
      return countriesJson
          .map((c) => MapCountry.fromJson(c as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('RegionService: Failed to load countries from asset: $e');
      return [];
    }
  }

  /// Load regions from bundled JSON asset (legacy support)
  static Future<List<MapRegion>> loadRegionsFromAsset() async {
    try {
      final String jsonString = await rootBundle.loadString(_regionsAssetPath);
      return _parseRegionsJson(jsonString);
    } catch (e) {
      debugPrint('RegionService: Failed to load regions from asset: $e');
      return _getDefaultRegions();
    }
  }

  /// Load regions from a remote API endpoint
  static Future<List<MapRegion>> loadRegionsFromApi(String apiUrl) async {
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        return _parseRegionsJson(response.body);
      } else {
        debugPrint('RegionService: API returned status ${response.statusCode}');
        return _getDefaultRegions();
      }
    } catch (e) {
      debugPrint('RegionService: Failed to load regions from API: $e');
      return _getDefaultRegions();
    }
  }

  static List<MapRegion> _parseRegionsJson(String jsonString) {
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> regionsJson = data['regions'] as List<dynamic>;
    return regionsJson
        .map((r) => MapRegion.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Default regions when JSON loading fails
  static List<MapRegion> _getDefaultRegions() {
    return [
      MapRegion(
        id: 'zurich',
        name: 'Zurich, Switzerland',
        size: '35 MB',
        url: 'https://github.com/openmaptiles/mbtiles-extracts/releases/download/v3.15/zurich_switzerland.mbtiles',
        description: 'City of Zurich vector tiles',
        centerLat: 47.3769,
        centerLng: 8.5417,
        minZoom: 0,
        maxZoom: 14,
      ),
      MapRegion(
        id: 'monaco',
        name: 'Monaco',
        size: '5 MB',
        url: 'https://github.com/openmaptiles/mbtiles-extracts/releases/download/v3.15/monaco.mbtiles',
        description: 'Principality of Monaco',
        centerLat: 43.7384,
        centerLng: 7.4246,
        minZoom: 0,
        maxZoom: 14,
      ),
    ];
  }

  /// Get the local file path for a region's MBTiles file
  static Future<String> getMbTilesPath(String regionId) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/mbtiles_cache/$regionId.mbtiles';
  }

  /// Check if an MBTiles file exists locally
  static Future<bool> isRegionDownloaded(String regionId) async {
    final path = await getMbTilesPath(regionId);
    final file = File(path);
    if (!await file.exists()) return false;
    return await validateMbTilesFile(path);
  }

  /// Validate that a file is a proper MBTiles SQLite database
  static Future<bool> validateMbTilesFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('MBTiles validation: File does not exist: $filePath');
        return false;
      }

      // Check file size (MBTiles should be at least a few KB)
      final fileSize = await file.length();
      if (fileSize < 1024) {
        debugPrint('MBTiles validation: File too small ($fileSize bytes): $filePath');
        return false;
      }

      // Check SQLite header magic bytes
      final bytes = await file.openRead(0, 16).first;
      final header = String.fromCharCodes(bytes.take(15));
      if (!header.startsWith('SQLite format 3')) {
        debugPrint('MBTiles validation: Invalid SQLite header: $filePath');
        return false;
      }

      // Try to open and query the database
      Database? db;
      try {
        db = sqlite3.open(filePath, mode: OpenMode.readOnly);

        // Check for required MBTiles tables
        final tables = db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND (name='tiles' OR name='metadata')"
        );

        if (tables.isEmpty) {
          debugPrint('MBTiles validation: Missing required tables: $filePath');
          return false;
        }

        // Reject vector tile formats (pbf/mvt) — only raster tiles (png/jpg/webp)
        // can be rendered by the MemoryImage-based raster TileLayer.
        // Attempting to decode PBF bytes as an image causes "Could not decompress image".
        final fmtResult = db.select(
          "SELECT value FROM metadata WHERE name='format' LIMIT 1"
        );
        if (fmtResult.isNotEmpty) {
          final format = (fmtResult.first['value'] as String?)?.toLowerCase();
          if (format == 'pbf' || format == 'mvt') {
            debugPrint(
              'MBTiles validation: Vector tiles ($format) are not supported - raster only: $filePath',
            );
            return false;
          }
        }

        // Check if tiles table has data
        final tileCount = db.select('SELECT COUNT(*) as count FROM tiles');
        final count = tileCount.first['count'] as int;

        if (count == 0) {
          debugPrint('MBTiles validation: No tiles found in database: $filePath');
          return false;
        }

        debugPrint(
          'MBTiles validation: Valid raster MBTiles with $count tiles: $filePath',
        );
        return true;
      } finally {
        db?.dispose();
      }
    } catch (e) {
      debugPrint('MBTiles validation error: $e');
      return false;
    }
  }

  /// Get metadata from an MBTiles file
  static Future<Map<String, String>?> getMbTilesMetadata(String filePath) async {
    Database? db;
    try {
      db = sqlite3.open(filePath, mode: OpenMode.readOnly);
      final result = db.select('SELECT name, value FROM metadata');

      final metadata = <String, String>{};
      for (final row in result) {
        metadata[row['name'] as String] = row['value'] as String;
      }
      return metadata;
    } catch (e) {
      debugPrint('Failed to read MBTiles metadata: $e');
      return null;
    } finally {
      db?.dispose();
    }
  }

  /// Delete a downloaded region
  static Future<bool> deleteRegion(String regionId) async {
    try {
      final path = await getMbTilesPath(regionId);
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to delete region $regionId: $e');
      return false;
    }
  }

  /// Get all downloaded regions
  static Future<List<String>> getDownloadedRegionIds() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/mbtiles_cache');

      if (!await cacheDir.exists()) {
        return [];
      }

      final files = await cacheDir.list().toList();
      final validRegions = <String>[];

      for (final file in files) {
        if (file.path.endsWith('.mbtiles')) {
          if (await validateMbTilesFile(file.path)) {
            final id = file.path.split('/').last.replaceAll('.mbtiles', '');
            validRegions.add(id);
          }
        }
      }

      return validRegions;
    } catch (e) {
      debugPrint('Failed to list downloaded regions: $e');
      return [];
    }
  }
}
