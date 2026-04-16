import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/map_region.dart';
import '../storage/storage_manager.dart';
import '../map/vector_tile_server.dart';
import '../map/guru_maps_style.dart';
import 'offline_places_service.dart';
import 'offline_routing_service.dart';
import 'valhalla_setup_service.dart';

/// The central orchestrator for all fully offline capabilities.
///
/// This service manages the lifecycle of offline data (tiles, routing, search)
/// and provides a unified API for the UI to interact with offline features
/// without needing to know which native or local provider is being used.
class OfflineManager extends ChangeNotifier {
  final StorageManager _storage = StorageManager();
  final OfflinePlacesService _search = OfflinePlacesService();
  final OfflineRoutingService _routing = OfflineRoutingService();

  final Map<String, double> _downloadProgress = {};
  VectorTileServer? _tileServer;
  String? _mapStyleUrl;

  MapRegion? _activeRegion;
  bool _isInitialized = false;
  String? _statusMessage;
  double _initializationProgress = 0.0;

  MapRegion? get activeRegion => _activeRegion;
  bool get isInitialized => _isInitialized;
  String? get statusMessage => _statusMessage;
  double get initializationProgress => _initializationProgress;
  VectorTileServer? get tileServer => _tileServer;

  String? get mapStyleUrl => _mapStyleUrl ?? _tileServer?.styleUrl;

  /// Real-time download progress for each region (0.0 to 1.0)
  Map<String, double> get downloadProgress => _downloadProgress;

  /// Download a region from its configured download URL.
  Future<void> downloadRegion(MapRegion region) async {
    if (region.downloadUrl == null) {
      debugPrint('[OfflineManager] No download URL for ${region.name}');
      return;
    }

    _downloadProgress[region.id] = 0.0;
    notifyListeners();

    try {
      // For the demo, we use the ZIP method to get everything at once
      await _storage.downloadAndExtractRegionZip(
        region.id,
        region.downloadUrl!,
        onProgress: (p) {
          _downloadProgress[region.id] = p;
          notifyListeners();
        },
      );

      _downloadProgress.remove(region.id);

      // Refresh the local server once download is complete
      if (_activeRegion?.id == region.id) {
        await loadRegion(region);
      }

      notifyListeners();
    } catch (e) {
      _downloadProgress.remove(region.id);
      notifyListeners();
      debugPrint('[OfflineManager] Download failed: $e');
      rethrow;
    }
  }

