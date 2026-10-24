import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/audio.dart';
import 'common.dart';
import 'game_state.dart';
import 'heroes.dart';
import 'monster.dart';
import 'player.dart';
import 'save_store.dart';
import 'scenery.dart';
import 'stages.dart';

/// Build with --dart-define=QUICK=true to need only 3 kills per stage.
const kQuick = bool.fromEnvironment('QUICK');

/// The flying platform is switched off for now (set true to bring it back).
const kPlatforms = false;

const _crystalColors = ['red', 'red', 'blue', 'violet'];

/// Offline action game: 4 worlds of slime hordes and bosses, 7 heroes, loot,
/// quests, a shop and checkpoint saves.
class VillageGame extends FlameGame with KeyboardEvents {
  VillageGame()
      : super(camera: CameraComponent.withFixedResolution(width: 800, height: 450));

  static const double worldWidth = 800;
  static const double worldHeight = 450;
  static const double groundTop = 200; // feet can go from groundTop + 50
  static const double groundBottom = 425;
  static final playerStart = Vector2(80, 350);

  final GameState state = GameState();
  late final Player player;
  late final Background background;
  late final ParticleLayer fx;
  double _shakeT = 0, _shakeAmp = 0;
  late FlyPlatform platform;
  late final JoystickComponent joystick;
  final List<Monster> monsters = [];
  final Set<LogicalKeyboardKey> _keys = {};

  int stageIdx = 0;
  int stageKills = 0;
  int selectedHero = 0;
  int runKills = 0;
  int _recordedKills = 0;
  double runTime = 0;
  bool bossDefeated = false;
  Monster? bossRef;

  /// True while a run is being played (false on menu / select / end screens).
  bool inPlay = false;
  bool _changing = false;

  /// Fired once assets are loaded (the debug entry uses it to auto-start).
  VoidCallback? onReady;
  Map<String, dynamic>? _checkpoint;

  /// Pending monster respawns: (seconds left, on platform, stage index).
  final _respawns = <(double, bool, int)>[];

  StageDef get stageDef => stages[stageIdx];
  bool get isBossStage => stageDef.boss != null;
  int get killGoal => kQuick ? 3 : 50;
  bool get portalOpen => isBossStage ? bossDefeated : stageKills >= killGoal;
  bool get isLastStage => stageIdx == stages.length - 1;

  @override
  Color backgroundColor() => Colors.black;

  Sprite sprite(String file, [double x = 0, double y = 0, double? w, double? h]) {
    final image = images.fromCache(file);
    return Sprite(image,
        srcPosition: Vector2(x, y),
        srcSize: Vector2(w ?? image.width.toDouble(), h ?? image.height.toDouble()));
  }

  Sprite itemSprite(ItemId id) => sprite('${itemDefs[id]!.icon}.png');

