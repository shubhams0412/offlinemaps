import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../data/india_states.dart';
import '../models/map_region.dart';
import '../storage/storage_manager.dart';
import 'download_state.dart';

/// Manages the download lifecycle for all map regions.
///
/// Uses [ChangeNotifier] so any widget can listen with
/// `context.watch<DownloadManager>()`.
///
/// Downloads MBTiles files from configured URLs. If no URL is configured,
/// shows an error instructing the user to configure a download source.
class DownloadManager extends ChangeNotifier {
  final StorageManager storage;
  final Dio _dio = Dio();

  /// Active download cancel tokens (to support cancellation)
  final Map<String, CancelToken> _cancelTokens = {};

  DownloadManager(this.storage) {
    _loadExistingDownloads();
  }

  // ── State map ─────────────────────────────────────────────────────────────
  final Map<String, RegionDownloadState> _states = {};

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the current [RegionDownloadState] for [regionId].
  /// Always returns a state (defaults to notDownloaded).
  RegionDownloadState getState(String regionId) {
    return _states[regionId] ??
        RegionDownloadState(regionId: regionId);
  }

  /// All regionIds whose status == downloaded.
  List<String> get downloadedRegionIds => _states.entries
      .where((e) => e.value.isDownloaded)
      .map((e) => e.key)
      .toList();

  /// Number of regions currently downloading.
  int get activeDownloads =>
      _states.values.where((s) => s.isActive).length;

  // ─────────────────────────────────────────────────────────────────────────
  // Download control
  // ─────────────────────────────────────────────────────────────────────────

  /// Starts downloading (simulated) the given region.
  /// No-op if already downloaded or actively downloading.
  Future<void> startDownload(MapRegion region) async {
    final current = getState(region.id);
    if (current.isDownloaded || current.isActive) return;

    _updateState(region.id, const RegionDownloadState(regionId: '')
        .copyWith(status: DownloadStatus.queued, progress: 0.0)
        ._withId(region.id));

    // Small delay before starting (queued → downloading)
    await Future.delayed(const Duration(milliseconds: 300));
    if (!getState(region.id).isQueued) return; // was cancelled

    _updateState(region.id, RegionDownloadState(
      regionId: region.id,
      status: DownloadStatus.downloading,
      progress: 0.0,
    ));

    return _downloadMbTiles(region);
  }

  /// Cancels an active download and resets to [DownloadStatus.notDownloaded].
  void cancelDownload(String regionId) {
    _cancelTokens[regionId]?.cancel('User cancelled');
    _cancelTokens.remove(regionId);
    _updateState(regionId, RegionDownloadState(regionId: regionId));
    debugPrint('DownloadManager: Cancelled $regionId');
  }

  /// Deletes the downloaded file and resets state to notDownloaded.
  Future<void> deleteDownload(String regionId) async {
    cancelDownload(regionId); // stops any active timer first
    await storage.deleteRegion(regionId);
    _updateState(regionId, RegionDownloadState(regionId: regionId));
    debugPrint('DownloadManager: Deleted $regionId');
  }

