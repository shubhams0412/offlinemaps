import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:developer' as developer;
import 'package:offlinemaps/services/offline_routing_service.dart';

class ValhallaSetupService {
  static const String _assetDir = 'assets/offline_data';
  static const String _valhallaJson = 'gujarat.json';
  static const String _valhallaTar = 'gujarat_tiles.tar';

  /// Sets up Valhalla config and tiles in the internal storage.
  static Future<void> setup() async {
    try {
      final Directory docDir = await getApplicationDocumentsDirectory();
      final String docPath = docDir.path;

      final File jsonFile = File(p.join(docPath, _valhallaJson));
      final File tarFile = File(p.join(docPath, _valhallaTar));

      // 1. Copy tiles from assets ONLY if missing on disk AND present in assets
      if (!await tarFile.exists()) {
        try {
          developer.log('Checking for bundled $_valhallaTar in assets...', name: 'ValhallaSetup');
          final ByteData data = await rootBundle.load(p.join(_assetDir, _valhallaTar));
          final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          await tarFile.parent.create(recursive: true);
          await tarFile.writeAsBytes(bytes);
          developer.log('Tiles copied from assets successfully.', name: 'ValhallaSetup');
        } catch (e) {
          developer.log('No bundled tiles found in assets. Expecting download.', name: 'ValhallaSetup');
        }
      } else {
        developer.log('Using existing tiles in storage: ${tarFile.path}', name: 'ValhallaSetup');
      }

      // 2. Load JSON: Priority local storage > Assets
      String originalJson;
      if (await jsonFile.exists()) {
        developer.log('Using existing $_valhallaJson from storage.', name: 'ValhallaSetup');
        originalJson = await jsonFile.readAsString();
      } else {
        try {
          originalJson = await rootBundle.loadString(p.join(_assetDir, _valhallaJson));
          developer.log('Loaded base config from assets.', name: 'ValhallaSetup');
        } catch (e) {
          developer.log('Warning: No $_valhallaJson found anywhere. Initialization might fail.', name: 'ValhallaSetup');
          return;
        }
      }
      
      // Parse to update paths and settings
      Map<String, dynamic> config = json.decode(originalJson);
      
      if (config.containsKey('mjolnir')) {
        config['mjolnir']['tile_dir'] = docPath;
        config['mjolnir']['tile_extract'] = tarFile.path;
        config['mjolnir']['scan_tar'] = true;
      }

      // Save updated JSON
      await jsonFile.writeAsBytes(utf8.encode(json.encode(config)));
      developer.log('Config updated and saved to ${jsonFile.path}', name: 'ValhallaSetup');

      // 3. Initialize the routing engine
      final bool initialized = await OfflineRoutingService().init(jsonFile.path);
      if (initialized) {
        developer.log('Valhalla Routing Engine initialized successfully.', name: 'ValhallaSetup');
      } else {
        developer.log('Failed to initialize Valhalla Routing Engine.', name: 'ValhallaSetup');
      }
    } catch (e, stack) {
      developer.log('Error during Valhalla setup: $e', name: 'ValhallaSetup', error: e, stackTrace: stack);
    }
  }
}