  @override
  Future<void> onLoad() async {
    await images.loadAll([
      for (final k in EnemyKind.values) if (k.file != null) k.file!,
      for (final folder in CharAnims.folders)
        for (final spec in CharAnims.specs.values) '$folder/${spec.$1}.png',
      for (final p in projDefs.values) '${p.folder}/Proj.png',
      for (final d in itemDefs.values) '${d.icon}.png',
      for (var i = 1; i <= 4; i++) 'Portraits/boss$i.png',
      for (var i = 1; i <= 10; i++) 'Props/bush$i.png',
      for (final c in _crystalColors)
        for (final n in const [1, 3, 5]) 'Props/crystal_$c$n.png',
    ]);
    camera.world = world;
    camera.viewfinder
      ..anchor = Anchor.topLeft
      ..position = Vector2.zero();

    background = Background();
    world.add(background);
    world.add(SceneFx());
    fx = ParticleLayer();
    world.add(fx);
    world.add(ExitArrow());
    platform = FlyPlatform(430, 320);
    if (kPlatforms) world.add(platform);
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
      ActionButton('Đánh', 'J', const Color(0xFFE53935), 36, Vector2(745, 385), () => player.useSkill(0),
          cooldown: () => player.cooldownFraction(0)),
      ActionButton('', 'K', const Color(0xFF1E88E5), 28, Vector2(662, 405), () => player.useSkill(1),
          cooldown: () => player.cooldownFraction(1), title: () => player.skillName(1)),
      ActionButton('', 'L', const Color(0xFF7E57C2), 28, Vector2(692, 325), () => player.useSkill(2),
          cooldown: () => player.cooldownFraction(2), title: () => player.skillName(2)),
      // Support buttons: run, shield, jump.
      ActionButton('Chạy', 'Shift', const Color(0xFFF9A825), 22, Vector2(598, 424), () => player.toggleRun(),
          active: () => player.running),
      ActionButton('Khiên', 'F', const Color(0xFF43A047), 22, Vector2(578, 372), () => player.useSkill(3),
          cooldown: () => player.cooldownFraction(3), active: () => player.shielded),
      ActionButton('Nhảy', 'X', const Color(0xFF00ACC1), 22, Vector2(612, 322), () => player.jump(),
          cooldown: () => player.jumpCooldownFraction),
      Hud(),
    ]);
    pauseEngine(); // wait on the main menu overlay
    GameAudio.init();
    GameAudio.music('menu');
    onReady?.call();
  }

  /// Screen shake (boss slams, big hits).
  void shake(double amp, [double dur = .3]) {
    if (amp >= _shakeAmp || _shakeT <= 0) _shakeAmp = amp;
    _shakeT = dur;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_shakeT > 0) {
      _shakeT -= dt;
      final k = _shakeAmp * min(1.0, _shakeT / .25);
      camera.viewfinder.position = Vector2((rng.nextDouble() - .5) * 2 * k, (rng.nextDouble() - .5) * 2 * k);
    } else if (!camera.viewfinder.position.isZero()) {
      camera.viewfinder.position = Vector2.zero();
    }
    if (!inPlay) return;
    runTime += dt;
    for (var i = _respawns.length - 1; i >= 0; i--) {
      final (t, onPlat, st) = _respawns[i];
      if (t - dt > 0) {
        _respawns[i] = (t - dt, onPlat, st);
        continue;
      }
      _respawns.removeAt(i);
      if (st == stageIdx && !portalOpen) _spawnMonster(onPlatform: onPlat);
    }
  }

  // ---- run flow ----
  /// New run with [heroIndex] from stage 1.
  Future<void> startNew(int heroIndex, {int stage = 0}) async {
    selectedHero = heroIndex;
    state.reset();
    stageIdx = stage.clamp(0, stages.length - 1);
    runKills = 0;
    _recordedKills = 0;
    runTime = 0;
    await SaveStore.clearRun();
    await _enterStage();
    _beginPlay();
  }

  /// Resume from the checkpoint written at the start of the last stage.
  Future<bool> continueRun() async {
    final run = await SaveStore.loadRun();
    if (run == null) return false;
    try {
      _applyRun(run);
    } catch (_) {
      return false;
    }
    await _enterStage(checkpoint: false);
    _beginPlay();
    return true;
  }

  /// After a game over: retry the current stage from its checkpoint.
  Future<void> retryStage() async {
    final run = _checkpoint;
    if (run == null) return;
    _applyRun(run);
    state.hp = state.maxHp;
    state.mp = state.maxMp;
    await _enterStage(checkpoint: false);
    _beginPlay();
  }

  Map<String, dynamic> _runJson() => {
        'hero': selectedHero,
        'stage': stageIdx,
        'kills': runKills,
        'time': runTime.round(),
        'state': state.toJson(),
      };

  void _applyRun(Map<String, dynamic> run) {
    selectedHero = run['hero'] as int;
    stageIdx = run['stage'] as int;
    runKills = run['kills'] as int;
    _recordedKills = runKills;
    runTime = (run['time'] as int).toDouble();
    state.loadJson(run['state'] as Map<String, dynamic>);
  }

  void _beginPlay() {
    overlays
      ..remove('menu')
      ..remove('select')
      ..remove('gameover')
      ..remove('victory')
      ..remove('pause')
      ..add('hud');
    inPlay = true;
    resumeEngine();
  }


  void toMenu() {
    _flushRecords();
    inPlay = false;
    _keys.clear();
    for (final o in const ['hud', 'inventory', 'quests', 'shop', 'pause', 'gameover', 'victory', 'select', 'help']) {
      overlays.remove(o);
    }
    overlays.add('menu');
    GameAudio.music('menu');
    pauseEngine();
  }

  void openSelect() {
    overlays
      ..remove('menu')
      ..remove('gameover')
      ..add('select');
  }

  void openPause() {
    if (!inPlay || overlays.isActive('pause')) return;
    _keys.clear();
    overlays.add('pause');
    pauseEngine();
  }

  void closePause() {
    overlays.remove('pause');
    if (inPlay && !panelOpen) resumeEngine();
  }

  void _flushRecords({bool win = false}) {
    SaveStore.addRecords(stage: stageIdx + (win ? 1 : 0) + 1, kills: runKills - _recordedKills, win: win);
    _recordedKills = runKills;
  }

  void _clearStage() {
    for (final m in List<Monster>.from(world.children.whereType<Monster>())) {
      m.removeFromParent();
    }
    monsters.clear();
    _respawns.clear();
    fx.clear();
    for (final c in [
      ...world.children.whereType<Drop>(),
      ...world.children.whereType<Projectile>(),
      ...world.children.whereType<Prop>(),
    ]) {
      c.removeFromParent();
    }
  }

  Future<void> _enterStage({bool checkpoint = true}) async {
    _changing = true;
    await background.setIndex(stageDef.bg);
    _clearStage();
    stageKills = 0;
    bossDefeated = false;
    bossRef = null;
    platform.removeFromParent();
    final spot = FlyPlatform.spots[stageIdx % FlyPlatform.spots.length];
    platform = FlyPlatform(spot.$1, spot.$2);
    if (kPlatforms) world.add(platform);
    player.reset(selectedHero);
    _spawnProps();
    final boss = stageDef.boss;
    if (boss != null) {
      bossRef = Monster(EnemyKind.slime, stageIdx, boss: boss)..position = Vector2(620, 340);
      monsters.add(bossRef!);
      world.add(bossRef!);
      for (var i = 0; i < 3; i++) {
        _spawnMonster(kind: EnemyKind.slime);
      }
    } else {
      for (var i = 0; i < 7; i++) {
        _spawnMonster();
      }
    }
    for (var i = 0; i < (kPlatforms ? 2 : 0); i++) {
      _spawnMonster(onPlatform: true);
    }
    if (checkpoint) {
      _checkpoint = _runJson();
      SaveStore.saveRun(_checkpoint!);
    }
    world.add(FloatingText(
        boss != null ? 'BOSS: ${boss.name}' : 'Màn ${stageIdx + 1}: ${stageDef.name}',
        Vector2(400, 140),
        boss != null ? Colors.redAccent : Colors.yellow));
    GameAudio.music(boss != null ? 'boss' : 'w${stageDef.bg + 1}');
    GameAudio.sfx(boss != null ? 'roar' : 'stage');
    _changing = false;
  }

  Future<void> nextStage() async {
    if (_changing || !inPlay) return;
    if (isLastStage) {
      victory();
      return;
    }
    stageIdx++;
    state.hp = max(state.hp, state.maxHp ~/ 2);
    state.mp = state.maxMp;
    state.touch();
    _flushRecords();
    await _enterStage();
  }

  void gameOver() {
    if (!inPlay) return;
    inPlay = false;
    _keys.clear();
    _flushRecords();
    overlays
      ..remove('hud')
      ..remove('inventory')
      ..remove('quests')
      ..remove('shop')
      ..add('gameover');
    GameAudio.music(null);
    GameAudio.sfx('gameover');
    pauseEngine();
  }

  void victory() {
    if (!inPlay) return;
    inPlay = false;
    _keys.clear();
    _flushRecords(win: true);
    SaveStore.clearRun();
    overlays
      ..remove('hud')
      ..remove('inventory')
      ..remove('quests')
      ..remove('shop')
      ..add('victory');
    GameAudio.music(null);
    GameAudio.sfx('victory');
    pauseEngine();
  }

  void _spawnProps() {
    // Glowing crystals suit the dark scenes; the dead forest also gets a few
    // withered bushes (darkened so they do not pop against the background).
    final crystal = _crystalColors[stageDef.bg];
    const tints = [Color(0xFFE0A0A8), Color(0xFFE0A0A8), Color(0xFF9CB8FF), Color(0xFFC8A0FF)];
    const glows = [Color(0xFFFF4A5A), Color(0xFFFF3A4A), Color(0xFF5A8CFF), Color(0xFFA05AFF)];
    for (var i = 0; i < 5; i++) {
      final left = i.isEven;
      final x = left ? 24 + rng.nextDouble() * 150 : 626 + rng.nextDouble() * 150;
      final img = images.fromCache('Props/crystal_$crystal${const [1, 3, 5][rng.nextInt(3)]}.png');
      world.add(Prop(img, .4 + rng.nextDouble() * .25, tints[stageDef.bg], glows[stageDef.bg])
        ..position = Vector2(x, groundTop + 70 + rng.nextDouble() * (groundBottom - groundTop - 80)));
    }
    if (stageDef.bg == 3) {
      for (var i = 0; i < 3; i++) {
        final img = images.fromCache('Props/bush${1 + rng.nextInt(10)}.png');
        world.add(Prop(img, .5 + rng.nextDouble() * .2, const Color(0xFF6E5E70), const Color(0xFF402030))
          ..position = Vector2(40 + rng.nextDouble() * 720, groundTop + 80 + rng.nextDouble() * 140));
      }
    }
  }

  EnemyKind _randomKind() => stageDef.enemies[rng.nextInt(stageDef.enemies.length)];

  void _spawnMonster({EnemyKind? kind, bool onPlatform = false}) {
    final k = onPlatform ? EnemyKind.slime : (kind ?? _randomKind());
    final m = Monster(k, stageIdx, onPlatform: onPlatform)
      ..position = onPlatform
          ? Vector2(platform.left + 20 + rng.nextDouble() * (FlyPlatform.slabWidth - 40), platform.y)
          : Vector2(250 + rng.nextDouble() * (worldWidth - 340),
              groundTop + 60 + rng.nextDouble() * (groundBottom - groundTop - 70));
    monsters.add(m);
    world.add(m);
  }

  /// Boss minions.
  void spawnAdd() => _spawnMonster(kind: EnemyKind.slime);

  void monsterDied(Monster m) {
    monsters.remove(m);
    state.onKill();
    runKills++;
    if (!m.isBoss && stageKills < killGoal) {
      stageKills++;
      if (!isBossStage && portalOpen) {
        world.add(FloatingText('Hoàn thành màn! Đi sang phải →', Vector2(400, 150), Colors.yellow));
      }
    }
    state.touch();
    if (portalOpen || m.isBoss) GameAudio.sfx('portal');
    final gold = m.goldDrop;
    state.gold += gold;
    world.add(FloatingText('+$gold vàng', m.position + Vector2(0, -50), const Color(0xFFFFD54F)));
    void drop(ItemId id, double chance) {
      if (rng.nextDouble() < chance) {
        world.add(Drop(id)..position = m.position + Vector2(rng.nextDouble() * 30 - 15, 0));
      }
    }

    if (m.isBoss) {
      bossDefeated = true;
      for (var i = 0; i < 3; i++) {
        drop(ItemId.stone, 1);
        drop(ItemId.potion, 1);
      }
      for (final other in List<Monster>.from(monsters)) {
        if (!other.onPlatform) other.hurt(99999); // minions die with the boss
      }
      world.add(FloatingText(isLastStage ? 'CHIẾN THẮNG! Đi sang phải →' : 'Boss bị hạ! Đi sang phải →',
          Vector2(400, 150), Colors.yellow));
      return;
    }
    final human = m.human;
    drop(ItemId.gel, human ? 0 : .65);
    drop(ItemId.potion, human ? .3 : .15);
    drop(ItemId.stone, human ? .4 : .2);
    if (m.onPlatform || !isBossStage) _respawns.add((3.0, m.onPlatform, stageIdx));
  }

  // ---- panels ----
  void openPanel(String name) {
    if (!inPlay) return;
    closePanel();
    _keys.clear();
    overlays.add(name);
    pauseEngine();
    state.touch();
  }

  void closePanel() {
    overlays
      ..remove('inventory')
      ..remove('quests')
      ..remove('shop');
    if (inPlay && !overlays.isActive('pause')) resumeEngine();
  }

  bool get panelOpen =>
      overlays.isActive('inventory') || overlays.isActive('quests') || overlays.isActive('shop');

  void quickPotion() {
    if (!inPlay || player.dead) return;
    if (!state.usePotion()) {
      world.add(FloatingText('Không dùng được', player.position + Vector2(0, -90), Colors.white));
    } else {
      GameAudio.sfx('heal');
      world.add(FloatingText('+HP', player.position + Vector2(0, -90), Colors.greenAccent));
    }
  }

  bool get shiftHeld => _keys.contains(LogicalKeyboardKey.shiftLeft) || _keys.contains(LogicalKeyboardKey.shiftRight);

  Vector2 get inputDirection {
    final d = Vector2.zero();
    if (_keys.contains(LogicalKeyboardKey.keyA) || _keys.contains(LogicalKeyboardKey.arrowLeft)) d.x -= 1;
    if (_keys.contains(LogicalKeyboardKey.keyD) || _keys.contains(LogicalKeyboardKey.arrowRight)) d.x += 1;
    if (_keys.contains(LogicalKeyboardKey.keyW) || _keys.contains(LogicalKeyboardKey.arrowUp)) d.y -= 1;
    if (_keys.contains(LogicalKeyboardKey.keyS) || _keys.contains(LogicalKeyboardKey.arrowDown)) d.y += 1;
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
    if (overlays.isActive('pause')) {
      if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyP) closePause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyP) {
      panelOpen ? closePanel() : openPause();
    } else if (k == LogicalKeyboardKey.keyI) {
      overlays.isActive('inventory') ? closePanel() : openPanel('inventory');
    } else if (k == LogicalKeyboardKey.keyQ) {
      overlays.isActive('quests') ? closePanel() : openPanel('quests');
    } else if (k == LogicalKeyboardKey.keyB) {
      overlays.isActive('shop') ? closePanel() : openPanel('shop');
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

/// Round on-screen button (skill or support) with cooldown pie and key hint.
class ActionButton extends PositionComponent with TapCallbacks {
  ActionButton(this.label, this.keyHint, this.color, this.radius, Vector2 pos, this.onPress,
      {this.cooldown, this.active, this.title})
      : super(position: pos, size: Vector2.all(radius * 2), anchor: Anchor.center);

  final String label, keyHint;
  final Color color;
  final double radius;
  final VoidCallback onPress;
  final double Function()? cooldown;
  final bool Function()? active;
  final String Function()? title;

  final _label = TextPaint(
      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 2)]));

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
          ..strokeWidth = on ? 4 : 2);
    if (cd > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: radius), -pi / 2, 2 * pi * cd, true,
          Paint()..color = Colors.black.withValues(alpha: .6));
    }
    _label.render(canvas, title?.call() ?? label, Vector2(radius, radius - 3), anchor: Anchor.center);
    _label.render(canvas, '[$keyHint]', Vector2(radius, radius + 9), anchor: Anchor.center);
  }
}

