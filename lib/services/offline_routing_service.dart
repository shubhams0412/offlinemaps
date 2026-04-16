import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class OfflineRoutingService {
  // Singleton pattern
  static final OfflineRoutingService _instance = OfflineRoutingService._internal();
  factory OfflineRoutingService() => _instance;
  OfflineRoutingService._internal();

  static const MethodChannel _channel = MethodChannel('com.example.offlinemaps/routing');
  
  Future<bool> init(String configPath) async {
    try {
      final bool success = await _channel.invokeMethod('init', {
        'configPath': configPath,
      });
      return success;
    } catch (e) {
      developer.log('Valhalla initialization failed: $e', name: 'OfflineRouting');
      return false;
    }
  }

  Future<bool> isReady() async {
    try {
      final bool ready = await _channel.invokeMethod('isReady');
      return ready;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    String profile = 'auto',
  }) async {
    try {
      developer.log('Requesting Valhalla route from ($startLat, $startLng) to ($endLat, $endLng)...', name: 'OfflineRouting');
      
      final dynamic result = await _channel.invokeMethod('getRoute', {
        'startLat': startLat,
        'startLng': startLng,
        'endLat': endLat,
        'endLng': endLng,
        'profile': profile,
      });

      if (result != null && result is String) {
        final Map<String, dynamic> rawData = json.decode(result);
        
        if (rawData.containsKey('error')) {
            developer.log('Valhalla Engine Error: ${rawData['error']}', name: 'OfflineRouting');
            return null;
        }

        // Valhalla JSON Structure transformation
        final trip = rawData['trip'];
        if (trip == null || trip['legs'] == null) return null;

        final summary = trip['summary'];
        final List legs = trip['legs'];
        final firstLeg = legs.first;

        // 1. Decode Shape (Polyline6)
        final String shape = firstLeg['shape'] ?? '';
        final List<LatLng> points = _decodePolyline(shape);

        // 2. Map maneuvers to instructions
        final List maneuvers = firstLeg['maneuvers'] ?? [];
        final instructions = maneuvers.map((m) => {
          'text': m['instruction'] ?? '',
          'distance': (m['length'] ?? 0.0) * 1000.0, // Convert km to meters
          'time': (((m['time'] as num?)?.toDouble() ?? 0.0) * 1000.0).round(), // Convert sec to ms
          'sign': (m['type'] as num?)?.toInt() ?? 0,
        }).toList();

        return {
          'points': points,
          'distance': (summary['length'] ?? 0.0) * 1000.0, // km to m
          'time': (((summary['time'] as num?)?.toDouble() ?? 0.0) * 1000.0).round(), // sec to ms
          'instructions': instructions,
        };
      }
      return null;
    } on PlatformException catch (e) {
        developer.log('Platform error during routing: ${e.message}', name: 'OfflineRouting');
        return null;
    } catch (e) {
      developer.log('Unexpected error fetching Valhalla route: $e', name: 'OfflineRouting');
      return null;
    }
  }

  /// Decodes a Valhalla Polyline6 string into a list of LatLng coordinates.
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    const double precision = 1e6;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        if (index >= len) return points; // Safety breakthrough
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        if (index >= len) return points; // Safety breakthrough
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / precision, lng / precision));
    }
    return points;
  }
}
