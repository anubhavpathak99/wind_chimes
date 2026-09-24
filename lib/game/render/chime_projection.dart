import 'dart:math' as math;

/// Maps the simulation's world (meters; x right, y up, z toward the viewer) to canvas pixels,
/// and back.
///
/// Orthographic with the camera pitched up by [pitch], since you look up at a hanging chime, plus
/// a weak perspective scale so nearer tubes read slightly larger. Results are written to fields
/// ([x], [y], [scale], [depth] and [worldX], [worldY], [worldZ]) so projecting never allocates.
class ChimeProjection {
  ChimeProjection({this.pitch = 10 * math.pi / 180, this.viewDistance = 2.5})
      : _cos = math.cos(pitch),
        _sin = math.sin(pitch);

  final double pitch;

  /// Camera distance for the perspective scale, meters.
  final double viewDistance;

  final double _cos;
  final double _sin;

  double pixelsPerMeter = 1;
  double _centerX = 0;
  double _pivotScreenY = 0;
  double _pivotWorldY = 0;

  /// Canvas y of the hook (world origin).
  double hookY = 0;

  double x = 0;
  double y = 0;
  double scale = 1;

  /// Toward the viewer is positive, relative to the chime's middle.
  double depth = 0;

  double worldX = 0;
  double worldY = 0;
  double worldZ = 0;

  /// Places the hook near the top of a [width]×[height] canvas and scales the chime, which hangs
  /// from y = 0 down to [chimeBottom] and spans ±[halfWidth], to fill most of the height.
  void fit({
    required double width,
    required double height,
    required double chimeBottom,
    required double halfWidth,
  }) {
    const topMargin = 0.12;
    const heightFill = 0.72;
    const widthFill = 0.5;
    final extent = -chimeBottom;
    pixelsPerMeter = math.min(heightFill * height / extent, widthFill * width / (2 * halfWidth));
    _centerX = width / 2;
    hookY = topMargin * height;
    _pivotWorldY = chimeBottom / 2;
    // Solve for the pivot's canvas y that puts the hook exactly at [hookY].
    final hookUp = -_pivotWorldY * _cos;
    final hookDepth = _pivotWorldY * _sin;
    _pivotScreenY =
        hookY + hookUp * pixelsPerMeter * viewDistance / (viewDistance - hookDepth);
  }

  void project(double wx, double wy, double wz) {
    final ry = wy - _pivotWorldY;
    final up = ry * _cos + wz * _sin;
    depth = wz * _cos - ry * _sin;
    scale = viewDistance / (viewDistance - depth);
    final k = pixelsPerMeter * scale;
    x = _centerX + wx * k;
    y = _pivotScreenY - up * k;
  }

  /// Inverse of [project] for a canvas point on the plane at [atDepth].
  void unproject(double sx, double sy, double atDepth) {
    final k = pixelsPerMeter * viewDistance / (viewDistance - atDepth);
    final up = -(sy - _pivotScreenY) / k;
    worldX = (sx - _centerX) / k;
    worldY = up * _cos - atDepth * _sin + _pivotWorldY;
    worldZ = up * _sin + atDepth * _cos;
  }
}