/// Right-edge arrow that opens the next stage once the stage is cleared.
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
          ..strokeWidth = 3);
  }
}

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
  double heightAt(Vector2 p) => kPlatforms && p.x >= left && p.x <= right && (p.y - y).abs() <= 26 ? topHeight : 0;

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
        GameAudio.sfx('pickup');
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
    // A coloured glow so loot reads clearly against the dark scenery.
    final glow = switch (id) {
      ItemId.potion => const Color(0xFFFF4A5A),
      ItemId.stone => const Color(0xFF5AAEFF),
      ItemId.gel => const Color(0xFF6CFF86),
      _ => const Color(0xFFFFCC50),
    };
    final gc = Offset(14, 10 - (sin(_t * 4) + 1) * 2);
    canvas.drawCircle(
        gc,
        26,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(gc, 26, [glow.withValues(alpha: .55 + .15 * sin(_t * 5)), glow.withValues(alpha: 0)]));
    _sprite.render(canvas, position: Vector2(0, -4 - (sin(_t * 4) + 1) * 3), size: size, overridePaint: pixelPaint);
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
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold, shadows: const [Shadow(blurRadius: 3)])),
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

  final _text = TextPaint(style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold));
  final _title = TextPaint(
      style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 12, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 3)]));

  @override
  void render(Canvas canvas) {
    final p = game.state;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(10, 10, 190, 120), const Radius.circular(8)),
        Paint()..color = Colors.black54);
    _text.render(canvas, 'Lv ${p.level}   EXP ${p.exp}/${p.expToNext}', Vector2(18, 14));
    _bar(canvas, 18, 32, p.hp / p.maxHp, Colors.red, '${p.hp}/${p.maxHp}');
    _bar(canvas, 18, 50, p.mp / p.maxMp, Colors.blue, '${p.mp}/${p.maxMp}');
    _text.render(canvas, 'Vàng: ${p.gold}', Vector2(18, 72));
    _text.render(canvas, 'Nhân vật: ${game.player.hero.name}', Vector2(18, 90));
    _text.render(
        canvas,
        game.isBossStage
            ? 'Màn ${game.stageIdx + 1}/${stages.length}: BOSS'
            : 'Màn ${game.stageIdx + 1}/${stages.length}: ${game.stageKills}/${game.killGoal} quái',
        Vector2(18, 108));
    final boss = game.bossRef;
    if (boss != null && !game.bossDefeated) {
      final def = boss.boss!;
      const x = 250.0, y = 398.0, w = 300.0;
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(x - 50, y - 22, w + 60, 50), const Radius.circular(8)),
          Paint()..color = Colors.black54);
      final portrait = game.images.fromCache(def.portrait);
      canvas.drawImageRect(portrait, Rect.fromLTWH(0, 0, portrait.width.toDouble(), portrait.height.toDouble()),
          const Rect.fromLTWH(x - 44, y - 18, 34, 44), pixelPaint);
      _title.render(canvas, def.name, Vector2(x, y - 18));
      canvas.drawRect(const Rect.fromLTWH(x, y, w, 12), Paint()..color = Colors.black87);
      canvas.drawRect(Rect.fromLTWH(x, y, w * max(0, boss.hp) / boss.maxHp, 12), Paint()..color = const Color(0xFFD32F2F));
    }
  }

  void _bar(Canvas c, double x, double y, double f, Color col, String t) {
    c.drawRect(Rect.fromLTWH(x, y, 174, 14), Paint()..color = Colors.black45);
    c.drawRect(Rect.fromLTWH(x, y, 174 * f, 14), Paint()..color = col);
    _text.render(c, t, Vector2(x + 4, y));
  }
}
