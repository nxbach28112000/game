import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'game/village_game.dart';
import 'ui/panels.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: GameScreen()),
  ));
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final VillageGame game = VillageGame();

  @override
  Widget build(BuildContext context) => GameWidget<VillageGame>(
        game: game,
        initialActiveOverlays: const ['select'],
        overlayBuilderMap: {
          'select': (context, g) => CharacterSelect(game: g),
          'gameover': (context, g) => GameOverScreen(game: g),
          'hud': (context, g) => HudButtons(game: g),
          'inventory': (context, g) => InventoryPanel(game: g),
          'quests': (context, g) => QuestPanel(game: g),
        },
      );
}
