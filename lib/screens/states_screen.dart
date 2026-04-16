import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../download/download_manager.dart';
import '../download/download_state.dart';
import '../models/map_region.dart';
import '../services/offline_manager.dart';
import 'download_manager_screen.dart';
import 'vector_map_screen.dart';

import '../data/india_states.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Screen 2 — All states & regions list with dynamic fetching and per-state download controls.
class StatesScreen extends StatefulWidget {
  final String countryName;
  final String countryFlag;

  const StatesScreen({
    super.key,
    required this.countryName,
    required this.countryFlag,
  });

  @override
  State<StatesScreen> createState() => _StatesScreenState();
}

class _StatesScreenState extends State<StatesScreen> {
  static const Color _surface = Color(0xFF1B2330);
  static const Color _surfaceOverlay = Color(0xFF202938);
  static const Color _border = Color(0xFF2B3647);
  static const Color _primary = Color(0xFF4C8DFF);
  static const Color _success = Color(0xFF00C48C);
  static const Color _muted = Color(0xFF95A1B3);

  final TextEditingController _searchCtrl = TextEditingController();
  List<MapRegion> _allRegions = [];
  List<MapRegion> _filtered = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRegions();
    _searchCtrl.addListener(_filter);
  }

  Future<void> _fetchRegions() async {
    try {
      final countryParam = Uri.encodeComponent(widget.countryName);
      final response = await http.get(
        Uri.parse(
            'https://countriesnow.space/api/v0.1/countries/states/q?country=$countryParam'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['error'] == false) {
          final List<dynamic> states = data['data']['states'];

          final List<MapRegion> regions = states.map((s) {
            final stateName = s['name'];

            final MapRegion? match = kIndiaStates
                .where((r) =>
                    r.name.toLowerCase() == stateName.toLowerCase() ||
                    stateName.toLowerCase().contains(r.name.toLowerCase()))
                .firstOrNull;

            if (match != null) return match;

            return MapRegion(
              id: '${widget.countryName.toLowerCase()}_${stateName.toLowerCase().replaceAll(' ', '_')}',
              name: stateName,
              centerLat: 0.0,
              centerLng: 0.0,
              size: 'Unknown',
              mbtilesPath: '',
              downloadUrl: null,
            );
          }).toList();

          setState(() {
            _allRegions = regions;
            _filtered = regions;
            _isLoading = false;
          });
          return;
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.from(_allRegions)
          : _allRegions.where((r) => r.name.toLowerCase().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManager>();
    final downloadedCount = dm.downloadedRegionIds.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.countryFlag}  ${widget.countryName}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              if (!_isLoading)
                Text(
                  '${_allRegions.length} regions',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: 'Manage Downloads',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DownloadManagerScreen()),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            _buildStatsRow(downloadedCount, dm.activeDownloads),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: _primary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text('Loading regions...',
                              style: TextStyle(color: _muted, fontSize: 13)),
                        ],
                      ),
                    )
                  : _filtered.isEmpty && _searchCtrl.text.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: _surfaceOverlay,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(Icons.map_outlined,
                                    color: _muted, size: 24),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'No regions found',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'No regions available for this country',
                                style: TextStyle(color: _muted, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : _buildList(dm),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border, width: 0.5),
        ),
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: const InputDecoration(
            hintText: 'Search regions...',
            hintStyle: TextStyle(color: Color(0xFF5A6577), fontSize: 15),
            prefixIcon:
                Icon(Icons.search_rounded, color: _muted, size: 20),
            border: InputBorder.none,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(int downloaded, int active) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          _StatChip(
            icon: Icons.check_circle_outline_rounded,
            label: '$downloaded downloaded',
            color: _success,
          ),
          const SizedBox(width: 14),
          if (active > 0)
            _StatChip(
              icon: Icons.downloading_rounded,
              label: '$active downloading',
              color: _primary,
            )
          else
            _StatChip(
              icon: Icons.download_outlined,
              label: '${_allRegions.length - downloaded} available',
              color: _muted,
            ),
        ],
      ),
    );
  }

  Widget _buildList(DownloadManager dm) {
    if (_filtered.isEmpty) {
      return const Center(
        child: Text(
          'No regions match your search',
          style: TextStyle(color: _muted, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _filtered.length,
      itemBuilder: (ctx, i) {
        final region = _filtered[i];
        final state = dm.getState(region.id);
        return _StateCard(
          region: region,
          downloadState: state,
          onTap: () {
            if (state.isDownloaded) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => VectorMapScreen(region: region)),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('Download ${region.name} first to view the map'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
          onDownload: () async {
            try {
              await dm.startDownload(region);
              if (context.mounted) {
                final om = Provider.of<OfflineManager>(context, listen: false);
                await om.loadRegion(region);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VectorMapScreen(region: region),
                  ),
                );
              }
            } catch (e) {
              debugPrint('Download failed: $e');
            }
          },
          onCancel: () => dm.cancelDownload(region.id),
          onDelete: () => dm.deleteDownload(region.id),
        );
      },
    );
  }
}

// ─── Stat chip ───────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── State card ───────────────────────────────────────────────────────────────

class _StateCard extends StatelessWidget {
  static const Color _surface = Color(0xFF1B2330);
  static const Color _border = Color(0xFF2B3647);
  static const Color _primary = Color(0xFF4C8DFF);
  static const Color _success = Color(0xFF00C48C);
  static const Color _muted = Color(0xFF95A1B3);

  final MapRegion region;
  final RegionDownloadState downloadState;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _StateCard({
    required this.region,
    required this.downloadState,
    required this.onTap,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  Color get _avatarColor {
    final hue = (region.id.hashCode % 360).abs().toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.3).toColor();
  }

  String get _initials {
    final words = region.name.split(' ');
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}'.toUpperCase();
    return region.name.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDownloaded = downloadState.isDownloaded;
    final isActive = downloadState.isActive;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: _primary.withValues(alpha: 0.06),
          highlightColor: _primary.withValues(alpha: 0.03),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDownloaded
                    ? _success.withValues(alpha: 0.25)
                    : isActive
                        ? _primary.withValues(alpha: 0.25)
                        : _border.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _avatarColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          _initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            region.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          if (region.centerLat != 0.0)
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined,
                                    color: _muted, size: 12),
                                const SizedBox(width: 3),
                                Text(
                                  '${region.centerLat.toStringAsFixed(2)}°N, '
                                  '${region.centerLng.toStringAsFixed(2)}°E',
                                  style: const TextStyle(
                                      color: _muted, fontSize: 11),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),

                    // Action button
                    _buildActionButton(context),
                  ],
                ),

                // Progress bar
                if (isActive) ...[
                  const SizedBox(height: 10),
                  _ProgressBar(progress: downloadState.progress),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        downloadState.isQueued
                            ? 'Queued...'
                            : 'Downloading...',
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                      const Spacer(),
                      Text(
                        downloadState.percentText,
                        style: const TextStyle(
                          color: _primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],

                // Error message
                if (downloadState.hasError) ...[
                  const SizedBox(height: 6),
                  Text(
                    downloadState.errorMessage ?? 'Download failed. Tap to retry.',
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    // Downloaded
    if (downloadState.isDownloaded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _success.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: _success, size: 12),
                SizedBox(width: 4),
                Text(
                  'Ready',
                  style: TextStyle(
                    color: _success,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _confirmDelete(context),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 16),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.15), size: 18),
        ],
      );
    }

    // Downloading or queued
    if (downloadState.isActive) {
      return GestureDetector(
        onTap: onCancel,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(color: _primary.withValues(alpha: 0.3)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  value: downloadState.progress,
                  strokeWidth: 2.5,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(_primary),
                ),
              ),
              const Icon(Icons.close, color: Colors.white70, size: 12),
            ],
          ),
        ),
      );
    }

    // Error -> retry
    if (downloadState.hasError) {
      return GestureDetector(
        onTap: onDownload,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.refresh, color: Colors.redAccent, size: 18),
        ),
      );
    }

    // Not downloaded -> download
    return GestureDetector(
      onTap: onDownload,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _primary.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: _primary.withValues(alpha: 0.3)),
        ),
        child: const Icon(Icons.download_outlined,
            color: _primary, size: 18),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141922),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'Delete ${region.name}?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You\'ll need to re-download this map to use it offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 14),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onDelete();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Text('Delete',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Animated progress bar ────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final double progress;

  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 3,
        backgroundColor: Colors.white10,
        valueColor:
            const AlwaysStoppedAnimation(Color(0xFF4C8DFF)),
      ),
    );
  }
}
