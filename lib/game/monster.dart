import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'audio/audio.dart';
import 'common.dart';
import 'floors.dart';
import 'heroes.dart';
import 'stages.dart';
import 'village_game.dart';

class Monster extends PositionComponent with HasGameReference<VillageGame> {
  Monster(this.kind, this.stageIdx, {this.floor, this.boss})
      : maxHp = boss?.hp ?? _baseHp(kind, stageIdx),
        super(
            size: Vector2.all(100 * (boss?.scale ?? kind.sizeMul) * (folderScale[boss?.folder ?? kind.folder] ?? 1)),
            anchor: Anchor.bottomCenter) {
    hp = maxHp;
    _addCd = 6;
    _slamCd = 4;
  }

  /// Regular monster HP climbs steeply with the stage number.
  static int _baseHp(EnemyKind k, int st) => (k.baseHp * (1 + .5 * st)).round();

  final EnemyKind kind;
  final int stageIdx;

  /// Set for monsters that live on a raised floor.
  final FloorPlatform? floor;
  final BossDef? boss;
  final int maxHp;
  late int hp;

  bool get onPlatform => floor != null;
  bool get isBoss => boss != null;
  bool get ranged => isBoss ? boss!.ranged : kind == EnemyKind.mage;
  bool get dying => _dying;
  String get _folder => boss?.folder ?? kind.folder;

  /// Height above ground: floor monsters stand on their floor.
  double get z => floor?.z ?? 0;

  int get goldDrop {
    final base = 5 + rng.nextInt(11) + stageIdx * 3;
    return isBoss ? 150 + base * 5 : base * 2;
  }

  int get damage {
    final lv = game.state.level;
    if (isBoss) return boss!.dmg + lv * 2 + stageIdx * 2;
    return kind.baseDmg + lv + stageIdx * 3;
  }

  double get _speed {
    final base = isBoss ? (ranged ? 55.0 : 70.0) : kind.speed;
    return _enraged ? base * 1.25 : base;
  }

  double _atkCd = 0, _wanderT = 0, _hurtT = 0, _atkAnim = 0;
  double _slamCd = 0, _slamWind = 0, _slamFlash = 0, _addCd = 0, _deadT = 0;
  bool _faceRight = true, _moving = false, _dying = false, _enraged = false;
  Vector2 _wander = Vector2.zero();
  late final CharAnims _anim;
  late final Paint _paint;

  static const _slamTime = .9, _slamRadius = 130.0;

  @override
  Future<void> onLoad() async {
    _anim = CharAnims(game, _folder);
    _paint = tintPaint(boss?.tint ?? kind.tint);
  }

  void hurt(int dmg) {
    if (_dying) return;
    hp -= dmg;
    if (!isBoss) {
      _hurtT = .25;
      _anim.play('hurt', restart: true);
      position.x += (x > game.player.x ? 1 : -1) * 16;
    }
    game.world.add(FloatingText('$dmg', position + Vector2(0, -size.y * .7), Colors.white));
    final spot = position + Vector2(0, -size.y * .45);
    game.fx.burst(spot, const Color(0xFFFFE0A0), 7, speed: 110, life: .35);
    GameAudio.sfx('hit');
    if (isBoss) game.shake(2.5, .12);
    if (isBoss && !_enraged && hp < maxHp * .5) {
      _enraged = true;
      game.world.add(FloatingText('GIẬN DỮ!', position + Vector2(0, -size.y), Colors.redAccent));
    }
    if (hp <= 0) {
      game.fx.burst(spot, const Color(0xFFFF9060), 22, speed: 190, life: .7, size: 3);
      GameAudio.sfx('kill');
      if (isBoss) {
        game.shake(10, .6);
        GameAudio.sfx('roar');
        game.fx.ring(position.clone(), Colors.orangeAccent, count: 40, speed: 220);
      }
      _dying = true;
      _anim.play('dead', restart: true);
      game.monsterDied(this);
    }
  }

  @override
  void update(double dt) {
    if (_dying) {
      _deadT += dt;
      _anim.update(dt);
      if (_deadT > 1.1) removeFromParent();
      return;
    }
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
    final pf = floor;
    if (pf != null) {
      position.x = position.x.clamp(pf.left + 12, pf.right - 12);
      position.y = pf.y;
    } else {
      position.x = position.x.clamp(30, VillageGame.worldWidth - 30);
      position.y = position.y.clamp(VillageGame.groundTop + 40, VillageGame.groundBottom);
    }
    priority = y.toInt();
    if (_hurtT > 0) {
      _anim.play('hurt');
    } else if (_atkAnim > 0 || _slamWind > 0) {
      _anim.play('attack');
    } else {
      _anim.play(_moving ? 'walk' : 'idle');
    }
    _anim.update(dt);
  }

  void _meleeAi(Vector2 to, double dist, double dt) {
    final reach = isBoss ? 100.0 : 62.0 * kind.sizeMul;
    if (dist > reach * .7) {
      position += to.normalized() * _speed * dt;
      _moving = true;
    }
    if (to.x.abs() > 4) _faceRight = to.x > 0;
    if (isBoss && _slamCd <= 0 && dist < 320) {
      _slamWind = _slamTime;
      GameAudio.sfx('warn');
      _slamCd = _enraged ? 4.5 : 6.5;
      game.world.add(FloatingText('!', position + Vector2(0, -size.y), Colors.redAccent));
      return;
    }
    if (dist < reach && _atkCd <= 0) {
      _atkCd = isBoss ? (_enraged ? .7 : .95) : 1.2;
      _atkAnim = .35;
      _anim.play('attack', restart: true);
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
      _anim.play('attack', restart: true);
      GameAudio.sfx('cast');
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
    game.shake(8, .4);
    GameAudio.sfx('slam');
    game.fx.ring(position.clone(), const Color(0xFFFFB070), count: 44, speed: 260);
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
          center: Offset(size.x / 2, size.y - 4), width: _slamRadius * 2, height: _slamRadius * .9);
      final f = _slamWind > 0 ? 1 - _slamWind / _slamTime : 1.0;
      canvas.drawOval(ring, Paint()..color = Colors.red.withValues(alpha: _slamWind > 0 ? .12 + .25 * f : .5));
      canvas.drawOval(
          ring,
          Paint()
            ..color = Colors.redAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    canvas.drawOval(Rect.fromLTWH(size.x * .28, size.y * .9, size.x * .44, size.y * .12), Paint()..color = Colors.black26);
    _anim.render(canvas, size, flip: !_faceRight, paint: _paint);
    if (!isBoss && !_dying) {
      final barX = (size.x - 40) / 2;
      final barY = size.y * (1 - (folderHeightFrac[_folder] ?? .6)) - 8;
      canvas.drawRect(Rect.fromLTWH(barX, barY, 40, 5), Paint()..color = Colors.black54);
      canvas.drawRect(Rect.fromLTWH(barX, barY, 40 * max(0, hp) / maxHp, 5), Paint()..color = Colors.redAccent);
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
    final color = switch (def.folder) {
      'FireWizard' => const Color(0xFFFF8A30),
      'LightningMage' => const Color(0xFFFFE850),
      _ => const Color(0xFF8AB8FF),
    };
    game.fx.burst(Vector2(x, y - z), color, 12, speed: 140, life: .4);
    GameAudio.sfx('boom');
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
