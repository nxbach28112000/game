import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_state.dart';

final _rng = Random();

final _pixel = Paint()
  ..filterQuality = FilterQuality.none
  ..isAntiAlias = false;

/// Arena backgrounds (full 3840x2160 scenes scaled to the 800x450 view).
const backgroundFiles = <(String, String)>[
  ('Sân thượng', 'backgrounds/1/terrace.png'),
  ('Phòng ngai vàng', 'backgrounds/2/throne room.png'),
  ('Lâu đài', 'backgrounds/3/castle.png'),
  ('Rừng chết', 'backgrounds/4/dead forest.png'),
];

/// Offline prototype: stages of slimes, a selectable hero, loot, quests.
class VillageGame extends FlameGame with KeyboardEvents {
  VillageGame() : super(camera: CameraComponent.withFixedResolution(width: 800, height: 450));

  static const double worldWidth = 800;
  static const double worldHeight = 450;
  static const double groundTop = 200; // feet can go from groundTop + 50
  static const double groundBottom = 425;
  static final playerStart = Vector2(80, 350);

  /// Kills needed to open the exit arrow of a stage.
  static const killGoal = 50;

  final GameState state = GameState();
  late final Player player;
  late final Background background;
  late FlyPlatform platform;
  late final JoystickComponent joystick;
  final List<Monster> monsters = [];
  final Set<LogicalKeyboardKey> _keys = {};

  int stage = 0;
  int stageKills = 0;
  int selectedHero = 0;

  /// True while a run is being played (false on the select / game over screens).
  bool inPlay = false;

  bool get portalOpen => stageKills >= killGoal;

  @override
  Color backgroundColor() => Colors.black;

  Sprite sprite(String file, [double x = 0, double y = 0, double? w, double? h]) {
    final image = images.fromCache(file);
    return Sprite(image, srcPosition: Vector2(x, y), srcSize: Vector2(w ?? image.width.toDouble(), h ?? image.height.toDouble()));
  }

  Sprite itemSprite(ItemId id) => sprite('${itemDefs[id]!.icon}.png');

  @override
  Future<void> onLoad() async {
    await images.loadAll([
      'monster.png',
      for (final folder in CharAnims.folders)
        for (final spec in CharAnims.specs.values) '$folder/${spec.$1}.png',
      for (final d in itemDefs.values) '${d.icon}.png',
    ]);
    camera.world = world;
    camera.viewfinder
      ..anchor = Anchor.topLeft
      ..position = Vector2.zero();

    background = Background();
    world.add(background);
    world.add(ExitArrow());
    platform = FlyPlatform(430, 320);
    world.add(platform);
    player = Player()..position = playerStart.clone();
    world.add(player);

    joystick = JoystickComponent(
      knob: CircleComponent(radius: 22, paint: Paint()..color = Colors.white.withValues(alpha: .8)),
      background: CircleComponent(radius: 50, paint: Paint()..color = Colors.black.withValues(alpha: .35)),
      margin: const EdgeInsets.only(left: 36, bottom: 36),
    );
    camera.viewport.addAll([
      joystick,
      // Attack 1 (basic), then the two skills (attack 2 / attack 3).
      ActionButton('Đánh', 'J', const Color(0xFFE53935), 36, Vector2(745, 385), () => player.useSkill(0), cooldown: () => player.cooldownFraction(0)),
      ActionButton(
        '',
        'K',
        const Color(0xFF1E88E5),
        28,
        Vector2(662, 405),
        () => player.useSkill(1),
        cooldown: () => player.cooldownFraction(1),
        title: () => player.skillName(1),
      ),
      ActionButton(
        '',
        'L',
        const Color(0xFF7E57C2),
        28,
        Vector2(692, 325),
        () => player.useSkill(2),
        cooldown: () => player.cooldownFraction(2),
        title: () => player.skillName(2),
      ),
      // Support buttons: run, shield, jump.
      ActionButton('Chạy', 'Shift', const Color(0xFFF9A825), 22, Vector2(598, 424), () => player.toggleRun(), active: () => player.running),
      ActionButton(
        'Khiên',
        'F',
        const Color(0xFF43A047),
        22,
        Vector2(578, 372),
        () => player.useSkill(3),
        cooldown: () => player.cooldownFraction(3),
        active: () => player.shielded,
      ),
      ActionButton('Nhảy', 'X', const Color(0xFF00ACC1), 22, Vector2(612, 322), () => player.jump(), cooldown: () => player.jumpCooldownFraction),
      Hud(),
    ]);
    pauseEngine(); // wait on the character select overlay
  }

