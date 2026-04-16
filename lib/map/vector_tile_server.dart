import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'vector_tile_sanitizer.dart';

/// Information about a vector tile layer
class VectorLayerInfo {
  final String id;
  final String? description;
  final int? minzoom;
  final int? maxzoom;
  final Map<String, String> fields;

  VectorLayerInfo({
    required this.id,
    this.description,
    this.minzoom,
    this.maxzoom,
    this.fields = const {},
  });
}

/// Detected tile schema type
enum TileSchema { openMapTiles, shortbread, bbBike, unknown }

/// Local HTTP server that serves vector tiles from MBTiles files.
class VectorTileServer {
  static const String richSingleLayerStyleProfile = 'rich_single_layer';
  final String mbtilesPath;
  final int port;

  HttpServer? _server;
  Database? _db;
  String? _format;
  Map<String, dynamic>? _metadata;
  List<VectorLayerInfo> _vectorLayers = [];
  TileSchema _detectedSchema = TileSchema.unknown;
  final LinkedHashMap<String, Uint8List> _sanitizedTileCache = LinkedHashMap();

  VectorTileServer({required this.mbtilesPath, this.port = 8765});

  bool get isRunning => _server != null;
  String? _serverAddress;
  String? _cachedStyleJson;

  String get baseUrl => 'http://127.0.0.1:$port';
  String get tileJsonUrl => '$baseUrl/tiles.json';
  String get tileUrlTemplate => '$baseUrl/tiles/{z}/{x}/{y}.pbf';
  // String get styleUrl => '$baseUrl/style.json?v=${DateTime.now().millisecondsSinceEpoch}';
  String get styleUrl => '$baseUrl/style.json';

  void setStyleJson(String styleJson) {
    _cachedStyleJson = styleJson;
  }

  String? get styleJson => _cachedStyleJson;

  int get minZoom => int.tryParse(_metadata?['minzoom'] ?? '0') ?? 0;
  int get maxZoom => int.tryParse(_metadata?['maxzoom'] ?? '14') ?? 14;
  List<String> get layerNames => _vectorLayers.map((l) => l.id).toList();
  TileSchema get detectedSchema => _detectedSchema;
  bool get supportsRichSingleLayerStyle =>
      _metadata?['offlinemaps_style_profile'] == richSingleLayerStyleProfile;