  /// Deletes ALL downloaded files and resets all states.
  Future<void> clearAllDownloads() async {
    // Cancel all active downloads
    for (final token in _cancelTokens.values) {
      token.cancel('Clear all');
    }
    _cancelTokens.clear();

    await storage.clearAllDownloads();

    _states.removeWhere((_, s) => s.isDownloaded || s.isActive);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internals
  // ─────────────────────────────────────────────────────────────────────────

  /// Scans mbtiles_cache on startup and marks existing files as downloaded.
  Future<void> _loadExistingDownloads() async {
    for (final region in kIndiaStates) {
      final exists = await storage.fileExists(region.id);
      if (exists) {
        _states[region.id] = RegionDownloadState(
          regionId: region.id,
          status: DownloadStatus.downloaded,
          progress: 1.0,
        );
      }
    }
    notifyListeners();
  }

  /// Downloads MBTiles from the region's configured URL.
  /// Shows error if no URL is configured.
  Future<void> _downloadMbTiles(MapRegion region) async {
    if (!region.hasDownloadUrl) {
      // No download URL configured — show helpful error
      _updateState(region.id, RegionDownloadState(
        regionId: region.id,
        status: DownloadStatus.error,
        errorMessage: 'No download URL configured for ${region.name}. '
            'Please add MBTiles file manually to Documents/mbtiles_cache/${region.id}.mbtiles',
      ));
      debugPrint('DownloadManager: No download URL for ${region.id}');
      return;
    }

    final cancelToken = CancelToken();
    _cancelTokens[region.id] = cancelToken;
    
    try {
      debugPrint('DownloadManager: Downloading ${region.downloadUrl}');

      // For the demo, we use the consolidated ZIP method
      await storage.downloadAndExtractRegionZip(
        region.id,
        region.downloadUrl!,
        cancelToken: cancelToken,
        onProgress: (p) {
          if (!cancelToken.isCancelled) {
            _updateState(region.id, RegionDownloadState(
              regionId: region.id,
              status: DownloadStatus.downloading,
              progress: p.clamp(0.0, 0.99),
            ));
          }
        },
      );

      if (cancelToken.isCancelled) return;

      // After ZIP extraction, verify the MBTiles exists in the cache
      final mbtilesPath = await storage.getFilePath(region.id);
      final exists = await File(mbtilesPath).exists();
      
      if (!exists) {
        _updateState(region.id, RegionDownloadState(
          regionId: region.id,
          status: DownloadStatus.error,
          errorMessage: 'Extraction failed: ${region.id}.mbtiles not found in ZIP.',
        ));
        debugPrint('DownloadManager: Extraction failed, file missing: $mbtilesPath');
        return;
      }

      _updateState(region.id, RegionDownloadState(
        regionId: region.id,
        status: DownloadStatus.downloaded,
        progress: 1.0,
      ));
      debugPrint('DownloadManager: Completed ${region.name}');

      // Prefetch common fonts for this region if needed
      unawaited(precacheEssentialFonts());

    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        debugPrint('DownloadManager: Download cancelled for ${region.id}');
        return;
      }
      _updateState(region.id, RegionDownloadState(
        regionId: region.id,
        status: DownloadStatus.error,
        errorMessage: 'Download failed: ${e.message}',
      ));
      debugPrint('DownloadManager: Download error ${region.id}: $e');
    } catch (e) {
      _updateState(region.id, RegionDownloadState(
        regionId: region.id,
        status: DownloadStatus.error,
        errorMessage: 'Download failed. Please try again.',
      ));
      debugPrint('DownloadManager: Error ${region.id}: $e');
    } finally {
      _cancelTokens.remove(region.id);
    }
  }

  void _updateState(String regionId, RegionDownloadState state) {
    _states[regionId] = state;
    notifyListeners();
  }

  /// Automatically pre-caches essential font glyphs for offline use.
  Future<void> precacheEssentialFonts() async {
    const fonts = ['Open Sans Regular', 'Arial Unicode MS Regular'];
    const range = '0-255'; // Basic latin covers most road labels

    for (final font in fonts) {
      try {
        final cachePath = path.join(
          await storage.getAppDirectoryPath(),
          'font_cache',
          font,
          '$range.pbf',
        );
        final file = File(cachePath);
        if (file.existsSync()) continue;

        // Ensure directory exists
        file.parent.createSync(recursive: true);

        final url = 'https://demotiles.maplibre.org/font/$font/$range.pbf';
        await _dio.download(url, cachePath);
        debugPrint('DownloadManager: Pre-cached font $font/$range');
      } catch (e) {
        // Silently skip if fonts can't be fetched (probably offline)
      }
    }
  }

  @override
  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel('Dispose');
    }
    _cancelTokens.clear();
    _dio.close();
    super.dispose();
  }
}

// ─── Extension to attach regionId since copyWith loses it ───────────────────

extension _WithId on RegionDownloadState {
  RegionDownloadState _withId(String id) => RegionDownloadState(
    regionId: id,
    status: status,
    progress: progress,
    errorMessage: errorMessage,
  );
}
