import 'dart:ui';

import 'package:flame/components.dart';

/// Full-bleed dusk gradient. The shader is rebuilt only on resize.
class SkyBackground extends Component {
  static const top = Color(0xFF0B1426);
  static const middle = Color(0xFF1B2A4B);
  static const bottom = Color(0xFF3B3252);

  final Paint _paint = Paint();
  Rect _rect = Rect.zero;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _rect = Offset.zero & Size(size.x, size.y);
    _paint.shader = Gradient.linear(
      Offset.zero,
      Offset(0, size.y),
      const [top, middle, bottom],
      const [0, 0.55, 1],
    );
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(_rect, _paint);
}
