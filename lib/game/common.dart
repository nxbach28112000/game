import 'dart:math';
import 'dart:ui';

final rng = Random();

/// Crisp pixel-art drawing (no smoothing).
final pixelPaint = Paint()
  ..filterQuality = FilterQuality.none
  ..isAntiAlias = false;

Paint tintPaint(Color c) => Paint()
  ..filterQuality = FilterQuality.none
  ..isAntiAlias = false
  ..colorFilter = ColorFilter.mode(c, BlendMode.modulate);
