import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.runAsync(() async => await game.toBeLoaded());

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
      for (final slot in [0, 1, 2, 3]) {
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

    // Death -> game over -> retry the stage.
    await tester.runAsync(() => game.startNew(0));
    game.state.hp = 1;
    game.player.hurt(9999);
    step(200);
    expect(game.overlays.isActive('gameover'), isTrue);
    await tester.runAsync(() => game.retryStage());
    expect(game.inPlay, isTrue);
    expect(game.state.hp, game.state.maxHp);
  });
}
