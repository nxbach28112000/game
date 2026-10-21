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

/// Offline prototype: an arena, a switchable hero, monsters, loot, quests.
class VillageGame extends FlameGame with KeyboardEvents {
  VillageGame()
      : super(
            camera: CameraComponent.withFixedResolution(
                width: 800, height: 450));

  static const double worldWidth = 800;
  static const double worldHeight = 450;
  static const double groundTop = 200; // feet can go from groundTop + 50
  static const double groundBottom = 425;
  static final npcPosition = Vector2(110, 330);
  static final playerStart = Vector2(400, 350);

  final GameState state = GameState();
  late final Player player;
  late final Npc npc;
  late final Background background;
  late final JoystickComponent joystick;
  final List<Monster> monsters = [];
  final Set<LogicalKeyboardKey> _keys = {};

  /// Whether the quest panel was opened by talking to the NPC.
  bool questAtNpc = false;

  @override
  Color backgroundColor() => Colors.black;

  Sprite sprite(String file,
      [double x = 0, double y = 0, double? w, double? h]) {
    final image = images.fromCache(file);
    return Sprite(image,
        srcPosition: Vector2(x, y),
        srcSize: Vector2(w ?? image.width.toDouble(), h ?? image.height.toDouble()));
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
    npc = Npc()..position = npcPosition;
    world.add(npc);
    player = Player()..position = playerStart.clone();
    world.add(player);
    for (var i = 0; i < 7; i++) {
      _spawnMonster();
    }

    joystick = JoystickComponent(
      knob: CircleComponent(
          radius: 22,
          paint: Paint()..color = Colors.white.withValues(alpha: .8)),
      background: CircleComponent(
          radius: 50,
          paint: Paint()..color = Colors.black.withValues(alpha: .35)),
      margin: const EdgeInsets.only(left: 36, bottom: 36),
    );
    camera.viewport.addAll([
      joystick,
      SkillButton(0, 34, Vector2(770, 420)),
      SkillButton(1, 26, Vector2(688, 420)),
      SkillButton(2, 26, Vector2(630, 420)),
      SkillButton(3, 26, Vector2(572, 420)),
      Hud(),
    ]);
  }

  void _spawnMonster() {
    final roll = _rng.nextDouble();
    final kind = roll < .6
        ? MonsterKind.slime
        : (roll < .8 ? MonsterKind.fighter : MonsterKind.samurai);
    final m = Monster(kind)
      ..position = Vector2(
          250 + _rng.nextDouble() * (worldWidth - 320),
          groundTop + 60 + _rng.nextDouble() * (groundBottom - groundTop - 70));
    monsters.add(m);
    world.add(m);
  }

