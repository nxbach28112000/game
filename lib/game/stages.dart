import 'dart:ui';

/// Enemy types. slime/goblin/bat/spider are small CC0 sprites (CREDITS.md);
/// brute and mage reuse the hero sheets (tinted) instead.
enum EnemyKind {
  slime('monsters/slime.png', 55, 1, 1, 15, 48),
  goblin('monsters/goblin.png', 75, 1.5, 1.3, 25, 64),
  bat('monsters/bat.png', 95, .8, .9, 20, 48),
  spider('monsters/spider.png', 65, 2, 1.6, 40, 56),
  brute(null, 55, 1, 1, 30, 100),
  mage(null, 50, 1, 1, 28, 100);

  const EnemyKind(this.file, this.speed, this.hpMul, this.dmgMul, this.exp, this.drawSize);

  final String? file;
  final double speed, hpMul, dmgMul, drawSize;
  final int exp;

  bool get isSprite => file != null;
}

/// A boss fight at the end of each world.
class BossDef {
  const BossDef(this.name, this.folder, this.tint, this.scale, this.portrait,
      this.hp, this.dmg,
      {this.projFolder});

  final String name, folder, portrait;
  final Color tint;
  final double scale;
  final int hp, dmg;

  /// Non-null => ranged boss firing this folder's projectile fan.
  final String? projFolder;

  bool get ranged => projFolder != null;
}

class StageDef {
  const StageDef(this.name, this.bg, this.enemies, {this.boss});

  final String name;
  final int bg; // index into backgroundFiles
  final List<EnemyKind> enemies;
  final BossDef? boss;
}

const _boss1 = BossDef('Hiệp sĩ Hoàng Kim', 'Samurai', Color(0xFFFFD27A), 2.1, 'Portraits/boss1.png', 900, 26);
const _boss2 = BossDef('Pháp sư Lửa', 'FireWizard', Color(0xFFFFB38A), 2.3, 'Portraits/boss2.png', 1100, 22,
    projFolder: 'FireWizard');
const _boss3 = BossDef('Pháp sư Sét', 'LightningMage', Color(0xFFB8C8FF), 2.3, 'Portraits/boss3.png', 1300, 24,
    projFolder: 'LightningMage');
const _boss4 = BossDef('Sát thủ Bóng Đêm', 'Shinobi', Color(0xFF9A7BFF), 2.1, 'Portraits/boss4.png', 1700, 32);

/// 4 worlds x (50-kill stage + boss) = 8 stages.
const stages = [
  StageDef('Sân thượng', 0, [EnemyKind.slime]),
  StageDef('Sân thượng - Boss', 0, [EnemyKind.slime], boss: _boss1),
  StageDef('Phòng ngai vàng', 1, [EnemyKind.slime, EnemyKind.goblin, EnemyKind.bat]),
  StageDef('Phòng ngai vàng - Boss', 1, [EnemyKind.slime], boss: _boss2),
  StageDef('Lâu đài', 2, [EnemyKind.goblin, EnemyKind.bat, EnemyKind.spider, EnemyKind.brute, EnemyKind.mage]),
  StageDef('Lâu đài - Boss', 2, [EnemyKind.slime], boss: _boss3),
  StageDef('Rừng chết', 3, [EnemyKind.goblin, EnemyKind.spider, EnemyKind.brute, EnemyKind.mage, EnemyKind.bat]),
  StageDef('Rừng chết - Boss', 3, [EnemyKind.slime], boss: _boss4),
];
