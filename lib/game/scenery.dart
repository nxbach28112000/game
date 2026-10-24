import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'bg_layers.dart';
import 'common.dart';
import 'village_game.dart';

/// Arena names, one per background world.
const backgroundNames = ['Sân thượng', 'Phòng ngai vàng', 'Lâu đài', 'Rừng chết'];

/// Light sources found in the layers (see tool scripts): world -> (layer
/// number, x, y, radius, colour) in 3840x2160 scene coordinates. They get
/// animated glows that follow their layer's parallax.
const _glows = <int, List<(int, double, double, double, int)>>{
  1: [(4, 2122, 355, 420, 0xFFFF8A3C)],
  2: [(3, 792, 489, 170, 0xFFFFB347), (3, 3049, 490, 170, 0xFFFFB347)],
  3: [(4, 2619, 205, 560, 0xFFB9C8FF)],
  4: [(6, 2676, 127, 540, 0xFFFF4A4A)],
};

/// Per-world floating motes: (colour, count, vx, vy, size, rising?).
const _ambient = <int, (int, int, double, double, double)>{
  1: (0xFFFF9A40, 38, -6, -26, 2.0), // embers rising
  2: (0xFFFFB8A0, 30, 3, -6, 1.7), // dust in the candle light
  3: (0xFFBBD2FF, 30, -4, -4, 2.2), // drifting spirit lights
  4: (0xFFE8A8A8, 44, -10, 14, 1.7), // ash falling
};

const _sc = 800 / 3840; // scene -> view scale
const _zoom = 1.06; // slight zoom so parallax never shows the layer edges
const _maxShift = 22.0;

class _Layer {
  _Layer(this.img, this.n, this.x, this.y, this.w, this.h, this.file);

  final ui.Image img;
  final int n;
  final double x, y, w, h;
  final String file;
}

/// The arena: parallax layers (back to front, the nearest one is drawn by
/// [SceneFx] over the characters) with animated light sources.
class Background extends Component with HasGameReference<VillageGame> {
  Background() : super(priority: -10000);

  int index = 0;
  final _layers = <_Layer>[];
  final _loaded = <String>{};
  int _req = 0;
  double _t = 0, _px = 400;
  final _paint = Paint()..filterQuality = FilterQuality.medium;

  String get name => backgroundNames[index];
  int get depthCount => _layers.length;

  @override
  Future<void> onLoad() => _load(0);

  Future<void> setIndex(int i) => _load(i);

  /// A newer request wins over a slower older one; scenes that are no longer
  /// used are freed once the new one is in place.
  Future<void> _load(int i) async {
    final mine = ++_req;
    final defs = bgLayers[i + 1]!;
    final imgs = await Future.wait([
      for (final d in defs) game.images.load(d.$1),
    ]);
    _loaded.addAll([for (final d in defs) d.$1]);
    if (mine != _req) return;
    _layers
      ..clear()
      ..addAll([
        for (var k = 0; k < defs.length; k++)
          _Layer(imgs[k], int.parse(defs[k].$1.split('_').last.split('.').first), defs[k].$2, defs[k].$3, defs[k].$4,
              defs[k].$5, defs[k].$1),
      ]);
    index = i;
    final keep = {for (final d in defs) d.$1};
    for (final f in _loaded.where((f) => !keep.contains(f)).toList()) {
      game.images.clear(f);
      _loaded.remove(f);
    }
  }

  @override
  void update(double dt) {
    _t += dt;
    _px += (game.player.x - _px) * min(1, dt * 3);
  }

  double shiftOf(int n) {
    final total = max(2, _layers.length);
    final f = 1 - (n - 1) / (total - 1);
    return -((_px - 400) / 400) * _maxShift * f;
  }

  Rect _rectOf(_Layer l, double shift) => Rect.fromLTWH(
        400 + (l.x * _sc - 400) * _zoom + shift,
        225 + (l.y * _sc - 225) * _zoom,
        l.w * _sc * _zoom,
        l.h * _sc * _zoom,
      );

