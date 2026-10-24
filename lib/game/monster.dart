import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'heroes.dart';
import 'stages.dart';
import 'village_game.dart';

class Monster extends PositionComponent with HasGameReference<VillageGame> {
  Monster(this.kind, this.stageIdx, {this.onPlatform = false, this.boss})
      : maxHp = boss?.hp ?? _baseHp(kind, stageIdx),
        super(
            size: boss != null
                ? Vector2.all(100 * boss.scale)
                : (kind.isSprite ? Vector2(48, 48) : Vector2.all(100)),
            anchor: Anchor.bottomCenter) {
    hp = maxHp;
    _addCd = 6;
    _slamCd = 4;
  }

  static int _baseHp(EnemyKind k, int st) => switch (k) {
        EnemyKind.brute => 120 + st * 35,
        EnemyKind.mage => 70 + st * 25,
        _ => ((40 + st * 22) * k.hpMul).round(),
      };

  final EnemyKind kind;
  final int stageIdx;
  final bool onPlatform;
  final BossDef? boss;
  final int maxHp;
  late int hp;

  bool get isBoss => boss != null;
  bool get human => isBoss || !kind.isSprite;
  bool get ranged => isBoss ? boss!.ranged : kind == EnemyKind.mage;
  bool get dying => _dying;

  /// Height above ground: platform slimes stand on the flying platform.
  double get z => onPlatform ? FlyPlatform.topHeight : 0;

  int get exp => isBoss
      ? 250
      : switch (kind) {
          EnemyKind.brute => 30,
          EnemyKind.mage => 28,
          _ => kind.exp,
        };

  int get goldDrop {
    final base = 5 + rng.nextInt(11) + stageIdx * 3;
    return isBoss ? 150 + base * 5 : base * (human ? 2 : 1);
  }

  int get damage {
    final lv = game.state.level;
    if (isBoss) return boss!.dmg + lv * 2 + stageIdx * 2;
    return switch (kind) {
      EnemyKind.brute => 16 + lv * 2 + stageIdx * 3,
      EnemyKind.mage => 14 + lv + stageIdx * 3,
      _ => ((10 + lv * 2 + stageIdx * 3) * kind.dmgMul).round(),
    };
  }

  double get _speed {
    final base = isBoss ? (ranged ? 55.0 : 70.0) : switch (kind) {
      EnemyKind.brute => 55.0,
      EnemyKind.mage => 50.0,
      _ => kind.speed,
    };
    return _enraged ? base * 1.25 : base;
  }

  double _atkCd = 0, _wanderT = 0, _hurtT = 0, _atkAnim = 0;
  double _slamCd = 0, _slamWind = 0, _slamFlash = 0, _addCd = 0, _deadT = 0;
  double _t = rng.nextDouble() * 5;
  bool _faceRight = true, _moving = false, _dying = false, _enraged = false;
  Vector2 _wander = Vector2.zero();
  late final List<Sprite> _frames;
  CharAnims? _anim;
  late final Paint _paint;

  static const _slamTime = .9, _slamRadius = 130.0;

  @override
  Future<void> onLoad() async {
    if (human) {
      final folder = boss?.folder ?? (kind == EnemyKind.brute ? 'Fighter' : 'Wanderer');
      _anim = CharAnims(game, folder);
      _paint = tintPaint(boss?.tint ??
          (kind == EnemyKind.brute
              ? const Color(0xFFFF9A9A)
              : const Color(0xFFD2A8FF)));
    } else {
      final file = kind.file!;
      _frames = switch (kind) {
        // 3 colour rows (picked by stage) x 3 idle frames, 24px cells.
        EnemyKind.slime => [for (var i = 0; i < 3; i++) game.sprite(file, i * 24.0, (stageIdx % 3) * 24.0, 24, 24)],
        // 8 colour rows x 7 walk frames, 32px cells.
        EnemyKind.goblin => [for (var i = 0; i < 7; i++) game.sprite(file, i * 32.0, (stageIdx % 8) * 32.0, 32, 32)],
        _ => [game.sprite(file)],
      };
    }
  }

  void hurt(int dmg) {
    if (_dying) return;
    hp -= dmg;
    if (!isBoss) {
      _hurtT = .25;
      _anim?.play('hurt', restart: true);
      position.x += (x > game.player.x ? 1 : -1) * 16;
    }
    game.world.add(FloatingText(
        '$dmg', position + Vector2(0, human ? -size.y * .7 : -50), Colors.white));
    if (isBoss && !_enraged && hp < maxHp * .5) {
      _enraged = true;
      game.world.add(FloatingText('GIẬN DỮ!', position + Vector2(0, -size.y), Colors.redAccent));
    }
    if (hp <= 0) {
      if (game.state.gainExp(exp)) {
        game.world.add(FloatingText('LEVEL UP!',
            game.player.position + Vector2(0, -110), Colors.yellow));
      }
      _dying = true;
      game.monsterDied(this);
      if (human) {
        _anim!.play('dead', restart: true);
      } else {
        removeFromParent();
      }
    }
  }