  void monsterDied(Monster m) {
    monsters.remove(m);
    state.onKill();
    final human = m.kind != MonsterKind.slime;
    final gold = (5 + _rng.nextInt(11)) * (human ? 3 : 1);
    state.gold += gold;
    world.add(FloatingText('+$gold vàng', m.position + Vector2(0, -50),
        const Color(0xFFFFD54F)));
    void drop(ItemId id, double chance) {
      if (_rng.nextDouble() < chance) {
        world.add(Drop(id)
          ..position = m.position + Vector2(_rng.nextDouble() * 30 - 15, 0));
      }
    }

    drop(ItemId.gel, human ? 0 : .65);
    drop(ItemId.potion, human ? .3 : .15);
    drop(ItemId.stone, human ? .4 : .2);
    Future.delayed(const Duration(seconds: 4), () {
      if (isMounted) _spawnMonster();
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
    resumeEngine();
  }

  bool get panelOpen =>
      overlays.isActive('inventory') || overlays.isActive('quests');

  void talkToNpc() {
    if (panelOpen) return;
    if (player.position.distanceTo(npc.position) > 140) {
      world.add(FloatingText('Lại gần làng trưởng hơn',
          npc.position + Vector2(0, -110), Colors.white));
      return;
    }
    questAtNpc = true;
    openPanel('quests');
  }

  void quickPotion() {
    if (!state.usePotion()) {
      world.add(FloatingText('Không dùng được',
          player.position + Vector2(0, -90), Colors.white));
    } else {
      world.add(FloatingText(
          '+HP', player.position + Vector2(0, -90), Colors.greenAccent));
    }
  }

  void switchCharacter() => player.switchCharacter();

  Future<void> nextBackground() => background.next();

  Vector2 get inputDirection {
    final d = Vector2.zero();
    if (_keys.contains(LogicalKeyboardKey.keyA) ||
        _keys.contains(LogicalKeyboardKey.arrowLeft)) {
      d.x -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyD) ||
        _keys.contains(LogicalKeyboardKey.arrowRight)) {
      d.x += 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyW) ||
        _keys.contains(LogicalKeyboardKey.arrowUp)) {
      d.y -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyS) ||
        _keys.contains(LogicalKeyboardKey.arrowDown)) {
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
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      if (panelOpen) closePanel();
    } else if (k == LogicalKeyboardKey.keyI) {
      panelOpen ? closePanel() : openPanel('inventory');
    } else if (k == LogicalKeyboardKey.keyQ) {
      if (panelOpen) {
        closePanel();
      } else {
        questAtNpc = false;
        openPanel('quests');
      }
    } else if (panelOpen) {
      return KeyEventResult.handled;
    } else if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyJ) {
      player.useSkill(0);
    } else if (k == LogicalKeyboardKey.digit1 || k == LogicalKeyboardKey.keyK) {
      player.useSkill(1);
    } else if (k == LogicalKeyboardKey.digit2 || k == LogicalKeyboardKey.keyL) {
      player.useSkill(2);
    } else if (k == LogicalKeyboardKey.digit3 ||
        k == LogicalKeyboardKey.keyF) {
      player.useSkill(3);
    } else if (k == LogicalKeyboardKey.keyC) {
      switchCharacter();
    } else if (k == LogicalKeyboardKey.keyM) {
      nextBackground();
    } else if (k == LogicalKeyboardKey.keyH) {
      quickPotion();
    } else if (k == LogicalKeyboardKey.keyE) {
      talkToNpc();
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

  Future<void> next() => _load((index + 1) % backgroundFiles.length);

  @override
  void render(Canvas canvas) {
    final img = _image;
    if (img == null) return;
    canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        const Rect.fromLTWH(0, 0, VillageGame.worldWidth, VillageGame.worldHeight),
        _paint);
  }
}

/// Round on-screen button for a skill slot, with cooldown pie and key hint.
class SkillButton extends PositionComponent
    with HasGameReference<VillageGame>, TapCallbacks {
  SkillButton(this.slot, this.radius, Vector2 pos)
      : super(
            position: pos,
            size: Vector2.all(radius * 2),
            anchor: Anchor.bottomRight);

  final int slot;
  final double radius;

  static const _keys = ['Space', '1', '2', '3'];
  static const _colors = [
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF7E57C2),
    Color(0xFF43A047),
  ];

  final _label = TextPaint(
      style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(blurRadius: 2)]));

  @override
  void onTapDown(TapDownEvent event) => game.player.useSkill(slot);

  @override
  void render(Canvas canvas) {
    final p = game.player;
    final c = Offset(radius, radius);
    final ready = p.cooldownFraction(slot) <= 0;
    canvas.drawCircle(c, radius, Paint()..color = _colors[slot]);
    canvas.drawCircle(
        c,
        radius,
        Paint()
          ..color = Colors.white54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    if (!ready) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: radius),
          -pi / 2,
          2 * pi * p.cooldownFraction(slot),
          true,
          Paint()..color = Colors.black.withValues(alpha: .6));
    }
    _label.render(canvas, p.skillName(slot), Vector2(radius, radius - 3),
        anchor: Anchor.center);
    _label.render(canvas, '[${_keys[slot]}]', Vector2(radius, radius + 9),
        anchor: Anchor.center);
  }
}

/// Animated 128px-frame character sheets (assets/images/FOLDER/NAME.png).
class CharAnims {
  CharAnims(VillageGame game, this.folder) {
    for (final e in specs.entries) {
      final image = game.images.fromCache('$folder/${e.value.$1}.png');
      final anim = SpriteAnimation.fromFrameData(
        image,
        SpriteAnimationData.sequenced(
          amount: image.width ~/ 128,
          stepTime: e.value.$2,
          textureSize: Vector2.all(128),
          loop: e.value.$3,
        ),
      );
      _tickers[e.key] = anim.createTicker();
    }
  }

  static const folders = ['Fighter', 'Samurai', 'Shinobi'];

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
    _tickers[_cur]!
        .getSprite()
        .render(canvas, size: size, overridePaint: _pixel);
    canvas.restore();
  }
}

class HeroDef {
  const HeroDef(this.name, this.folder, this.speed, this.dmgMul,
      this.defBonus, this.skills);

