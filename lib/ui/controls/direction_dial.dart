import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../weather/wind_timeline.dart';

/// A compass for the manual wind: drag round it to set where the wind comes from. North is up,
/// as on a map; the arrow shows the way the wind blows.
class DirectionDial extends StatelessWidget {
  const DirectionDial({super.key, required this.from, required this.onChanged, this.size = 112});

  /// Degrees clockwise from north.
  final double from;
  final ValueChanged<double> onChanged;
  final double size;

  static const step = 5.0;

  void _setFrom(Offset p) {
    final dx = p.dx - size / 2, dy = p.dy - size / 2;
    if (dx * dx + dy * dy < 12 * 12) return;
    final degrees = math.atan2(dx, -dy) * 180 / math.pi;
    onChanged(((degrees / step).round() * step) % 360);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Wind direction',
      value: 'from ${WindReading.compassName(from)}, ${from.round()} degrees',
      increasedValue: 'from ${WindReading.compassName(from + 15)}',
      decreasedValue: 'from ${WindReading.compassName(from - 15)}',
      onIncrease: () => onChanged((from + 15) % 360),
      onDecrease: () => onChanged((from - 15) % 360),
      child: RawGestureDetector(
        gestures: {
          _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
            _EagerPan.new,
            (pan) => pan
              ..onDown = ((d) => _setFrom(d.localPosition))
              ..onUpdate = ((d) => _setFrom(d.localPosition)),
          ),
        },
        child: CustomPaint(
          size: Size.square(size),
          painter: _DialPainter(
            from: from,
            ring: scheme.outlineVariant,
            text: scheme.onSurfaceVariant,
            accent: scheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Claims the gesture on touch, so turning the dial never scrolls the sheet it sits in.
class _EagerPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.from, required this.ring, required this.text, required this.accent});

  final double from;
  final Color ring;
  final Color text;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ring;
    canvas.drawCircle(c, r, ringPaint);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(c + dir * (r - (i.isEven ? 7 : 4)), c + dir * r, ringPaint);
    }
    for (final (label, a) in [('N', 0.0), ('E', 90.0), ('S', 180.0), ('W', 270.0)]) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: TextStyle(color: text, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      final dir = Offset(math.sin(a * math.pi / 180), -math.cos(a * math.pi / 180));
      painter.paint(canvas, c + dir * (r - 17) - painter.size.center(Offset.zero));
    }

    // From the rim where the wind comes from, across to where it goes.
    final a = from * math.pi / 180;
    final dir = Offset(math.sin(a), -math.cos(a));
    final tail = c + dir * (r - 4), head = c - dir * (r - 22);
    final arrow = Paint()
      ..color = accent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tail, head, arrow);
    final side = Offset(-dir.dy, dir.dx);
    final tip = Path()
      ..moveTo(head.dx - dir.dx * 10, head.dy - dir.dy * 10)
      ..lineTo(head.dx + side.dx * 7, head.dy + side.dy * 7)
      ..lineTo(head.dx - side.dx * 7, head.dy - side.dy * 7)
      ..close();
    canvas.drawPath(tip, Paint()..color = accent);
    canvas.drawCircle(tail, 5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.from != from || old.ring != ring || old.text != text || old.accent != accent;
}
