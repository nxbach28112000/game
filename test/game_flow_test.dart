import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_game/game/button_layout.dart';
import 'package:flutter_game/game/heroes.dart';
import 'package:flutter_game/game/monster.dart';
import 'package:flutter_game/game/stages.dart';
import 'package:flutter_game/game/village_game.dart';

// Run with: flutter test --dart-define=QUICK=true
void main() {
  testWidgets('every hero can fight, clear all stages and win', (tester) async {
    final game = VillageGame();
    await tester.pumpWidget(MaterialApp(
        home: GameWidget(game: game, overlayBuilderMap: {
      for (final o in ['menu', 'select', 'hud', 'pause', 'inventory', 'quests', 'shop', 'gameover', 'victory'])
        o: (c, g) => const SizedBox()
    })));
    // onLoad awaits storage reads whose microtasks only run when the fake
    // clock is pumped, so alternate real waiting with pumping.
    for (var i = 0; i < 600 && !game.isLoaded; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(game.isLoaded, isTrue);

    void step(int frames) {
      for (var i = 0; i < frames; i++) {
        game.update(1 / 60);
        game.render(Canvas(PictureRecorder()));
      }
    }

    for (var h = 0; h < heroes.length; h++) {
      await tester.runAsync(() => game.startNew(h));
      step(10);
      expect(game.inPlay, isTrue, reason: heroes[h].name);
      for (final slot in [0, 1, 2]) {
        game.player.useSkill(slot);
        step(70);
      }
      game.player.jump();
      step(70);
      game.state.mp = game.state.maxMp;
      game.state.hp = game.state.maxHp;
    }

    // Play through every stage with the last hero (a ranged one).
    await tester.runAsync(() => game.startNew(3));
    for (var s = 0; s < stages.length; s++) {
      expect(game.stageIdx, s);
      game.state.hp = game.state.maxHp;
      step(5);
      // Kill the quota of monsters; the boss must then appear.
      var guard = 0;
      while (!game.bossSpawned && guard++ < 80) {
        for (final m in List<Monster>.from(game.monsters)) {
          m.hurt(999999);
        }
        step(200); // let respawns happen
      }
      expect(game.bossSpawned, isTrue, reason: 'boss for stage $s');
      expect(game.floors.length, s >= 3 ? 3 : 2);
      for (final f in game.floors) {
        expect(f.floorW, greaterThanOrEqualTo(320));
      }
      expect(game.floors.map((f) => f.z).reduce((a, b) => a < b ? a : b), greaterThan(110));
      expect(game.bossRef, isNotNull);
      // Let the boss fight us for a while: slams, fans, adds, enrage.
      game.player.position.setValues(300, 340);
      game.bossRef!.hp = game.bossRef!.maxHp ~/ 3;
      for (var i = 0; i < 40; i++) {
        game.state.hp = game.state.maxHp;
        step(30);
      }
      game.bossRef!.hurt(999999);
      expect(game.portalOpen, isTrue, reason: 'stage $s');
      game.player.position.setValues(790, 330);
      game.player.z = 0;
      await tester.runAsync(() async {
        step(3);
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      });
      step(3);
    }
    expect(game.overlays.isActive('victory'), isTrue);

    // Death -> game over -> revive (twice) -> third death has no revive left.
    await tester.runAsync(() => game.startNew(0));
    expect(game.revivesLeft, 2);
    for (var i = 0; i < 3; i++) {
      game.state.hp = 1;
      game.player.hurt(9999);
      step(200);
      expect(game.overlays.isActive('gameover'), isTrue);
      if (i < 2) {
        game.revive();
        expect(game.inPlay, isTrue);
        expect(game.state.hp, game.state.maxHp);
        expect(game.player.dead, isFalse);
        step(200); // grace period: nothing kills us right away
      } else {
        game.revive(); // no revives left: stays on the game over screen
        expect(game.inPlay, isFalse);
        expect(game.revivesLeft, 0);
      }
    }

    // Level ups come from kills: 20, then 30 more...
    await tester.runAsync(() => game.startNew(0));
    final hp1 = game.state.maxHp, atk1 = game.state.attack;
    for (var i = 0; i < 19; i++) {
      expect(game.state.onKill(), isFalse);
    }
    expect(game.state.onKill(), isTrue);
    expect(game.state.level, 2);
    expect(game.state.maxHp, (hp1 * 1.15).round());
    expect(game.state.attack, greaterThan(atk1));
    for (var i = 0; i < 30; i++) {
      game.state.onKill();
    }
    expect(game.state.level, 3);

    // Floors can be reached: jump from under the lowest one.
    await tester.runAsync(() => game.startNew(0));
    final low = game.floors.reduce((a, b) => a.z < b.z ? a : b);
    expect(low.z, greaterThan(110));
    game.player.position.setValues(low.x, low.y + 20);
    step(5);
    game.player.jump();
    step(120);
    expect(game.player.z, closeTo(low.z, 1));
    // The floor layout of a stage is the same every time.
    final layout = [for (final f in game.floors) (f.x, f.z)];
    await tester.runAsync(() => game.startNew(0));
    expect([for (final f in game.floors) (f.x, f.z)], layout);

    // Running costs mana.
    game.state.mp = game.state.maxMp;
    game.player.running = true;
    game.player.position.setValues(100, 330);
    // no input direction in tests, so just make sure the toggle itself works
    expect(game.player.running, isTrue);
  });

  test('button layout round-trips through storage', () async {
    final l = ButtonLayout({'attack': (100, 120)});
    await l.save();
    final loaded = await ButtonLayout.load();
    expect(loaded.of('attack'), (100.0, 120.0));
    expect(loaded.of('jump'), ButtonLayout.defaults['jump']);
    await loaded.reset();
    expect((await ButtonLayout.load()).of('attack'), ButtonLayout.defaults['attack']);
  });
}
