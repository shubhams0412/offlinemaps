/// Represents a single downloadable/offline map region (state or UT).
class MapRegion {
  final String id;
  final String name;
  final double centerLat;
  final double centerLng;
  final double defaultZoom;

  /// Human-readable download size estimate
  final String size;

  /// Absolute path to the local .mbtiles file.
  /// e.g. /mbtiles/india_gujarat.mbtiles
  /// In a real app this would be under getApplicationDocumentsDirectory().
  final String mbtilesPath;

  /// URL to download the MBTiles file from.
  /// Set to null or empty to disable real download (demo mode).
  final String? downloadUrl;

  const MapRegion({
    required this.id,
    required this.name,
    required this.centerLat,
    required this.centerLng,
    required this.size,
    required this.mbtilesPath,
    this.defaultZoom = 20.0,
    this.downloadUrl,
  });

  /// Whether this region has a real download URL configured.
  bool get hasDownloadUrl => downloadUrl != null && downloadUrl!.isNotEmpty;
}
