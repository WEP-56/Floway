import 'bridge.dart';

/// Native counters restart with each runtime generation. Keep observed totals
/// across applies, and derive rates from elapsed time rather than UI frames.
class TrafficTracker {
  CoreStatus? _previous;
  Duration? _sampledAt;
  Duration? _connectedAt;
  double uploadRate = 0;
  double downloadRate = 0;
  int sessionUpload = 0;
  int sessionDownload = 0;
  int totalUpload = 0;
  int totalDownload = 0;

  void sample(CoreStatus status, Duration now) {
    final previous = _previous;
    final previousTime = _sampledAt;
    _previous = status;
    _sampledAt = now;
    if (!status.running) {
      _connectedAt = null;
      uploadRate = downloadRate = 0;
      return;
    }
    if (previous == null || !previous.running) {
      _connectedAt = now;
      sessionUpload = sessionDownload = 0;
    }
    final sameRuntime =
        previous != null &&
        previous.running &&
        previous.generation == status.generation;
    final up = sameRuntime ? status.upload - previous.upload : status.upload;
    final down = sameRuntime
        ? status.download - previous.download
        : status.download;
    final deltaUp = up < 0 ? 0 : up;
    final deltaDown = down < 0 ? 0 : down;
    sessionUpload += deltaUp;
    sessionDownload += deltaDown;
    totalUpload += deltaUp;
    totalDownload += deltaDown;
    final seconds = previousTime == null
        ? 0.0
        : (now - previousTime).inMicroseconds / Duration.microsecondsPerSecond;
    // Applying/rolling back a configuration replaces counters. Do not invent
    // a transfer rate for bytes whose observation interval is unknown.
    uploadRate = sameRuntime && seconds > 0 ? deltaUp / seconds : 0;
    downloadRate = sameRuntime && seconds > 0 ? deltaDown / seconds : 0;
  }

  int uptime(Duration now) =>
      _connectedAt == null ? 0 : (now - _connectedAt!).inSeconds;

  bool fresh(Duration now) =>
      _sampledAt != null && now - _sampledAt! <= const Duration(seconds: 6);
}