  // ---- run flow ----
  void startGame(int heroIndex) {
    selectedHero = heroIndex;
    restart();
  }

  Future<void> restart() async {
    state.reset();
    stage = 0;
    await background.setIndex(0);
    _beginStage();
    overlays
      ..remove('select')
      ..remove('gameover')
      ..add('hud');
    inPlay = true;
    resumeEngine();
  }

  void openSelect() {
    inPlay = false;
    _keys.clear();
    overlays
      ..remove('gameover')
      ..remove('hud')
      ..remove('inventory')
      ..remove('quests')
      ..add('select');
    pauseEngine();
  }

  void _beginStage() {
    for (final m in List<Monster>.from(monsters)) {
      m.removeFromParent();
    }
    monsters.clear();
    for (final d in world.children.whereType<Drop>().toList()) {
      d.removeFromParent();
    }
    stageKills = 0;
    platform.removeFromParent();
    final spot = FlyPlatform.spots[stage % FlyPlatform.spots.length];
    platform = FlyPlatform(spot.$1, spot.$2);
    world.add(platform);
    player.reset(selectedHero);
    for (var i = 0; i < 7; i++) {
      _spawnMonster();
    }
    for (var i = 0; i < 2; i++) {
      _spawnMonster(onPlatform: true);
    }
  }

  Future<void> nextStage() async {
    if (_changingStage) return;
    _changingStage = true;
    stage++;
    await background.setIndex(stage % backgroundFiles.length);
    final keepHp = state.hp;
    _beginStage();
    state.hp = min(state.maxHp, max(keepHp, state.maxHp ~/ 2));
    state.touch();
    world.add(FloatingText('Màn ${stage + 1}', Vector2(400, 150), Colors.yellow));
    _changingStage = false;
  }

  bool _changingStage = false;

  void gameOver() {
    if (!inPlay) return;
    inPlay = false;
    _keys.clear();
    overlays
      ..remove('hud')
      ..remove('inventory')
      ..remove('quests')
      ..add('gameover');
    pauseEngine();
  }

  void _spawnMonster({bool onPlatform = false}) {
    final m = Monster(MonsterKind.slime, stage, onPlatform: onPlatform)
      ..position = onPlatform
          ? Vector2(platform.left + 20 + _rng.nextDouble() * (FlyPlatform.slabWidth - 40), platform.y)
          : Vector2(250 + _rng.nextDouble() * (worldWidth - 340), groundTop + 60 + _rng.nextDouble() * (groundBottom - groundTop - 70));
    monsters.add(m);
    world.add(m);
  }

  void monsterDied(Monster m) {
    monsters.remove(m);
    state.onKill();
    if (stageKills < killGoal) {
      stageKills++;
      if (portalOpen) {
        world.add(FloatingText('Hoàn thành màn! Đi sang phải →', Vector2(400, 150), Colors.yellow));
      }
    }
    state.touch();
    final gold = 5 + _rng.nextInt(11) + stage * 3;
    state.gold += gold;
    world.add(FloatingText('+$gold vàng', m.position + Vector2(0, -50), const Color(0xFFFFD54F)));
    void drop(ItemId id, double chance) {
      if (_rng.nextDouble() < chance) {
        world.add(Drop(id)..position = m.position + Vector2(_rng.nextDouble() * 30 - 15, 0));
      }
    }

    drop(ItemId.gel, .65);
    drop(ItemId.potion, .15);
    drop(ItemId.stone, .2);
    final spawnStage = stage;
    Future.delayed(const Duration(seconds: 3), () {
      if (isMounted && inPlay && spawnStage == stage && !portalOpen) {
        _spawnMonster(onPlatform: m.onPlatform);
      }
    });
  }

  // ---- panels ----
  void openPanel(String name) {
    closePanel();
    _keys.clear();
    overlays.add(name);
    pauseEngine();
    state.touch();
  }

  void closePanel() {
    overlays
      ..remove('inventory')
      ..remove('quests');
    if (inPlay) resumeEngine();
  }

  bool get panelOpen => overlays.isActive('inventory') || overlays.isActive('quests');

