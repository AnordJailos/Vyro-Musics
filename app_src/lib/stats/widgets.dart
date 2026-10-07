import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 1,234 -> 1.2K, 2,500,000 -> 2.5M
String compact(int n) {
  String fmt(double v, String suffix) {
    final text = v.toStringAsFixed(v >= 10 ? 0 : 1);
    final clean = text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
    return '$clean$suffix';
  }

  if (n >= 1000000) return fmt(n / 1000000, 'M');
  if (n >= 1000) return fmt(n / 1000, 'K');
  return '$n';
}

const _up = Color(0xFF12B886);
const _down = Color(0xFFF76707);

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: text.bodySmall),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Arrow and percentage against the previous period.
class DeltaChip extends StatelessWidget {
  const DeltaChip({super.key, required this.value, required this.previous});

  final int value;
  final int previous;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (previous == 0) {
      return value == 0 ? const SizedBox(height: 20) : Text('new', style: text.labelMedium?.copyWith(color: _up));
    }
    final change = (value - previous) / previous * 100;
    final up = change >= 0;
    final color = up ? _up : _down;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded, color: color, size: 22),
        Text('${change.abs().round()}%', style: text.labelLarge?.copyWith(color: color)),
        const SizedBox(width: 4),
        Text('vs before', style: text.labelSmall),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.previous});

  final String label;
  final int value;
  final int? previous;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: text.labelLarge),
            const SizedBox(height: 6),
            Text(compact(value), style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (previous != null) DeltaChip(value: value, previous: previous!) else const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class BarRow {
  const BarRow(this.label, this.fraction, this.trailing);
  final String label;
  final double fraction;
  final String trailing;
}

class BarList extends StatelessWidget {
  const BarList({super.key, required this.rows});

  final List<BarRow> rows;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(r.label, style: text.bodyMedium)),
                    Text(r.trailing, style: text.bodySmall),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: r.fraction.clamp(0.0, 1.0).toDouble(), minHeight: 6),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Line chart with up to two series (for example plays and listeners).
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.primary, this.secondary, this.height = 170, this.showAxes = true});

  final List<int> primary;
  final List<int>? secondary;
  final double height;
  final bool showAxes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendPainter(
          primary: primary,
          secondary: secondary,
          showAxes: showAxes,
          line: scheme.primary,
          line2: scheme.tertiary,
          grid: scheme.outlineVariant,
          label: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

void _paintLabel(Canvas canvas, String text, Offset at, Color color) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 11)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at);
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.primary,
    required this.secondary,
    required this.showAxes,
    required this.line,
    required this.line2,
    required this.grid,
    required this.label,
  });

  final List<int> primary;
  final List<int>? secondary;
  final bool showAxes;
  final Color line;
  final Color line2;
  final Color grid;
  final Color label;

  Path _path(List<int> values, double maxV, Size size, double top) {
    final path = Path();
    final h = size.height - top;
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : i / (values.length - 1) * size.width;
      final y = size.height - (values[i] / maxV) * h;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (primary.isEmpty) return;
    final all = [...primary, ...?secondary];
    final maxV = math.max(1, all.reduce(math.max)).toDouble();
    final top = showAxes ? 16.0 : 2.0;

    if (showAxes) {
      final gridPaint = Paint()
        ..color = grid
        ..strokeWidth = 1;
      for (final f in [0.0, 0.5, 1.0]) {
        final y = size.height - f * (size.height - top);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
      _paintLabel(canvas, '${maxV.round()}', const Offset(0, 0), label);
    }

    final main = _path(primary, maxV, size, top);
    final area = Path.from(main)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.12));
    canvas.drawPath(
      main,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    final second = secondary;
    if (second != null && second.isNotEmpty) {
      canvas.drawPath(
        _path(second, maxV, size, top),
        Paint()
          ..color = line2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.primary != primary || old.secondary != secondary || old.line != line || old.showAxes != showAxes;
}

/// Share of plays still going at each 10% of a song (0% to 100%).
class RetentionChart extends StatelessWidget {
  const RetentionChart({super.key, required this.points});

  final List<double> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(painter: _RetentionPainter(points, scheme.primary, scheme.outlineVariant, scheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text('Start', style: text.bodySmall), Text('Middle', style: text.bodySmall), Text('End', style: text.bodySmall)],
        ),
      ],
    );
  }
}

class _RetentionPainter extends CustomPainter {
  _RetentionPainter(this.points, this.line, this.grid, this.label);

  final List<double> points;
  final Color line;
  final Color grid;
  final Color label;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = size.height - f * (size.height - 14);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    _paintLabel(canvas, '100%', const Offset(0, 0), label);

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i / (points.length - 1) * size.width;
      final y = size.height - points[i].clamp(0.0, 1.0).toDouble() * (size.height - 14);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.14));
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RetentionPainter old) => old.points != points || old.line != line;
}

/// 24 bars, one per hour of the day: when you listen.
class ClockChart extends StatelessWidget {
  const ClockChart({super.key, required this.values});

  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final maxV = math.max(1, values.reduce(math.max));
    return Column(
      children: [
        SizedBox(
          height: 90,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var h = 0; h < values.length; h++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: FractionallySizedBox(
                      heightFactor: math.max(0.04, values[h] / maxV),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.35 + 0.65 * values[h] / maxV),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final l in const ['12 am', '6 am', '12 pm', '6 pm', '12 am']) Text(l, style: text.bodySmall),
          ],
        ),
      ],
    );
  }
}

String pct(double v) => '${(v * 100).round()}%';

String monthDay(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}';
}

/// 41059 -> 41,059
String thousands(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
