import 'dart:convert';
import 'vector_tile_server.dart';

/// Guru Maps-inspired dark theme style generator for MapLibre
///
/// Supports two MBTiles formats:
/// 1. OpenMapTiles schema (standard layers: water, transportation, building, etc.)
/// 2. Single-layer GeoJSON export (all data in one layer, filtered by attributes)
class GuruMapsStyle {
  static const String bgDark = '#0b0f14';
  static const String landColor = '#1a1f26';
  static const String roadOrange = '#ffffff'; // Changed from orange to white
  static const String roadSecondary = '#ffffff'; // Changed from amber to white
  static const String roadMinor = '#4A5568'; // Slate Gray for minor roads
  static const String waterBlue =
      '#00E5FF'; // Electric Cyan for professional look
  static const String boundaryColor = '#4a5568';
  static const String buildingColor = '#2d3748';
  static const String labelColor = '#ffffff';
  static const String labelHalo = '#000000';
  static const String accentColor = '#1E6EFF'; // Professional blue accent

  static String generateStyle({
    required String tileUrlTemplate,
    required TileSchema schema,
    required List<String> availableLayers,
    bool safeSingleLayerFallback = false,
    int minZoom = 2,
    int maxZoom = 14,
    bool debugMode = false,
    String? glyphsUrl,
  }) {
    // Detect if this is a single-layer GeoJSON-based MBTiles
    // (common when using tippecanoe on a GeoJSON file)
    final isSingleLayer = availableLayers.length == 1;
    final sourceLayer = isSingleLayer ? availableLayers.first : null;

    // Build layers based on detected schema
    final List<Map<String, dynamic>> layers = isSingleLayer
        ? (safeSingleLayerFallback
              ? _buildSafeSingleLayerStyle(sourceLayer!)
              : _buildSingleLayerStyle(sourceLayer!))
        : _buildOpenMapTilesStyle();

    final effectiveGlyphsUrl =
        glyphsUrl ??
        tileUrlTemplate.replaceFirst(
          '/tiles/{z}/{x}/{y}.pbf',
          '/fonts/{fontstack}/{range}.pbf',
        );

    final style = {
      'version': 8,
      'name': 'Guru Maps Dark',
      'glyphs': effectiveGlyphsUrl,
      'sources': {
        'offline': {
          'type': 'vector',
          'tiles': [tileUrlTemplate],
          'minzoom': minZoom,
          'maxzoom': 14, // Data limit; MapLibre will 'overzoom' automatically above this
        },
        'offline-route': {
          'type': 'geojson',
          'data': {'type': 'FeatureCollection', 'features': []},
        },
      },
      'layers': layers,
    };

    return json.encode(style);
  }