  Future<void> start() async {
    _sanitizedTileCache.clear();
    if (_server != null) return;

    try {
      final file = File(mbtilesPath);
      if (!await file.exists()) {
        throw 'MBTiles file not found at: $mbtilesPath';
      }
      final size = await file.length();
      debugPrint('[TileServer] Opening MBTiles ($size bytes): $mbtilesPath');

      _db = sqlite3.open(mbtilesPath, mode: OpenMode.readOnly);
      _loadMetadata();
      debugPrint('[TileServer] Opened MBTiles: $mbtilesPath');
    } catch (e) {
      debugPrint('[TileServer] Failed to open MBTiles: $e');
      rethrow;
    }

    final router = Router();
    router.get('/style.json', _handleStyle);
    router.get('/tiles.json', _handleTileJson);
    router.get('/tiles/<z|[0-9]+>/<x|[0-9]+>/<y|[0-9]+>.pbf', _handleTile);
    router.get('/tiles/<z|[0-9]+>/<x|[0-9]+>/<y|[0-9]+>.png', _handleTile);
    router.get('/sprites/<name>@2x.json', _handleSpriteJson2x);
    router.get('/sprites/<name>@2x.png', _handleSpritePng2x);
    router.get('/sprites/<name>.json', _handleSpriteJson);
    router.get('/sprites/<name>.png', _handleSpritePng);

    // Smart font cacher - Proxies font requests and saves them for offline use
    router.get('/fonts/<fontstack>/<range>.pbf', (Request request) async {
      final fontstack = request.params['fontstack'] ?? 'Open Sans Regular';
      final range = request.params['range'] ?? '0-255';

      final cacheDir = Directory(
        path.join(path.dirname(mbtilesPath), 'font_cache', fontstack),
      );
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      final cacheFile = File(path.join(cacheDir.path, '$range.pbf'));

      // If we have it in cache, serve it instantly!
      if (cacheFile.existsSync()) {
        debugPrint(
          '[TileServer] ← Font served from local cache: $fontstack/$range',
        );
        return Response.ok(
          cacheFile.readAsBytesSync(),
          headers: {
            'content-type': 'application/x-protobuf',
            'access-control-allow-origin': '*',
          },
        );
      }

      // If not in cache, try to download and cache it (if online)
      try {
        final url = 'https://demotiles.maplibre.org/font/$fontstack/$range.pbf';
        debugPrint('[TileServer] → Attempting to fetch font for cache: $url');

        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();

        if (response.statusCode == 200) {
          final List<int> bytesList = [];
          await for (var chunk in response) {
            bytesList.addAll(chunk);
          }
          final bytes = Uint8List.fromList(bytesList);
          cacheFile.writeAsBytesSync(bytes);
          debugPrint('[TileServer] ✅ Font cached locally: $fontstack/$range');
          return Response.ok(
            bytes,
            headers: {
              'content-type': 'application/x-protobuf',
              'access-control-allow-origin': '*',
            },
          );
        }
      } catch (e) {
        // Quietly handle offline fetch failures to avoid log pollution
        if (e is! SocketException && e is! HttpException) {
          debugPrint('[TileServer] ⚠️ Font fetch failed for $fontstack/$range: $e');
        }
      }

      // Ultimate fallback: return a valid binary header if everything else fails
      final List<int> nameBytes = utf8.encode(Uri.decodeComponent(fontstack));
      final List<int> inner = [
        0x0a,
        nameBytes.length,
        ...nameBytes,
        0x12,
        0x00,
      ];
      final List<int> outer = [0x0a, inner.length, ...inner];

      return Response.ok(
        Uint8List.fromList(outer),
        headers: {
          'content-type': 'application/x-protobuf',
          'access-control-allow-origin': '*',
        },
      );
    });

    router.get('/health', _handleHealth);

    final pipeline = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(logRequests());
    final handler = pipeline.addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    _serverAddress = '127.0.0.1';
    debugPrint(
      '[TileServer] Started on http://$_serverAddress:$port (Global Access Enabled)',
    );
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _db?.dispose();
    _db = null;
    _cachedStyleJson = null;
    _sanitizedTileCache.clear();
    debugPrint('[TileServer] Stopped');
  }

  void _loadMetadata() {
    final results = _db!.select('SELECT name, value FROM metadata');
    final Map<String, String> meta = {};
    for (final row in results) {
      meta[row['name'] as String] = row['value'] as String;
    }
    _metadata = meta;
    _format = meta['format'] ?? 'pbf';

    if (meta.containsKey('json')) {
      try {
        final Map<String, dynamic> jsonData = json.decode(meta['json']!);
        if (jsonData.containsKey('vector_layers')) {
          final layers = jsonData['vector_layers'] as List;
          _vectorLayers = layers
              .map(
                (l) => VectorLayerInfo(
                  id: l['id'] as String,
                  fields: Map<String, String>.from(l['fields'] ?? {}),
                ),
              )
              .toList();
        }
      } catch (e) {
        debugPrint('[TileServer] Error parsing metadata JSON: $e');
      }
    }
    _detectSchema();
  }

  void _detectSchema() {
    final layerIds = _vectorLayers.map((l) => l.id).toSet();
    if (layerIds.contains('transportation') && layerIds.contains('water')) {
      _detectedSchema = TileSchema.openMapTiles;
    }

    for (final layer in _vectorLayers) {
      debugPrint(
        '[TileServer] Layer "${layer.id}" fields: ${layer.fields.keys.toList()}',
      );
    }
  }

