import 'package:flame/components.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'village_game.dart';

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

  static const folders = [
    'Fighter',
    'Samurai',
    'Shinobi',
    'FireWizard',
    'LightningMage',
    'Wanderer',
    'Knight1',
    'Knight2',
    'Knight3',
    'Minotaur1',
    'Minotaur2',
    'Minotaur3',
  ];

  /// name -> (file, seconds per frame, loops)
  static const specs = <String, (String, double, bool)>{
    'idle': ('Idle', .14, true),
    'walk': ('Walk', .1, true),
    'run': ('Run', .07, true),
    'attack': ('Attack_1', .06, false),
    'skill': ('Attack_3', .07, false),
    'hurt': ('Hurt', .1, false),
    'skill1': ('Attack_2', .08, false),
    'jump': ('Jump', .08, false),
    'dead': ('Dead', .14, false),
  };

  final String folder;
  final _tickers = <String, SpriteAnimationTicker>{};
  String _cur = 'idle';

  bool get finished => _tickers[_cur]!.done();

  void play(String name, {bool restart = false}) {
    if (_cur != name || restart) {
      _cur = name;
      _tickers[name]!.reset();
    }
  }

  void update(double dt) => _tickers[_cur]!.update(dt);

  void render(Canvas canvas, Vector2 size, {bool flip = false, Paint? paint}) {
    canvas.save();
    if (flip) {
      canvas.translate(size.x, 0);
      canvas.scale(-1, 1);
    }
    // Some sheets draw the body off-centre in the 128px cell.
    final shift = (folderShiftX[folder] ?? 0) * size.x / 128;
    _tickers[_cur]!
        .getSprite()
        .render(canvas, position: Vector2(shift, 0), size: size, overridePaint: paint ?? pixelPaint);
    canvas.restore();
  }
}

/// A projectile sheet: frames [0, travel) loop in flight, the rest play on hit.
class ProjDef {
  const ProjDef(this.folder, this.fw, this.fh, this.travel, this.drawScale);

  final String folder;
  final int fw, fh, travel;
  final double drawScale;
}

const projDefs = {
  'FireWizard': ProjDef('FireWizard', 64, 64, 5, 1.7),
  'LightningMage': ProjDef('LightningMage', 64, 64, 4, 1.9),
  'Wanderer': ProjDef('Wanderer', 64, 128, 5, .9),
};

class HeroDef {
  const HeroDef(this.name, this.folder, this.speed, this.dmgMul, this.defBonus,
      this.skills, this.blurb,
      {this.projFolder});

  final String name, folder, blurb;
  final double speed, dmgMul;

  /// Draw scale so every hero stands the same height on screen.
  double get scale => folderScale[folder] ?? 1;
  final int defBonus;

  /// Names of skill slots 0..3 (basic attack, two attacks, guard).
  final List<String> skills;

  /// Non-null => ranged hero throwing this projectile.
  final String? projFolder;

  bool get ranged => projFolder != null;
  ProjDef? get proj => projFolder == null ? null : projDefs[projFolder];
}

const heroes = [
  HeroDef('Shinobi', 'Shinobi', 190, 1.0, 0,
      ['Đánh', 'Chém nhanh', 'Vòng xoáy'],
      'Nhanh nhẹn, di chuyển linh hoạt.'),
  HeroDef('Samurai', 'Samurai', 150, 1.25, 0,
      ['Đánh', 'Trảm', 'Kiếm khí'], 'Sát thương cao, tốc độ vừa.'),
  HeroDef('Fighter', 'Fighter', 165, 1.1, 3,
      ['Đánh', 'Đấm', 'Chấn động'],
      'Trâu bò, giảm thêm sát thương nhận.'),
  HeroDef('Pháp sư Lửa', 'FireWizard', 150, 1.15, 0,
      ['Hỏa cầu', 'Cầu lửa lớn', 'Phun lửa'],
      'Tầm xa. Bắn hỏa cầu, phun lửa xuyên quái.',
      projFolder: 'FireWizard'),
  HeroDef('Pháp sư Sét', 'LightningMage', 165, 1.1, 0,
      ['Tia sét', 'Cầu sét', 'Sét lan'],
      'Tầm xa. Di chuyển nhanh, sét xuyên mục tiêu.',
      projFolder: 'LightningMage'),
  HeroDef('Lữ khách', 'Wanderer', 155, 1.2, 0,
      ['Mũi tên phép', 'Chú thuật', 'Cầu ma thuật'],
      'Tầm xa. Phép thuật cân bằng, sát thương cao.',
      projFolder: 'Wanderer'),
  // The knight sheets have three different attacks, so they are heroes.
  HeroDef('Hiệp sĩ Thép', 'Knight1', 150, 1.3, 4, ['Chém', 'Chém ngang', 'Bão kiếm'],
      'Giáp dày, 3 kiểu chém liên hoàn.'),
  HeroDef('Hiệp sĩ Đỏ', 'Knight2', 160, 1.35, 2, ['Chém', 'Chém ngang', 'Bão kiếm'],
      'Cân bằng giữa công và thủ.'),
  HeroDef('Hiệp sĩ Đen', 'Knight3', 170, 1.4, 1, ['Chém', 'Chém ngang', 'Bão kiếm'],
      'Nhanh và hung hãn.'),
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
];

/// The sheets draw their characters at different sizes inside the 128px cell
/// (melee ~80px, mages ~65px tall). Scaling by this makes every character
/// the same on-screen height (~80/128 of the cell).
const folderScale = {
  'Shinobi': 1.0,
  'Samurai': 0.99,
  'Fighter': 0.99,
  'FireWizard': 1.2,
  'LightningMage': 1.27,
  'Wanderer': 1.2,
  'Knight1': 1.25,
  'Knight2': 1.25,
  'Knight3': 1.25,
  'Minotaur1': .87,
  'Minotaur2': .94,
  'Minotaur3': .86,
};

/// Fraction of the (unscaled) cell a standing character fills, from its feet.
const folderHeightFrac = {
  'Shinobi': .617,
  'Samurai': .633,
  'Fighter': .633,
  'FireWizard': .516,
  'LightningMage': .492,
  'Wanderer': .516,
  'Knight1': .5,
  'Knight2': .5,
  'Knight3': .5,
  'Minotaur1': .719,
  'Minotaur2': .664,
  'Minotaur3': .727,
};

/// Cell pixels to shift a sheet right so its body is centred.
const folderShiftX = {
  'Knight1': 31.0,
  'Knight2': 31.0,
  'Knight3': 31.0,
  'Minotaur1': 6.0,
  'Minotaur2': 17.0,
  'Minotaur3': 0.0,
};
