import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import '../models/map_download_models.dart';
import '../services/region_service.dart';

class CountryRegionsScreen extends StatefulWidget {
  final MapCountry country;

  const CountryRegionsScreen({super.key, required this.country});

  @override
  State<CountryRegionsScreen> createState() => _CountryRegionsScreenState();
}

class _CountryRegionsScreenState extends State<CountryRegionsScreen> {
  final Dio _dio = Dio();
  MapSortOption _sortOption = MapSortOption.nearest;
  final TextEditingController _searchController = TextEditingController();
  List<MapSubRegion> _filteredRegions = [];
  String? _expandedRegionId;
  Position? _currentPosition;

  // Download state tracking
  final Map<String, double> _progressMap = {};
  final Map<String, bool> _downloadingMap = {};
  final Map<String, CancelToken> _cancelTokenMap = {};

  @override
  void initState() {
    super.initState();
    _filteredRegions = List.from(widget.country.subRegions);
    _searchController.addListener(_filterRegions);
    _getCurrentLocation();
    _checkDownloadedFiles();

    // If country has no sub-regions, expand the data items view
    if (!widget.country.hasSubRegions) {
      _expandedRegionId = widget.country.id;
    }
  }

  Future<void> _checkDownloadedFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/mbtiles_cache');

    if (!await cacheDir.exists()) return;

    // Check country-level data items
    for (final item in widget.country.dataItems) {
      final filePath = '${cacheDir.path}/${item.id}.mbtiles';
      if (await File(filePath).exists()) {
        final isValid = await RegionService.validateMbTilesFile(filePath);
        if (isValid) {
          setState(() { _progressMap[item.id] = 1.0; });
        } else {
          // Delete incompatible files (e.g. previously downloaded vector/PBF tiles)
          try { await File(filePath).delete(); } catch (_) {}
        }
      }
    }

