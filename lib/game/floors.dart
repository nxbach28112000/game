import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'village_game.dart';

/// A raised floor the hero (and some monsters) can stand and fight on. It is
/// built from random pieces of the medieval field tileset: grass ground,
/// wooden scaffolds or stone slabs, decorated with crates, barrels, hay and
/// bushes. `z` is the height of its top above the arena ground.
class FloorPlatform extends PositionComponent with HasGameReference<VillageGame> {
  FloorPlatform({
    required double cx,
    required double depth,
    required this.floorW,
    required this.z,
    required this.style,
    required this.tint,
  }) : super(position: Vector2(cx, depth), size: Vector2(floorW, 20), anchor: Anchor.bottomCenter);

  /// Floors must be at least 40% of the 800px screen wide.
  static const minWidth = 320.0;

  /// How far (in depth) from the floor's lane a hero can still stand on it.
  static const laneTolerance = 34.0;

  final double floorW, z;
  final int style; // 0 grass ground, 1 wooden scaffold, 2 stone slabs
  final Color tint;

  double get left => x - floorW / 2;
  double get right => x + floorW / 2;

  bool covers(Vector2 p) => p.x >= left && p.x <= right && (p.y - y).abs() <= laneTolerance;

  final _pieces = <(ui.Image, Rect)>[];
  final _decor = <(ui.Image, Rect)>[];
  late final Paint _paint = tintPaint(tint);

  ui.Image _img(String file) => game.images.fromCache(file);

  @override
  Future<void> onLoad() async {
    priority = (y - z).toInt() - 1; // behind every character standing lower
    switch (style) {
      case 0:
        const tops = ['02', '07', '08', '10', '11', '12'];
        const t = 46.0;
        final n = (floorW / t).ceil();
        final w = floorW / n;
        for (var i = 0; i < n; i++) {
          final img = _img('Tiles/ground${tops[rng.nextInt(tops.length)]}.png');
          _pieces.add((img, Rect.fromLTWH(i * w, -3, w + 1, w + 1)));
        }
      case 1:
        final n = (floorW / 64).ceil();
        final w = floorW / n;
        for (var i = 0; i < n; i++) {
          final img = _img(i.isEven ? 'Tiles/table1.png' : 'Tiles/table2.png');
          _pieces.add((img, Rect.fromLTWH(i * w, -6, w + 1, w + 1)));
        }
      default:
        var cx = 0.0;
        var i = 0;
        while (cx < floorW - 20) {
          final img = _img(i.isEven ? 'Tiles/rockflat1.png' : 'Tiles/rockflat2.png');
          final w = 96.0;
          _pieces.add((img, Rect.fromLTWH(min(cx, floorW - w), -22, w, w * img.height / img.width)));
          cx += w * .72;
          i++;
        }
    }
    // Random decorations standing on top.
    const items = [
      'Tiles/crate.png',
      'Tiles/barrel.png',
      'Tiles/hay1.png',
      'Tiles/hay2.png',
      'Tiles/rock1.png',
      'Tiles/rock2.png',
      'Tiles/plant1.png',
      'Tiles/plant2.png',
      'Tiles/fence1.png',
      'Tiles/sign1.png',
      'Props/bush1.png',
      'Props/bush3.png',
      'Props/bush5.png',
      'Props/bush7.png',
      'Props/bush9.png',
    ];
    final count = 2 + rng.nextInt(3);
    for (var i = 0; i < count; i++) {
      final img = _img(items[rng.nextInt(items.length)]);
      final h = 20 + rng.nextDouble() * 18;
      final w = h * img.width / img.height;
      final dx = 12 + rng.nextDouble() * (floorW - 24 - w);
      _decor.add((img, Rect.fromLTWH(dx, -h + 2, w, h)));
    }
  }

  @override
  void render(Canvas canvas) {
    // Soft shadow on the arena ground far below.
    canvas.drawOval(Rect.fromLTWH(floorW * .12, 4, floorW * .76, 12), Paint()..color = Colors.black26);
    canvas.save();
    canvas.translate(0, 20 - z);
    // Slight dark fade under the platform so it reads as floating.
    canvas.drawRect(
        Rect.fromLTWH(0, 38, floorW, 14),
        Paint()
          ..shader = ui.Gradient.linear(
              const Offset(0, 38), const Offset(0, 52), [Colors.black.withValues(alpha: .25), Colors.black.withValues(alpha: 0)]));
    for (final p in _pieces) {
      canvas.drawImageRect(p.$1, Rect.fromLTWH(0, 0, p.$1.width.toDouble(), p.$1.height.toDouble()), p.$2, _paint);
    }
    for (final d in _decor) {
      canvas.drawImageRect(d.$1, Rect.fromLTWH(0, 0, d.$1.width.toDouble(), d.$1.height.toDouble()), d.$2, _paint);
    }
    canvas.restore();
  }
}