  void quickPotion() {
    if (!inPlay || player.dead) return;
    if (!state.usePotion()) {
      world.add(FloatingText('Không dùng được', player.position + Vector2(0, -90), Colors.white));
    } else {
      world.add(FloatingText('+HP', player.position + Vector2(0, -90), Colors.greenAccent));
    }
  }

  bool get shiftHeld => _keys.contains(LogicalKeyboardKey.shiftLeft) || _keys.contains(LogicalKeyboardKey.shiftRight);

  Vector2 get inputDirection {
    final d = Vector2.zero();
    if (_keys.contains(LogicalKeyboardKey.keyA) || _keys.contains(LogicalKeyboardKey.arrowLeft)) {
      d.x -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyD) || _keys.contains(LogicalKeyboardKey.arrowRight)) {
      d.x += 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyW) || _keys.contains(LogicalKeyboardKey.arrowUp)) {
      d.y -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyS) || _keys.contains(LogicalKeyboardKey.arrowDown)) {
      d.y += 1;
    }
    if (d.isZero()) return joystick.relativeDelta.clone();
    return d..normalize();
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    _keys
      ..clear()
      ..addAll(keysPressed);
    if (event is! KeyDownEvent || !inPlay) return KeyEventResult.handled;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      if (panelOpen) closePanel();
    } else if (k == LogicalKeyboardKey.keyI) {
      panelOpen ? closePanel() : openPanel('inventory');
    } else if (k == LogicalKeyboardKey.keyQ) {
      panelOpen ? closePanel() : openPanel('quests');
    } else if (panelOpen) {
      return KeyEventResult.handled;
    } else if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyJ) {
      player.useSkill(0);
    } else if (k == LogicalKeyboardKey.digit1 || k == LogicalKeyboardKey.keyK) {
      player.useSkill(1);
    } else if (k == LogicalKeyboardKey.digit2 || k == LogicalKeyboardKey.keyL) {
      player.useSkill(2);
    } else if (k == LogicalKeyboardKey.digit3 || k == LogicalKeyboardKey.keyF) {
      player.useSkill(3);
    } else if (k == LogicalKeyboardKey.keyR) {
      player.toggleRun();
    } else if (k == LogicalKeyboardKey.keyX) {
      player.jump();
    } else if (k == LogicalKeyboardKey.keyH) {
      quickPotion();
    }
    return KeyEventResult.handled;
  }
}

class Background extends Component with HasGameReference<VillageGame> {
  Background() : super(priority: -10000);

  int index = 0;
  ui.Image? _image;
  final _paint = Paint()..filterQuality = FilterQuality.medium;

  String get name => backgroundFiles[index].$1;

  @override
  Future<void> onLoad() => _load(0);

  /// Loads one big scene at a time to keep memory low.
  Future<void> _load(int i) async {
    final old = backgroundFiles[index].$2;
    final image = await game.images.load(backgroundFiles[i].$2);
    if (i != index) game.images.clear(old);
    index = i;
    _image = image;
  }

  Future<void> setIndex(int i) => _load(i);

  @override
  void render(Canvas canvas) {
    final img = _image;
    if (img == null) return;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      const Rect.fromLTWH(0, 0, VillageGame.worldWidth, VillageGame.worldHeight),
      _paint,
    );
  }
}

/// Round on-screen button (skill or support) with cooldown pie and key hint.
class ActionButton extends PositionComponent with TapCallbacks {
  ActionButton(this.label, this.keyHint, this.color, this.radius, Vector2 pos, this.onPress, {this.cooldown, this.active, this.title})
    : super(position: pos, size: Vector2.all(radius * 2), anchor: Anchor.center);

  final String label, keyHint;
  final Color color;
  final double radius;
  final VoidCallback onPress;
  final double Function()? cooldown;
  final bool Function()? active;
  final String Function()? title;

  final _label = TextPaint(
    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 2)]),
  );

  @override
  void onTapDown(TapDownEvent event) => onPress();

  @override
  void render(Canvas canvas) {
    final c = Offset(radius, radius);
    final cd = cooldown?.call() ?? 0;
    final on = active?.call() ?? false;
    canvas.drawCircle(c, radius, Paint()..color = color.withValues(alpha: .85));
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..color = on ? Colors.yellowAccent : Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 4 : 2,
    );
    if (cd > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: radius), -pi / 2, 2 * pi * cd, true, Paint()..color = Colors.black.withValues(alpha: .6));
    }
    _label.render(canvas, title?.call() ?? label, Vector2(radius, radius - 3), anchor: Anchor.center);
    _label.render(canvas, '[$keyHint]', Vector2(radius, radius + 9), anchor: Anchor.center);
  }
}

