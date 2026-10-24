// Copies the Knight and Minotaur packs into assets/images/<Name>/ using the
// canonical animation names, plus the tileset pieces used for floors.
import 'dart:io';

const dl = 'C:/Users/Admin/Downloads';
const knights = '$dl/craftpix-net-803217-free-knight-character-sprites-pixel-art';
const minotaurs = '$dl/craftpix-net-170637-free-minotaur-sprite-sheet-pixel-art-pack';
const tiles = '$dl/craftpix-net-867123-free-medieval-field-work-2d-tileset-for-platformer/PNG';

void cp(String from, String to) {
  File(to).parent.createSync(recursive: true);
  File(from).copySync(to);
}

void main() {
  for (var i = 1; i <= 3; i++) {
    final src = '$knights/Knight_$i';
    final map = {
      'Idle': 'Idle', 'Walk': 'Walk', 'Run': 'Run', 'Attack_1': 'Attack 1', 'Attack_2': 'Attack 2',
      'Attack_3': 'Attack 3', 'Shield': 'Defend', 'Hurt': 'Hurt', 'Jump': 'Jump', 'Dead': 'Dead',
    };
    for (final e in map.entries) {
      cp('$src/${e.value}.png', 'assets/images/Knight$i/${e.key}.png');
    }
  }
  for (var i = 1; i <= 3; i++) {
    final src = '$minotaurs/Minotaur_$i';
    final map = {
      'Idle': 'Idle', 'Walk': 'Walk', 'Run': 'Walk', 'Attack_1': 'Attack', 'Attack_2': 'Attack',
      'Attack_3': 'Attack', 'Shield': 'Idle', 'Hurt': 'Hurt', 'Jump': 'Idle', 'Dead': 'Dead',
    };
    for (final e in map.entries) {
      cp('$src/${e.value}.png', 'assets/images/Minotaur$i/${e.key}.png');
    }
  }
  const env = 'Cartoon_Medieval_Field_Work_Level_Set_Environment - ';
  const plat = 'Cartoon_Medieval_Field_Work_Level_Set_Platformer - ';
  for (final n in ['02', '05', '07', '08', '10', '11', '12']) {
    cp('$tiles/Platformer/${plat}Ground $n.png', 'assets/images/Tiles/ground$n.png');
  }
  const items = {
    'crate': 'Wooden Crate', 'barrel': 'Wooden Barrel', 'hay1': 'Hay 01', 'hay2': 'Hay 02', 'rock1': 'Rock 01',
    'rock2': 'Rock 02', 'rockflat1': 'Rock 03', 'rockflat2': 'Rock 04', 'plant1': 'Plants 01', 'plant2': 'Plants 02',
    'fence1': 'Fence 01', 'sign1': 'Sign 01', 'table1': 'Table 01', 'table2': 'Table 02 ', 'cart1': 'Cart 01',
  };
  for (final e in items.entries) {
    cp('$tiles/Environment/$env${e.value}.png', 'assets/images/Tiles/${e.key}.png');
  }
}
