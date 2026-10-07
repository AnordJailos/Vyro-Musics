import 'dart:math' as math;

double _clamp01(double t) => t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);

/// Equal-power crossfade curves: the combined loudness stays constant, so the
/// middle of a transition never dips or jumps.
double equalPowerOut(double t) => math.cos(_clamp01(t) * math.pi / 2);
double equalPowerIn(double t) => math.sin(_clamp01(t) * math.pi / 2);