/// Right-edge arrow that opens the next stage once the kill goal is met.
class ExitArrow extends PositionComponent with HasGameReference<VillageGame> {
  ExitArrow() : super(position: Vector2(740, 305), size: Vector2(50, 60), priority: 90000);

  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    if (game.portalOpen && game.inPlay && !game.player.dead && game.player.x > VillageGame.worldWidth - 55) {
      game.nextStage();
    }
  }

  @override
  void render(Canvas canvas) {
    if (!game.portalOpen) return;
    final dx = sin(_t * 6) * 5;
    final path = Path()
      ..moveTo(0 + dx, 18)
      ..lineTo(26 + dx, 18)
      ..lineTo(26 + dx, 4)
      ..lineTo(50 + dx, 30)
      ..lineTo(26 + dx, 56)
      ..lineTo(26 + dx, 42)
      ..lineTo(0 + dx, 42)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.yellowAccent);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
}

/// Animated 128px-frame character sheets (assets/images/FOLDER/NAME.png).
class CharAnims {
  CharAnims(VillageGame game, this.folder) {
    for (final e in specs.entries) {
      final image = game.images.fromCache('$folder/${e.value.$1}.png');
      final anim = SpriteAnimation.fromFrameData(
        image,
        SpriteAnimationData.sequenced(amount: image.width ~/ 128, stepTime: e.value.$2, textureSize: Vector2.all(128), loop: e.value.$3),
      );
      _tickers[e.key] = anim.createTicker();
    }
  }

  static const folders = ['Fighter', 'Samurai', 'Shinobi', 'Ronin'];

  /// name -> (file, seconds per frame, loops)
  static const specs = <String, (String, double, bool)>{
    'idle': ('Idle', .14, true),
    'walk': ('Walk', .1, true),
    'run': ('Run', .07, true),
    'attack': ('Attack_1', .06, false),
    'skill': ('Attack_3', .07, false),
    'hurt': ('Hurt', .1, false),
    'skill1': ('Attack_2', .08, false),
    'shield': ('Shield', .12, true),
    'jump': ('Jump', .08, false),
    'dead': ('Dead', .14, false),
  };

  final String folder;
  final _tickers = <String, SpriteAnimationTicker>{};
  String _cur = 'idle';

  void play(String name, {bool restart = false}) {
    if (_cur != name || restart) {
      _cur = name;
      _tickers[name]!.reset();
    }
  }

  void update(double dt) => _tickers[_cur]!.update(dt);

  void render(Canvas canvas, Vector2 size, {bool flip = false}) {
    canvas.save();
    if (flip) {
      canvas.translate(size.x, 0);
      canvas.scale(-1, 1);
    }
    _tickers[_cur]!.getSprite().render(canvas, size: size, overridePaint: _pixel);
    canvas.restore();
  }
}

class HeroDef {
  const HeroDef(this.name, this.folder, this.speed, this.dmgMul, this.defBonus, this.skills, this.blurb);

  final String name, folder, blurb;
  final double speed, dmgMul;
  final int defBonus;

  /// Names of skill slots 0..3 (basic attack, two attacks, guard).
  final List<String> skills;
}

const heroes = [
  HeroDef('Shinobi', 'Shinobi', 190, 1.0, 0, ['Đánh', 'Chém nhanh', 'Vòng xoáy', 'Ẩn thân'], 'Nhanh nhẹn, di chuyển linh hoạt.'),
  HeroDef('Samurai', 'Samurai', 150, 1.25, 0, ['Đánh', 'Trảm', 'Kiếm khí', 'Thủ thế'], 'Sát thương cao, tốc độ vừa.'),
  HeroDef('Fighter', 'Fighter', 165, 1.1, 3, ['Đánh', 'Đấm', 'Chấn động', 'Giáp sắt'], 'Trâu bò, giảm thêm sát thương nhận.'),
  HeroDef('Ronin', 'Ronin', 175, 1.2, 1, ['Đánh', 'Đâm', 'Vòng kiếm', 'Khiên'], 'Kiếm khách cân bằng, có khiên và đòn xoáy.'),
];

