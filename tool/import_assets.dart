// Copies the downloaded asset packs into assets/images with the names the
// game expects (same 10 animation names as the Fighter/Samurai/Shinobi sheets).
import 'dart:io';
import 'package:image/image.dart';

const dl = 'C:/Users/Admin/Downloads';
const wiz = '$dl/craftpix-net-529677-free-wizard-sprite-sheets-pixel-art';

void cp(String from, String to) {
  File(to).parent.createSync(recursive: true);
  File(from).copySync(to);
}

void main() {
  // name in game -> source file in the pack
  const mages = {
    'FireWizard': (
      'Fire Wizard',
      {
        'Idle': 'Idle', 'Walk': 'Walk', 'Run': 'Run',
        'Attack_1': 'Attack_2', // basic: short cast
        'Attack_2': 'Fireball', // skill 1: throw fireball
        'Attack_3': 'Flame_jet', // skill 2: flame beam
        'Shield': 'Idle', 'Hurt': 'Hurt', 'Jump': 'Jump', 'Dead': 'Dead',
        'Proj': 'Charge',
      }
    ),
    'LightningMage': (
      'Lightning Mage',
      {
        'Idle': 'Idle', 'Walk': 'Walk', 'Run': 'Run',
        'Attack_1': 'Attack_2',
        'Attack_2': 'Light_ball',
        'Attack_3': 'Light_charge',
        'Shield': 'Idle', 'Hurt': 'Hurt', 'Jump': 'Jump', 'Dead': 'Dead',
        'Proj': 'Charge',
      }
    ),
    'Wanderer': (
      'Wanderer Magican',
      {
        'Idle': 'Idle', 'Walk': 'Walk', 'Run': 'Run',
        'Attack_1': 'Magic_arrow',
        'Attack_2': 'Attack_2',
        'Attack_3': 'Magic_sphere',
        'Shield': 'Idle', 'Hurt': 'Hurt', 'Jump': 'Jump', 'Dead': 'Dead',
        'Proj': 'Charge_1',
      }
    ),
  };
  for (final e in mages.entries) {
    final (src, files) = e.value;
    for (final f in files.entries) {
      cp('$wiz/$src/${f.value}.png', 'assets/images/${e.key}/${f.key}.png');
    }
  }

  // Boss portraits: crop the 512x1024 art to the character and shrink.
  const portraits = {5: 'boss1', 260: 'boss2', 320: 'boss3', 410: 'boss4'};
  for (final e in portraits.entries) {
    final im = decodePng(File('$dl/Characters 500+ (by batareya)/Characters/${e.key}.png').readAsBytesSync())!;
    final t = trim(im, mode: TrimMode.transparent);
    final r = copyResize(t, height: 200, interpolation: Interpolation.nearest);
    Directory('assets/images/Portraits').createSync(recursive: true);
    File('assets/images/Portraits/${e.value}.png').writeAsBytesSync(encodePng(r));
  }

  // Props: first frame of every bush, three crystals of four colours.
  for (var i = 1; i <= 10; i++) {
    cp('$dl/craftpix-net-699134-free-bush-assets-pixel-art-pack/PNG/Bushes$i/Bush${i}_1.png',
        'assets/images/Props/bush$i.png');
  }
  for (final c in ['red-pink', 'violet', 'blue', 'green']) {
    for (final n in [1, 3, 5]) {
      cp('$dl/craftpix-net-924817-free-crystals-pixel-art-asset-pack/PNG/crystals_$c/crystal_$c$n.png',
          'assets/images/Props/crystal_${c.split('-').first}$n.png');
    }
  }
}