    // Check sub-region data items
    for (final region in widget.country.subRegions) {
      for (final item in region.dataItems) {
        final filePath = '${cacheDir.path}/${item.id}.mbtiles';
        if (await File(filePath).exists()) {
          final isValid = await RegionService.validateMbTilesFile(filePath);
          if (isValid) {
            setState(() { _progressMap[item.id] = 1.0; });
          } else {
            // Delete incompatible files (e.g. previously downloaded vector/PBF tiles)
            try { await File(filePath).delete(); } catch (_) {}
          }
        }
      }
    }
  }


  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition();
      if (mounted) {
        _sortRegions();
      }
    } catch (e) {
      debugPrint('Could not get location: $e');
    }
  }

  void _filterRegions() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredRegions = List.from(widget.country.subRegions);
      } else {
        _filteredRegions = widget.country.subRegions.where((region) {
          return region.name.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _sortRegions() {
    List<MapSubRegion> sorted = List.from(widget.country.subRegions);

    if (_sortOption == MapSortOption.alphabetical) {
      sorted.sort((a, b) => a.name.compareTo(b.name));
    } else if (_sortOption == MapSortOption.nearest && _currentPosition != null) {
      sorted.sort((a, b) {
        final distA = _calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          a.centerLat ?? 0,
          a.centerLng ?? 0,
        );
        final distB = _calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          b.centerLat ?? 0,
          b.centerLng ?? 0,
        );
        return distA.compareTo(distB);
      });
    }

    setState(() {
      _filteredRegions = sorted;
    });
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  void _onSortChanged(MapSortOption option) {
    setState(() {
      _sortOption = option;
    });
    _sortRegions();
  }

  void _toggleRegionExpansion(String regionId) {
    setState(() {
      if (_expandedRegionId == regionId) {
        _expandedRegionId = null;
      } else {
        _expandedRegionId = regionId;
      }
    });
  }

  Future<void> _downloadDataItem(MapDataItem item) async {
    setState(() {
      _downloadingMap[item.id] = true;
      _progressMap[item.id] = 0.0;
      _cancelTokenMap[item.id] = CancelToken();
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/mbtiles_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final filePath = '${cacheDir.path}/${item.id}.mbtiles';

      await _dio.download(
        item.url,
        filePath,
        cancelToken: _cancelTokenMap[item.id],
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progressMap[item.id] = received / total;
            });
          }
        },
      );

      setState(() {
        _downloadingMap[item.id] = false;
        _progressMap[item.id] = 1.0;
      });

      _showSnackBar('${item.type.displayName} downloaded successfully! You can now use it offline.', isSuccess: true);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _showSnackBar('Download cancelled');
      } else {
        String errorMsg = _getReadableError(e);
        _showSnackBar(errorMsg, isError: true);
      }
      setState(() {
        _downloadingMap[item.id] = false;
        _progressMap[item.id] = 0.0;
      });
    } catch (e) {
      _showSnackBar('Download failed. Please try again.', isError: true);
      setState(() {
        _downloadingMap[item.id] = false;
        _progressMap[item.id] = 0.0;
      });
    }
  }

  String _getReadableError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please try again.';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == 404) {
          return 'Map file not available on server.';
        } else if (statusCode == 403) {
          return 'Access denied to map file.';
        } else if (statusCode != null && statusCode >= 500) {
          return 'Server error. Please try again later.';
        }
        return 'Download failed (Error $statusCode).';
      case DioExceptionType.connectionError:
        return 'No internet connection.';
      default:
        return 'Download failed. Please try again.';
    }
  }

  void _showSnackBar(String message, {bool isSuccess = false, bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : (isSuccess ? Colors.green : null),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(),
        body: _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.arrow_back_ios_new, size: 18),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        widget.country.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextButton(
            onPressed: () {
              // TODO: Implement download all
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey[850],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              'Download All',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildSearchBar(),
        _buildSortTabs(),
        Expanded(child: _buildRegionsList()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search',
            hintStyle: TextStyle(color: Colors.grey[500]),
            prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildSortTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _buildSortTab('Nearest', MapSortOption.nearest),
            ),
            Expanded(
              child: _buildSortTab('A-Z', MapSortOption.alphabetical),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortTab(String label, MapSortOption option) {
    final isSelected = _sortOption == option;
    return GestureDetector(
      onTap: () => _onSortChanged(option),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey[700] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[500],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildRegionsList() {
    if (!widget.country.hasSubRegions) {
      // Country without sub-regions - show data items directly
      return _buildCountryDataItems();
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _filteredRegions.length,
      itemBuilder: (context, index) {
        final region = _filteredRegions[index];
        return _buildRegionTile(region);
      },
    );
  }

  Widget _buildCountryDataItems() {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        _buildRegionHeader(
          widget.country.name,
          widget.country.totalSize,
          widget.country.downloadStatusCode,
        ),
        ...widget.country.dataItems.map((item) => _buildDataItemTile(item)),
      ],
    );
  }

  Widget _buildRegionTile(MapSubRegion region) {
    final isExpanded = _expandedRegionId == region.id;

    return Column(
      children: [
        InkWell(
          onTap: () => _toggleRegionExpansion(region.id),
          child: _buildRegionHeader(
            region.name,
            region.totalSize,
            region.downloadStatusCode,
          ),
        ),
        if (isExpanded) ...[
          ...region.dataItems.map((item) => _buildDataItemTile(item)),
        ],
        if (!isExpanded)
          Divider(color: Colors.grey[850], height: 1, indent: 16),
      ],
    );
  }

  Widget _buildRegionHeader(String name, String size, String statusCode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  size,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (statusCode.isNotEmpty)
            Text(
              statusCode,
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDataItemTile(MapDataItem item) {
    final isDownloading = _downloadingMap[item.id] ?? false;
    final progress = _progressMap[item.id] ?? 0.0;
    final isDownloaded = progress >= 1.0 || item.isDownloaded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[850]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.type.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.size,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 13,
                  ),
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[800],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ],
              ],
            ),
          ),
          if (item.type == MapDataType.map && isDownloaded)
            TextButton(
              onPressed: () {
                // TODO: Navigate to map
                Navigator.pop(context);
              },
              child: const Text(
                'Go to the map',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 14,
                ),
              ),
            )
          else if (!isDownloaded && !isDownloading)
            IconButton(
              icon: const Icon(Icons.download, color: Colors.blue),
              onPressed: () => _downloadDataItem(item),
            )
          else if (isDownloading)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: () {
                _cancelTokenMap[item.id]?.cancel();
              },
            )
          else if (isDownloaded)
            const Icon(Icons.check_circle, color: Colors.green, size: 24),
        ],
      ),
    );
  }
}
