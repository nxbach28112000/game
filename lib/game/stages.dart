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

/// A boss that appears once a stage's monster quota is killed. [scale] is
/// relative to a normal hero (1.5 = one and a half times as tall).
class BossDef {
  const BossDef(this.name, this.folder, this.tint, this.scale, this.hp, this.dmg, {this.projFolder});

  final String name, folder;
  final Color tint;
  final double scale;
  final int hp, dmg;

  /// Non-null => ranged boss firing this folder's projectile fan.
  final String? projFolder;

  bool get ranged => projFolder != null;
}

const _white = Color(0xFFFFFFFF);

const _knight1 = BossDef('Hiệp sĩ Thép', 'Knight1', _white, 1.5, 800, 22);
const _minotaur1 = BossDef('Minotaur Cuồng Nộ', 'Minotaur1', _white, 1.5, 1050, 25);
const _knight2 = BossDef('Hiệp sĩ Đỏ', 'Knight2', _white, 1.5, 1300, 28);
const _fireMage = BossDef('Pháp sư Lửa', 'FireWizard', Color(0xFFFFB38A), 1.5, 1450, 24, projFolder: 'FireWizard');
const _minotaur2 = BossDef('Minotaur Chiến Binh', 'Minotaur2', _white, 1.5, 1800, 33);
const _stormMage = BossDef('Pháp sư Sét', 'LightningMage', Color(0xFFB8C8FF), 1.5, 1950, 28, projFolder: 'LightningMage');
const _knight3 = BossDef('Hiệp sĩ Bóng Tối', 'Knight3', _white, 1.5, 2300, 38);
const _minotaur3 = BossDef('Minotaur Chúa', 'Minotaur3', _white, 1.5, 3000, 42);

class StageDef {
  const StageDef(this.name, this.bg, this.enemies, this.boss);

  final String name;
  final int bg; // index into the 4 background worlds
  final List<EnemyKind> enemies;
  final BossDef boss;
}

/// 4 worlds x 2 stages. Each stage asks for 10 x (stage number) kills, then
/// its boss appears; beating the boss opens the arrow to the next stage.
const stages = [
  StageDef('Sân thượng', 0, [EnemyKind.slime], _knight1),
  StageDef('Sân thượng II', 0, [EnemyKind.slime, EnemyKind.goblin], _minotaur1),
  StageDef('Phòng ngai vàng', 1, [EnemyKind.slime, EnemyKind.goblin, EnemyKind.bat], _knight2),
  StageDef('Phòng ngai vàng II', 1, [EnemyKind.goblin, EnemyKind.bat, EnemyKind.spider], _fireMage),
  StageDef('Lâu đài', 2, [EnemyKind.goblin, EnemyKind.bat, EnemyKind.spider, EnemyKind.brute], _minotaur2),
  StageDef('Lâu đài II', 2, [EnemyKind.goblin, EnemyKind.spider, EnemyKind.brute, EnemyKind.mage], _stormMage),
  StageDef('Rừng chết', 3, [EnemyKind.spider, EnemyKind.brute, EnemyKind.mage, EnemyKind.bat], _knight3),
  StageDef('Rừng chết II', 3, [EnemyKind.goblin, EnemyKind.spider, EnemyKind.brute, EnemyKind.mage], _minotaur3),
];
