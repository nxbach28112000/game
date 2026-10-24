import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'audio/audio.dart';
import 'common.dart';
import 'floors.dart';
import 'game_state.dart';
import 'heroes.dart';
import 'monster.dart';
import 'village_game.dart';

class Player extends PositionComponent with HasGameReference<VillageGame> {
  Player() : super(size: Vector2.all(100), anchor: Anchor.bottomCenter);

  static const jumpCooldown = .3;
  static const jumpSpeed = 560.0;
  static const gravity = 950.0;

  /// Mana spent per second while running (shift held or run locked on).
  static const runManaPerSecond = 3.0;

  late final Map<String, CharAnims> _anims;
  int heroIndex = 0;
  final _cd = List<double>.filled(3, 0);
  double _swing = 0, _swingMax = .35, _hurtCd = 0, _grace = 0, _mpT = 0, _runMana = 0;
  double _jumpCd = 0, _deadT = 0;

  /// Height above the ground plane (floors sit well above the ground).
  double z = 0, _vz = 0;
  bool _grounded = true;
  FloorPlatform? _onFloor;
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
  bool get airborne => !_grounded;
  double get jumpCooldownFraction => (_jumpCd / jumpCooldown).clamp(0.0, 1.0);
  double cooldownFraction(int slot) => (_cd[slot] / skillDefs[slot].cd).clamp(0.0, 1.0);

  @override
  Future<void> onLoad() async => _anims = {for (final h in heroes) h.folder: CharAnims(game, h.folder)};

  /// Fresh start for a stage (also used to pick the hero).
  void reset(int hero) {
    heroIndex = hero;
    dead = false;
    _deadT = 0;
    _swing = 0;
    _hurtCd = 0;
    _grace = 0;
    z = 0;
    _vz = 0;
    _grounded = true;
    _onFloor = null;
    _jumpCd = 0;
    running = false;
    facingRight = true;
    _beams.clear();
    _cd.fillRange(0, _cd.length, 0);
    position = VillageGame.playerStart.clone();
    _anim.play('idle', restart: true);
  }

  /// Back on your feet where you fell, with a short grace period.
  void revive() {
    dead = false;
    _deadT = 0;
    _swing = 0;
    _grace = 2.5;
    _beams.clear();
    _cd.fillRange(0, _cd.length, 0);
    _anim.play('idle', restart: true);
  }

  /// Drops whatever attack is in progress (turning around, jumping).
  void _cancelAttack() {
    _swing = 0;
    _beams.clear();
  }

  void toggleRun() {
    if (dead || !game.inPlay) return;
    if (!running && s.mp <= 0) {
      game.world.add(FloatingText('Hết MP', position + Vector2(0, -90), Colors.white));
      return;
    }
    running = !running;
  }

  void jump() {
    if (dead || !game.inPlay || !_grounded || _jumpCd > 0) return;
    _cancelAttack();
    _grounded = false;
    _onFloor = null;
    _vz = jumpSpeed;
    _jumpCd = jumpCooldown;
    GameAudio.sfx('jump');
    _anim.play('jump', restart: true);
  }

  void useSkill(int slot) {
    if (dead || !game.inPlay || _cd[slot] > 0 || _swing > 0) return;
    final d = skillDefs[slot];
    if (s.mp < d.mp) {
      game.world.add(FloatingText('Hết MP', position + Vector2(0, -90), Colors.white));
      return;
    }
    s.mp -= d.mp;
    _cd[slot] = d.cd;
    _active = d;
    _swing = _swingMax = hero.ranged && slot == 2 ? .9 : d.dur;
    _anim.play(d.anim, restart: true);
    GameAudio.sfx(hero.ranged ? 'cast' : 'swing');
    if (hero.ranged) {
      _castRanged(slot, d);
      return;
    }
    for (final m in List<Monster>.from(game.monsters)) {
      final dx = m.x - x;
      final front = d.aoe || dx * (facingRight ? 1 : -1) > -10;
      if (front && dx.abs() < d.reach && (m.y - y).abs() < (d.aoe ? 60 : 40) && (m.z - z).abs() < 50) {
        m.hurt(_damage(d));
      }
    }
  }