class SkillDef {
  const SkillDef(this.mp, this.cd, this.mult, this.reach, this.anim, {this.aoe = false, this.dur = .35});

  final int mp;
  final double cd, mult, reach, dur;
  final String anim;
  final bool aoe;
}

const skillDefs = [
  SkillDef(0, .4, 1, 80, 'attack'),
  SkillDef(8, 1.5, 1.7, 95, 'skill1', dur: .3),
  SkillDef(15, 3, 2.2, 140, 'skill', aoe: true),
  SkillDef(12, 8, 0, 0, 'shield', dur: 0), // guard: see Player._shield
];

class Player extends PositionComponent with HasGameReference<VillageGame> {
  Player() : super(size: Vector2.all(100), anchor: Anchor.bottomCenter);

  static const shieldTime = 2.5;
  static const jumpCooldown = .3;
  static const jumpSpeed = 430.0;
  static const gravity = 950.0;

  late final Map<String, CharAnims> _anims;
  int heroIndex = 0;
  final _cd = List<double>.filled(4, 0);
  double _swing = 0, _hurtCd = 0, _mpT = 0, _shield = 0;
  double _jumpCd = 0, _deadT = 0;

  /// Height above the ground plane (the platform top is [FlyPlatform.topHeight]).
  double z = 0, _vz = 0;
  bool _grounded = true;
  SkillDef _active = skillDefs[0];
  bool facingRight = true;
  bool _moving = false;
  bool running = false;
  bool dead = false;

