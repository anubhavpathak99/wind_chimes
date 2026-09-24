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

  ChimeProjection fitted() =>
      ChimeProjection()..fit(width: 390, height: 844, chimeBottom: -0.9, halfWidth: 0.07);

  void settle(ChimeProjection p, {required double minX, required double maxX, double minY = -0.9}) {
    for (var i = 0; i < 900; i++) {
      p.follow(minX: minX, maxX: maxX, minY: minY, dt: 1 / 60);
    }
  }

  test('at rest, following keeps the fitted framing', () {
    final p = fitted();
    final hookY = p.hookY;
    settle(p, minX: -0.07, maxX: 0.07);
    expect(p.zoom, closeTo(1, 1e-9));
    expect(p.panX, closeTo(0, 1e-9));
    expect(p.hookY, closeTo(hookY, 1e-6));
  });

  test('a chime blown sideways is panned to, zoomed out and centered', () {
    final p = fitted();
    settle(p, minX: 0.05, maxX: 0.7, minY: -0.6);
    expect(p.panX, closeTo(0.35, 0.01));
    expect(p.zoom, lessThan(1));
    p.project(0, 0, 0);
    expect(p.y, closeTo(p.hookY, 1e-9));
    expect(p.hookY, greaterThan(0.12 * 844));
    for (final x in [0.0, 0.7]) {
      p.project(x, -0.3, 0);
      expect(p.x, inInclusiveRange(0, 390));
    }
    p.project(0.35, -0.6, 0);
    expect(p.y, lessThan(844 * 0.9));
  });

  test('a gust peak widens the frame at once and it relaxes slowly', () {
    final p = fitted();
    settle(p, minX: -0.07, maxX: 0.07);
    p.follow(minX: -0.07, maxX: 0.8, minY: -0.9, dt: 1 / 60);
    for (var i = 0; i < 60; i++) {
      p.follow(minX: -0.07, maxX: 0.07, minY: -0.9, dt: 1 / 60);
    }
    expect(p.panX, greaterThan(0.1));
  });

  test('unproject inverts project with the camera panned and zoomed', () {
    final p = fitted();
    settle(p, minX: -0.1, maxX: 0.9, minY: -0.7);
    p.project(0.3, -0.4, 0.02);
    p.unproject(p.x, p.y, p.depth);
    expect(p.worldX, closeTo(0.3, 1e-9));
    expect(p.worldY, closeTo(-0.4, 1e-9));
    expect(p.worldZ, closeTo(0.02, 1e-9));
  });
}