  VectorLayerInfo? getLayerInfo(String id) {
    try {
      return _vectorLayers.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  Response _handleStyle(Request request) {
    debugPrint('[TileServer] ← Style request received');
    if (_cachedStyleJson == null) {
      debugPrint('[TileServer] ✗ Style not set!');
      return Response.notFound('Style not set');
    }
    debugPrint(
      '[TileServer] ✓ Serving style (${_cachedStyleJson!.length} bytes)',
    );
    // Print first 500 chars for debugging
    debugPrint(
      '[TileServer] Style preview: ${_cachedStyleJson!.substring(0, _cachedStyleJson!.length > 500 ? 500 : _cachedStyleJson!.length)}...',
    );
    return Response.ok(
      _cachedStyleJson!,
      headers: {
        'content-type': 'application/json',
        'access-control-allow-origin': '*',
        'cache-control':
            'no-store, no-cache, must-revalidate, proxy-revalidate',
        'pragma': 'no-cache',
        'expires': '0',
      },
    );
  }

  Response _handleSpriteJson(Request request) =>
      _serveSpriteJson(request, pixelRatio: 1);
  Response _handleSpritePng(Request request) =>
      _serveSpritePng(request, pixelRatio: 1);
  Response _handleSpriteJson2x(Request request) =>
      _serveSpriteJson(request, pixelRatio: 2);
  Response _handleSpritePng2x(Request request) =>
      _serveSpritePng(request, pixelRatio: 2);

  Response _serveSpriteJson(Request request, {required int pixelRatio}) {
    final name = request.params['name'] ?? 'sprite';
    if (name != 'sprite') return Response.notFound('Unknown sprite "$name"');
    final sprite = _GeneratedSprite.get(pixelRatio: pixelRatio);
    return Response.ok(
      sprite.json,
      headers: {
        'content-type': 'application/json',
        'access-control-allow-origin': '*',
        'cache-control': 'no-store',
      },
    );
  }

  Response _serveSpritePng(Request request, {required int pixelRatio}) {
    final name = request.params['name'] ?? 'sprite';
    if (name != 'sprite') return Response.notFound('Unknown sprite "$name"');
    final sprite = _GeneratedSprite.get(pixelRatio: pixelRatio);
    return Response.ok(
      sprite.png,
      headers: {
        'content-type': 'image/png',
        'access-control-allow-origin': '*',
        'cache-control': 'no-store',
      },
    );
  }

  Response _handleTileJson(Request request) {
    final tileJson = {
      'tilejson': '2.2.0',
      'tiles': [tileUrlTemplate],
      'minzoom': minZoom,
      'maxzoom': 14, // Data ends here; allow engine to stretch (overzoom)
      'format': _format,
      'vector_layers': _vectorLayers
          .map(
            (l) => {
              'id': l.id,
              'fields': l.fields,
              'minzoom': 0,
              'maxzoom': 14,
            },
          )
          .toList(),
    };
    return Response.ok(
      json.encode(tileJson),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _handleTile(Request request) async {
    if (_db == null) return Response.notFound('No MBTiles open');

    final z = int.parse(request.params['z']!);
    final x = int.parse(request.params['x']!);
    final y = int.parse(request.params['y']!);

    // Local First: Serve from MBTiles if available
    final tmsY = (1 << z) - 1 - y;

    try {
      // Optimized query: Try TMS first, if not found and z is low, try XYZ
      var result = _db!.select(
        'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
        [z, x, tmsY],
      );

      if (result.isEmpty) {
        // Fallback to XYZ
        result = _db!.select(
          'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
          [z, x, y],
        );
      }

      if (result.isEmpty) {
        // Smart Remote Fallback: Only if local tile is missing AND we are online
        final remote = await _tryFetchRemoteTile(z: z, x: x, y: y);
        if (remote != null) return remote;

        // Return a clean empty response to prevent MapLibre from hanging/stalling
        debugPrint('[TileServer] ← Tile $z/$x/$y Not Found (Serving Empty)');
        return Response.ok(
          Uint8List(0),
          headers: {
            'content-type': _format == 'png'
                ? 'image/png'
                : 'application/x-protobuf',
            'access-control-allow-origin': '*',
          },
        );
      }

      final rawTileData = result.first['tile_data'] as Uint8List;
      final tileData = _format == 'png'
          ? rawTileData
          : _sanitizeTileData('$z/$x/$y', rawTileData);
      final isGzipped =
          tileData.length >= 2 && tileData[0] == 0x1f && tileData[1] == 0x8b;
      debugPrint(
        '[TileServer] ← Tile $z/$x/$y OK (${tileData.length} bytes, gzip: $isGzipped)',
      );

      return Response.ok(
        tileData,
        headers: {
          'content-type': _format == 'png'
              ? 'image/png'
              : 'application/x-protobuf',
          if (isGzipped) 'content-encoding': 'gzip',
          'access-control-allow-origin': '*',
        },
      );
    } catch (e) {
      debugPrint('[TileServer] ← Tile $z/$x/$y ERROR: $e');
      return Response.internalServerError(body: '$e');
    }
  }

  Future<Response?> _tryFetchRemoteTile({
    required int z,
    required int x,
    required int y,
  }) async {
    if (!await _checkInternet()) return null;
    try {
      final remoteUrl = 'https://demotiles.maplibre.org/tiles/$z/$x/$y.pbf';
      final client = HttpClient();
      try {
        final remoteReq = await client
            .getUrl(Uri.parse(remoteUrl))
            .timeout(const Duration(seconds: 2));
        remoteReq.headers.set('accept', 'application/x-protobuf');
        final remoteRes = await remoteReq.close();

        if (remoteRes.statusCode != 200) return null;
        final bytesList = <int>[];
        await for (var chunk in remoteRes) {
          bytesList.addAll(chunk);
        }

        final tileBytes = Uint8List.fromList(bytesList);
        final isGzipped = tileBytes.length >= 2 &&
            tileBytes[0] == 0x1f &&
            tileBytes[1] == 0x8b;
        debugPrint('[TileServer] ← Remote Tile Served: $z/$x/$y (gzip: $isGzipped)');

        return Response.ok(
          tileBytes,
          headers: {
            'content-type': 'application/x-protobuf',
            if (isGzipped) 'content-encoding': 'gzip',
            'access-control-allow-origin': '*',
            'cache-control': 'no-store',
          },
        );
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('[TileServer] ⚠️ Remote fetch failed: $e');
      return null;
    }
  }

  Uint8List _sanitizeTileData(String cacheKey, Uint8List tileData) {
    final cached = _sanitizedTileCache.remove(cacheKey);
    if (cached != null) {
      _sanitizedTileCache[cacheKey] = cached;
      return cached;
    }

    final result = VectorTileSanitizer.sanitize(tileData);
    if (result.changed) {
      debugPrint(
        '[TileServer] Sanitized tile $cacheKey '
        '(dropped tag pairs: ${result.droppedTagPairs}, '
        'dropped invalid values: ${result.droppedInvalidValues})',
      );
    }

    _sanitizedTileCache[cacheKey] = result.bytes;
    if (_sanitizedTileCache.length > 256) {
      _sanitizedTileCache.remove(_sanitizedTileCache.keys.first);
    }
    return result.bytes;
  }

  Response _handleHealth(Request request) => Response.ok(
    'OK',
    headers: {'access-control-allow-origin': '*', 'connection': 'keep-alive'},
  );

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok(
            '',
            headers: {
              'access-control-allow-origin': '*',
              'access-control-allow-methods': 'GET, OPTIONS',
              'access-control-allow-headers': '*',
              'connection': 'keep-alive',
            },
          );
        }
        final response = await handler(request);
        return response.change(
          headers: {
            'access-control-allow-origin': '*',
            'connection': 'keep-alive',
            'cache-control': 'no-store',
          },
        );
      };
    };
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(milliseconds: 500));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

class _GeneratedSpriteAsset {
  final String json;
  final Uint8List png;
  _GeneratedSpriteAsset({required this.json, required this.png});
}

class _GeneratedSprite {
  static final Map<int, _GeneratedSpriteAsset> _cache = {};

  static _GeneratedSpriteAsset get({required int pixelRatio}) {
    final cached = _cache[pixelRatio];
    if (cached != null) return cached;

    final iconNames = const [
      'hospital',
      'fuel',
      'restaurant',
      'cafe',
      'bank',
      'poi',
    ];

    final iconColors = const {
      'hospital': 0xFFE53935,
      'fuel': 0xFF43A047,
      'restaurant': 0xFFFB8C00,
      'cafe': 0xFF6D4C41,
      'bank': 0xFF1E88E5,
      'poi': 0xFF9CA3AF,
    };

    final iconSize = 32 * pixelRatio;
    final width = iconSize * iconNames.length;
    final height = iconSize;

    final pixels = Uint8List(width * height * 4);
    void setPixel(int x, int y, int argb) {
      if (x < 0 || y < 0 || x >= width || y >= height) return;
      final i = (y * width + x) * 4;
      pixels[i + 0] = (argb >> 16) & 0xFF; // R
      pixels[i + 1] = (argb >> 8) & 0xFF; // G
      pixels[i + 2] = (argb) & 0xFF; // B
      pixels[i + 3] = (argb >> 24) & 0xFF; // A
    }

    void drawFilledCircle({
      required int cx,
      required int cy,
      required int radius,
      required int argb,
    }) {
      final r2 = radius * radius;
      for (var dy = -radius; dy <= radius; dy++) {
        final y = cy + dy;
        for (var dx = -radius; dx <= radius; dx++) {
          final x = cx + dx;
          if (dx * dx + dy * dy <= r2) setPixel(x, y, argb);
        }
      }
    }

    void drawCircleOutline({
      required int cx,
      required int cy,
      required int radius,
      required int thickness,
      required int argb,
    }) {
      final outer2 = radius * radius;
      final inner = math.max(0, radius - thickness);
      final inner2 = inner * inner;
      for (var dy = -radius; dy <= radius; dy++) {
        final y = cy + dy;
        for (var dx = -radius; dx <= radius; dx++) {
          final x = cx + dx;
          final d2 = dx * dx + dy * dy;
          if (d2 <= outer2 && d2 >= inner2) setPixel(x, y, argb);
        }
      }
    }

    for (var idx = 0; idx < iconNames.length; idx++) {
      final name = iconNames[idx];
      final x0 = idx * iconSize;
      final cx = x0 + iconSize ~/ 2;
      final cy = iconSize ~/ 2;
      final color = iconColors[name] ?? 0xFF9CA3AF;

      // Shadow-ish ring
      drawFilledCircle(
        cx: cx,
        cy: cy,
        radius: (12 * pixelRatio).toInt(),
        argb: 0xCC000000,
      );
      // Main fill
      drawFilledCircle(
        cx: cx,
        cy: cy,
        radius: (11 * pixelRatio).toInt(),
        argb: color,
      );
      // White outline
      drawCircleOutline(
        cx: cx,
        cy: cy,
        radius: (11 * pixelRatio).toInt(),
        thickness: math.max(1, pixelRatio),
        argb: 0xFFFFFFFF,
      );
    }

    final spriteMap = <String, dynamic>{};
    for (var idx = 0; idx < iconNames.length; idx++) {
      final name = iconNames[idx];
      spriteMap[name] = {
        'x': idx * iconSize,
        'y': 0,
        'width': iconSize,
        'height': iconSize,
        'pixelRatio': pixelRatio,
      };
    }

    final jsonText = json.encode(spriteMap);
    final pngBytes = _PngEncoder.encodeRgba(
      width: width,
      height: height,
      rgba: pixels,
    );

    final created = _GeneratedSpriteAsset(json: jsonText, png: pngBytes);
    _cache[pixelRatio] = created;
    return created;
  }
}

class _PngEncoder {
  static final List<int> _signature = const [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
  ];

  static Uint8List encodeRgba({
    required int width,
    required int height,
    required Uint8List rgba,
  }) {
    final raw = BytesBuilder(copy: false);
    final rowStride = width * 4;
    for (var y = 0; y < height; y++) {
      raw.addByte(0); // filter type 0
      raw.add(rgba.sublist(y * rowStride, (y + 1) * rowStride));
    }

    final compressed = ZLibEncoder().convert(raw.toBytes());

    final out = BytesBuilder(copy: false);
    out.add(_signature);
    out.add(_chunk(
      'IHDR',
      _ihdrData(width: width, height: height),
    ));
    out.add(_chunk('IDAT', Uint8List.fromList(compressed)));
    out.add(_chunk('IEND', Uint8List(0)));
    return out.toBytes();
  }

  static Uint8List _ihdrData({required int width, required int height}) {
    final b = BytesBuilder(copy: false);
    b.add(_u32be(width));
    b.add(_u32be(height));
    b.addByte(8); // bit depth
    b.addByte(6); // color type: RGBA
    b.addByte(0); // compression
    b.addByte(0); // filter
    b.addByte(0); // interlace
    return b.toBytes();
  }

  static Uint8List _chunk(String type, Uint8List data) {
    final t = ascii.encode(type);
    final body = BytesBuilder(copy: false);
    body.add(t);
    body.add(data);
    final crc = _Crc32.compute(body.toBytes());

    final out = BytesBuilder(copy: false);
    out.add(_u32be(data.length));
    out.add(t);
    out.add(data);
    out.add(_u32be(crc));
    return out.toBytes();
  }

  static Uint8List _u32be(int v) => Uint8List.fromList([
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ]);
}

class _Crc32 {
  static final List<int> _table = _makeTable();

  static int compute(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static List<int> _makeTable() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      table[i] = c;
    }
    return table;
  }
}
