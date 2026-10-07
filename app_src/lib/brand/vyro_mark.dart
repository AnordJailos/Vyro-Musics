import 'package:flutter/material.dart';
import '../theme/vyro_theme.dart';

/// The Play Y: two crossing ribbons (the previous and the next track) that
/// merge into one stem, with a play symbol between the arms.
class VyroMark extends StatelessWidget {
  const VyroMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vyro',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: _VyroMarkPainter()),
      ),
    );
  }
}

class _VyroMarkPainter extends CustomPainter {
  const _VyroMarkPainter();

  static const _alpha = 0.92;

  Paint _ribbon(Rect bounds, Color top, Color bottom) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 26
    ..strokeCap = StrokeCap.round
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top.withValues(alpha: _alpha), bottom.withValues(alpha: _alpha)],
    ).createShader(bounds);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);

    final left = Path()
      ..moveTo(62, 52)
      ..cubicTo(66, 98, 104, 104, 106, 156);
    final right = Path()
      ..moveTo(138, 52)
      ..cubicTo(134, 98, 96, 104, 94, 156);
    canvas.drawPath(
      left,
      _ribbon(const Rect.fromLTRB(62, 52, 106, 156), VyroColors.violetLight, VyroColors.violetDeep),
    );
    canvas.drawPath(
      right,
      _ribbon(const Rect.fromLTRB(94, 52, 138, 156), VyroColors.teal, VyroColors.tealDeep),
    );

    final play = Path()
      ..moveTo(92, 60)
      ..lineTo(92, 82)
      ..lineTo(111, 71)
      ..close();
    canvas.drawPath(play, Paint()..color = Colors.white);
    canvas.drawPath(
      play,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VyroMarkPainter oldDelegate) => false;
}

/// The app icon tile: the mark on the dark rounded square.
class VyroAppIcon extends StatelessWidget {
  const VyroAppIcon({super.key, this.size = 112});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: VyroColors.panel,
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: VyroColors.panelBorder),
      ),
      child: VyroMark(size: size * 0.77),
    );
  }
}

/// Wordmark, set in lowercase.
class VyroWordmark extends StatelessWidget {
  const VyroWordmark({super.key, this.fontSize = 48, this.color});

  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'vyro',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -fontSize * 0.02,
        height: 1,
        color: color,
      ),
    );
  }
}