  @override
  void update(double dt) {
    if (_dying) {
      _deadT += dt;
      _anim?.update(dt);
      if (_deadT > 1.1) removeFromParent();
      return;
    }
    _t += dt;
    _atkCd -= dt;
    _hurtT -= dt;
    _atkAnim -= dt;
    _slamCd -= dt;
    _addCd -= dt;
    _slamFlash -= dt;
    final p = game.player;
    final to = p.position - position;
    final dist = to.length;
    final sees = !p.dead && (p.z - z).abs() < 50;
    _moving = false;
    if (isBoss && _addCd <= 0) {
      _addCd = _enraged ? 7 : 10;
      if (game.monsters.length < 6) game.spawnAdd();
    }
    if (_slamWind > 0) {
      _slamWind -= dt;
      if (_slamWind <= 0) _slam();
    } else if (sees && dist < (isBoss ? 900 : 220)) {
      if (ranged) {
        _rangedAi(to, dt);
      } else {
        _meleeAi(to, dist, dt);
      }
    } else {
      _wanderT -= dt;
      if (_wanderT <= 0) {
        _wanderT = 1 + rng.nextDouble() * 2;
        _wander = rng.nextBool()
            ? Vector2.zero()
            : (Vector2(rng.nextDouble() - .5, rng.nextDouble() - .5)..normalize());
      }
      position += _wander * 28 * dt;
      _moving = !_wander.isZero();
      if (_wander.x.abs() > .1) _faceRight = _wander.x > 0;
    }
    if (onPlatform) {
      final pf = game.platform;
      position.x = position.x.clamp(pf.left + 12, pf.right - 12);
      position.y = pf.y;
    } else {
      position.x = position.x.clamp(30, VillageGame.worldWidth - 30);
      position.y = position.y.clamp(VillageGame.groundTop + 40, VillageGame.groundBottom);
    }
    priority = y.toInt();
    final a = _anim;
    if (a != null) {
      if (_hurtT > 0) {
        a.play('hurt');
      } else if (_atkAnim > 0 || _slamWind > 0) {
        a.play('attack');
      } else {
        a.play(_moving ? 'walk' : 'idle');
      }
      a.update(dt);
    }
  }

  void _meleeAi(Vector2 to, double dist, double dt) {
    final reach = isBoss ? 100.0 : (human ? 62.0 : 55.0);
    if (dist > reach * .7) {
      position += to.normalized() * _speed * dt;
      _moving = true;
    }
    if (to.x.abs() > 4) _faceRight = to.x > 0;
    if (isBoss && _slamCd <= 0 && dist < 320) {
      _slamWind = _slamTime;
      _slamCd = _enraged ? 4.5 : 6.5;
      game.world.add(FloatingText('!', position + Vector2(0, -size.y), Colors.redAccent));
      return;
    }
    if (dist < reach && _atkCd <= 0) {
      _atkCd = isBoss ? (_enraged ? .7 : .95) : 1.2;
      _atkAnim = .35;
      _anim?.play('attack', restart: true);
      game.player.hurt(damage);
    }
  }

  void _rangedAi(Vector2 to, double dt) {
    final want = isBoss ? 290.0 : 220.0;
    if (to.y.abs() > 14) {
      position.y += to.y.sign * _speed * .8 * dt;
      _moving = true;
    }
    if (to.x.abs() < want - 60) {
      position.x -= to.x.sign * _speed * dt;
      _moving = true;
    } else if (to.x.abs() > want + 60) {
      position.x += to.x.sign * _speed * dt;
      _moving = true;
    }
    if (to.x.abs() > 4) _faceRight = to.x > 0;
    if (_atkCd <= 0 && to.x.abs() < 480 && to.y.abs() < 40) {
      _atkCd = isBoss ? (_enraged ? 1.5 : 2.2) : 2.4;
      _atkAnim = .4;
      _anim?.play('attack', restart: true);
      final dir = _faceRight ? 1.0 : -1.0;
      final def = projDefs[boss?.projFolder ?? 'Wanderer']!;
      for (final vy in isBoss ? const [-75.0, 0.0, 75.0] : const [0.0]) {
        game.world.add(Projectile(
          friendly: false,
          pos: Vector2(x + dir * 30, y),
          vel: Vector2(dir * (isBoss ? 300 : 280), vy),
          dmg: damage,
          def: def,
          z: z + size.y * .35,
          life: 2.2,
          sizeMul: isBoss ? 1.3 : 1,
        ));
      }
    }
  }

