import 'package:devpulse_mobile/core/design_system/widgets/status_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 11, 10);
  const step = Duration(minutes: 30);

  test('inserts a null where buckets are missing, so lines break instead of bridging', () {
    final points = [(t0, 1.0), (t0.add(step), 2.0), (t0.add(step * 5), 3.0)];
    final out = fillGaps(points, step);
    expect(out.map((p) => p.$2), [1.0, 2.0, null, 3.0]);
    expect(out[2].$1, t0.add(step * 2));
  });

  test('contiguous series and unknown steps are untouched', () {
    final points = [(t0, 1.0), (t0.add(step), 2.0)];
    expect(fillGaps(points, step), points);
    expect(fillGaps([(t0, 1.0), (t0.add(step * 9), 2.0)], Duration.zero), hasLength(2));
  });
}
