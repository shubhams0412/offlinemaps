import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/india_states.dart';
import '../download/download_manager.dart';
import '../storage/storage_manager.dart';

/// Shows all downloaded maps with size info and delete controls.
class DownloadManagerScreen extends StatefulWidget {
  const DownloadManagerScreen({super.key});

  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen> {
  static const Color _surfaceOverlay = Color(0xFF202938);
  static const Color _border = Color(0xFF2B3647);
  static const Color _primary = Color(0xFF4C8DFF);
  static const Color _muted = Color(0xFF95A1B3);

  final Map<String, int> _fileSizes = {};

  @override
  void initState() {
    super.initState();
    _loadSizes();
  }

  Future<void> _loadSizes() async {
    final storage = context.read<StorageManager>();
    for (final region in kIndiaStates) {
      final size = await storage.getFileSize(region.id);
      if (mounted) setState(() => _fileSizes[region.id] = size);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadManager>(
      builder: (ctx, dm, _) {
        final downloaded = kIndiaStates
            .where((r) => dm.getState(r.id).isDownloaded)
            .toList();

        final totalBytes = _fileSizes.values.fold(0, (a, b) => a + b);

        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Offline Maps',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${downloaded.length} maps downloaded',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
            actions: [
              if (downloaded.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClearAll(dm),
                  child: const Text(
                    'Clear All',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          body: downloaded.isEmpty
              ? _buildEmpty()
              : Column(
                  children: [
                    _buildStorageHeader(totalBytes, downloaded.length),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: downloaded.length,
                        itemBuilder: (ctx, i) {
                          final region = downloaded[i];
                          final size = _fileSizes[region.id] ?? 0;
                          return _DownloadedCard(
                            regionName: region.name,
                            regionId: region.id,
                            fileSize: size,
                            onDelete: () => _deleteRegion(dm, region.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildStorageHeader(int totalBytes, int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2635), Color(0xFF141922)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storage_outlined,
                color: _primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Storage Used',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  StorageManager.formatBytes(totalBytes),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _surfaceOverlay,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'maps',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _surfaceOverlay,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.map_outlined, color: _muted, size: 36),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Offline Maps',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Download maps from the\nregions list to use them offline.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRegion(DownloadManager dm, String regionId) async {
    await dm.deleteDownload(regionId);
    if (!mounted) return;
    setState(() => _fileSizes[regionId] = 0);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Map deleted')),
    );
  }

  Future<void> _confirmClearAll(DownloadManager dm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2330),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear All Downloads?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This will delete all offline maps. You\'ll need to re-download them to use offline.',
          style: TextStyle(color: _muted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete All',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await dm.clearAllDownloads();
      if (!mounted) return;
      setState(() => _fileSizes.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All offline maps cleared')),
      );
    }
  }
}

// ─── Downloaded map card ─────────────────────────────────────────────────────

class _DownloadedCard extends StatelessWidget {
  static const Color _surface = Color(0xFF1B2330);
  static const Color _success = Color(0xFF00C48C);

  final String regionName;
  final String regionId;
  final int fileSize;
  final VoidCallback onDelete;

  const _DownloadedCard({
    required this.regionName,
    required this.regionId,
    required this.fileSize,
    required this.onDelete,
  });

  Color get _avatarColor {
    final hue = (regionId.hashCode % 360).abs().toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.3).toColor();
  }

  String get _initials {
    final words = regionName.split(' ');
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}'.toUpperCase();
    return regionName.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _success.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Row(
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

          // Name & size
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  regionName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.cloud_done_outlined,
                        color: _success, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      'Downloaded  ·  ${StorageManager.formatBytes(fileSize)}',
                      style: const TextStyle(
                        color: _success,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Delete button
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 18),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
