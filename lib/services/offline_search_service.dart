import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:vector_tile/vector_tile.dart' as vt;
import '../models/place.dart';

/// Service to extract searchable data from MBTiles and manage a local FTS-indexed search database.
class OfflineSearchService {
  Database? _db;
  bool _isIndexing = false;
  double _indexProgress = 0;

  bool get isIndexing => _isIndexing;
  double get indexProgress => _indexProgress;

  Future<void> initialize() async {
    if (_db != null) return;
    
    final dbPath = p.join(await getDatabasesPath(), 'offline_search.db');
    _db = await openDatabase(
      dbPath,
      version: 2, // Upgraded version
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE places ADD COLUMN address TEXT');
          await db.execute('ALTER TABLE places ADD COLUMN phone TEXT');
          await db.execute('ALTER TABLE places ADD COLUMN website TEXT');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE places(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            display_name TEXT,
            lat REAL,
            lon REAL,
            type TEXT,
            icon TEXT,
            address TEXT,
            phone TEXT,
            website TEXT,
            metadata TEXT
          )
        ''');
        
        await db.execute('''
          CREATE VIRTUAL TABLE places_fts USING fts5(
            name,
            display_name,
            content='places',
            content_rowid='id'
          )
        ''');
        
        await db.execute('''
          CREATE TRIGGER places_ai AFTER INSERT ON places BEGIN
            INSERT INTO places_fts(rowid, name, display_name) VALUES (new.id, new.name, new.display_name);
          END
        ''');
      },
    );
  }

  Future<List<Place>> search(String query, {int limit = 20}) async {
    if (_db == null || query.isEmpty) return [];

    try {
      final List<Map<String, dynamic>> results = await _db!.rawQuery('''
        SELECT p.*
        FROM places p
        JOIN places_fts f ON p.id = f.rowid
        WHERE places_fts MATCH ?
        ORDER BY rank
        LIMIT ?
      ''', ['$query*', limit]);

      if (results.isEmpty) {
        final List<Map<String, dynamic>> fallbackResults = await _db!.query(
          'places',
          where: 'name LIKE ? OR display_name LIKE ?',
          whereArgs: ['%$query%', '%$query%'],
          limit: limit,
        );
        return fallbackResults.map(_mapToPlace).toList();
      }

      return results.map(_mapToPlace).toList();
    } catch (e) {
      debugPrint('[OfflineSearch] Search error: $e');
      return [];
    }
  }

  Place _mapToPlace(Map<String, dynamic> m) {
    return Place(
      id: 'offline_${m['id']}',
      name: m['name'] ?? '',
      displayName: m['display_name'] ?? m['name'] ?? '',
      lat: m['lat'],
      lon: m['lon'],
      type: m['type'] ?? 'place',
      icon: m['icon'],
      address: m['address'],
      phone: m['phone'],
      website: m['website'],
    );
  }

  Future<void> indexMBTiles(String mbtilesPath) async {
    if (_db == null || _isIndexing) return;

    final countRes = await _db!.rawQuery('SELECT COUNT(*) as count FROM places');
    // If we have very few results, maybe we need to re-index or it's empty
    if ((countRes.first['count'] as int) > 5) return;

    _isIndexing = true;
    _indexProgress = 0;

    try {
      final mbtiles = await openDatabase(mbtilesPath, readOnly: true);
      final tiles = await mbtiles.rawQuery('''
        SELECT zoom_level, tile_column, tile_row, tile_data 
        FROM tiles 
        WHERE zoom_level IN (6, 10, 12, 14)
      ''');

      final Set<String> seen = {};
      var processed = 0;

      for (var tile in tiles) {
        final z = tile['zoom_level'] as int;
        final x = tile['tile_column'] as int;
        final y = _flipY(tile['tile_row'] as int, z);
        final data = tile['tile_data'] as Uint8List;

        final entries = await _extractFromTile(data, z, x, y);
        
        await _db!.transaction((txn) async {
          for (var entry in entries) {
            final key = '${entry['name']}_${entry['type']}_${(entry['lat'] as double).toStringAsFixed(4)}';
            if (seen.contains(key)) continue;
            seen.add(key);
            await txn.insert('places', entry);
          }
        });

        processed++;
        _indexProgress = processed / tiles.length;
      }
      await mbtiles.close();
    } catch (e) {
      debugPrint('[OfflineSearch] Indexing error: $e');
    } finally {
      _isIndexing = false;
    }
  }

  Future<List<Map<String, dynamic>>> _extractFromTile(Uint8List data, int z, int x, int y) async {
    try {
      final unzipped = GZipCodec().decode(data);
      final tile = vt.VectorTile.fromBytes(bytes: Uint8List.fromList(unzipped));
      final List<Map<String, dynamic>> results = [];

      for (var layer in tile.layers) {
        if (!['place', 'transportation_name', 'poi'].contains(layer.name)) continue;

        for (var feature in layer.features) {
          final props = feature.decodeProperties();
          final name = props['name:latin'] ?? props['name'];
          if (name == null || name.toString().isEmpty) continue;

          final coords = _getCoords(feature, z, x, y);
          if (coords == null) continue;

          results.add({
            'name': name.toString(),
            'display_name': props['name:latin'] ?? name.toString(),
            'lat': coords.latitude,
            'lon': coords.longitude,
            'type': layer.name == 'transportation_name' ? 'road' : (props['class'] ?? layer.name),
            'icon': _getIcon(layer.name, props),
            'address': props['addr:full'] ?? props['address'],
            'phone': props['phone'] ?? props['contact:phone'],
            'website': props['website'] ?? props['url'],
          });
        }
      }
      return results;
    } catch (e) {
      debugPrint('[OfflineSearch] Tile extraction error: $e');
      return [];
    }
  }

  String _getIcon(String layer, Map<String, dynamic> props) {
    if (layer == 'place') return '🏘️';
    if (layer == 'transportation_name') return '🛣️';
    final cls = (props['class'] ?? '').toString().toLowerCase();
    if (cls.contains('hospital')) return '🏥';
    if (cls.contains('airport')) return '✈️';
    return '📍';
  }

  _LatLng? _getCoords(vt.VectorTileFeature feature, int z, int x, int y) {
    final geometry = feature.decodeGeometry();
    if (geometry == null) return null;

    List<int>? coordinate;
    try {
      final geom = geometry as dynamic;
      if (feature.type == vt.VectorTileGeomType.POINT) {
        coordinate = (geom.points as List).first;
      } else if (feature.type == vt.VectorTileGeomType.LINESTRING) {
        coordinate = (geom.lines as List).first.first;
      } else if (feature.type == vt.VectorTileGeomType.POLYGON) {
        coordinate = (geom.rings as List).first.first;
      }
    } catch (_) {}

    if (coordinate == null) return null;

    const extent = 4096;
    final size = extent * math.pow(2, z);
    final px = x * extent + coordinate[0];
    final py = y * extent + coordinate[1];

    final lon = (px / size) * 360.0 - 180.0;
    final n = math.pi - (2.0 * math.pi * py) / size;
    final lat = (180.0 / math.pi) * math.atan(0.5 * (math.exp(n) - math.exp(-n)));

    return _LatLng(lat, lon);
  }

  int _flipY(int y, int z) {
    return (math.pow(2, z).toInt() - 1) - y;
  }
}

class _LatLng {
  final double latitude;
  final double longitude;
  _LatLng(this.latitude, this.longitude);
}