  void _glow(Canvas canvas, Offset c, double r, Color color, double a) {
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(c, r, [color.withValues(alpha: a), color.withValues(alpha: 0)]));
  }

  @override
  void render(Canvas canvas) {
    if (_layers.isEmpty) return;
    final world = index + 1;
    for (final l in _layers) {
      if (l.n == 1) continue; // foreground: drawn by SceneFx
      final shift = shiftOf(l.n);
      var rect = _rectOf(l, shift);
      final src = Rect.fromLTWH(0, 0, l.img.width.toDouble(), l.img.height.toDouble());
      if (world == 1 && l.n == 3) {
        // The bat flock circles slowly over the sunset.
        final w = rect.width, h = rect.height;
        final x = ((_t * 22) % 1100) - 250;
        rect = Rect.fromLTWH(x, 10 + sin(_t * 1.3) * 12, w, h);
      }
      canvas.drawImageRect(l.img, src, rect, _paint);
      for (final g in _glows[world] ?? const <(int, double, double, double, int)>[]) {
        if (g.$1 != l.n) continue;
        final c = Offset(400 + (g.$2 * _sc - 400) * _zoom + shift, 225 + (g.$3 * _sc - 225) * _zoom);
        final flicker = world == 2 ? .55 + .25 * sin(_t * 9 + g.$2) + .1 * sin(_t * 23 + g.$2) : .45 + .1 * sin(_t * 1.5);
        final radius = g.$4 * _sc * _zoom * (world == 2 ? 1 + .12 * sin(_t * 8 + g.$2) : 1);
        _glow(canvas, c, radius, Color(g.$5), flicker);
      }
    }
  }

  /// The nearest layer, drawn above the characters.
  void renderForeground(Canvas canvas) {
    for (final l in _layers) {
      if (l.n != 1) continue;
      canvas.drawImageRect(
          l.img,
          Rect.fromLTWH(0, 0, l.img.width.toDouble(), l.img.height.toDouble()),
          _rectOf(l, shiftOf(1)),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = const Color(0xCCFFFFFF));
    }
  }
}

class _Mote {
  _Mote(this.x, this.y, this.vx, this.vy, this.size, this.phase);

  double x, y, vx, vy, size, phase;
}

/// Everything drawn on top of the characters: the nearest scenery layer, ash
/// and embers, a soft light around the hero and a vignette.
class SceneFx extends Component with HasGameReference<VillageGame> {
  SceneFx() : super(priority: 60000);

  final _motes = <_Mote>[];
  int _world = 0;
  double _t = 0;
  late final Paint _vignette = Paint()
    ..shader = ui.Gradient.radial(const Offset(400, 225), 470, [
      Colors.black.withValues(alpha: 0),
      Colors.black.withValues(alpha: .62),
    ], const [
      .55,
      1.0
    ]);

  void _seed(int world) {
    _world = world;
    _motes.clear();
    final cfg = _ambient[world]!;
    for (var i = 0; i < cfg.$2; i++) {
      _motes.add(_Mote(rng.nextDouble() * 800, rng.nextDouble() * 450, cfg.$3 * (.5 + rng.nextDouble()),
          cfg.$4 * (.5 + rng.nextDouble()), cfg.$5 * (.5 + rng.nextDouble()), rng.nextDouble() * 6));
    }
  }

  @override
  void update(double dt) {
    _t += dt;
    final world = game.background.index + 1;
    if (world != _world) _seed(world);
    for (final m in _motes) {
      m.x += (m.vx + sin(_t + m.phase) * 6) * dt;
      m.y += m.vy * dt;
      if (m.y < -5) m.y = 455;
      if (m.y > 455) m.y = -5;
      if (m.x < -5) m.x = 805;
      if (m.x > 805) m.x = -5;
    }
  }

