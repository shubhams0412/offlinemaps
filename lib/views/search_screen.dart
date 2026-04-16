import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/search_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SearchService _searchService = SearchService();

  List<dynamic> _results = [];
  bool _isLoading = false;
  String _errorMessage = '';
  String? _selectedCategory;

  void _performSearch(String query) async {
    if (query.trim().isEmpty && _selectedCategory == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _results = [];
    });

    try {
      // Get current position for nearest sorting
      final position = await _getCurrentPosition();
      
      final limit = (query.trim().isEmpty && _selectedCategory != null) ? 5 : 15;
      
      final results = await _searchService.searchPlaces(
        query, 
        category: _selectedCategory,
        userLat: position?.latitude,
        userLon: position?.longitude,
        limit: limit,
      );
      
      setState(() {
        _results = results;
        if (_results.isEmpty) {
          _errorMessage = 'No results found.';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<LatLng?> _getCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search for places...',
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _results = [];
                  _errorMessage = '';
                });
              },
            ),
          ),
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (val) {
             _performSearch(val);
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: _buildCategoryChips(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildChip('Hospital', 'hospital'),
          const SizedBox(width: 8),
          _buildChip('Petrol Pump', 'petrol_pump'),
        ],
      ),
    );
  }

  Widget _buildChip(String label, String category) {
    final isSelected = _selectedCategory == category;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedCategory = selected ? category : null;
        });
        if (_searchController.text.isNotEmpty || _selectedCategory != null) {
          _performSearch(_searchController.text);
        }
      },
      selectedColor: Colors.blue.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue : Colors.white70,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 16),
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Text('Type a location and press enter', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final place = _results[index];
        final displayName = place['display_name'] ?? 'Unknown location';
        final name = place['name'] ?? displayName.split(',').first;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFC4C7CC),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on, color: Colors.white, size: 20),
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          onTap: () {
            final lat = double.tryParse(place['lat']?.toString() ?? '0');
            final lon = double.tryParse(place['lon']?.toString() ?? '0');
            if (lat != null && lon != null) {
              Navigator.pop(context, LatLng(lat, lon));
            }
          },
        );
      },
    );
  }
}
