import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:dio/dio.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;


/// Manages the /Documents/mbtiles_cache/ directory.
///
/// All methods are async and safe to call from any widget.
/// Use [getFilePath] to get the canonical path for a region — the same path
/// the DownloadManager writes to and MapScreen reads from.
class StorageManager {
  static const _cacheDir = 'mbtiles_cache';
  static const _routingDir = 'offline_routing';

  static const _valhallaTilesDir = 'valhalla_tiles';

  // ─────────────────────────────────────────────────────────────────────────
  // Directory helpers
  Future<String> getAppDirectoryPath() async {
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  /// Returns the canonical path to the valhalla_tiles directory.
  Future<String> getValhallaTilesPath() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_valhallaTilesDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// Returns (and creates if needed) the mbtiles_cache directory.
  Future<Directory> getCacheDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_cacheDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns (and creates if needed) the offline_routing directory.
  Future<Directory> getRoutingDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_routingDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }







  /// Returns the canonical absolute path for a region's .mbtiles file.
  Future<String> getFilePath(String regionId) async {
    final dir = await getCacheDirectory();
    return '${dir.path}/$regionId.mbtiles';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // File checks
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> fileExists(String regionId) async {
    final path = await getFilePath(regionId);
    return File(path).exists();
  }

  Future<int> getFileSize(String regionId) async {
    final path = await getFilePath(regionId);
    final f = File(path);
    if (!await f.exists()) return 0;
    return f.length();
  }

  /// Returns all regionIds that have an existing .mbtiles file.
  Future<List<String>> getDownloadedRegionIds() async {
    final dir = await getCacheDirectory();
    final files = await dir
        .list()
        .where((e) => e.path.endsWith('.mbtiles') && !path.basename(e.path).startsWith('._'))
        .toList();
    return files.map((e) {
      final name = path.basename(e.path);
      return name.replaceAll('.mbtiles', '');
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Storage stats
  // ─────────────────────────────────────────────────────────────────────────

  /// Total bytes used by all files in the cache directory.
  Future<int> getTotalStorageUsed() async {
    final dir = await getCacheDirectory();
    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Delete
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> deleteRegion(String regionId) async {
    final path = await getFilePath(regionId);
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
      debugPrint('StorageManager: Deleted $regionId');
    }
  }

  Future<void> clearAllDownloads() async {
    final dir = await getCacheDirectory();
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.mbtiles')) {
        await entity.delete();
      }
    }
    debugPrint('StorageManager: Cleared all downloads');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Asset copy (bundled MBTiles)
  // ─────────────────────────────────────────────────────────────────────────

  /// Ensures MBTiles file is available in local storage.
  ///
  /// If the file doesn't exist locally, attempts to copy it from bundled assets.
  /// This enables zero-setup offline maps — just bundle the MBTiles in assets.
  ///
  /// Returns true if file is available (either existed or was copied).
  /// Returns false if file doesn't exist and couldn't be copied from assets.
  Future<bool> ensureMbtilesFromAssets(String regionId) async {
    final filePath = await getFilePath(regionId);
    final file = File(filePath);

    // Already exists locally — nothing to do
    if (await file.exists()) {
        debugPrint('[StorageManager] MBTiles already exists: $regionId');
        return true;
    }

    // Try to copy from bundled assets
    final assetPath = 'assets/mbtiles/$regionId.mbtiles';
    try {
      debugPrint('[StorageManager] Checking for bundled asset: $assetPath');
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();

      // Ensure directory exists
      await getCacheDirectory();

      // Write to local storage
      await file.writeAsBytes(bytes);

      debugPrint(
        '[StorageManager] Copied MBTiles (${formatBytes(bytes.length)}) '
        'from assets to: $filePath',
      );
      return true;
    } catch (e) {
      // Asset doesn't exist or copy failed — this is normal for regions
      // that aren't bundled. The app can still download them later.
      debugPrint('[StorageManager] No bundled asset for $regionId: $e');
      return false;
    }
  }

  /// Checks if an MBTiles file is bundled in assets (without copying it).
  ///
  /// Useful for showing UI indicators of which regions are pre-bundled.
  Future<bool> hasAssetMbtiles(String regionId) async {
    final assetPath = 'assets/mbtiles/$regionId.mbtiles';
    try {
      // Try to load just the first byte to check if asset exists
      await rootBundle.load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Copies all bundled MBTiles from assets to local storage.
  ///
  /// Call this once on app startup to pre-populate local cache.
  /// [regionIds] - List of region IDs to check for bundled assets.
  /// Returns list of region IDs that were successfully copied.
  Future<List<String>> copyAllBundledAssets(List<String> regionIds) async {
    final copied = <String>[];
    for (final regionId in regionIds) {
      final success = await ensureMbtilesFromAssets(regionId);
      if (success) {
        final existed = await fileExists(regionId);
        if (existed) copied.add(regionId);
      }
    }
    if (copied.isNotEmpty) {
      debugPrint(
        '[StorageManager] Copied ${copied.length} bundled MBTiles: $copied',
      );
    }
    return copied;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MBTiles file operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves downloaded MBTiles data to the cache directory.
  ///
  /// [filePath] - Full path where the file should be saved
  /// [data] - Raw bytes of the MBTiles file
  Future<void> saveMbTilesData(String filePath, Uint8List data) async {
    final file = File(filePath);

    // Delete if exists (overwrite)
    if (await file.exists()) await file.delete();

    await file.writeAsBytes(data);
    debugPrint(
      '[StorageManager] Saved MBTiles (${formatBytes(data.length)}) at: $filePath',
    );
  }

  Future<void> downloadMbtiles(
    String regionId,
    String url, {
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dio = Dio();
    final path = await getFilePath(regionId);
    final tempPath = '$path.temp';
    final tempFile = File(tempPath);

    try {
      await getCacheDirectory();

      // Handle Dropbox direct-download conversion
      String downloadUrl = url;
      if (url.contains('dropbox.com')) {
        final uri = Uri.parse(url);
        final rlkey = uri.queryParameters['rlkey'];
        
        // Force the direct download domain
        const host = 'dl.dropboxusercontent.com';
        final path = uri.path;

        if (rlkey != null) {
          downloadUrl = "https://$host$path?rlkey=$rlkey&raw=1";
        } else {
          downloadUrl = "https://$host$path?raw=1";
        }
        debugPrint('[StorageManager] Converted Dropbox link: $downloadUrl');
      }

      await dio.download(
        downloadUrl,
        tempPath,
        cancelToken: cancelToken,
        options: Options(
          followRedirects: true,
          maxRedirects: 10,
        ),
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      if (await tempFile.exists()) {
        // DEBUG: Peek at the file content
        try {
          final bytes = await tempFile.openRead(0, 100).first;
          final peek = String.fromCharCodes(bytes.where((b) => b >= 32 && b <= 126));
          debugPrint('[StorageManager] Downloaded peek: $peek');
        } catch (e) {
          debugPrint('[StorageManager] Peek failed: $e');
        }

        final finalFile = File(path);
        if (await finalFile.exists()) await finalFile.delete();
        await tempFile.rename(path);
        debugPrint('[StorageManager] Downloaded $regionId successfully to: $path');
      }
    } catch (e) {
      if (await tempFile.exists()) await tempFile.delete();
      debugPrint('[StorageManager] Download failed: $e');
      rethrow;
    }
  }

  /// Validates that an MBTiles file is valid and contains tiles.
  ///
  /// Returns null if valid, or an error message if invalid.
  Future<String?> validateMbTilesFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return 'File does not exist';
    }

    Database? db;
    try {
      db = sqlite3.open(filePath, mode: OpenMode.readOnly);

      // Check required tables exist (can be tables or views in modern MBTiles)
      final tables = db.select(
        "SELECT name FROM sqlite_master WHERE name IN ('tiles', 'metadata')",
      );
      if (tables.length < 2) {
        return 'Missing required entities (tiles, metadata). Found: ${tables.map((t) => t['name'])}';
      }

      // Check tile count
      final countResult = db.select('SELECT COUNT(*) as cnt FROM tiles');
      final tileCount = countResult.first['cnt'] as int? ?? 0;
      if (tileCount == 0) {
        return 'MBTiles contains no tiles';
      }
      if (tileCount < 100) {
        return 'MBTiles has insufficient tiles ($tileCount). Need 100+ for usable map.';
      }

      // Check format (prefer vector for this app)
      final fmtResult = db.select(
        "SELECT value FROM metadata WHERE name='format' LIMIT 1",
      );
      if (fmtResult.isNotEmpty) {
        final format = (fmtResult.first['value'] as String?)?.toLowerCase();
        if (format != 'pbf' &&
            format != 'mvt' &&
            format != 'png' &&
            format != 'jpg' &&
            format != 'webp') {
          return 'Unsupported format ($format). Need Vector (pbf/mvt) or Raster (png/jpg/webp).';
        }
        debugPrint('[StorageManager] Tile format: $format');
      }

      debugPrint('[StorageManager] Validated MBTiles: $tileCount tiles');
      return null; // Valid
    } catch (e) {
      return 'Failed to open MBTiles: $e';
    } finally {
      db?.dispose();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Formatting helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Downloads a single ZIP containing all offline files and extracts them to correct paths.
  /// This is ideal for a one-click demo setup from Dropbox.
  Future<void> downloadAndExtractRegionZip(
    String regionId,
    String url, {
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dio = Dio();
    final docs = await getApplicationDocumentsDirectory();
    final zipPath = '${docs.path}/$regionId.zip';
    
    try {
      // 1. Handle Dropbox conversion
      String downloadUrl = url;
      if (url.contains('dropbox.com')) {
        downloadUrl = url.replaceAll('www.dropbox.com', 'dl.dropboxusercontent.com')
                         .replaceAll('/scl/fi/', '/s/')
                         .replaceAll('?dl=0', '?dl=1')
                         .replaceAll('?dl=1', '?raw=1');
      }

      // 2. Download
      await dio.download(
        downloadUrl,
        zipPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      // 3. Extract
      final bytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        final basename = path.basename(filename); // Ignore internal folders
        
        if (file.isFile) {
          final data = file.content as List<int>;
          
          if (basename.endsWith('.mbtiles')) {
            final target = File('${docs.path}/$_cacheDir/$basename');
            await target.parent.create(recursive: true);
            await target.writeAsBytes(data);
            debugPrint('[ZIP] Extracted MBTiles: $basename');
          } else if (basename.endsWith('.tar')) {
             final target = File('${docs.path}/$basename');
             await target.writeAsBytes(data);
             debugPrint('[ZIP] Extracted Routing Tar: $basename');
          } else if (basename.endsWith('.json') && !basename.contains('places')) {
             final target = File('${docs.path}/$basename');
             await target.writeAsBytes(data);
             debugPrint('[ZIP] Extracted Config JSON: $basename');
          } else if (basename.contains('places')) {
             final dataDir = Directory('${docs.path}/data');
             if (!await dataDir.exists()) await dataDir.create(recursive: true);
             final target = File('${dataDir.path}/$basename');
             await target.writeAsBytes(data);
             debugPrint('[ZIP] Extracted Places Search JSON: $basename');
          }
        }
      }

      // Cleanup ZIP
      await File(zipPath).delete();
      debugPrint('[ZIP] Setup complete for $regionId');
      
    } catch (e) {
      debugPrint('[ZIP] Error during download/extract: $e');
      rethrow;
    }
  }

  /// Formats bytes into a human-readable string (KB / MB).
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
