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
    'shield': ('Shield', .12, true),
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
    _tickers[_cur]!
        .getSprite()
        .render(canvas, size: size, overridePaint: paint ?? pixelPaint);
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
      ['Đánh', 'Chém nhanh', 'Vòng xoáy', 'Ẩn thân'],
      'Nhanh nhẹn, di chuyển linh hoạt.'),
  HeroDef('Samurai', 'Samurai', 150, 1.25, 0,
      ['Đánh', 'Trảm', 'Kiếm khí', 'Thủ thế'], 'Sát thương cao, tốc độ vừa.'),
  HeroDef('Fighter', 'Fighter', 165, 1.1, 3,
      ['Đánh', 'Đấm', 'Chấn động', 'Giáp sắt'],
      'Trâu bò, giảm thêm sát thương nhận.'),
  HeroDef('Pháp sư Lửa', 'FireWizard', 150, 1.15, 0,
      ['Hỏa cầu', 'Cầu lửa lớn', 'Phun lửa', 'Lá chắn'],
      'Tầm xa. Bắn hỏa cầu, phun lửa xuyên quái.',
      projFolder: 'FireWizard'),
  HeroDef('Pháp sư Sét', 'LightningMage', 165, 1.1, 0,
      ['Tia sét', 'Cầu sét', 'Sét lan', 'Lá chắn'],
      'Tầm xa. Di chuyển nhanh, sét xuyên mục tiêu.',
      projFolder: 'LightningMage'),
  HeroDef('Lữ khách', 'Wanderer', 155, 1.2, 0,
      ['Mũi tên phép', 'Chú thuật', 'Cầu ma thuật', 'Lá chắn'],
      'Tầm xa. Phép thuật cân bằng, sát thương cao.',
      projFolder: 'Wanderer'),
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
};

/// Fraction of the (unscaled) cell a standing character fills, from its feet.
const folderHeightFrac = {
  'Shinobi': .617,
  'Samurai': .633,
  'Fighter': .633,
  'FireWizard': .516,
  'LightningMage': .492,
  'Wanderer': .516,
};