  /// Initialize or switch the active offline region.
  ///
  /// This will:
  /// 1. Copy necessary assets (MBTiles, OSM PBF) if missing.
  /// 2. Initialize the Valhalla routing engine for the region.
  /// 3. Initialize the offline search index (places.json).
  Future<void> loadRegion(MapRegion region) async {
    _activeRegion = region;
    _isInitialized = false;
    _statusMessage = 'Initializing ${region.name}...';
    _initializationProgress = 0.05;
    // Use microtask to avoid "setState during build" if called from initState
    Future.microtask(() => notifyListeners());

    // Check if we already have the file in the local cache first
    final mbtilesPath = await _storage.getFilePath(region.id);
    final hasLocalMap = await File(mbtilesPath).exists();

    if (!hasLocalMap) {
      debugPrint(
        '[OfflineManager] No local map found for ${region.id}. Checking assets...',
      );
      await _storage.ensureMbtilesFromAssets(region.id);
    } else {
      debugPrint(
        '[OfflineManager] Using persistent local map for ${region.id}.',
      );
    }

    try {

      // 2. Map Tile Server
      _statusMessage = 'Starting map server...';
      _updateProgress(0.2);
      if (_tileServer != null) {
        await _tileServer!.stop();
      }
      _tileServer = VectorTileServer(mbtilesPath: mbtilesPath);
      await _tileServer!.start();

      if (!_tileServer!.isRunning) {
        throw Exception('Tile server failed to start');
      }

      // 3. Map Style Loading & Dynamic Processing
      _statusMessage = 'Loading map style...';
      _updateProgress(0.35);

      String styleJson;
      try {
        // Try to load the professional custom style from assets
        styleJson = await rootBundle.loadString('assets/style/style.json');
        debugPrint('[OfflineManager] style.json loaded (${styleJson.length} bytes)');

        // DYNAMIC LAYER REPLACEMENT:
        // Identify the actual layer name in the MBTiles (e.g. 'gujarat', 'india', 'pune')
        final detectedLayer = _tileServer!.layerNames.isNotEmpty ? _tileServer!.layerNames.first : 'gujarat';
        debugPrint('[OfflineManager] Detected MBTiles layer: $detectedLayer');
        
        // Replace "gujarat" with the actual layer name globally in the style
        // We use a more flexible replacement in case of different quotation marks or spacing
        styleJson = styleJson.replaceAll('"source-layer": "gujarat"', '"source-layer": "$detectedLayer"');
        styleJson = styleJson.replaceAll('"source-layer":"gujarat"', '"source-layer":"$detectedLayer"');

        // DYNAMIC URL REPLACEMENT:
        styleJson = styleJson.replaceAll(
          'http://127.0.0.1:8765/tiles/{z}/{x}/{y}.pbf',
          _tileServer!.tileUrlTemplate,
        );
        styleJson = styleJson.replaceAll(
          'http://127.0.0.1:8765/fonts/',
          '${_tileServer!.baseUrl}/fonts/',
        );
        styleJson = styleJson.replaceAll(
          'http://127.0.0.1:8765/sprites/',
          '${_tileServer!.baseUrl}/sprites/',
        );

      } catch (e) {
        debugPrint('[OfflineManager] Warning: style.json not found or invalid: $e. Falling back to dynamic generator.');
        styleJson = GuruMapsStyle.generateStyle(
          tileUrlTemplate: _tileServer!.tileUrlTemplate,
          schema: _tileServer!.detectedSchema,
          availableLayers: _tileServer!.layerNames,
          minZoom: _tileServer!.minZoom,
          maxZoom: _tileServer!.maxZoom,
        );
      }
      
      _tileServer!.setStyleJson(styleJson);
      // We prefer using the URL for iOS as it's more stable for the native SDK
      _mapStyleUrl = _tileServer!.styleUrl; 
      debugPrint('[OfflineManager] Target Style URL: $_mapStyleUrl');

      // 4. Initialize Valhalla Offline Routing
      _statusMessage = 'Configuring routing engine...';
      _updateProgress(0.5);
      
      final docs = await getApplicationDocumentsDirectory();
      final tarFile = File('${docs.path}/gujarat_tiles.tar');
      final jsonFile = File('${docs.path}/gujarat.json');
      bool tilesExist = true; 

      // Check if we have the bundled data we just added via ValhallaSetupService
      if (await tarFile.exists() && await jsonFile.exists()) {
          debugPrint('[OfflineManager] Found bundled Valhalla data. Initializing...');
          await ValhallaSetupService.setup();
          _statusMessage = 'Routing ready (Bundled)';
          tilesExist = true; 
      } else {
          // Fallback to legacy behavior for other regions/downloads
          final tilesDir = await _storage.getValhallaTilesPath();
          final tilesDirObj = Directory(tilesDir);
          final dirFiles = await tilesDirObj.list().toList();
          tilesExist = dirFiles.isNotEmpty;
          
          if (!tilesExist) {
              _statusMessage = 'Routing data missing. Download required. (Mocking...)';
              debugPrint('[OfflineManager] Valhalla tiles folder is empty or missing. FORCING init for Mock/Dev.');
              
              final configPath = await _createValhallaConfig(tilesDir);
              await _routing.init(configPath);
          } else {
              final configPath = await _createValhallaConfig(tilesDir);
              final routingReady = await _routing.init(configPath);
              if (!routingReady) {
                debugPrint('[OfflineManager] Warning: Valhalla routing failed to initialize.');
              } else {
                debugPrint('[OfflineManager] Valhalla routing initialized successfully.');
              }
          }
      }

      // 5. Initialize Offline Search
      _statusMessage = 'Loading search index...';
      _updateProgress(0.9);
      await _search.initialize();

      if (!tilesExist) {
          _isInitialized = false; // Force Download Prompt state
          _statusMessage = 'Offline Data Incomplete';
      } else {
          _isInitialized = true;
          _statusMessage = 'Offline services ready';
      }
      
      _initializationProgress = 1.0;
      notifyListeners();

      debugPrint(
        '[OfflineManager] Region ${region.name} initialization finished. Status: $_statusMessage',
      );
    } catch (e) {
      _statusMessage = 'Initialization failed: $e';
      _isInitialized = false;
      notifyListeners();
      debugPrint('[OfflineManager] Error: $e');
      rethrow;
    }
  }

  /// Dynamically creates a valhalla.json configuration file.
  Future<String> _createValhallaConfig(String tilesDir) async {
    final docs = await getApplicationDocumentsDirectory();
    final configFile = File('${docs.path}/valhalla.json');
    
    final config = {
      "mjolnir": {
        "tile_dir": tilesDir,
        "tile_extract": "$tilesDir/tiles.tar",
        "admin": "$tilesDir/admins.sqlite",
        "timezone": "$tilesDir/timezones.sqlite",
        "transit_dir": "$tilesDir/transit",
        "hierarchy": true
      },
      "service": {
        "routing": {
          "max_distance": 50000000,
          "max_locations": 20
        }
      }
    };

    await configFile.writeAsString(jsonEncode(config));
    debugPrint('[OfflineManager] Created Valhalla config at: ${configFile.path}');
    return configFile.path;
  }

  /// Search for places fully offline.
  Future<List<Map<String, dynamic>>> searchPlaces(
    String query, {
    String? category,
    double? userLat,
    double? userLon,
    int limit = 15,
  }) async {
    if (!_isInitialized) return [];

    final results = _search.search(query, limit: limit, category: category, userLat: userLat, userLon: userLon);

    return results
        .map(
          (place) => {
            'id': place.id,
            'display_name': place.displayName,
            'lat': place.lat.toString(),
            'lon': place.lon.toString(),
            'name': place.name,
            'type': place.type,
            'icon': place.typeIcon,
            'address': place.address,
          },
        )
        .toList();
  }

  /// Reverse geocode a coordinate offline to find the nearest place.
  Map<String, dynamic>? reverseGeocode(
    double lat,
    double lon, {
    double radiusKm = 5.0,
  }) {
    if (!_isInitialized) return null;

    final place = _search.reverseGeocode(lat, lon, radiusKm: radiusKm);
    if (place == null) return null;

    return {
      'id': place.id,
      'display_name': place.displayName,
      'lat': place.lat.toString(),
      'lon': place.lon.toString(),
      'name': place.name,
      'type': place.type,
      'icon': place.typeIcon,
      'address': place.address,
    };
  }

  void _updateProgress(double progress) {
    _initializationProgress = progress;
    notifyListeners();
  }

  @override
  void dispose() {
    _tileServer?.stop();
    _search.dispose();
    super.dispose();
  }
}
