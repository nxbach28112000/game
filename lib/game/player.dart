import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'game_state.dart';
import 'heroes.dart';
import 'monster.dart';
import 'village_game.dart';

class Player extends PositionComponent with HasGameReference<VillageGame> {
  Player() : super(size: Vector2.all(100), anchor: Anchor.bottomCenter);

  static const shieldTime = 2.5;
  static const jumpCooldown = .3;
  static const jumpSpeed = 430.0;
  static const gravity = 950.0;

  late final Map<String, CharAnims> _anims;
  int heroIndex = 0;
  final _cd = List<double>.filled(4, 0);
  double _swing = 0, _swingMax = .35, _hurtCd = 0, _mpT = 0, _shield = 0;
  double _jumpCd = 0, _deadT = 0;

  /// Height above the ground plane (the platform top is [FlyPlatform.topHeight]).
  double z = 0, _vz = 0;
  bool _grounded = true;
  SkillDef _active = skillDefs[0];
  bool facingRight = true;
  bool _moving = false;
  bool running = false;
  bool dead = false;

  /// Pending flame/lightning beam hits (seconds until each lands) + damage.
  final _beams = <double>[];
  int _beamDmg = 0;

  GameState get s => game.state;
  HeroDef get hero => heroes[heroIndex];
  CharAnims get _anim => _anims[hero.folder]!;
  String skillName(int slot) => hero.skills[slot];
  bool get shielded => _shield > 0;
  bool get airborne => !_grounded;
  double get jumpCooldownFraction => (_jumpCd / jumpCooldown).clamp(0.0, 1.0);
  double cooldownFraction(int slot) =>
      (_cd[slot] / skillDefs[slot].cd).clamp(0.0, 1.0);

  @override
  Future<void> onLoad() async => _anims = {
        for (final h in heroes) h.folder: CharAnims(game, h.folder)
      };

  /// Fresh start for a stage (also used to pick the hero).
  void reset(int hero) {
    heroIndex = hero;
    dead = false;
    _deadT = 0;
    _swing = 0;
    _shield = 0;
    _hurtCd = 0;
    z = 0;
    _vz = 0;
    _grounded = true;
    _jumpCd = 0;
    running = false;
    facingRight = true;
    _beams.clear();
    _cd.fillRange(0, _cd.length, 0);
    position = VillageGame.playerStart.clone();
    _anim.play('idle', restart: true);
  }

  void toggleRun() {
    if (dead || !game.inPlay) return;
    running = !running;
  }

  void jump() {
    if (dead || !game.inPlay || !_grounded || _jumpCd > 0) return;
    _grounded = false;
    _vz = jumpSpeed;
    _jumpCd = jumpCooldown;
    _anim.play('jump', restart: true);
  }

  void useSkill(int slot) {
    if (dead || !game.inPlay || _cd[slot] > 0 || _swing > 0) return;
    final d = skillDefs[slot];
    if (s.mp < d.mp) {
      game.world.add(
          FloatingText('Hết MP', position + Vector2(0, -90), Colors.white));
      return;
    }
    s.mp -= d.mp;
    _cd[slot] = d.cd;
    if (slot == 3) {
      _shield = shieldTime;
      game.world.add(FloatingText(
          hero.skills[3], position + Vector2(0, -90), Colors.lightGreenAccent));
      return;
    }
    _active = d;
    _swing = _swingMax = hero.ranged && slot == 2 ? .9 : d.dur;
    _anim.play(d.anim, restart: true);
    if (hero.ranged) {
      _castRanged(slot, d);
      return;
    }
    for (final m in List<Monster>.from(game.monsters)) {
      final dx = m.x - x;
      final front = d.aoe || dx * (facingRight ? 1 : -1) > -10;
      if (front &&
          dx.abs() < d.reach &&
          (m.y - y).abs() < (d.aoe ? 60 : 40) &&
          (m.z - z).abs() < 50) {
        m.hurt(((s.attack * hero.dmgMul + rng.nextInt(4)) * d.mult).round());
      }
    }
  }

  void _castRanged(int slot, SkillDef d) {
    final dmg = ((s.attack * hero.dmgMul + rng.nextInt(4)) * d.mult).round();
    if (slot == 2) {
      // Beam: two ticks of damage in front of the caster.
      _beamDmg = (dmg * .6).round();
      _beams
        ..clear()
        ..addAll([.3, .55]);
      return;
    }
    final dir = facingRight ? 1.0 : -1.0;
    game.world.add(Projectile(
      friendly: true,
      pos: Vector2(x + dir * 34, y),
      vel: Vector2(dir * (slot == 0 ? 430 : 350), 0),
      dmg: dmg,
      def: hero.proj!,
      z: z + 38,
      pierce: slot == 1,
      sizeMul: slot == 1 ? 1.4 : 1,
      life: slot == 1 ? 1.3 : .9,
    ));
  }