  void _slam() {
    _slamFlash = .3;
    final p = game.player;
    final dx = (p.x - x) / _slamRadius, dy = (p.y - y) / (_slamRadius * .45);
    game.world.add(FloatingText('RẦM!', position + Vector2(0, -size.y), Colors.orangeAccent));
    if (dx * dx + dy * dy < 1 && p.z < 25) p.hurt((damage * 1.4).round());
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(0, -z);
    if (_slamWind > 0 || _slamFlash > 0) {
      final ring = Rect.fromCenter(
          center: Offset(size.x / 2, size.y - 4),
          width: _slamRadius * 2,
          height: _slamRadius * .9);
      final f = _slamWind > 0 ? 1 - _slamWind / _slamTime : 1.0;
      canvas.drawOval(
          ring,
          Paint()..color = Colors.red.withValues(alpha: _slamWind > 0 ? .12 + .25 * f : .5));
      canvas.drawOval(
          ring,
          Paint()
            ..color = Colors.redAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    if (human) {
      canvas.drawOval(Rect.fromLTWH(size.x * .28, size.y * .9, size.x * .44, size.y * .12),
          Paint()..color = Colors.black26);
      _anim!.render(canvas, size, flip: !_faceRight, paint: _paint);
    } else {
      canvas.drawOval(const Rect.fromLTWH(4, 40, 40, 8), Paint()..color = Colors.black26);
      canvas.save();
      if (!_faceRight) {
        canvas.translate(size.x, 0);
        canvas.scale(-1, 1);
      }
      final fly = kind == EnemyKind.bat ? 14 + sin(_t * 6) * 5 : 0.0;
      final d = kind.drawSize;
      _frames[(_t * (kind == EnemyKind.goblin ? 8 : 4)).floor() % _frames.length].render(canvas,
          position: Vector2((size.x - d) / 2, size.y - d - fly), size: Vector2.all(d), overridePaint: pixelPaint);
      canvas.restore();
    }
    if (!isBoss && !_dying) {
      final barX = (size.x - 40) / 2;
      final barY = human ? size.y * .28 : -6.0;
      canvas.drawRect(Rect.fromLTWH(barX, barY, 40, 5), Paint()..color = Colors.black54);
      canvas.drawRect(Rect.fromLTWH(barX, barY, 40 * max(0, hp) / maxHp, 5),
          Paint()..color = Colors.redAccent);
    }
    canvas.restore();
  }
}

/// A magic bolt. Friendly ones hit monsters, hostile ones hit the player.
class Projectile extends PositionComponent with HasGameReference<VillageGame> {
  Projectile({
    required this.friendly,
    required Vector2 pos,
    required this.vel,
    required this.dmg,
    required this.def,
    required this.z,
    this.pierce = false,
    this.sizeMul = 1,
    this.life = 1,
  }) : super(position: pos, size: Vector2.all(10), anchor: Anchor.center);

  final bool friendly, pierce;
  final Vector2 vel;
  final int dmg;
  final ProjDef def;
  final double z, sizeMul;
  double life;
  double _t = 0;
  bool _exploding = false;
  final _hit = <Monster>{};

  @override
  void update(double dt) {
    _t += dt;
    if (_exploding) {
      if (_t > .6) removeFromParent();
      return;
    }
    position += vel * dt;
    life -= dt;
    priority = y.toInt() + 2;
    if (life <= 0 || x < -30 || x > VillageGame.worldWidth + 30) {
      removeFromParent();
      return;
    }
    if (friendly) {
      for (final m in List<Monster>.from(game.monsters)) {
        if (_hit.contains(m)) continue;
        if ((m.x - x).abs() < 28 * sizeMul &&
            (m.y - y).abs() < 34 &&
            (m.z + 28 - z).abs() < 55) {
          _hit.add(m);
          m.hurt(dmg);
          if (!pierce) {
            _explode();
            return;
          }
        }
      }
    } else {
      final p = game.player;
      if (!p.dead &&
          (p.x - x).abs() < 24 &&
          (p.y - y).abs() < 30 &&
          (p.z + 30 - z).abs() < 45) {
        p.hurt(dmg);
        _explode();
      }
    }
  }

  void _explode() {
    _exploding = true;
    _t = 0;
  }

  @override
  void render(Canvas canvas) {
    final img = game.images.fromCache('${def.folder}/Proj.png');
    final frames = img.width ~/ def.fw;
    final int f;
    if (_exploding) {
      f = min(frames - 1, def.travel + (_t / .06).floor());
    } else {
      f = (_t * 16).floor() % def.travel;
    }
    final w = def.fw * def.drawScale * sizeMul, h = def.fh * def.drawScale * sizeMul;
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2 - z);
    if (vel.x < 0) canvas.scale(-1, 1);
    canvas.drawImageRect(
        img,
        Rect.fromLTWH(f * def.fw.toDouble(), 0, def.fw.toDouble(), def.fh.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        pixelPaint);
    canvas.restore();
  }
}