  int _damage(SkillDef d) => ((s.attack * hero.dmgMul + rng.nextInt(4)) * d.mult).round();

  void _castRanged(int slot, SkillDef d) {
    final dmg = _damage(d);
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
    // Mid-air jumps (not standing on a floor) dodge hits; so does the grace
    // period after a revive.
    if (dead || _hurtCd > 0 || _grace > 0 || (!_grounded && _vz != 0)) return;
    _hurtCd = .8;
    final real = max(1, dmg - s.defense - hero.defBonus);
    s.hp = max(0, s.hp - real);
    game.fx.burst(position + Vector2(0, -40 - z), const Color(0xFFFF4040), 9, speed: 120, life: .4);
    game.shake(4, .2);
    GameAudio.sfx('hurt');
    _anim.play('hurt', restart: true);
    _cancelAttack();
    game.world.add(FloatingText('-$real', position + Vector2(0, -90), Colors.red));
    if (s.hp == 0) {
      dead = true;
      GameAudio.sfx('dead');
      _deadT = 0;
      z = 0;
      _vz = 0;
      _grounded = true;
      _onFloor = null;
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
    _grace -= dt;
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
    final run = (running || game.shiftHeld) && s.mp > 0;
    if (running && s.mp <= 0) {
      running = false; // out of mana: back to walking
      game.world.add(FloatingText('Hết MP', position + Vector2(0, -90), Colors.white));
    }
    if (run && _moving) {
      // Running continuously burns mana.
      _runMana += runManaPerSecond * dt;
      if (_runMana >= 1) {
        s.mp = max(0, s.mp - _runMana.floor());
        _runMana -= _runMana.floor();
        s.touch();
      }
    }
    position += dir * hero.speed * (run ? 1.0 : .55) * dt;
    position.x = position.x.clamp(30, VillageGame.worldWidth - 30);
    position.y = position.y.clamp(VillageGame.groundTop + 50, VillageGame.groundBottom);
    final wasRight = facingRight;
    if (dir.x > 0.1) facingRight = true;
    if (dir.x < -0.1) facingRight = false;
    if (wasRight != facingRight) _cancelAttack(); // turning around drops the move
    _physics(dt);
    // Standing on a floor: you walk along it, not through depth.
    final f = _onFloor;
    if (f != null && _grounded) position.y = f.y;
    _mpT += dt;
    if (_mpT > 1.5) {
      _mpT = 0;
      if (s.mp < s.maxMp && !(run && _moving)) s.mp++;
    }
    if (_swing > 0) {
      _anim.play(_active.anim);
    } else if (!_grounded) {
      _anim.play('jump');
    } else if (_hurtCd > .5) {
      _anim.play('hurt');
    } else {
      _anim.play(_moving ? (run ? 'run' : 'walk') : 'idle');
    }
    _anim.update(dt);
    priority = y.toInt();
  }

  /// Vertical motion: jump arc, landing on / walking off the raised floors
  /// (one-way: you can jump up through them). Landing snaps you onto the
  /// floor's lane so it behaves like a side-view platform.
  void _physics(double dt) {
    if (_grounded) {
      final f = _onFloor;
      if (f != null && !(f.covers(position) && (z - f.z).abs() < 1)) {
        _grounded = false; // walked off the edge
        _onFloor = null;
      }
      return;
    }
    final prev = z;
    _vz -= gravity * dt;
    z += _vz * dt;
    FloorPlatform? land;
    if (_vz <= 0) land = game.floorAt(position, prev + 1);
    if (land != null && z <= land.z) {
      z = land.z; // landed on a floor
      _onFloor = land;
      position.y = land.y;
    } else if (z <= 0) {
      z = 0;
      _onFloor = null;
    } else {
      return;
    }
    _vz = 0;
    _grounded = true;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(const Rect.fromLTWH(28, 90, 44, 12), Paint()..color = Colors.black26);
    canvas.save();
    canvas.translate(0, -z);
    final sz = size * hero.scale;
    canvas.save();
    canvas.translate((size.x - sz.x) / 2, size.y - sz.y);
    // Blink while the revive grace period runs.
    if (_grace <= 0 || (_grace * 10).floor().isEven) {
      _anim.render(canvas, sz, flip: !facingRight);
    }
    canvas.restore();
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