  GameState get s => game.state;
  HeroDef get hero => heroes[heroIndex];
  CharAnims get _anim => _anims[hero.folder]!;
  String skillName(int slot) => hero.skills[slot];
  bool get shielded => _shield > 0;
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
    _shield = 0;
    _hurtCd = 0;
    z = 0;
    _vz = 0;
    _grounded = true;
    _jumpCd = 0;
    running = false;
    facingRight = true;
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
      game.world.add(FloatingText('Hết MP', position + Vector2(0, -90), Colors.white));
      return;
    }
    s.mp -= d.mp;
    _cd[slot] = d.cd;
    if (slot == 3) {
      _shield = shieldTime;
      game.world.add(FloatingText(hero.skills[3], position + Vector2(0, -90), Colors.lightGreenAccent));
      return;
    }
    _active = d;
    _swing = d.dur;
    _anim.play(d.anim, restart: true);
    for (final m in List<Monster>.from(game.monsters)) {
      final dx = m.x - x;
      final front = d.aoe || dx * (facingRight ? 1 : -1) > -10;
      if (front && dx.abs() < d.reach && (m.y - y).abs() < (d.aoe ? 60 : 40) && (m.z - z).abs() < 50) {
        m.hurt(((s.attack * hero.dmgMul + _rng.nextInt(4)) * d.mult).round());
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
    game.world.add(FloatingText(guarded ? 'Chặn -$real' : '-$real', position + Vector2(0, -90), guarded ? Colors.lightGreenAccent : Colors.red));
    if (s.hp == 0) {
      dead = true;
      _deadT = 0;
      _shield = 0;
      _swing = 0;
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
    final dir = game.inputDirection;
    _moving = dir.length > .1;
    final run = running || game.shiftHeld;
    position += dir * hero.speed * (run ? 1.0 : .55) * dt;
    position.x = position.x.clamp(30, VillageGame.worldWidth - 30);
    position.y = position.y.clamp(VillageGame.groundTop + 50, VillageGame.groundBottom);
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
    canvas.drawOval(const Rect.fromLTWH(28, 90, 44, 12), Paint()..color = Colors.black26);
    canvas.save();
    canvas.translate(0, -z);
    _anim.render(canvas, size, flip: !facingRight);
    if (_shield > 0) {
      canvas.drawCircle(
        Offset(size.x / 2, 66),
        46,
        Paint()
          ..color = Colors.lightGreenAccent.withValues(alpha: .25)
          ..style = PaintingStyle.fill,
      );
    }
    if (_swing > 0 && _active.aoe) {
      canvas.drawCircle(
        Offset(size.x / 2, 70),
        90 * (1 - _swing / _active.dur) + 20,
        Paint()
          ..color = Colors.white.withValues(alpha: _swing / _active.dur)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    canvas.restore();
  }
}

/// A floating slab the hero can jump onto; fights can happen on top of it.
class FlyPlatform extends PositionComponent with HasGameReference<VillageGame> {
  FlyPlatform(double cx, double depth) : super(position: Vector2(cx, depth), size: Vector2(slabWidth, 20), anchor: Anchor.bottomCenter);

  static const slabWidth = 170.0;
  static const topHeight = 70.0;

  /// Candidate spots (centre x, depth y), cycled per stage.
  static const spots = [(430.0, 320.0), (300.0, 350.0), (520.0, 300.0)];

  double _t = 0;

  double get left => x - slabWidth / 2;
  double get right => x + slabWidth / 2;

  /// Platform top height if [p] is over it, else 0.
  double heightAt(Vector2 p) => p.x >= left && p.x <= right && (p.y - y).abs() <= 26 ? topHeight : 0;

  @override
  void update(double dt) {
    _t += dt;
    priority = y.toInt() - 1;
  }

  @override
  void render(Canvas canvas) {
    final bob = sin(_t * 2) * 3;
    // Faint shadow on the ground far below: the island clearly hovers.
    canvas.drawOval(Rect.fromLTWH(30, 6, slabWidth - 60, 10), Paint()..color = Colors.black26);
    canvas.save();
    canvas.translate(0, -topHeight + bob);
    // Glow under the island.
    canvas.drawOval(
      Rect.fromLTWH(35, 34, slabWidth - 70, 22),
      Paint()
        ..color = const Color(0xFF80DEEA).withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Tapered rock body.
    final body = Path()
      ..moveTo(0, 6)
      ..quadraticBezierTo(8, 26, slabWidth * .38, 38)
      ..lineTo(slabWidth * .5, 52)
      ..lineTo(slabWidth * .62, 36)
      ..quadraticBezierTo(slabWidth - 8, 26, slabWidth, 6)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFF6D5A4B));
    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Grassy top surface (ellipse reads as a top-down tile).
    final top = Rect.fromLTWH(0, -8, slabWidth, 26);
    canvas.drawOval(top, Paint()..color = const Color(0xFF66BB6A));
    canvas.drawOval(top.deflate(5), Paint()..color = const Color(0xFF81C784));
    canvas.drawOval(
      top,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Little rocks drifting around it.
    final r = Paint()..color = const Color(0xFF6D5A4B);
    canvas.drawCircle(Offset(-6, 40 + sin(_t * 3) * 3), 5, r);
    canvas.drawCircle(Offset(slabWidth + 4, 34 + cos(_t * 2.5) * 3), 4, r);
    canvas.restore();
  }
}

enum MonsterKind { slime }

class Monster extends PositionComponent with HasGameReference<VillageGame> {
  Monster(this.kind, this.stage, {this.onPlatform = false}) : maxHp = 40 + stage * 25, super(size: Vector2(48, 48), anchor: Anchor.bottomCenter) {
    hp = maxHp;
  }

  final MonsterKind kind;
  final int stage;
  final bool onPlatform;
  final int maxHp;
  late int hp;

  /// Height above ground: platform slimes stand on the flying platform.
  double get z => onPlatform ? FlyPlatform.topHeight : 0;
  double _atkCd = 0, _wanderT = 0;
  double _t = _rng.nextDouble() * 5;
  bool _faceRight = true;
  Vector2 _wander = Vector2.zero();
  late final List<Sprite> _frames;

  @override
  Future<void> onLoad() async {
    _frames = [for (var i = 0; i < 2; i++) game.sprite('monster.png', i * 16.0, 0, 16, 16)];
  }

  void hurt(int dmg) {
    hp -= dmg;
    game.world.add(FloatingText('$dmg', position + Vector2(0, -50), Colors.white));
    position.x += (x > game.player.x ? 1 : -1) * 16;
    if (hp <= 0) {
      if (game.state.gainExp(15)) {
        game.world.add(FloatingText('LEVEL UP!', game.player.position + Vector2(0, -110), Colors.yellow));
      }
      game.monsterDied(this);
      removeFromParent();
    }
  }

  @override
  void update(double dt) {
    _t += dt;
    _atkCd -= dt;
    final p = game.player;
    final to = p.position - position;
    final dist = to.length;
    if (dist < 220 && !p.dead && (p.z - z).abs() < 50) {
      if (dist > 40) position += to.normalized() * 60 * dt;
      if (to.x.abs() > 4) _faceRight = to.x > 0;
      if (dist < 55 && _atkCd <= 0) {
        _atkCd = 1.2;
        p.hurt(10 + game.state.level * 2 + stage * 3);
      }
    } else {
      _wanderT -= dt;
      if (_wanderT <= 0) {
        _wanderT = 1 + _rng.nextDouble() * 2;
        _wander = _rng.nextBool() ? Vector2.zero() : (Vector2(_rng.nextDouble() - .5, _rng.nextDouble() - .5)..normalize());
      }
      position += _wander * 28 * dt;
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
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(0, -z);
    canvas.drawOval(const Rect.fromLTWH(4, 40, 40, 8), Paint()..color = Colors.black26);
    canvas.save();
    if (!_faceRight) {
      canvas.translate(size.x, 0);
      canvas.scale(-1, 1);
    }
    _frames[(_t * 2.5).floor() % 2].render(canvas, size: size, overridePaint: _pixel);
    canvas.restore();
    canvas.drawRect(const Rect.fromLTWH(4, -6, 40, 5), Paint()..color = Colors.black54);
    canvas.drawRect(Rect.fromLTWH(4, -6, 40 * hp / maxHp, 5), Paint()..color = Colors.redAccent);
    canvas.restore();
  }
}

class Drop extends PositionComponent with HasGameReference<VillageGame> {
  Drop(this.id) : super(size: Vector2.all(28), anchor: Anchor.bottomCenter);

  final ItemId id;
  double _life = 40, _t = 0, _warn = 0;
  late final Sprite _sprite;

  @override
  Future<void> onLoad() async => _sprite = game.itemSprite(id);

  @override
  void update(double dt) {
    _t += dt;
    _warn -= dt;
    _life -= dt;
    if (_life <= 0) removeFromParent();
    priority = y.toInt();
    if (!game.player.dead && position.distanceTo(game.player.position) < 36) {
      if (game.state.addItem(id)) {
        game.world.add(FloatingText('+${itemDefs[id]!.name}', position + Vector2(0, -30), const Color(0xFF80DEEA)));
        removeFromParent();
      } else if (_warn <= 0) {
        _warn = 2;
        game.world.add(FloatingText('Túi đầy', position + Vector2(0, -30), Colors.red));
      }
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(const Rect.fromLTWH(4, 24, 20, 6), Paint()..color = Colors.black26);
    _sprite.render(canvas, position: Vector2(0, -4 - (sin(_t * 4) + 1) * 3), size: size, overridePaint: _pixel);
  }
}

class FloatingText extends TextComponent {
  FloatingText(String text, Vector2 pos, Color color)
    : super(
        text: text,
        position: pos,
        anchor: Anchor.center,
        priority: 100000,
        textRenderer: TextPaint(
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold, shadows: const [Shadow(blurRadius: 3)]),
        ),
      );

  double _life = .9;

  @override
  void update(double dt) {
    y -= 40 * dt;
    _life -= dt;
    if (_life <= 0) removeFromParent();
  }
}

class Hud extends PositionComponent with HasGameReference<VillageGame> {
  Hud() : super(priority: 100);

  final _text = TextPaint(
    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
  );

  @override
  void render(Canvas canvas) {
    final p = game.state;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(10, 10, 190, 120), const Radius.circular(8)), Paint()..color = Colors.black54);
    _text.render(canvas, 'Lv ${p.level}   EXP ${p.exp}/${p.expToNext}', Vector2(18, 14));
    _bar(canvas, 18, 32, p.hp / p.maxHp, Colors.red, '${p.hp}/${p.maxHp}');
    _bar(canvas, 18, 50, p.mp / p.maxMp, Colors.blue, '${p.mp}/${p.maxMp}');
    _text.render(canvas, 'Vàng: ${p.gold}', Vector2(18, 72));
    _text.render(canvas, 'Nhân vật: ${game.player.hero.name}', Vector2(18, 90));
    _text.render(canvas, 'Màn ${game.stage + 1}: ${game.stageKills}/${VillageGame.killGoal} quái', Vector2(18, 108));
  }

  void _bar(Canvas c, double x, double y, double f, Color col, String t) {
    c.drawRect(Rect.fromLTWH(x, y, 174, 14), Paint()..color = Colors.black45);
    c.drawRect(Rect.fromLTWH(x, y, 174 * f, 14), Paint()..color = col);
    _text.render(c, t, Vector2(x + 4, y));
  }
}
