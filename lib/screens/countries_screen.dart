import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'states_screen.dart';

class CountriesScreen extends StatefulWidget {
  const CountriesScreen({super.key});

  @override
  State<CountriesScreen> createState() => _CountriesScreenState();
}

class _CountriesScreenState extends State<CountriesScreen> {
  static const Color _surface = Color(0xFF1B2330);
  static const Color _border = Color(0xFF2B3647);
  static const Color _primary = Color(0xFF4C8DFF);
  static const Color _muted = Color(0xFF95A1B3);

  List<dynamic> _allCountries = [];
  List<dynamic> _countries = [];
  bool _isLoading = true;
  bool _hasError = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCountries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCountries() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final response = await http.get(
        Uri.parse('https://restcountries.com/v3.1/all?fields=name,flag,region'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        data.sort(
          (a, b) => (a['name']['common'] ?? '').toString().compareTo(
                (b['name']['common'] ?? '').toString(),
              ),
        );
        setState(() {
          _allCountries = data;
          _countries = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _filterCountries(String query) {
    if (query.isEmpty) {
      setState(() => _countries = _allCountries);
    } else {
      setState(() {
        _countries = _allCountries.where((country) {
          final name =
              (country['name']['common'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase());
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4C8DFF), Color(0xFF3A6FD8)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.public, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offline Maps',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Select a country to download',
                          style: TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border, width: 0.5),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Search countries...',
                    hintStyle: TextStyle(color: Color(0xFF5A6577), fontSize: 15),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: _muted, size: 20),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                  ),
                  onChanged: _filterCountries,
                ),
              ),
            ),

            // Section label
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'AVAILABLE REGIONS',
                    style: TextStyle(
                      color: _muted.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!_isLoading)
                    Text(
                      '${_countries.length}',
                      style: TextStyle(
                        color: _primary.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),

            // Country list
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : _hasError
                      ? _buildErrorState()
                      : _countries.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _countries.length,
                              itemBuilder: (context, index) {
                                final country = _countries[index];
                                return _CountryCard(
                                  flag: country['flag'] ?? '',
                                  name:
                                      country['name']['common'] ?? 'Unknown',
                                  region: country['region'] ?? 'Unknown',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StatesScreen(
                                        countryName:
                                            country['name']['common'] ??
                                                'Unknown',
                                        countryFlag:
                                            country['flag'] ?? '',
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Loading countries...',
            style: TextStyle(color: _muted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.wifi_off_rounded,
                color: Colors.redAccent, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'Failed to load countries',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Check your internet connection',
            style: TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _fetchCountries,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: TextButton.styleFrom(foregroundColor: _primary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'No countries match your search',
        style: TextStyle(color: _muted, fontSize: 14),
      ),
    );
  }
}

class _CountryCard extends StatelessWidget {
  static const Color _surface = Color(0xFF1B2330);
  static const Color _surfaceOverlay = Color(0xFF202938);
  static const Color _border = Color(0xFF2B3647);
  static const Color _primary = Color(0xFF4C8DFF);
  static const Color _muted = Color(0xFF95A1B3);

  final String flag;
  final String name;
  final String region;
  final VoidCallback onTap;

  const _CountryCard({
    required this.flag,
    required this.name,
    required this.region,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: _primary.withValues(alpha: 0.08),
          highlightColor: _primary.withValues(alpha: 0.04),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.5),
            ),
            child: Row(
              children: [
                // Flag
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _surfaceOverlay,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(flag, style: const TextStyle(fontSize: 26)),
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _surfaceOverlay,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              region,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.2), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