  final String name, folder;
  final double speed, dmgMul;
  final int defBonus;

  /// Names of skill slots 0..3 (basic attack, two attacks, guard).
  final List<String> skills;
}

const heroes = [
  HeroDef('Shinobi', 'Shinobi', 190, 1.0, 0,
      ['Đánh', 'Chém nhanh', 'Vòng xoáy', 'Ẩn thân']),
  HeroDef('Samurai', 'Samurai', 150, 1.25, 0,
      ['Đánh', 'Trảm', 'Kiếm khí', 'Thủ thế']),
  HeroDef('Fighter', 'Fighter', 165, 1.1, 3,
      ['Đánh', 'Đấm', 'Chấn động', 'Giáp sắt']),
];

class SkillDef {
  const SkillDef(this.mp, this.cd, this.mult, this.reach, this.anim,
      {this.aoe = false, this.dur = .35});

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
  late final Map<String, CharAnims> _anims;
  int heroIndex = 0;
  final _cd = List<double>.filled(4, 0);
  double _swing = 0, _hurtCd = 0, _mpT = 0, _shield = 0;
  SkillDef _active = skillDefs[0];
  bool facingRight = true;
  bool _moving = false;

  GameState get s => game.state;
  HeroDef get hero => heroes[heroIndex];
  CharAnims get _anim => _anims[hero.folder]!;
  String skillName(int slot) => hero.skills[slot];
  double cooldownFraction(int slot) =>
      (_cd[slot] / skillDefs[slot].cd).clamp(0.0, 1.0);

  @override
  Future<void> onLoad() async => _anims = {
        for (final h in heroes) h.folder: CharAnims(game, h.folder)
      };

  void switchCharacter() {
    heroIndex = (heroIndex + 1) % heroes.length;
    _swing = 0;
    _shield = 0;
    _cd.fillRange(0, _cd.length, 0);
    game.world.add(FloatingText(
        hero.name, position + Vector2(0, -100), Colors.cyanAccent));
  }

  void useSkill(int slot) {
    if (_cd[slot] > 0 || _swing > 0) return;
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
    _swing = d.dur;
    _anim.play(d.anim, restart: true);
    for (final m in List<Monster>.from(game.monsters)) {
      final dx = m.x - x;
      final front = d.aoe || dx * (facingRight ? 1 : -1) > -10;
      if (front && dx.abs() < d.reach && (m.y - y).abs() < (d.aoe ? 60 : 40)) {
        m.hurt(((s.attack * hero.dmgMul + _rng.nextInt(4)) * d.mult).round());
      }
    }
  }

  void hurt(int dmg) {
    if (_hurtCd > 0) return;
    _hurtCd = .8;
    final guarded = _shield > 0;
    final base = max(1, dmg - s.defense - hero.defBonus);
    final real = guarded ? max(1, (base * .2).round()) : base;
    s.hp = max(0, s.hp - real);
    if (!guarded) _anim.play('hurt', restart: true);
    game.world.add(FloatingText(guarded ? 'Chặn -$real' : '-$real',
        position + Vector2(0, -90), guarded ? Colors.lightGreenAccent : Colors.red));
    if (s.hp == 0) {
      s.hp = s.maxHp;
      position = VillageGame.playerStart.clone();
      game.world.add(FloatingText(
          'Hồi sinh', position + Vector2(0, -90), Colors.white));
    }
  }

