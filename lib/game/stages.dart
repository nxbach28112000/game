import 'dart:ui';

/// Regular enemies: the three minotaur sheets plus tinted copies of the Fighter
/// (brute) and Wanderer (ranged mage) sheets.
enum EnemyKind {
  mino1('Minotaur1', Color(0xFFFFFFFF), .85, 60, 50, 9, ),
  mino2('Minotaur2', Color(0xFFFFC8A8), .95, 65, 80, 12),
  mino3('Minotaur3', Color(0xFFB8C0FF), 1.05, 70, 115, 15),
  brute('Fighter', Color(0xFFFF9A9A), 1.0, 55, 130, 16),
  mage('Wanderer', Color(0xFFD2A8FF), 1.0, 50, 85, 13);

  const EnemyKind(this.folder, this.tint, this.sizeMul, this.speed, this.baseHp, this.baseDmg);

  final String folder;
  final Color tint;
  final double sizeMul, speed;
  final int baseHp, baseDmg;
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

const _shadow = BossDef('Sát thủ Bóng Đêm', 'Shinobi', Color(0xFF9A7BFF), 1.5, 900, 22);
const _goldMino = BossDef('Minotaur Vàng', 'Minotaur2', Color(0xFFFFD870), 1.5, 1300, 26);
const _bloodSamurai = BossDef('Samurai Huyết', 'Samurai', Color(0xFFFF7070), 1.5, 1700, 30);
const _fireMage = BossDef('Pháp sư Lửa', 'FireWizard', Color(0xFFFFB38A), 1.5, 1900, 26, projFolder: 'FireWizard');
const _warMino = BossDef('Minotaur Chiến Thần', 'Minotaur3', Color(0xFFFF6A5A), 1.5, 2500, 36);
const _stormMage = BossDef('Pháp sư Sét', 'LightningMage', Color(0xFFB8C8FF), 1.5, 2700, 30, projFolder: 'LightningMage');
const _darkMaster = BossDef('Võ sư Tà Đạo', 'Fighter', Color(0xFFB070FF), 1.5, 3300, 40);
const _minoKing = BossDef('Minotaur Chúa', 'Minotaur1', Color(0xFF9A6060), 1.5, 4300, 46);

class StageDef {
  const StageDef(this.name, this.bg, this.enemies, this.boss);

  final String name;
  final int bg; // index into the 4 background worlds
  final List<EnemyKind> enemies;
  final BossDef boss;
}

/// Fixed order: 4 worlds x 2 stages. Each stage asks for 10 x (stage number)
/// kills, then its boss appears; beating the boss opens the arrow onward.
const stages = [
  StageDef('Sân thượng', 0, [EnemyKind.mino1], _shadow),
  StageDef('Sân thượng II', 0, [EnemyKind.mino1, EnemyKind.mino2], _goldMino),
  StageDef('Phòng ngai vàng', 1, [EnemyKind.mino1, EnemyKind.mino2, EnemyKind.brute], _bloodSamurai),
  StageDef('Phòng ngai vàng II', 1, [EnemyKind.mino2, EnemyKind.brute, EnemyKind.mage], _fireMage),
  StageDef('Lâu đài', 2, [EnemyKind.mino2, EnemyKind.mino3, EnemyKind.brute], _warMino),
  StageDef('Lâu đài II', 2, [EnemyKind.mino3, EnemyKind.brute, EnemyKind.mage], _stormMage),
  StageDef('Rừng chết', 3, [EnemyKind.mino3, EnemyKind.brute, EnemyKind.mage, EnemyKind.mino2], _darkMaster),
  StageDef('Rừng chết II', 3, [EnemyKind.mino3, EnemyKind.brute, EnemyKind.mage], _minoKing),
];