  @override
  void render(Canvas canvas) {
    game.background.renderForeground(canvas);
    final color = Color(_ambient[_world]?.$1 ?? 0xFFFFFFFF);
    final p = Paint()..blendMode = BlendMode.plus;
    for (final m in _motes) {
      final a = .35 + .45 * (.5 + .5 * sin(_t * 3 + m.phase));
      p.color = color.withValues(alpha: a);
      canvas.drawCircle(Offset(m.x, m.y), m.size, p);
    }
    if (game.inPlay && !game.player.dead) {
      // Warm light pooling around the hero.
      final c = Offset(game.player.x, game.player.y - 30 - game.player.z);
      canvas.drawCircle(
          c,
          130,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(c, 130, [color.withValues(alpha: .16), color.withValues(alpha: 0)]));
    }
    canvas.drawRect(const Rect.fromLTWH(0, 0, 800, 450), _vignette);
  }
}

class _Spark {
  _Spark(this.x, this.y, this.vx, this.vy, this.life, this.size, this.color, this.gravity);

  double x, y, vx, vy, life, size, gravity;
  final double maxLife = 1;
  final Color color;
  double age = 0;
}

/// Hit sparks, dust and bursts. Lives in the world so it is sorted over the
/// characters.
class ParticleLayer extends Component {
  ParticleLayer() : super(priority: 59000);

  final _sparks = <_Spark>[];

  void burst(Vector2 at, Color color, int count,
      {double speed = 120, double life = .5, double size = 2.2, double gravity = 220, double up = 40}) {
    for (var i = 0; i < count; i++) {
      final a = rng.nextDouble() * pi * 2;
      final s = speed * (.3 + rng.nextDouble() * .7);
      _sparks.add(_Spark(at.x, at.y, cos(a) * s, sin(a) * s * .8 - up, life * (.6 + rng.nextDouble() * .6),
          size * (.6 + rng.nextDouble() * .8), color, gravity));
    }
  }

  /// An expanding ring of dust/light (level up, ground slam).
  void ring(Vector2 at, Color color, {int count = 26, double speed = 150}) {
    for (var i = 0; i < count; i++) {
      final a = i / count * pi * 2;
      _sparks.add(_Spark(at.x, at.y, cos(a) * speed, sin(a) * speed * .35, .55, 2.6, color, 0));
    }
  }

  @override
  void update(double dt) {
    for (var i = _sparks.length - 1; i >= 0; i--) {
      final s = _sparks[i];
      s.age += dt;
      if (s.age >= s.life) {
        _sparks.removeAt(i);
        continue;
      }
      s.vy += s.gravity * dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
    }
  }

  void clear() => _sparks.clear();

  @override
  void render(Canvas canvas) {
    final p = Paint()..blendMode = BlendMode.plus;
    for (final s in _sparks) {
      final f = 1 - s.age / s.life;
      p.color = s.color.withValues(alpha: f.clamp(0, 1) * .95);
      canvas.drawRect(Rect.fromCenter(center: Offset(s.x, s.y), width: s.size * (.5 + f), height: s.size * (.5 + f)), p);
    }
  }
}

/// Scenery that glows (crystals) so it belongs to the dark gothic scenes.
class Prop extends PositionComponent {
  Prop(this._img, double scale, Color tint, this._glowColor)
      : _paint = tintPaint(tint),
        super(anchor: Anchor.bottomCenter) {
    size = Vector2(_img.width * scale, _img.height * scale);
    _t = rng.nextDouble() * 6;
  }

  final ui.Image _img;
  final Color _glowColor;
  final Paint _paint;
  double _t = 0;

  @override
  void onMount() {
    super.onMount();
    priority = y.toInt() - 2;
  }

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y * .55);
    final r = size.y * .95;
    canvas.drawOval(Rect.fromLTWH(size.x * .1, size.y - 6, size.x * .8, 10), Paint()..color = Colors.black38);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(c, r, [
            _glowColor.withValues(alpha: .35 + .12 * sin(_t * 2)),
            _glowColor.withValues(alpha: 0),
          ]));
    canvas.drawImageRect(_img, Rect.fromLTWH(0, 0, _img.width.toDouble(), _img.height.toDouble()),
        Offset.zero & Size(size.x, size.y), _paint);
  }
}