  @override
  void update(double dt) {
    for (var i = 0; i < _cd.length; i++) {
      _cd[i] -= dt;
    }
    _swing -= dt;
    _hurtCd -= dt;
    _shield -= dt;
    final dir = game.inputDirection;
    _moving = dir.length > .1;
    position += dir * hero.speed * dt;
    position.x = position.x.clamp(30, VillageGame.worldWidth - 30);
    position.y =
        position.y.clamp(VillageGame.groundTop + 50, VillageGame.groundBottom);
    if (dir.x > 0.1) facingRight = true;
    if (dir.x < -0.1) facingRight = false;
    _mpT += dt;
    if (_mpT > 1.5) {
      _mpT = 0;
      if (s.mp < s.maxMp) s.mp++;
    }
    if (_swing > 0) {
      _anim.play(_active.anim);
    } else if (_hurtCd > .5 && _shield <= 0) {
      _anim.play('hurt');
    } else if (_shield > 0) {
      _anim.play('shield');
    } else {
      _anim.play(_moving ? 'run' : 'idle');
    }
    _anim.update(dt);
    priority = y.toInt();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(const Rect.fromLTWH(28, 90, 44, 12),
        Paint()..color = Colors.black26);
    _anim.render(canvas, size, flip: !facingRight);
    if (_shield > 0) {
      canvas.drawCircle(
          Offset(size.x / 2, 66),
          46,
          Paint()
            ..color = Colors.lightGreenAccent.withValues(alpha: .25)
            ..style = PaintingStyle.fill);
    }
    if (_swing > 0 && _active.aoe) {
      canvas.drawCircle(
          Offset(size.x / 2, 70),
          90 * (1 - _swing / _active.dur) + 20,
          Paint()
            ..color = Colors.white.withValues(alpha: _swing / _active.dur)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
    }
  }
}

enum MonsterKind { slime, fighter, samurai }

class Monster extends PositionComponent with HasGameReference<VillageGame> {
  Monster(this.kind)
      : maxHp = kind == MonsterKind.slime ? 40 : 80,
        super(
            size: kind == MonsterKind.slime
                ? Vector2(48, 48)
                : Vector2.all(100),
            anchor: Anchor.bottomCenter) {
    hp = maxHp;
  }

  final MonsterKind kind;
  final int maxHp;
  late int hp;
  double _atkCd = 0, _wanderT = 0, _hurtT = 0, _atkAnim = 0;
  double _t = _rng.nextDouble() * 5;
  bool _faceRight = true, _moving = false;
  Vector2 _wander = Vector2.zero();
  late final List<Sprite> _frames;
  CharAnims? _anim;

  bool get human => kind != MonsterKind.slime;

  @override
  Future<void> onLoad() async {
    if (human) {
      _anim = CharAnims(
          game, kind == MonsterKind.fighter ? 'Fighter' : 'Samurai');
    } else {
      _frames = [
        for (var i = 0; i < 2; i++) game.sprite('monster.png', i * 16.0, 0, 16, 16)
      ];
    }
  }

  void hurt(int dmg) {
    hp -= dmg;
    _hurtT = .3;
    _anim?.play('hurt', restart: true);
    game.world.add(FloatingText(
        '$dmg', position + Vector2(0, human ? -70 : -50), Colors.white));
    position.x += (x > game.player.x ? 1 : -1) * 16;
    if (hp <= 0) {
      if (game.state.gainExp(human ? 30 : 15)) {
        game.world.add(FloatingText('LEVEL UP!',
            game.player.position + Vector2(0, -110), Colors.yellow));
      }
      game.monsterDied(this);
      removeFromParent();
    }
  }

  @override
  void update(double dt) {
    _t += dt;
    _atkCd -= dt;
    _hurtT -= dt;
    _atkAnim -= dt;
    final p = game.player;
    final to = p.position - position;
    final dist = to.length;
    final speed = human ? 70.0 : 60.0;
    _moving = false;
    if (dist < 220) {
      if (dist > 40) {
        position += to.normalized() * speed * dt;
        _moving = true;
      }
      if (to.x.abs() > 4) _faceRight = to.x > 0;
      if (dist < 55 && _atkCd <= 0) {
        _atkCd = 1.2;
        _atkAnim = .35;
        _anim?.play('attack', restart: true);
        p.hurt((human ? 16 : 10) + game.state.level * 2);
      }
    } else {
      _wanderT -= dt;
      if (_wanderT <= 0) {
        _wanderT = 1 + _rng.nextDouble() * 2;
        _wander = _rng.nextBool()
            ? Vector2.zero()
            : (Vector2(_rng.nextDouble() - .5, _rng.nextDouble() - .5)
              ..normalize());
      }
      position += _wander * 28 * dt;
      _moving = !_wander.isZero();
      if (_wander.x.abs() > .1) _faceRight = _wander.x > 0;
    }
    position.x = position.x.clamp(30, VillageGame.worldWidth - 30);
    position.y = position.y
        .clamp(VillageGame.groundTop + 40, VillageGame.groundBottom);
    priority = y.toInt();
    final a = _anim;
    if (a != null) {
      if (_hurtT > 0) {
        a.play('hurt');
      } else if (_atkAnim > 0) {
        a.play('attack');
      } else {
        a.play(_moving ? 'walk' : 'idle');
      }
      a.update(dt);
    }
  }