  /// Build style for single-layer MBTiles (GeoJSON export via tippecanoe).
  static List<Map<String, dynamic>> _buildSingleLayerStyle(String sourceLayer) {
    return [
      // Background
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': bgDark},
      },

      // ALL LINES - catch-all to show something (debug)
      {
        'id': 'all-lines',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'paint': {
          'line-color': '#FFFFFF',
          'line-width': 0.5,
          'line-opacity': 0.05,
        },
      },

      // Water (natural=water)
      {
        'id': 'water-area',
        'type': 'fill',
        'source': 'offline',
        'source-layer': sourceLayer,
        'filter': ['==', 'natural', 'water'],
        'paint': {'fill-color': waterBlue, 'fill-opacity': 0.8},
      },

      // Waterways (rivers, streams)
      {
        'id': 'waterway-river',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'filter': ['==', 'waterway', 'river'],
        'paint': {'line-color': waterBlue, 'line-width': 3},
      },
      {
        'id': 'waterway-stream',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'filter': ['==', 'waterway', 'stream'],
        'paint': {'line-color': waterBlue, 'line-width': 1},
      },

      // Landuse - forests
      {
        'id': 'landuse-forest',
        'type': 'fill',
        'source': 'offline',
        'source-layer': sourceLayer,
        'filter': ['==', 'landuse', 'forest'],
        'paint': {'fill-color': '#1a2a1a', 'fill-opacity': 0.5},
      },

      // Buildings
      {
        'id': 'building',
        'type': 'fill',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 13,
        'filter': ['has', 'building'],
        'paint': {'fill-color': buildingColor, 'fill-opacity': 0.7},
      },

      // Boundaries
      {
        'id': 'boundary',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'filter': ['has', 'admin_level'],
        'paint': {
          'line-color': boundaryColor,
          'line-width': 1,
          'line-dasharray': [3, 2],
        },
      },

      // Railways
      {
        'id': 'railway',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'filter': ['has', 'railway'],
        'paint': {
          'line-color': '#555555',
          'line-width': 2,
          'line-dasharray': [4, 2],
        },
      },

      // Roads - residential/service
      {
        'id': 'roads-residential',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 12,
        'filter': ['==', 'highway', 'residential'],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': roadMinor,
          'line-width': 2,
          'line-opacity': 0.7,
        },
      },
      {
        'id': 'roads-service',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 13,
        'filter': ['==', 'highway', 'service'],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': roadMinor,
          'line-width': 1,
          'line-opacity': 0.5,
        },
      },
      {
        'id': 'roads-unclassified',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 11,
        'filter': ['==', 'highway', 'unclassified'],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': roadMinor, 'line-width': 2},
      },

      // Roads - tertiary
      {
        'id': 'roads-tertiary',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 10,
        'filter': ['==', 'highway', 'tertiary'],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': roadMinor, 'line-width': 3},
      },

      // Roads - secondary
      {
        'id': 'roads-secondary',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 8,
        'filter': ['==', 'highway', 'secondary'],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': roadSecondary, 'line-width': 4},
      },

      // Roads - primary
      {
        'id': 'roads-primary',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 6,
        'filter': ['==', 'highway', 'primary'],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': roadOrange, 'line-width': 5},
      },

      // Roads - trunk
      {
        'id': 'roads-trunk',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 5,
        'filter': ['==', 'highway', 'trunk'],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': roadOrange, 'line-width': 6},
      },

      // Roads - motorway
      {
        'id': 'roads-motorway',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 4,
        'filter': ['==', 'highway', 'motorway'],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': roadOrange, 'line-width': 7},
      },

      // Route line (for navigation)
      {
        'id': 'route-line',
        'type': 'line',
        'source': 'offline-route',
        'layout': {'line-join': 'round', 'line-cap': 'round'},
        'paint': {
          'line-color': '#1E6EFF',
          'line-width': 8,
          'line-opacity': 0.9,
        },
      },

      // Road names
      {
        'id': 'road-names',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 13,
        'filter': [
          'all',
          ['has', 'highway'],
          ['has', 'name'],
        ],
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Regular'],
          'text-size': 12,
          'symbol-placement': 'line',
          'text-max-angle': 30,
          'text-padding': 5,
        },
        'paint': {
          'text-color': labelColor,
          'text-halo-color': labelHalo,
          'text-halo-width': 1,
        },
      },

      // Place names - cities/towns
      {
        'id': 'place-city',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 6,
        'filter': ['==', 'place', 'city'],
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Regular'],
          'text-size': 16,
          'text-anchor': 'center',
        },
        'paint': {
          'text-color': labelColor,
          'text-halo-color': labelHalo,
          'text-halo-width': 2,
        },
      },
      {
        'id': 'place-town',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 8,
        'filter': ['==', 'place', 'town'],
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Regular'],
          'text-size': 14,
          'text-anchor': 'center',
        },
        'paint': {
          'text-color': labelColor,
          'text-halo-color': labelHalo,
          'text-halo-width': 1.5,
        },
      },
      {
        'id': 'place-village',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 10,
        'filter': ['==', 'place', 'village'],
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Regular'],
          'text-size': 11,
          'text-anchor': 'center',
        },
        'paint': {
          'text-color': '#cccccc',
          'text-halo-color': labelHalo,
          'text-halo-width': 1,
        },
      },

      // POI Icons
      {
        'id': 'poi-hospital',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 13,
        'filter': [
          'any',
          ['==', 'amenity', 'hospital'],
          ['==', 'amenity', 'clinic'],
          ['==', 'healthcare', 'hospital'],
        ],
        'layout': {
          'text-field': '🏥',
          'text-font': ['Open Sans Regular'],
          'text-size': 16,
          'text-allow-overlap': false,
        },
        'paint': {'text-halo-color': labelHalo, 'text-halo-width': 2},
      },
      {
        'id': 'poi-fuel',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 13,
        'filter': [
          'any',
          ['==', 'amenity', 'fuel'],
          ['==', 'amenity', 'petrol'],
          ['==', 'fuel', 'yes'],
        ],
        'layout': {
          'text-field': '⛽',
          'text-font': ['Open Sans Regular'],
          'text-size': 16,
          'text-allow-overlap': false,
        },
        'paint': {'text-halo-color': labelHalo, 'text-halo-width': 2},
      },
      {
        'id': 'poi-restaurant',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 14,
        'filter': [
          'any',
          ['==', 'amenity', 'restaurant'],
          ['==', 'amenity', 'cafe'],
          ['==', 'amenity', 'fast_food'],
        ],
        'layout': {
          'text-field': '🍽️',
          'text-font': ['Open Sans Regular'],
          'text-size': 16,
          'text-allow-overlap': false,
        },
        'paint': {'text-halo-color': labelHalo, 'text-halo-width': 2},
      },
      {
        'id': 'poi-labels',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': sourceLayer,
        'minzoom': 15,
        'filter': [
          'all',
          ['has', 'amenity'],
          ['has', 'name'],
        ],
        'layout': {
          'text-field': '{name}',
          'text-font': ['Open Sans Regular'],
          'text-size': 11,
          'text-anchor': 'top',
          'text-offset': [0, 1.2],
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': labelHalo,
          'text-halo-width': 1,
        },
      },
    ];
  }

  /// Build style for single-layer MBTiles on Android when native rendering
  /// becomes unstable with property-driven filters.
  ///
  /// Some single-layer exports contain inconsistent feature-property key tables
  /// that can crash native MapLibre rendering when filters or labels access
  /// arbitrary properties. This fallback style only uses geometry-based filters
  /// so the map stays stable even with imperfect tiles.
  static List<Map<String, dynamic>> _buildSafeSingleLayerStyle(
    String sourceLayer,
  ) {
    return [
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': bgDark},
      },
      {
        'id': 'geometry-polygons',
        'type': 'fill',
        'source': 'offline',
        'source-layer': sourceLayer,
        'filter': ['==', '\$type', 'Polygon'],
        'paint': {'fill-color': landColor, 'fill-opacity': 0.55},
      },
      {
        'id': 'geometry-polygons-outline',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'filter': ['==', '\$type', 'Polygon'],
        'paint': {
          'line-color': boundaryColor,
          'line-width': 0.8,
          'line-opacity': 0.6,
        },
      },
      {
        'id': 'geometry-lines',
        'type': 'line',
        'source': 'offline',
        'source-layer': sourceLayer,
        'filter': ['==', '\$type', 'LineString'],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': roadSecondary,
          'line-width': 1.4,
          'line-opacity': 0.9,
        },
      },
      {
        'id': 'geometry-points',
        'type': 'circle',
        'source': 'offline',
        'source-layer': sourceLayer,
        'filter': ['==', '\$type', 'Point'],
        'paint': {
          'circle-radius': 3,
          'circle-color': accentColor,
          'circle-opacity': 0.85,
          'circle-stroke-color': '#FFFFFF',
          'circle-stroke-width': 1,
        },
      },
      {
        'id': 'route-line',
        'type': 'line',
        'source': 'offline-route',
        'layout': {'line-join': 'round', 'line-cap': 'round'},
        'paint': {
          'line-color': accentColor,
          'line-width': 8,
          'line-opacity': 0.9,
        },
      },
    ];
  }

  /// Build style for standard OpenMapTiles schema
  static List<Map<String, dynamic>> _buildOpenMapTilesStyle() {
    return [
      // Background
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': bgDark},
      },

      // Landcover
      {
        'id': 'landcover',
        'type': 'fill',
        'source': 'offline',
        'source-layer': 'landcover',
        'paint': {'fill-color': landColor, 'fill-opacity': 0.7},
      },

      // Water
      {
        'id': 'water',
        'type': 'fill',
        'source': 'offline',
        'source-layer': 'water',
        'paint': {'fill-color': waterBlue},
      },

      // Boundary
      {
        'id': 'boundary',
        'type': 'line',
        'source': 'offline',
        'source-layer': 'boundary',
        'paint': {
          'line-color': boundaryColor,
          'line-width': 1,
          'line-dasharray': [3, 2],
        },
      },

      // Buildings
      {
        'id': 'building',
        'type': 'fill',
        'source': 'offline',
        'source-layer': 'building',
        'minzoom': 13,
        'paint': {'fill-color': buildingColor, 'fill-opacity': 0.8},
      },

      // Roads
      {
        'id': 'roads-minor',
        'type': 'line',
        'source': 'offline',
        'source-layer': 'transportation',
        'minzoom': 13,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': roadMinor,
          'line-width': 2,
          'line-opacity': 0.6,
        },
      },
      {
        'id': 'roads-secondary',
        'type': 'line',
        'source': 'offline',
        'source-layer': 'transportation',
        'filter': ['in', 'class', 'secondary', 'tertiary'],
        'minzoom': 10,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': roadSecondary, 'line-width': 3},
      },
      {
        'id': 'roads-primary',
        'type': 'line',
        'source': 'offline',
        'source-layer': 'transportation',
        'filter': ['in', 'class', 'primary', 'trunk'],
        'minzoom': 6,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': roadOrange, 'line-width': 4},
      },
      {
        'id': 'roads-motorway',
        'type': 'line',
        'source': 'offline',
        'source-layer': 'transportation',
        'filter': ['==', 'class', 'motorway'],
        'minzoom': 4,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': roadOrange, 'line-width': 5},
      },

      // Route line
      {
        'id': 'route-line',
        'type': 'line',
        'source': 'offline-route',
        'layout': {'line-join': 'round', 'line-cap': 'round'},
        'paint': {
          'line-color': '#1E6EFF',
          'line-width': 8,
          'line-opacity': 0.9,
        },
      },

      {
        'id': 'road-names',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': 'transportation_name',
        'minzoom': 13,
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Regular'],
          'text-size': 12,
          'symbol-placement': 'line',
          'text-padding': 2,
        },
        'paint': {
          'text-color': labelColor,
          'text-halo-color': labelHalo,
          'text-halo-width': 1,
        },
      },

      // POI Icons - Hospital
      {
        'id': 'poi-hospital',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': 'poi',
        'minzoom': 14,
        'filter': ['in', 'class', 'hospital', 'clinic'],
        'layout': {
          'text-field': '🏥',
          'text-font': ['Open Sans Regular'],
          'text-size': 15,
          'text-allow-overlap': false,
        },
        'paint': {'text-halo-color': labelHalo, 'text-halo-width': 1},
      },

      // POI Icons - Fuel
      {
        'id': 'poi-fuel',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': 'poi',
        'minzoom': 14,
        'filter': ['==', 'class', 'fuel'],
        'layout': {
          'text-field': '⛽',
          'text-font': ['Open Sans Regular'],
          'text-size': 15,
          'text-allow-overlap': false,
        },
        'paint': {'text-halo-color': labelHalo, 'text-halo-width': 1},
      },

      // POI Icons - Restaurant
      {
        'id': 'poi-restaurant',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': 'poi',
        'minzoom': 14,
        'filter': ['in', 'class', 'restaurant', 'cafe', 'food_court'],
        'layout': {
          'text-field': '🍽️',
          'text-font': ['Open Sans Regular'],
          'text-size': 15,
          'text-allow-overlap': false,
        },
        'paint': {'text-halo-color': labelHalo, 'text-halo-width': 1},
      },

      // Place Labels
      {
        'id': 'place-names',
        'type': 'symbol',
        'source': 'offline',
        'source-layer': 'place',
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Regular'],
          'text-size': 14,
          'text-padding': 5,
        },
        'paint': {
          'text-color': labelColor,
          'text-halo-color': labelHalo,
          'text-halo-width': 1.5,
        },
      },
    ];
  }

  static String getDiagnosticInfo(String path, List<String> layers) =>
      'Offline Map: $path, Layers: ${layers.join(", ")}';
}
