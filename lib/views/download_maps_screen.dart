import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../models/map_download_models.dart';
import '../services/region_service.dart';
import 'country_regions_screen.dart';

class DownloadMapsScreen extends StatefulWidget {
  const DownloadMapsScreen({super.key});

  @override
  State<DownloadMapsScreen> createState() => _DownloadMapsScreenState();
}

class _DownloadMapsScreenState extends State<DownloadMapsScreen> {
  List<MapCountry> _countries = [];
  List<MapCountry> _filteredCountries = [];
  bool _isLoading = true;
  bool _isUpdatingAll = false;
  String? _loadError;
  MapSortOption _sortOption = MapSortOption.nearest;
  final TextEditingController _searchController = TextEditingController();
  final Dio _dio = Dio();
  Position? _currentPosition;

  // Track downloaded items
  final Set<String> _downloadedItems = {};

  @override
  void initState() {
    super.initState();
    _loadCountries();
    _getCurrentLocation();
    _searchController.addListener(_filterCountries);
  }

  @override
  void dispose() {
    _dio.close();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      _currentPosition = await Geolocator.getCurrentPosition();
      if (mounted) {
        _sortCountries();
      }
    } catch (e) {
      debugPrint('Could not get location: $e');
    }
  }

  Future<void> _loadCountries() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final String jsonString = await rootBundle.loadString('assets/regions.json');
      final Map<String, dynamic> data = json.decode(jsonString);
      final List<dynamic> countriesJson = data['countries'] as List<dynamic>;

      _countries = countriesJson
          .map((c) => MapCountry.fromJson(c as Map<String, dynamic>))
          .toList();

      await _checkDownloadedFiles();
      _sortCountries();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to load countries: $e');
      setState(() {
        _isLoading = false;
        _loadError = 'Failed to load map data: $e';
      });
    }
  }

  Future<void> _checkDownloadedFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/mbtiles_cache');

    if (!await cacheDir.exists()) return;

    _downloadedItems.clear();

    for (final country in _countries) {
      // Check country-level data items
      for (final item in country.dataItems) {
        final filePath = '${cacheDir.path}/${item.id}.mbtiles';
        if (await File(filePath).exists()) {
          final isValid = await RegionService.validateMbTilesFile(filePath);
          if (isValid) {
            _downloadedItems.add(item.id);
          } else {
            // Delete incompatible files (e.g. previously downloaded vector/PBF tiles)
            try { await File(filePath).delete(); } catch (_) {}
          }
        }
      }

      // Check sub-region data items
      for (final region in country.subRegions) {
        for (final item in region.dataItems) {
          final filePath = '${cacheDir.path}/${item.id}.mbtiles';
          if (await File(filePath).exists()) {
            final isValid = await RegionService.validateMbTilesFile(filePath);
            if (isValid) {
              _downloadedItems.add(item.id);
            } else {
              // Delete incompatible files (e.g. previously downloaded vector/PBF tiles)
              try { await File(filePath).delete(); } catch (_) {}
            }
          }
        }
      }
    }
  }

  void _filterCountries() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCountries = List.from(_countries);
      } else {
        _filteredCountries = _countries.where((country) {
          return country.name.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _sortCountries() {
    List<MapCountry> sorted = List.from(_countries);

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
      _countries = sorted;
      _filterCountries();
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
    _sortCountries();
  }

  Future<void> _openCountryDetail(MapCountry country) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CountryRegionsScreen(country: country),
      ),
    );
    // Refresh download status when returning
    await _checkDownloadedFiles();
    setState(() {});
  }

  List<MapDataItem> _getDownloadedDataItems() {
    final downloadedItems = <String, MapDataItem>{};

    for (final country in _countries) {
      for (final item in country.dataItems) {
        if (_downloadedItems.contains(item.id)) {
          downloadedItems[item.id] = item;
        }
      }

      for (final region in country.subRegions) {
        for (final item in region.dataItems) {
          if (_downloadedItems.contains(item.id)) {
            downloadedItems[item.id] = item;
          }
        }
      }
    }

    return downloadedItems.values.toList();
  }

  Future<void> _updateAllDownloads() async {
    if (_isUpdatingAll) return;

    final itemsToUpdate = _getDownloadedDataItems();
    if (itemsToUpdate.isEmpty) {
      _showSnackBar('No downloaded maps to update.');
      return;
    }

    setState(() {
      _isUpdatingAll = true;
    });

    int successCount = 0;
    int failureCount = 0;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/mbtiles_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      await Future.wait(itemsToUpdate.map((item) async {
        final filePath = '${cacheDir.path}/${item.id}.mbtiles';
        final tempPath = '$filePath.tmp';
        final tempFile = File(tempPath);
        final targetFile = File(filePath);

        try {
          await _dio.download(
            item.url,
            tempPath,
            options: Options(
              responseType: ResponseType.bytes,
            ),
            deleteOnError: true,
          );

          final isValid = await RegionService.validateMbTilesFile(tempPath);
          if (!isValid) {
            throw Exception('Invalid MBTiles file');
          }

          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await tempFile.rename(filePath);
          successCount++;
        } catch (_) {
          failureCount++;
          if (await tempFile.exists()) {
            try {
              await tempFile.delete();
            } catch (_) {}
          }
        }
      }));

      await _checkDownloadedFiles();
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingAll = false;
        });
      }
    }

    if (!mounted) return;

    if (failureCount == 0) {
      _showSnackBar(
        successCount == 1
            ? '1 map updated successfully.'
            : '$successCount maps updated successfully.',
        isSuccess: true,
      );
      return;
    }

    _showSnackBar(
      successCount == 0
          ? 'Failed to update maps. Please try again.'
          : 'Updated $successCount maps. $failureCount failed.',
      isError: successCount == 0,
    );
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
      title: const Text(
        'Download Maps',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: false,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextButton(
            onPressed: (_isLoading || _isUpdatingAll) ? null : _updateAllDownloads,
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey[850],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              _isUpdatingAll ? 'Updating...' : 'Update All',
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
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _loadError!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadCountries,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildSearchBar(),
        _buildSortTabs(),
        Expanded(child: _buildCountryList()),
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

  Widget _buildCountryList() {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _filteredCountries.length,
      separatorBuilder: (context, index) => Divider(
        color: Colors.grey[850],
        height: 1,
        indent: 70,
      ),
      itemBuilder: (context, index) {
        final country = _filteredCountries[index];
        return _buildCountryTile(country);
      },
    );
  }

  Widget _buildCountryTile(MapCountry country) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Text(
        country.flagEmoji,
        style: const TextStyle(fontSize: 28),
      ),
      title: Text(
        country.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: country.hasSubRegions
          ? Text(
              country.totalSize,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 13,
              ),
            )
          : null,
      trailing: _buildTrailing(country),
      onTap: () => _openCountryDetail(country),
    );
  }

  Widget _buildTrailing(MapCountry country) {
    if (country.hasSubRegions) {
      // Count downloaded regions
      int downloadedCount = 0;
      for (final region in country.subRegions) {
        bool hasAnyDownloaded = region.dataItems.any((item) => _downloadedItems.contains(item.id));
        if (hasAnyDownloaded) downloadedCount++;
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$downloadedCount/${country.subRegions.length}',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            color: Colors.grey[500],
            size: 20,
          ),
        ],
      );
    } else {
      // Show download status code (M, N, T) for countries without sub-regions
      String statusCode = '';
      for (final item in country.dataItems) {
        if (_downloadedItems.contains(item.id)) {
          statusCode += item.type.shortCode;
        }
      }

      if (statusCode.isNotEmpty) {
        return Text(
          statusCode,
          style: const TextStyle(
            color: Colors.blue,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        );
      }
      return const SizedBox.shrink();
    }
  }
}
