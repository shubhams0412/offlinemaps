/// Represents a type of map data that can be downloaded
enum MapDataType {
  map,
  navigationData,
  topographicData,
}

extension MapDataTypeExtension on MapDataType {
  String get displayName {
    switch (this) {
      case MapDataType.map:
        return 'Map';
      case MapDataType.navigationData:
        return 'Navigation Data';
      case MapDataType.topographicData:
        return 'Topographic Data';
    }
  }

  String get shortCode {
    switch (this) {
      case MapDataType.map:
        return 'M';
      case MapDataType.navigationData:
        return 'N';
      case MapDataType.topographicData:
        return 'T';
    }
  }
}

/// Represents a downloadable map data item (Map, Navigation, Topographic)
class MapDataItem {
  final String id;
  final MapDataType type;
  final String size;
  final String url;
  final bool isDownloaded;

  MapDataItem({
    required this.id,
    required this.type,
    required this.size,
    required this.url,
    this.isDownloaded = false,
  });

  factory MapDataItem.fromJson(Map<String, dynamic> json) {
    return MapDataItem(
      id: json['id'] as String,
      type: MapDataType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MapDataType.map,
      ),
      size: json['size'] as String,
      url: json['url'] as String,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
    );
  }

  MapDataItem copyWith({bool? isDownloaded}) {
    return MapDataItem(
      id: id,
      type: type,
      size: size,
      url: url,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }
}

/// Represents a sub-region (state/province) within a country
class MapSubRegion {
  final String id;
  final String name;
  final String totalSize;
  final List<MapDataItem> dataItems;
  final double? centerLat;
  final double? centerLng;

  MapSubRegion({
    required this.id,
    required this.name,
    required this.totalSize,
    required this.dataItems,
    this.centerLat,
    this.centerLng,
  });

  factory MapSubRegion.fromJson(Map<String, dynamic> json) {
    final dataItemsJson = json['dataItems'] as List<dynamic>? ?? [];
    return MapSubRegion(
      id: json['id'] as String,
      name: json['name'] as String,
      totalSize: json['totalSize'] as String? ?? json['size'] as String? ?? '0 MB',
      dataItems: dataItemsJson
          .map((item) => MapDataItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      centerLat: (json['centerLat'] as num?)?.toDouble(),
      centerLng: (json['centerLng'] as num?)?.toDouble(),
    );
  }

  int get downloadedCount => dataItems.where((item) => item.isDownloaded).length;
  bool get isFullyDownloaded => dataItems.isNotEmpty && downloadedCount == dataItems.length;
  bool get hasAnyDownloaded => downloadedCount > 0;

  String get downloadStatusCode {
    String code = '';
    for (final item in dataItems) {
      if (item.isDownloaded) {
        code += item.type.shortCode;
      }
    }
    return code;
  }
}

/// Represents a country with its flag, regions, and download status
class MapCountry {
  final String id;
  final String name;
  final String flagEmoji;
  final String totalSize;
  final List<MapSubRegion> subRegions;
  final List<MapDataItem> dataItems; // For countries without sub-regions
  final double? centerLat;
  final double? centerLng;

  MapCountry({
    required this.id,
    required this.name,
    required this.flagEmoji,
    required this.totalSize,
    this.subRegions = const [],
    this.dataItems = const [],
    this.centerLat,
    this.centerLng,
  });

  factory MapCountry.fromJson(Map<String, dynamic> json) {
    final subRegionsJson = json['subRegions'] as List<dynamic>? ?? [];
    final dataItemsJson = json['dataItems'] as List<dynamic>? ?? [];

    return MapCountry(
      id: json['id'] as String,
      name: json['name'] as String,
      flagEmoji: json['flagEmoji'] as String? ?? '🌍',
      totalSize: json['totalSize'] as String? ?? json['size'] as String? ?? '0 MB',
      subRegions: subRegionsJson
          .map((region) => MapSubRegion.fromJson(region as Map<String, dynamic>))
          .toList(),
      dataItems: dataItemsJson
          .map((item) => MapDataItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      centerLat: (json['centerLat'] as num?)?.toDouble(),
      centerLng: (json['centerLng'] as num?)?.toDouble(),
    );
  }

  bool get hasSubRegions => subRegions.isNotEmpty;

  int get downloadedSubRegionsCount {
    if (!hasSubRegions) return 0;
    return subRegions.where((r) => r.hasAnyDownloaded).length;
  }

  String get downloadProgress {
    if (hasSubRegions) {
      return '$downloadedSubRegionsCount/${subRegions.length}';
    }
    return '';
  }

  String get downloadStatusCode {
    if (!hasSubRegions && dataItems.isNotEmpty) {
      String code = '';
      for (final item in dataItems) {
        if (item.isDownloaded) {
          code += item.type.shortCode;
        }
      }
      return code;
    }
    return '';
  }
}

/// Sorting options for map lists
enum MapSortOption {
  nearest,
  alphabetical,
}
