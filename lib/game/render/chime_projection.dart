import 'dart:math' as math;

/// Maps the simulation's world (meters; x right, y up, z toward the viewer) to canvas pixels,
/// and back.
///
/// Orthographic with the camera pitched up by [pitch], since you look up at a hanging chime, plus
/// a weak perspective scale so nearer tubes read slightly larger. [follow] pans and, if needed,
/// zooms out so a chime blown sideways stays in frame. Results are written to fields ([x], [y],
/// [scale], [depth] and [worldX], [worldY], [worldZ]) so projecting never allocates.
class ChimeProjection {
  ChimeProjection({this.pitch = 10 * math.pi / 180, this.viewDistance = 2.5})
      : _cos = math.cos(pitch),
        _sin = math.sin(pitch);

  final double pitch;

  /// Camera distance for the perspective scale, meters.
  final double viewDistance;

  final double _cos;
  final double _sin;

  /// Scale with the camera at rest. Renderers build shaders for this and apply [zoom] on the
  /// canvas.
  double basePixelsPerMeter = 1;

  /// At most 1; below 1 when the chime swings wider than the screen.
  double zoom = 1;

  /// World x at the middle of the screen.
  double panX = 0;

  double get pixelsPerMeter => basePixelsPerMeter * zoom;

  double _width = 0;
  double _centerX = 0;
  double _height = 0;
  double _viewHeight = 0;
  double _lo = 0;
  double _hi = 0;
  double _bottom = 0;

  static const _topMargin = 0.12;
  static const _heightFill = 0.72;
  double _pivotScreenY = 0;
  double _pivotWorldY = 0;

  /// Canvas y of the hook (world origin). Near the top at rest; lower when [follow] zooms out.
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
    final extent = -chimeBottom;
    basePixelsPerMeter =
        math.min(_heightFill * height / extent, 0.5 * width / (2 * halfWidth));
    zoom = 1;
    panX = 0;
    _lo = -halfWidth;
    _hi = halfWidth;
    _bottom = chimeBottom;
    // Keep the share of the screen left visible (by an open sheet, say) across a resize.
    _viewHeight = _height > 0 ? height * _viewHeight / _height : height;
    _width = width;
    _height = height;
    _centerX = width / 2;
    hookY = _topMargin * height;
    _pivotWorldY = chimeBottom / 2;
    _placePivot();
  }

  /// How much of the canvas, from the top, is not covered by something like an open sheet, pixels.
  /// [follow] frames the chime within it, shrinking it if needed. At least 40% of the canvas.
  double get visibleHeight => _viewHeight;
  set visibleHeight(double value) => _viewHeight = value.clamp(0.4 * _height, _height);

  /// Eases the camera toward framing the box from the hook down to [minY] and across
  /// [minX]..[maxX] (the hook included): the box is fitted into the viewing area, zooming out but
  /// never in past the fitted scale, and centered in it. At rest this is exactly [fit]'s framing;
  /// a chime blown sideways is wide and short, so it zooms out and moves toward the middle. The
  /// box is tracked as an envelope that widens at once and narrows slowly, so gust peaks stay in
  /// frame without the camera hunting.
  void follow({
    required double minX,
    required double maxX,
    required double minY,
    required double dt,
  }) {
    const panSeconds = 0.5;
    const zoomSeconds = 0.8;
    const releaseSeconds = 4.0;
    const widthFill = 0.85;
    final release = 1 - math.exp(-dt / releaseSeconds);
    final lo = math.min(minX, 0.0), hi = math.max(maxX, 0.0), bottom = math.min(minY, 0.0);
    _lo = lo < _lo ? lo : _lo + (lo - _lo) * release;
    _hi = hi > _hi ? hi : _hi + (hi - _hi) * release;
    _bottom = bottom < _bottom ? bottom : _bottom + (bottom - _bottom) * release;

    final areaHeight = _heightFill * _viewHeight;
    final boxWidth = (_hi - _lo) * basePixelsPerMeter;
    final boxHeight = -_bottom * basePixelsPerMeter;
    var targetZoom = 1.0;
    if (boxWidth > 0) targetZoom = math.min(targetZoom, widthFill * _width / boxWidth);
    if (boxHeight > 0) targetZoom = math.min(targetZoom, areaHeight / boxHeight);
    final zoomStep = 1 - math.exp(-dt / zoomSeconds);
    zoom += (targetZoom - zoom) * zoomStep;
    final targetHookY =
        _topMargin * _viewHeight + math.max(0.0, areaHeight - boxHeight * zoom) / 2;
    hookY += (targetHookY - hookY) * zoomStep;
    panX += ((_lo + _hi) / 2 - panX) * (1 - math.exp(-dt / panSeconds));
    _placePivot();
  }

  /// Solves for the pivot's canvas y that puts the hook exactly at [hookY].
  void _placePivot() {
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
    x = _centerX + (wx - panX) * k;
    y = _pivotScreenY - up * k;
  }

  /// Inverse of [project] for a canvas point on the plane at [atDepth].
  void unproject(double sx, double sy, double atDepth) {
    final k = pixelsPerMeter * viewDistance / (viewDistance - atDepth);
    final up = -(sy - _pivotScreenY) / k;
    worldX = (sx - _centerX) / k + panX;
    worldY = up * _cos - atDepth * _sin + _pivotWorldY;
    worldZ = up * _sin + atDepth * _cos;
  }
}
