import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../download/download_manager.dart';
import '../models/map_region.dart';
import '../map/vector_tile_server.dart';

import '../services/offline_manager.dart';
import '../models/place.dart';
import '../widgets/guru_search_bar.dart';
import '../widgets/place_info_panel.dart';
import '../services/offline_routing_service.dart';
import 'countries_screen.dart';

/// Vector map screen with Guru Maps-inspired dark theme and search functionality.
class VectorMapScreen extends StatefulWidget {
  final MapRegion region;

  const VectorMapScreen({super.key, required this.region});

  @override
  State<VectorMapScreen> createState() => _VectorMapScreenState();
}

Line? _currentRouteLine;
List<LatLng> _routePoints = [];
bool _isRouting = false;

class _VectorMapScreenState extends State<VectorMapScreen>
    with TickerProviderStateMixin {
  static const bool _useNativeMyLocationPuck = true;
  static const Duration _userMarkerUpdateInterval = Duration(milliseconds: 600);
  static const Duration _locationUiUpdateInterval = Duration(milliseconds: 700);

  static const Color _surfaceColor = Color(0xFF141922);
  static const Color _surfaceElevatedColor = Color(0xFF1B2330);
  static const Color _surfaceOverlayColor = Color(0xFF202938);
  static const Color _borderColor = Color(0xFF2B3647);
  static const Color _primaryColor = Color(0xFF4C8DFF);
  static const Color _mutedTextColor = Color(0xFF95A1B3);

  MapLibreMapController? _mapController;
  VectorTileServer? _tileServer;

  // Loading state
  bool _isLoading = true;
  String _statusMessage = 'Initializing...';
  String? _errorMessage;

  // Offline search controller
  late OfflineManager _offlineManager;

  // Map state
  LatLng? _currentCenter;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Place> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  Place? _selectedPlace;
  Symbol? _selectedMarker;
  Circle? _selectedCircle;
  String? _selectedCategory;

  // Location state
  bool _isLocating = false;
  LatLng? _userLocation;
  Circle? _userLocationMarker;
  StreamSubscription<geo.Position>? _locationSubscription;

  // Track Recording
  bool _isRecording = false;
  final List<LatLng> _currentTrackPoints = [];
  final Set<String> _addedSources = {};

  bool _isMapStyleLoaded = false;
  bool _areStyleIconsRegistered = false;

  // UI state
  DateTime? _lastUserMarkerUpdateAt;
  LatLng? _lastUserMarkerLocation;
  DateTime? _lastLocationUiUpdateAt;
  LatLng? _lastLocationUiPosition;
  String? _mapStyleUrl;
  bool _shouldCenterOnFirstLocationFix = true;

  // Navigation UI state
  bool _isNavigationActive = false;
  bool _isPreviewActive = false;
  // Navigation route points, instructions, and current step index
  List<LatLng> _navigationRoutePoints = [];
  List<dynamic> _navigationInstructions = [];
  int _navigationStepIndex = 0;
  String _currentStepInstruction = 'Sindhu Bhavan Road11';
  String _currentStepDistance = '200 m';
  IconData _currentStepIcon = Icons.turn_left;
  double _currentSpeed = 0.0;
  String _eta = '18:03';
  String _totalDistance = '3.47 km';
  String _totalTime = '7 min';

  @override
  void initState() {
    super.initState();
    _init();
    _startLocationUpdates();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  DownloadManager? _downloadManager;

  @override
  void dispose() {
    // 1. Explicitly clear focus and map listeners first to avoid UI locks
    _searchController.dispose();
    _searchFocus.dispose();
    _locationSubscription?.cancel();
    _downloadManager?.removeListener(_onDownloadChanged);

    // 2. Disable map's internal tracking before disposal if controller is there
    // This helps avoid native IllegalStateException in MapLibre
    if (_mapController != null) {
      _mapController?.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
    }

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Color(0xFF0b0f14)),
    );

    _mapController = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _downloadManager = context.read<DownloadManager>();
      _downloadManager?.removeListener(_onDownloadChanged);
      _downloadManager?.addListener(_onDownloadChanged);
    } catch (_) {}
  }

  void _onDownloadChanged() {
    if (!mounted) return;
    try {
      final dm = context.read<DownloadManager>();
      final state = dm.getState(widget.region.id);
      if (state.isDownloaded && _errorMessage != null) {
        _init();
      }
    } catch (_) {}
  }

  Future<void> _init() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking for map data...';
      _errorMessage = null;
    });
    _mapStyleUrl = null;

    try {
      _offlineManager = context.read<OfflineManager>();
      await _offlineManager.loadRegion(widget.region);

      _tileServer = _offlineManager.tileServer;

      // _mapStyleUrl = _tileServer?.styleJson;

      _mapStyleUrl = _offlineManager.mapStyleUrl;

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Offline Map Ready';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load map: $e';
        });
      }
    }
  }

  Future<void> _startLocationUpdates() async {
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) return;
    }

    if (permission == geo.LocationPermission.deniedForever) return;

    try {
      final initialPosition = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      await _handleLocationUpdate(
        LatLng(initialPosition.latitude, initialPosition.longitude),
        centerMapIfNeeded: true,
      );
    } catch (_) {}

    _locationSubscription =
        geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((geo.Position position) {
          if (mounted) {
            unawaited(
              _handleLocationUpdate(
                LatLng(position.latitude, position.longitude),
                centerMapIfNeeded: true,
              ),
            );
          }
        });
  }

  Future<void> _handleLocationUpdate(
    LatLng nextLocation, {
    bool centerMapIfNeeded = false,
  }) async {
    if (!mounted) return;

    final shouldCenter = centerMapIfNeeded && _shouldCenterOnFirstLocationFix;

    if (_userLocation != null) {
      final distance = geo.Geolocator.distanceBetween(
        _userLocation!.latitude,
        _userLocation!.longitude,
        nextLocation.latitude,
        nextLocation.longitude,
      );
      _currentSpeed = (distance * 3600 / 1000).clamp(0, 120);
    }

    _userLocation = nextLocation;

    if (_isRecording) {
      _currentTrackPoints.add(nextLocation);
      unawaited(_updateRecordingLine());
    }

    if (shouldCenter) {
      _currentCenter = nextLocation;
      _shouldCenterOnFirstLocationFix = false;
    }

    final shouldRefreshUi =
        shouldCenter || _shouldRefreshLocationDrivenUi(nextLocation);

    if (shouldRefreshUi) {
      setState(() {});
    }

    // ---- Navigation progress handling ----
    if (_isNavigationActive && _navigationRoutePoints.isNotEmpty) {
      // Find remaining points from current index
      final remaining = _navigationRoutePoints.sublist(_navigationStepIndex);
      if (remaining.isNotEmpty) {
        final nextPoint = remaining.first;
        final distanceToNext = geo.Geolocator.distanceBetween(
          _userLocation!.latitude,
          _userLocation!.longitude,
          nextPoint.latitude,
          nextPoint.longitude,
        );
        // Update HUD distance
        setState(() {
          _currentStepDistance = _formatStepDistance(distanceToNext);
        });
        // Advance step when close enough (e.g., < 15m)
        if (distanceToNext < 15 &&
            _navigationStepIndex < _navigationRoutePoints.length - 1) {
          _navigationStepIndex++;
          // Update instruction/icon if we have next maneuver
          if (_navigationInstructions.isNotEmpty &&
              _navigationStepIndex < _navigationInstructions.length) {
            final instr = _navigationInstructions[_navigationStepIndex];
            setState(() {
              _currentStepInstruction =
                  instr['text'] ?? _currentStepInstruction;
              _currentStepIcon = _getManeuverIcon(
                (instr['sign'] as num?)?.toInt() ?? 0,
              );
            });
          }
        }
      }
    }

    if (shouldCenter && _mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(nextLocation, 16),
      );
    }

    await _updateUserLocationMarker(force: shouldCenter);
  }

  bool _shouldRefreshLocationDrivenUi(LatLng nextLocation) {
    if (!(_selectedPlace != null || _showSearchResults)) {
      return false;
    }

    final now = DateTime.now();
    final movedEnough =
        _lastLocationUiPosition == null ||
        geo.Geolocator.distanceBetween(
              _lastLocationUiPosition!.latitude,
              _lastLocationUiPosition!.longitude,
              nextLocation.latitude,
              nextLocation.longitude,
            ) >=
            10;
    final isDue =
        _lastLocationUiUpdateAt == null ||
        now.difference(_lastLocationUiUpdateAt!) >= _locationUiUpdateInterval;

    if (!movedEnough && !isDue) {
      return false;
    }

    _lastLocationUiUpdateAt = now;
    _lastLocationUiPosition = nextLocation;
    return true;
  }

  Future<void> _updateRecordingLine() async {
    if (!_isMapStyleLoaded ||
        _mapController == null ||
        _currentTrackPoints.length < 2) {
      return;
    }

    final geojson = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, dynamic>{},
          'geometry': {
            'type': 'LineString',
            'coordinates': _currentTrackPoints
                .map((p) => [p.longitude, p.latitude])
                .toList(),
          },
        },
      ],
    };

    try {
      if (!_addedSources.contains('recording-source')) {
        await _mapController!.addSource(
          'recording-source',
          GeojsonSourceProperties(data: geojson),
        );
        await _mapController!.addLineLayer(
          'recording-source',
          'recording-layer',
          LineLayerProperties(
            lineColor: '#FF3B30',
            lineWidth: 4.0,
            lineCap: 'round',
            lineJoin: 'round',
          ),
        );
        _addedSources.add('recording-source');
      } else {
        await _mapController!.setGeoJsonSource('recording-source', geojson);
      }
    } catch (_) {}
  }

  Future<void> _updateUserLocationMarker({bool force = false}) async {
    if (!_isMapStyleLoaded || _userLocation == null || _mapController == null)
      return;

    // If MapLibre's built-in location layer ("puck") is enabled, don't also draw
    // our own blue circle — that results in two blue dots on the map.
    if (_useNativeMyLocationPuck) {
      if (_userLocationMarker != null) {
        try {
          await _mapController!.removeCircle(_userLocationMarker!);
        } catch (_) {}
        _userLocationMarker = null;
      }
      return;
    }

    final now = DateTime.now();
    final movedEnough =
        _lastUserMarkerLocation == null ||
        geo.Geolocator.distanceBetween(
              _lastUserMarkerLocation!.latitude,
              _lastUserMarkerLocation!.longitude,
              _userLocation!.latitude,
              _userLocation!.longitude,
            ) >=
            4;
    final isDue =
        _lastUserMarkerUpdateAt == null ||
        now.difference(_lastUserMarkerUpdateAt!) >= _userMarkerUpdateInterval;

    if (!force && (!movedEnough || !isDue)) {
      return;
    }

    try {
      if (_userLocationMarker != null) {
        await _mapController!.removeCircle(_userLocationMarker!);
        _userLocationMarker = null;
      }
      _userLocationMarker = await _mapController!.addCircle(
        CircleOptions(
          geometry: _userLocation!,
          circleColor: '#4a90d9',
          circleRadius: 10,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
      );
      _lastUserMarkerUpdateAt = now;
      _lastUserMarkerLocation = _userLocation;
    } catch (e) {
      debugPrint('[VectorMapScreen] Marker update error: $e');
    }
  }

  Future<void> _renderSelectedPlaceCircle() async {
    if (!_isMapStyleLoaded ||
        _selectedPlace == null ||
        _mapController == null) {
      return;
    }

    final target = LatLng(_selectedPlace!.lat, _selectedPlace!.lon);

    try {
      if (_selectedCircle != null) {
        await _mapController!.removeCircle(_selectedCircle!);
        _selectedCircle = null;
      }

      _selectedCircle = await _mapController!.addCircle(
        CircleOptions(
          geometry: target,
          circleColor: '#FF7B00',
          circleRadius: 10,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
      );
    } catch (e) {
      debugPrint('[VectorMapScreen] Selected place marker error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            if (_errorMessage != null)
              _buildErrorState()
            else if (_isLoading || _tileServer == null)
              _buildLoadingState()
            else
              _buildMap(),

            if (!_isNavigationActive &&
                !_isPreviewActive &&
                !_isLoading &&
                _errorMessage == null) ...[
              if (_showSearchResults)
                _buildFullScreenSearch()
              else ...[
                _buildGuruSidebar(),
                _buildAttribution(),
                if (_selectedPlace != null) _buildPlaceInfoPanel(),
              ],
            ],

            // 🔥 NEW: Route Preview Overlay
            if (_isPreviewActive && !_isNavigationActive) ...[
              _buildRoutePreviewPanel(),
              _buildBackButton(),
            ],

            // 🔥 NEW: Navigation HUD overlays
            if (_isNavigationActive) ...[
              _buildNavigationHeader(),
              _buildRecenterButton(),
              _buildSpeedometer(),
              _buildNavigationBottomBar(),
            ],

            if (_isLoading) _buildBackButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return MapLibreMap(
      initialCameraPosition: CameraPosition(
        target:
            _currentCenter ??
            LatLng(widget.region.centerLat, widget.region.centerLng),
        zoom: _userLocation != null ? 16.0 : widget.region.defaultZoom,
      ),
      minMaxZoomPreference: const MinMaxZoomPreference(0, 22),
      styleString: _mapStyleUrl ?? _tileServer?.styleUrl ?? '',
      onMapCreated: (c) {
        _mapController = c;
        _isMapStyleLoaded = false;
      },
      onStyleLoadedCallback: () async {
        _isMapStyleLoaded = true;
        await _registerStyleIconsIfNeeded();
        await _updateUserLocationMarker(force: true);
        await _renderSelectedPlaceCircle();
      },
      onCameraIdle: _onCameraIdle,
      onMapClick: _onMapClick,
      compassEnabled: true,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      trackCameraPosition: true,
      myLocationEnabled: true,
      logoViewMargins: const Point(-100, -100),
      attributionButtonMargins: const Point(-100, -100),
      myLocationRenderMode: _isNavigationActive
          ? MyLocationRenderMode.gps
          : MyLocationRenderMode.normal,
      myLocationTrackingMode: _isNavigationActive
          ? MyLocationTrackingMode.tracking
          : MyLocationTrackingMode.none,
    );
  }

  Future<void> _registerStyleIconsIfNeeded() async {
    if (_mapController == null || _areStyleIconsRegistered) return;

    try {
      final icons = <String, _PoiIconDef>{
        'hospital': _PoiIconDef(
          Icons.local_hospital_rounded,
          const Color(0xFFE53935),
        ),
        'fuel': _PoiIconDef(
          Icons.local_gas_station_rounded,
          const Color(0xFF43A047),
        ),
        'restaurant': _PoiIconDef(
          Icons.restaurant_rounded,
          const Color(0xFFFB8C00),
        ),
        'cafe': _PoiIconDef(Icons.coffee_rounded, const Color(0xFF6D4C41)),
        'bank': _PoiIconDef(
          Icons.account_balance_rounded,
          const Color(0xFF1E88E5),
        ),
        'poi': _PoiIconDef(Icons.place_rounded, const Color(0xFF9CA3AF)),
      };

      for (final entry in icons.entries) {
        final bytes = await _buildPoiIconPng(entry.value);
        await _mapController!.addImage(entry.key, bytes);
      }

      _areStyleIconsRegistered = true;
      debugPrint('[VectorMapScreen] Style icons registered (${icons.length})');
    } catch (e) {
      debugPrint('[VectorMapScreen] Style icon registration failed: $e');
    }
  }

  Future<Uint8List> _buildPoiIconPng(_PoiIconDef def, {int size = 64}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2.0, size / 2.0);
    final radius = size * 0.42;

    // Drop shadow
    canvas.drawCircle(
      Offset(center.dx, center.dy + 1.5),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // White background circle
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);

    // Colored inner circle
    canvas.drawCircle(center, radius - 3, Paint()..color = def.color);

    // Draw the Material icon glyph in the center
    final iconSize = size * 0.44;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(def.icon.codePoint),
      style: TextStyle(
        fontSize: iconSize,
        fontFamily: def.icon.fontFamily,
        package: def.icon.fontPackage,
        color: Colors.white,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _onCameraIdle() {
    if (_mapController?.cameraPosition != null) {
      _currentCenter = _mapController!.cameraPosition!.target;
    }
  }

  String _formatDistanceKm(double distanceKm) {
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  double? _selectedPlaceDistanceKm() {
    if (_userLocation != null && _selectedPlace != null) {
      return geo.Geolocator.distanceBetween(
            _userLocation!.latitude,
            _userLocation!.longitude,
            _selectedPlace!.lat,
            _selectedPlace!.lon,
          ) /
          1000;
    }

    return null;
  }

  Future<void> _clearSelectedPlaceState({bool clearSearchText = false}) async {
    setState(() {
      _selectedPlace = null;
      _showSearchResults = false;
      _searchResults = [];
      if (clearSearchText) {
        _searchController.clear();
      }
      if (_currentRouteLine != null) {
        _mapController?.removeLine(_currentRouteLine!);
        _currentRouteLine = null;
      }
    });

    if (_selectedMarker != null) {
      await _mapController?.removeSymbol(_selectedMarker!);
      _selectedMarker = null;
    }

    if (_selectedCircle != null) {
      await _mapController?.removeCircle(_selectedCircle!);
      _selectedCircle = null;
    }
  }

  Future<void> _exitNavigation() async {
    await _resetNavigation();
    setState(() {
      _isPreviewActive = false;
      _isNavigationActive = false;
    });
  }

  Future<void> _resetNavigation() async {
    await _clearSelectedPlaceState(clearSearchText: true);
    setState(() {
      _isNavigationActive = false;
      _shouldCenterOnFirstLocationFix = true;
    });
    _goToCurrentLocation();
  }

  Widget _buildFullScreenSearch() {
    return Positioned.fill(
      child: Container(
        color: _surfaceColor.withValues(alpha: 0.98),
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: Column(
          children: [
            GuruSearchBar(
              controller: _searchController,
              focusNode: _searchFocus,
              onBack: () => setState(() {
                _showSearchResults = false;
                _isSearching = false;
              }),
              isSearching: _isSearching,
              onChanged: _onSearchChanged,
            ),
            _buildCategoryFilters(),
            Expanded(
              child: _searchResults.isEmpty && _searchController.text.isNotEmpty
                  ? const Center(
                      child: Text(
                        'No results found',
                        style: TextStyle(color: _mutedTextColor),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _searchResults.length,
                      separatorBuilder: (c, i) =>
                          const Divider(height: 1, color: _borderColor),
                      itemBuilder: (context, index) {
                        final place = _searchResults[index];
                        double? distanceKm;
                        if (_userLocation != null) {
                          distanceKm =
                              geo.Geolocator.distanceBetween(
                                _userLocation!.latitude,
                                _userLocation!.longitude,
                                place.lat,
                                place.lon,
                              ) /
                              1000;
                        }

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _surfaceOverlayColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                place.typeIcon,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                          title: Text(
                            place.name,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            '${distanceKm != null ? '${_formatDistanceKm(distanceKm)} • ' : ''}${place.displayName}',
                            style: GoogleFonts.inter(
                              color: _mutedTextColor,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            _selectPlace(place);
                            setState(() {
                              _showSearchResults = false;
                              _isSearching = false;
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildCategoryChip('🏥 Hospital', 'hospital'),
          const SizedBox(width: 8),
          _buildCategoryChip('⛽ Petrol Pump', 'petrol_pump'),
          const SizedBox(width: 8),
          _buildCategoryChip('🍽️ Restaurant', 'restaurant'),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, String category) {
    final isSelected = _selectedCategory == category;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = isSelected ? null : category;
          if (_selectedCategory != null) {
            _showSearchResults = true;
          }
        });
        _onSearchChanged(_searchController.text);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? _primaryColor
              : _surfaceColor.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : _borderColor,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _primaryColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceInfoPanel() {
    final distanceKm = _selectedPlaceDistanceKm();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: PlaceInfoPanel(
        title: _selectedPlace!.name,
        subtitle: distanceKm != null
            ? _formatDistanceKm(distanceKm)
            : 'Near you',
        address: _selectedPlace!.address ?? _selectedPlace!.displayName,
        phone: _selectedPlace!.phone,
        website: _selectedPlace!.website,
        latLng:
            '${_selectedPlace!.lat.toStringAsFixed(6)}, ${_selectedPlace!.lon.toStringAsFixed(6)}',
        onClose: _clearSelectedPlaceState,
        onNavigate: () {
          if (_selectedPlace != null) {
            _calculateAndDrawRoute(
              LatLng(_selectedPlace!.lat, _selectedPlace!.lon),
            );
            setState(() {
              _isNavigationActive = true;
            });
          }
        },
      ),
    );
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty && _selectedCategory == null) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _showSearchResults = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });

    // Fully offline search using Unified Manager
    _offlineManager
        .searchPlaces(
          query,
          category: _selectedCategory,
          userLat: _userLocation?.latitude,
          userLon: _userLocation?.longitude,
          limit: (query.isEmpty && _selectedCategory != null) ? 5 : 15,
        )
        .then((results) {
          if (mounted) {
            setState(() {
              _searchResults = results
                  .map(
                    (r) => Place(
                      id: r['id'] ?? 'unknown',
                      name: r['name'] ?? '',
                      displayName: r['display_name'] ?? '',
                      type: r['type'] ?? '',
                      lat: double.parse(r['lat']),
                      lon: double.parse(r['lon']),
                      address: r['address'],
                    ),
                  )
                  .toList();
              _isSearching = false;
            });
          }
        });
  }

  Future<void> _calculateAndDrawRoute(LatLng destination) async {
    if (_userLocation == null) {
      _showMessage("Aapki location nahi mil rahi hai.");
      return;
    }

    setState(() => _isRouting = true);

    try {
      final routingService = OfflineRoutingService();
      final routeData = await routingService.getRoute(
        startLat: _userLocation!.latitude,
        startLng: _userLocation!.longitude,
        endLat: destination.latitude,
        endLng: destination.longitude,
      );

      // Store route points for live navigation updates
      if (routeData != null && routeData['points'] != null) {
        _navigationRoutePoints = List<LatLng>.from(routeData['points']);
        _navigationStepIndex = 0;
        // Store navigation instructions if present
        final List? instr = routeData['instructions'] as List?;
        if (instr != null && instr.isNotEmpty) {
          _navigationInstructions = instr;
        }
      }

      if (routeData != null && routeData['points'] != null) {
        final List<LatLng> parsedPoints = List<LatLng>.from(
          routeData['points'],
        );
        debugPrint(
          "[OfflineRouting] Route found with ${parsedPoints.length} points",
        );

        if (parsedPoints.isNotEmpty) {
          await _drawRouteOnMap(parsedPoints);

          // Update HUD Data
          final double totalDistanceMeters =
              (routeData['distance'] as num?)?.toDouble() ?? 0.0;
          final int totalTimeMs = (routeData['time'] as num?)?.round() ?? 0;

          final double distKm = totalDistanceMeters / 1000.0;
          final int timeMins = (totalTimeMs / 60000.0).round();

          final etaTime = DateTime.now().add(Duration(minutes: timeMins));
          final etaString =
              "${etaTime.hour.toString().padLeft(2, '0')}:${etaTime.minute.toString().padLeft(2, '0')}";

          final List? instructions = routeData['instructions'] as List?;
          if (instructions != null && instructions.isNotEmpty) {
            final firstTurn = instructions.length > 1
                ? instructions[1]
                : instructions.first;

            setState(() {
              _isPreviewActive = true;
              _isNavigationActive = false;
              _totalDistance = "${distKm.toStringAsFixed(1)} km";
              _totalTime = "$timeMins min";
              _eta = etaString;
              _currentStepInstruction = firstTurn?['text'] ?? 'Maneuver';
              _currentStepDistance = _formatStepDistance(
                (firstTurn?['distance'] as num?)?.toDouble() ?? 0.0,
              );
              _currentStepIcon = _getManeuverIcon(
                (firstTurn?['sign'] as num?)?.toInt() ?? 0,
              );
            });
          } else {
            setState(() {
              _isPreviewActive = true;
              _isNavigationActive = false;
              _totalDistance = "${distKm.toStringAsFixed(1)} km";
              _totalTime = "$timeMins min";
              _eta = etaString;
            });
          }
        } else {
          _showMessage("Offline route not found.");
        }
      } else {
        _showMessage("Offline route not found.");
      }
    } catch (e) {
      debugPrint("Routing error: $e");
      _showMessage("Offline route not found.");
    } finally {
      setState(() => _isRouting = false);
    }
  }

  Future<void> _drawRouteOnMap(List<LatLng> points) async {
    if (_mapController == null) return;

    // Purani line delete karein agar koi hai
    if (_currentRouteLine != null) {
      await _mapController!.removeLine(_currentRouteLine!);
    }

    // Nayi line draw karein
    _currentRouteLine = await _mapController!.addLine(
      LineOptions(
        geometry: points,
        lineColor: "#4C8DFF",
        lineWidth: 5.0,
        lineOpacity: 0.8,
        lineJoin: "round",
      ),
    );

    // Map ko route par fit karein
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        _getBounds(points),
        left: 50,
        right: 50,
        top: 150,
        bottom: 250,
      ),
    );
  }

  // Bounding box calculate karne ke liye helper
  LatLngBounds _getBounds(List<LatLng> points) {
    double minLat = points.map((p) => p.latitude).reduce(min);
    double maxLat = points.map((p) => p.latitude).reduce(max);
    double minLon = points.map((p) => p.longitude).reduce(min);
    double maxLon = points.map((p) => p.longitude).reduce(max);
    return LatLngBounds(
      southwest: LatLng(minLat, minLon),
      northeast: LatLng(maxLat, maxLon),
    );
  }

  Future<void> _selectPlace(dynamic place) async {
    setState(() {
      _showSearchResults = false;
      _selectedPlace = place;
      _searchController.text = place.name;
      _searchFocus.unfocus();
    });

    final target = LatLng(place.lat, place.lon);
    await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));

    // Show a marker at the selected coordinate (tap/search result).
    await _renderSelectedPlaceCircle();

    if (_selectedMarker != null) {
      await _mapController?.removeSymbol(_selectedMarker!);
      _selectedMarker = null;
    }
  }

  Future<void> _onMapClick(Point<double> point, LatLng latLng) async {
    // 🔥 NAVIGATION MODE: Map clicking disabled for location selection
    if (_isNavigationActive) return;

    if (!_isMapStyleLoaded) return;

    setState(() => _isSearching = true);

    // Try offline reverse geocode via manager
    final result = _offlineManager.reverseGeocode(
      latLng.latitude,
      latLng.longitude,
      // Keep this small so we don't "snap" the tap to a far-away place.
      radiusKm: 0.5,
    );
    setState(() => _isSearching = false);

    if (result != null) {
      // IMPORTANT: Keep the tapped coordinate as the selected location.
      // We only use reverse-geocode result for naming/address.
      final place = Place(
        id: result['id'] ?? 'unknown',
        name: (result['name'] ?? 'Dropped Pin').toString(),
        displayName: (result['display_name'] ?? '').toString(),
        type: (result['type'] ?? 'coordinate').toString(),
        lat: latLng.latitude,
        lon: latLng.longitude,
        address: result['address'],
      );
      _selectPlace(place);
    } else {
      // No nearby place found, create a dropped pin
      _selectPlace(
        Place(
          id: 'custom',
          name: 'Dropped Pin',
          displayName:
              '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}',
          type: 'coordinate',
          lat: latLng.latitude,
          lon: latLng.longitude,
        ),
      );
    }
  }

  Future<void> _goToCurrentLocation() async {
    if (_userLocation != null) {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_userLocation!, 16),
      );
      unawaited(_updateUserLocationMarker(force: true));
      return;
    }

    setState(() => _isLocating = true);
    try {
      geo.Position pos = await geo.Geolocator.getCurrentPosition();
      LatLng target = LatLng(pos.latitude, pos.longitude);
      setState(() => _userLocation = target);
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(target, 16),
      );
      unawaited(_updateUserLocationMarker(force: true));
    } catch (e) {
      _showMessage('Could not get location');
    }
    setState(() => _isLocating = false);
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: _surfaceElevatedColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      child: _buildGlassIconButton(
        icon: Icons.arrow_back_ios_new,
        onTap: _handleBackNavigation,
      ),
    );
  }

  void _handleBackNavigation() {
    // 1. If searching, close search
    if (_showSearchResults) {
      setState(() {
        _showSearchResults = false;
        _isSearching = false;
      });
      return;
    }

    // 2. If navigating or previewing route, exit navigation
    if (_isNavigationActive || _isPreviewActive) {
      _exitNavigation();
      return;
    }

    // 3. If a place is selected, clear it
    if (_selectedPlace != null) {
      _clearSelectedPlaceState();
      return;
    }

    // 4. Otherwise, actually pop the screen if there's somewhere to go back to
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  // Widget _buildStatusBox() {
  //   return Positioned(
  //     top: MediaQuery.of(context).padding.top + 80, // Moved below search bar
  //     left: 16,
  //     child: Container(
  //       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  //       decoration: BoxDecoration(
  //         color: const Color(0xFF1a1f26).withValues(alpha: 0.8),
  //         borderRadius: BorderRadius.circular(8),
  //         border: Border.all(color: Colors.white10),
  //         boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
  //       ),
  //       child: Row(
  //         mainAxisSize: MainAxisSize.min,
  //         children: [
  //           _buildStatusItem(_currentSpeed.toStringAsFixed(1), 'km/h'),
  //           const SizedBox(width: 12),
  //           Container(width: 1, height: 20, color: Colors.white10),
  //           const SizedBox(width: 12),
  //           _buildStatusItem(
  //             _currentAltitude.toStringAsFixed(0),
  //             'm',
  //             icon: Icons.north,
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _buildGuruSidebar() {
    return Positioned(
      right: 16,
      top: MediaQuery.of(context).size.height * 0.22,
      child: Container(
        decoration: BoxDecoration(
          color: _surfaceColor.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSidebarItem(Icons.search_rounded, _showSearchScreen),
            _buildSidebarDivider(),
            _buildSidebarItem(
              Icons.gps_fixed_rounded,
              _goToCurrentLocation,
              isLoading: _isLocating,
            ),
            _buildSidebarDivider(),
            _buildSidebarItem(
              Icons.add_rounded,
              () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
            ),
            _buildSidebarDivider(),
            _buildSidebarItem(
              Icons.remove_rounded,
              () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
            ),
            _buildSidebarDivider(),
            _buildSidebarItem(
              Icons.map_outlined,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CountriesScreen()),
              ),
            ),
            _buildSidebarDivider(),
            _buildSidebarItem(Icons.folder_open_outlined, _showLibraryMenu),
          ],
        ),
      ),
    );
  }

  void _showSearchScreen() {
    setState(() {
      _showSearchResults = true;
      _isSearching = true;
    });
    _searchFocus.requestFocus();
  }

  void _showLibraryMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom + 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _surfaceOverlayColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.folder_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'My Library',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: _borderColor, height: 1),
            _buildLibraryItem(
              ctx,
              icon: Icons.history_rounded,
              title: 'Recent Tracks',
              subtitle: '0 tracks recorded',
              onTap: () => Navigator.pop(ctx),
            ),
            _buildLibraryItem(
              ctx,
              icon: Icons.bookmark_outline_rounded,
              title: 'Bookmarked Places',
              subtitle: '0 bookmarks',
              onTap: () => Navigator.pop(ctx),
            ),
            _buildLibraryItem(
              ctx,
              icon: Icons.download_done_rounded,
              title: 'Offline Maps',
              subtitle: 'Manage downloaded regions',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/downloads');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryItem(
    BuildContext ctx, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, color: Colors.white60, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: _mutedTextColor, fontSize: 12),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Colors.white.withValues(alpha: 0.15),
        size: 20,
      ),
      onTap: onTap,
    );
  }

  Widget _buildSidebarItem(
    IconData icon,
    VoidCallback onTap, {
    bool isLoading = false,
    Color? color,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            : Icon(
                icon,
                color: color ?? Colors.white.withValues(alpha: 0.85),
                size: 22,
              ),
      ),
    );
  }

  Widget _buildSidebarDivider() => Container(
    width: 28,
    height: 0.5,
    color: _borderColor.withValues(alpha: 0.5),
  );

  Widget _buildGlassIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _surfaceColor.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildLoadingState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _surfaceElevatedColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _borderColor, width: 0.5),
          ),
          child: const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: _primaryColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _statusMessage,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Preparing your offline map',
          style: GoogleFonts.inter(color: _mutedTextColor, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _buildErrorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              color: Colors.redAccent,
              size: 32,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Map Unavailable',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: _mutedTextColor,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 160,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _init,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Retry',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: BorderSide(color: _borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildRoutePreviewPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).padding.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _borderColor, width: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: _borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _totalTime,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF00C48C),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _totalDistance,
                      style: GoogleFonts.inter(
                        color: _mutedTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _surfaceOverlayColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'ETA',
                        style: GoogleFonts.inter(
                          color: _mutedTextColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _eta,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _exitNavigation,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isNavigationActive = true;
                        _isPreviewActive = false;
                      });
                      _goToCurrentLocation();
                    },
                    icon: const Icon(Icons.navigation_rounded, size: 20),
                    label: const Text(
                      'Start',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttribution() => Positioned(
    bottom: 6,
    left: 0,
    right: 0,
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _surfaceColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '© OpenStreetMap',
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ),
  );

  // ─── Navigation HUD Widgets ──────────────────────────────────────────────────

  Widget _buildNavigationHeader() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
        decoration: BoxDecoration(
          color: _surfaceColor.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _borderColor, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_currentStepIcon, color: _primaryColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentStepDistance,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _currentStepInstruction,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white38,
                size: 22,
              ),
              onPressed: _resetNavigation,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecenterButton() {
    return Positioned(
      bottom: 220,
      right: 16,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _mapController?.updateMyLocationTrackingMode(
              MyLocationTrackingMode.tracking,
            );
          });
          _goToCurrentLocation();
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _primaryColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.gps_fixed_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedometer() {
    return Positioned(
      bottom: 130,
      left: 16,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: _surfaceColor.withValues(alpha: 0.96),
          shape: BoxShape.circle,
          border: Border.all(color: _borderColor, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _currentSpeed.toStringAsFixed(0),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'km/h',
              style: GoogleFonts.inter(
                color: _mutedTextColor,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          24,
          18,
          24,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _borderColor, width: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: _borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildNavStat(_totalDistance, 'km'),
                _buildNavStat(_totalTime, 'min'),
                _buildNavStat(_eta, '', isTime: true),
                GestureDetector(
                  onTap: _exitNavigation,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavStat(String value, String unit, {bool isTime = false}) {
    // Split value and unit for specific styling
    final parts = value.split(' ');
    final val = parts[0];
    final u = parts.length > 1 ? parts[1] : unit;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isTime
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              val,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (u.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                u,
                style: GoogleFonts.inter(
                  color: _mutedTextColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ─── Data Formatting Helpers ──────────────────────────────────────────────────

  String _formatStepDistance(double meters) {
    if (meters >= 1000) {
      return "${(meters / 1000).toStringAsFixed(1)} km";
    } else {
      return "${meters.toStringAsFixed(0)} m";
    }
  }

  IconData _getManeuverIcon(int maneuverType) {
    // Valhalla maneuver types (DirectionsLeg_Maneuver_Type in directions.proto)
    switch (maneuverType) {
      case 1: // kStart
        return Icons.my_location;
      case 2: // kStartRight
      case 9: // kSlightRight
      case 10: // kRight
      case 11: // kSharpRight
      case 18: // kRampRight
      case 20: // kExitRight
      case 23: // kStayRight
      case 37: // kMergeRight
        return Icons.turn_right;

      case 3: // kStartLeft
      case 16: // kSlightLeft
      case 15: // kLeft
      case 14: // kSharpLeft
      case 19: // kRampLeft
      case 21: // kExitLeft
      case 24: // kStayLeft
      case 38: // kMergeLeft
        return Icons.turn_left;

      case 12: // kUturnRight
        return Icons.rotate_right;
      case 13: // kUturnLeft
        return Icons.rotate_left;

      case 7: // kBecomes
      case 8: // kContinue
      case 17: // kRampStraight
      case 22: // kStayStraight
        return Icons.straight;

      case 4: // kDestination
      case 5: // kDestinationRight
      case 6: // kDestinationLeft
      case 35: // kTransitConnectionDestination
      case 36: // kPostTransitConnectionDestination
        return Icons.flag;

      case 25: // kMerge
        return Icons.merge_type;

      case 26: // kRoundaboutEnter
      case 27: // kRoundaboutExit
        return Icons.autorenew;

      case 28: // kFerryEnter
      case 29: // kFerryExit
        return Icons.directions_ferry;

      case 30: // kTransit
        return Icons.directions_transit;
      case 31: // kTransitTransfer
      case 34: // kTransitConnectionTransfer
        return Icons.transfer_within_a_station;

      case 39: // kElevatorEnter
        return Icons.swap_vert;
      case 40: // kStepsEnter
        return Icons.stairs;
      case 41: // kEscalatorEnter
        return Icons.stairs;
      case 42: // kBuildingEnter
      case 43: // kBuildingExit
        return Icons.location_city;

      default:
        return Icons.navigation_rounded;
    }
  }
}

class _PoiIconDef {
  final IconData icon;
  final Color color;
  const _PoiIconDef(this.icon, this.color);
}
