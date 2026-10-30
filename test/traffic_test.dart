import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/traffic.dart';

CoreStatus running(int generation, int upload, int download) => CoreStatus(
  state: CoreState.running,
  generation: generation,
  upload: upload,
  download: download,
);

void main() {
  test('rates use native sample interval and totals count each byte once', () {
    final tracker = TrafficTracker();
    tracker.sample(running(1, 0, 0), Duration.zero);
    tracker.sample(running(1, 4096, 8192), const Duration(seconds: 2));
    expect(tracker.uploadRate, 2048);
    expect(tracker.downloadRate, 4096);
    tracker.sample(running(1, 4096, 8192), const Duration(seconds: 3));
    expect(tracker.uploadRate, 0);
    expect(tracker.totalUpload, 4096);
    expect(tracker.totalDownload, 8192);
    expect(tracker.uptime(const Duration(seconds: 8)), 8);
    expect(tracker.fresh(const Duration(seconds: 10)), isFalse);
  });

  test(
    'apply counter reset preserves totals; stop resets uptime and next session',
    () {
      final tracker = TrafficTracker();
      tracker.sample(running(1, 100, 200), Duration.zero);
      tracker.sample(running(2, 10, 20), const Duration(seconds: 2));
      expect(tracker.uploadRate, 0);
      expect(tracker.totalUpload, 110);
      expect(tracker.sessionDownload, 220);
      tracker.sample(const CoreStatus(), const Duration(seconds: 3));
      expect(tracker.uptime(const Duration(seconds: 9)), 0);
      tracker.sample(running(3, 5, 6), const Duration(seconds: 10));
      expect(tracker.totalUpload, 115);
      expect(tracker.sessionUpload, 5);
      expect(tracker.sessionDownload, 6);
    },
  );

  test('unexpected decreasing counters never create negative traffic', () {
    final tracker = TrafficTracker();
    tracker.sample(running(1, 100, 200), Duration.zero);
    tracker.sample(running(1, 0, 0), const Duration(seconds: 1));
    expect(tracker.totalUpload, 100);
    expect(tracker.uploadRate, 0);
  });
}
