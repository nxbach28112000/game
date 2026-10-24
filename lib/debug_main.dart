// Dev entry: jump straight into a stage with a hero (tanky, level 15).
//   flutter run -d chrome -t lib/debug_main.dart
// then open  http://localhost:PORT/?hero=4&stage=1  (hero 0-6, stage 0-7).
import 'package:flutter/material.dart';

import 'main.dart';

void main() {
  final q = Uri.base.queryParameters;
  final hero = int.tryParse(q['hero'] ?? '') ?? 0;
  final stage = int.tryParse(q['stage'] ?? '') ?? 0;
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: GameScreen(onReady: (g) async {
        await g.startNew(hero, stage: stage);
        g.state.gainExp(8000);
        g.state.maxHp = 3000;
        g.state.hp = 3000;
      }),
    ),
  ));
}
