import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/game/render/chime_projection.dart';

void main() {
  final projection = ChimeProjection()
    ..fit(width: 390, height: 844, chimeBottom: -0.9, halfWidth: 0.07);

  test('puts the hook near the top, centered', () {
    projection.project(0, 0, 0);
    expect(projection.x, closeTo(195, 1e-9));
    expect(projection.y, closeTo(projection.hookY, 1e-9));
    expect(projection.hookY, closeTo(0.12 * 844, 1e-9));
  });

  test('nearer points draw larger, and higher when looking up', () {
    projection.project(0, -0.4, 0.05);
    final near = (y: projection.y, scale: projection.scale);
    projection.project(0, -0.4, -0.05);
    expect(near.scale, greaterThan(projection.scale));
    expect(near.y, lessThan(projection.y));
  });

  test('unproject inverts project at the same depth', () {
    for (final p in [(0.03, -0.42, 0.05), (-0.06, -0.1, -0.04), (0.0, -0.8, 0.0)]) {
      projection.project(p.$1, p.$2, p.$3);
      projection.unproject(projection.x, projection.y, projection.depth);
      expect(projection.worldX, closeTo(p.$1, 1e-9));
      expect(projection.worldY, closeTo(p.$2, 1e-9));
      expect(projection.worldZ, closeTo(p.$3, 1e-9));
    }
  });
}