  @override
  void render(Canvas canvas) {
    final barY = human ? 28.0 : -6.0;
    final barX = human ? 30.0 : 4.0;
    final barW = 40.0;
    if (human) {
      canvas.drawOval(const Rect.fromLTWH(28, 90, 44, 12),
          Paint()..color = Colors.black26);
      _anim!.render(canvas, size, flip: !_faceRight);
    } else {
      canvas.drawOval(const Rect.fromLTWH(4, 40, 40, 8),
          Paint()..color = Colors.black26);
      canvas.save();
      if (!_faceRight) {
        canvas.translate(size.x, 0);
        canvas.scale(-1, 1);
      }
      _frames[(_t * 2.5).floor() % 2]
          .render(canvas, size: size, overridePaint: _pixel);
      canvas.restore();
    }
    canvas.drawRect(Rect.fromLTWH(barX, barY, barW, 5),
        Paint()..color = Colors.black54);
    canvas.drawRect(Rect.fromLTWH(barX, barY, barW * hp / maxHp, 5),
        Paint()..color = Colors.redAccent);
  }
}

class Npc extends PositionComponent
    with HasGameReference<VillageGame>, TapCallbacks {
  Npc() : super(size: Vector2.all(100), anchor: Anchor.bottomCenter);

  late final CharAnims _anim;
  double _t = 0;

  final _name = TextPaint(
      style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(blurRadius: 3)]));
  final _mark = TextPaint(
      style: const TextStyle(
          color: Color(0xFFFFD54F),
          fontSize: 26,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(blurRadius: 3)]));

  @override
  Future<void> onLoad() async {
    _anim = CharAnims(game, 'Samurai');
    priority = y.toInt();
  }

  @override
  void update(double dt) {
    _t += dt;
    _anim.update(dt);
  }

  @override
  void onTapDown(TapDownEvent event) => game.talkToNpc();

  @override
  void render(Canvas canvas) {
    canvas.drawOval(const Rect.fromLTWH(28, 90, 44, 12),
        Paint()..color = Colors.black26);
    _anim.render(canvas, size, flip: game.player.x < x);
    _name.render(canvas, 'Làng trưởng', Vector2(size.x / 2, 30),
        anchor: Anchor.bottomCenter);
    if (game.state.hasQuestAttention) {
      _mark.render(canvas, '!', Vector2(size.x / 2, 12 + sin(_t * 5) * 3),
          anchor: Anchor.bottomCenter);
    }
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
    if (position.distanceTo(game.player.position) < 36) {
      if (game.state.addItem(id)) {
        game.world.add(FloatingText('+${itemDefs[id]!.name}',
            position + Vector2(0, -30), const Color(0xFF80DEEA)));
        removeFromParent();
      } else if (_warn <= 0) {
        _warn = 2;
        game.world.add(
            FloatingText('Túi đầy', position + Vector2(0, -30), Colors.red));
      }
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(const Rect.fromLTWH(4, 24, 20, 6),
        Paint()..color = Colors.black26);
    _sprite.render(canvas,
        position: Vector2(0, -4 - (sin(_t * 4) + 1) * 3),
        size: size,
        overridePaint: _pixel);
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
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  shadows: const [Shadow(blurRadius: 3)])),
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
      style: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold));

  @override
  void render(Canvas canvas) {
    final p = game.state;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(10, 10, 190, 120), const Radius.circular(8)),
        Paint()..color = Colors.black54);
    _text.render(
        canvas, 'Lv ${p.level}   EXP ${p.exp}/${p.expToNext}', Vector2(18, 14));
    _bar(canvas, 18, 32, p.hp / p.maxHp, Colors.red, '${p.hp}/${p.maxHp}');
    _bar(canvas, 18, 50, p.mp / p.maxMp, Colors.blue, '${p.mp}/${p.maxMp}');
    _text.render(canvas, 'Vàng: ${p.gold}', Vector2(18, 72));
    _text.render(canvas, 'Nhân vật: ${game.player.hero.name} [C]',
        Vector2(18, 90));
    _text.render(
        canvas, 'Map: ${game.background.name} [M]', Vector2(18, 108));
  }

  void _bar(Canvas c, double x, double y, double f, Color col, String t) {
    c.drawRect(Rect.fromLTWH(x, y, 174, 14), Paint()..color = Colors.black45);
    c.drawRect(Rect.fromLTWH(x, y, 174 * f, 14), Paint()..color = col);
    _text.render(c, t, Vector2(x + 4, y));
  }
}
