/// All possible states a region's download can be in.
enum DownloadStatus {
  notDownloaded,
  queued,
  downloading,
  downloaded,
  error,
}

/// Immutable snapshot of a single region's download state.
class RegionDownloadState {
  final String regionId;
  final DownloadStatus status;

  /// Progress from 0.0 (started) → 1.0 (complete).
  final double progress;

  /// Human-readable error description, set only when status == error.
  final String? errorMessage;

  const RegionDownloadState({
    required this.regionId,
    this.status = DownloadStatus.notDownloaded,
    this.progress = 0.0,
    this.errorMessage,
  });

  RegionDownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    String? errorMessage,
  }) {
    return RegionDownloadState(
      regionId: regionId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
    );
  }

  // ── Convenience getters ──────────────────────────────────────────────────

  bool get isNotDownloaded => status == DownloadStatus.notDownloaded;
  bool get isQueued        => status == DownloadStatus.queued;
  bool get isDownloading   => status == DownloadStatus.downloading;
  bool get isDownloaded    => status == DownloadStatus.downloaded;
  bool get hasError        => status == DownloadStatus.error;
  bool get isActive        => isQueued || isDownloading;

  /// Percentage string for UI display, e.g. "45%"
  String get percentText => '${(progress * 100).round()}%';
}