  void _beamHit() {
    for (final m in List<Monster>.from(game.monsters)) {
      final dx = (m.x - x) * (facingRight ? 1 : -1);
      if (dx > -10 && dx < 150 && (m.y - y).abs() < 45 && (m.z - z).abs() < 50) {
        m.hurt(_beamDmg);
      }
    }
  }

  void hurt(int dmg) {
    // Mid-air jumps (not standing on a platform) dodge hits.
    if (dead || _hurtCd > 0 || (!_grounded && _vz != 0)) return;
    _hurtCd = .8;
    final guarded = _shield > 0;
    final base = max(1, dmg - s.defense - hero.defBonus);
    final real = guarded ? max(1, (base * .2).round()) : base;
    s.hp = max(0, s.hp - real);
    if (!guarded) _anim.play('hurt', restart: true);
    game.world.add(FloatingText(guarded ? 'Chặn -$real' : '-$real',
        position + Vector2(0, -90), guarded ? Colors.lightGreenAccent : Colors.red));
    if (s.hp == 0) {
      dead = true;
      _deadT = 0;
      _shield = 0;
      _swing = 0;
      _beams.clear();
      z = 0;
      _vz = 0;
      _grounded = true;
      _anim.play('dead', restart: true);
    }
    s.touch();
  }

  @override
  void update(double dt) {
    if (dead) {
      _deadT += dt;
      _anim.update(dt);
      if (_deadT > 1.6) game.gameOver();
      return;
    }
    for (var i = 0; i < _cd.length; i++) {
      _cd[i] -= dt;
    }
    _swing -= dt;
    _hurtCd -= dt;
    _shield -= dt;
    _jumpCd -= dt;
    for (var i = _beams.length - 1; i >= 0; i--) {
      _beams[i] -= dt;
      if (_beams[i] <= 0) {
        _beams.removeAt(i);
        _beamHit();
      }
    }
    final dir = game.inputDirection;
    _moving = dir.length > .1;
    final run = running || game.shiftHeld;
    position += dir * hero.speed * (run ? 1.0 : .55) * dt;
    position.x = position.x.clamp(30, VillageGame.worldWidth - 30);
    position.y =
        position.y.clamp(VillageGame.groundTop + 50, VillageGame.groundBottom);
    if (dir.x > 0.1) facingRight = true;
    if (dir.x < -0.1) facingRight = false;
    _physics(dt);
    _mpT += dt;
    if (_mpT > 1.5) {
      _mpT = 0;
      if (s.mp < s.maxMp) s.mp++;
    }
    if (_swing > 0) {
      _anim.play(_active.anim);
    } else if (!_grounded) {
      _anim.play('jump');
    } else if (_hurtCd > .5 && _shield <= 0) {
      _anim.play('hurt');
    } else if (_shield > 0) {
      _anim.play('shield');
    } else {
      _anim.play(_moving ? (run ? 'run' : 'walk') : 'idle');
    }
    _anim.update(dt);
    priority = y.toInt();
  }

  /// Vertical motion: jump arc, landing on / walking off the flying platform.
  void _physics(double dt) {
    final top = game.platform.heightAt(position);
    if (_grounded) {
      if (z > top + .5) _grounded = false; // walked off the edge
      return;
    }
    final prev = z;
    _vz -= gravity * dt;
    z += _vz * dt;
    if (_vz <= 0 && top > 0 && prev >= top - 1 && z <= top) {
      z = top; // landed on the platform
    } else if (z <= 0) {
      z = 0;
    } else {
      return;
    }
    _vz = 0;
    _grounded = true;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
        const Rect.fromLTWH(28, 90, 44, 12), Paint()..color = Colors.black26);
    canvas.save();
    canvas.translate(0, -z);
    final sz = size * hero.scale;
    canvas.save();
    canvas.translate((size.x - sz.x) / 2, size.y - sz.y);
    _anim.render(canvas, sz, flip: !facingRight);
    canvas.restore();
    if (_shield > 0) {
      canvas.drawCircle(
          Offset(size.x / 2, 66),
          46,
          Paint()
            ..color = Colors.lightGreenAccent.withValues(alpha: .25)
            ..style = PaintingStyle.fill);
    }
    if (_swing > 0 && _active.aoe && !hero.ranged) {
      canvas.drawCircle(
          Offset(size.x / 2, 70),
          90 * (1 - _swing / _swingMax) + 20,
          Paint()
            ..color = Colors.white.withValues(alpha: _swing / _swingMax)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
    }
    canvas.restore();
  }
}
