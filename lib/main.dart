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
  const GameScreen({super.key, this.onReady});

  /// Called once the game has loaded (used by lib/debug_main.dart).
  final void Function(VillageGame game)? onReady;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final VillageGame game = VillageGame();

  @override
  void initState() {
    super.initState();
    game.onReady = () => widget.onReady?.call(game);
  }

  @override
  Widget build(BuildContext context) => GameWidget<VillageGame>(
        game: game,
        initialActiveOverlays: const ['menu'],
        overlayBuilderMap: {
          'menu': (context, g) => MainMenu(game: g),
          'select': (context, g) => CharacterSelect(game: g),
          'hud': (context, g) => HudButtons(game: g),
          'pause': (context, g) => PauseMenu(game: g),
          'inventory': (context, g) => InventoryPanel(game: g),
          'quests': (context, g) => QuestPanel(game: g),
          'shop': (context, g) => ShopPanel(game: g),
          'gameover': (context, g) => GameOverScreen(game: g),
          'victory': (context, g) => VictoryScreen(game: g),
        },
      );
}
