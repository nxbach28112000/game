import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/audio/audio.dart';
import '../game/button_layout.dart';
import '../game/game_state.dart';
import '../game/heroes.dart';
import '../game/save_store.dart';
import '../game/stages.dart';
import '../game/village_game.dart';

const _panelColor = Color(0xF21A2238);
const _gold = Color(0xFFFFD54F);

/// Draws an item icon from the image already cached by the game.
Widget itemIcon(VillageGame game, ItemId id, {double size = 40}) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
          painter: _IconPainter(game.images.fromCache('${itemDefs[id]!.icon}.png'))),
    );

class _IconPainter extends CustomPainter {
  _IconPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.none);
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.image != image;
}

class HudButtons extends StatelessWidget {
  const HudButtons({super.key, required this.game});

  final VillageGame game;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: ListenableBuilder(
        listenable: game.state,
        builder: (context, _) => Row(
          children: [
            _btn('Bình máu (H) x${game.state.countOf(ItemId.potion)}',
                game.quickPotion),
            _btn('Túi đồ (I)', () => game.openPanel('inventory')),
            _btn('Nhiệm vụ (Q)${game.state.hasQuestAttention ? ' !' : ''}',
                () => game.openPanel('quests')),
            _btn('Cửa hàng (B)', () => game.openPanel('shop')),
            ValueListenableBuilder<bool>(
              valueListenable: GameAudio.mutedNotifier,
              builder: (context, muted, _) =>
                  _btn(muted ? '♪ Tắt' : '♪ Bật', () => GameAudio.setMuted(!muted)),
            ),
            _btn('⚙', game.openSettings),
            _btn('Dừng (P)', game.openPause),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame(
      {required this.title, required this.onClose, required this.child});

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _panelColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _gold, width: 2),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _gold)),
                  const Spacer(),
                  IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, color: Colors.white)),
                ]),
                Flexible(child: SingleChildScrollView(child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InventoryPanel extends StatefulWidget {
  const InventoryPanel({super.key, required this.game});

  final VillageGame game;

  @override
  State<InventoryPanel> createState() => _InventoryPanelState();
}

class _InventoryPanelState extends State<InventoryPanel> {
  Slot? _selected;
  String _message = '';

  GameState get s => widget.game.state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (_selected != null &&
            !s.bag.contains(_selected) &&
            _selected != s.weapon &&
            _selected != s.armor) {
          _selected = null;
        }
        return _PanelFrame(
          title: 'Túi đồ',
          onClose: widget.game.closePanel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vàng: ${s.gold}   •   Đá nâng cấp: ${s.countOf(ItemId.stone)}',
                  style: const TextStyle(color: _gold)),
              const SizedBox(height: 6),
              Text('Lv ${s.level}   Tấn công ${s.attack}   Phòng thủ ${s.defense}'
                  '   HP ${s.hp}/${s.maxHp}'),
              const SizedBox(height: 10),
              const Text('Trang bị'),
              const SizedBox(height: 4),
              Row(children: [
                _tile(s.weapon),
                const SizedBox(width: 8),
                _tile(s.armor),
              ]),
              const SizedBox(height: 10),
              Text('Hành trang (${s.bag.length}/${GameState.bagSize})'),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var i = 0; i < GameState.bagSize; i++)
                  _tile(i < s.bag.length ? s.bag[i] : null),
              ]),
              const SizedBox(height: 12),
              _details(),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(Slot? slot) {
    final selected = slot != null && slot == _selected;
    return GestureDetector(
      onTap: slot == null
          ? null
          : () => setState(() {
                _selected = slot;
                _message = '';
              }),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: selected ? _gold : Colors.white24, width: selected ? 2 : 1),
        ),
        child: slot == null
            ? null
            : Stack(children: [
                Center(child: itemIcon(widget.game, slot.id)),
                if (slot.def.stackable && slot.count > 1)
                  Positioned(
                      right: 3,
                      bottom: 1,
                      child: Text('${slot.count}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))),
                if (slot.plus > 0)
                  Positioned(
                      left: 3,
                      top: 1,
                      child: Text('+${slot.plus}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _gold))),
              ]),
      ),
    );
  }

  Widget _details() {
    final slot = _selected;
    if (slot == null) {
      return Text(_message.isEmpty ? 'Chạm vào vật phẩm để xem chi tiết.' : _message,
          style: const TextStyle(color: Colors.white70));
    }
    final def = slot.def;
    final equipped = slot == s.weapon || slot == s.armor;
    final stat = def.kind == ItemKind.weapon
        ? 'Tấn công +${def.power + slot.plus * 3}'
        : def.kind == ItemKind.armor
            ? 'Phòng thủ +${def.power + slot.plus * 2}'
            : '';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.black26, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            itemIcon(widget.game, slot.id, size: 32),
            const SizedBox(width: 8),
            Text(slot.label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (equipped)
              const Text('  (đang mặc)',
                  style: TextStyle(color: Colors.greenAccent)),
          ]),
          const SizedBox(height: 4),
          Text(def.desc, style: const TextStyle(color: Colors.white70)),
          if (stat.isNotEmpty) Text(stat),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (def.kind == ItemKind.consumable)
              FilledButton(
                  onPressed: () =>
                      setState(() => _message = s.use(slot)),
                  child: const Text('Dùng')),
            if (def.isEquip && !equipped)
              FilledButton(
                  onPressed: () => setState(() {
                        s.equip(slot);
                        _message = 'Đã trang bị ${slot.label}.';
                      }),
                  child: const Text('Trang bị')),
            if (def.isEquip)
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF6C00)),
                  onPressed: slot.plus >= GameState.maxPlus
                      ? null
                      : () => setState(() => _message = s.upgrade(slot)),
                  child: Text(slot.plus >= GameState.maxPlus
                      ? 'Tối đa'
                      : 'Nâng cấp (${s.stonesFor(slot)} đá, '
                          '${s.goldFor(slot)} vàng, '
                          '${(s.chanceFor(slot) * 100).round()}%)')),
          ]),
          if (_message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message, style: const TextStyle(color: _gold)),
            ),
        ],
      ),
    );
  }
}

class QuestPanel extends StatefulWidget {
  const QuestPanel({super.key, required this.game});

  final VillageGame game;

  @override
  State<QuestPanel> createState() => _QuestPanelState();
}

class _QuestPanelState extends State<QuestPanel> {
  String _message = '';

  GameState get s => widget.game.state;

  @override
  Widget build(BuildContext context) {
    const atNpc = true; // no village chief any more: accept/claim anywhere
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _PanelFrame(
        title: 'Nhiệm vụ',
        onClose: widget.game.closePanel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final q in s.quests) _quest(q, atNpc),
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_message, style: const TextStyle(color: _gold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quest(Quest q, bool atNpc) {
    final done = q.status == QuestStatus.claimed;
    final ready = s.isReady(q);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.black26, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.title + (done ? '  ✔' : ''),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: done ? Colors.white54 : Colors.white)),
          Text(q.desc, style: const TextStyle(color: Colors.white70)),
          Text('Thưởng: ${q.rewardText}',
              style: const TextStyle(color: _gold, fontSize: 12)),
          if (q.status == QuestStatus.active)
            Text('Tiến độ: ${s.progress(q)}/${q.need}'),
          if (atNpc && q.status == QuestStatus.available)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FilledButton(
                  onPressed: () => setState(() {
                        s.acceptQuest(q);
                        _message = 'Đã nhận nhiệm vụ "${q.title}".';
                      }),
                  child: const Text('Nhận nhiệm vụ')),
            ),
          if (atNpc && ready)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32)),
                  onPressed: () =>
                      setState(() => _message = s.claimQuest(q)),
                  child: const Text('Trả nhiệm vụ')),
            ),
        ],
      ),
    );
  }
}

/// Paints the first frame of a hero's Idle sheet (128px frames).
class _HeroPainter extends CustomPainter {
  _HeroPainter(this.image, [this.zoom = 1, this.frame = 0]);

  final ui.Image image;
  final double zoom;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(image, Rect.fromLTWH(frame * 128.0 + 64 - 64 / zoom, 128 - 128 / zoom, 128 / zoom, 128 / zoom), Offset.zero & size,
        Paint()..filterQuality = FilterQuality.none);
  }

  @override
  bool shouldRepaint(_HeroPainter old) => old.image != image || old.frame != frame;
}

/// A hero's Idle sheet played as a looping animation.
class _IdleHero extends StatefulWidget {
  const _IdleHero({required this.image, required this.zoom});

  final ui.Image image;
  final double zoom;

  @override
  State<_IdleHero> createState() => _IdleHeroState();
}

class _IdleHeroState extends State<_IdleHero> {
  Timer? _timer;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 140), (_) {
      if (mounted) setState(() => _frame++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _HeroPainter(widget.image, widget.zoom, _frame % (widget.image.width ~/ 128)));
}

/// Full-screen backdrop used by the menu style screens.
class _Screen extends StatelessWidget {
  const _Screen({required this.child, this.color = const Color(0xE60B1020)});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: DefaultTextStyle(style: const TextStyle(color: Colors.white, fontSize: 14), child: child),
          ),
        ),
      );
}

Widget _bigButton(String label, VoidCallback? onTap, {Color color = const Color(0xFF2E7D32), double width = 230}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: SizedBox(
        width: width,
        child: FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: Colors.white12,
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: onTap == null
              ? null
              : () {
                  GameAudio.sfx('click');
                  onTap();
                },
          child: Text(label, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );

class MainMenu extends StatefulWidget {
  const MainMenu({super.key, required this.game});

  final VillageGame game;

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  Map<String, dynamic>? _run;
  Map<String, dynamic> _rec = {'bestStage': 0, 'kills': 0, 'wins': 0};
  bool _busy = false;
  bool _help = false;

  @override
  void initState() {
    super.initState();
    SaveStore.loadRun().then((r) {
      if (mounted) setState(() => _run = r);
    });
    SaveStore.loadRecords().then((r) {
      if (mounted) setState(() => _rec = r);
    });
  }

  Future<void> _continue() async {
    setState(() => _busy = true);
    final ok = await widget.game.continueRun();
    if (!ok && mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_help) return HelpScreen(onBack: () => setState(() => _help = false));
    final run = _run;
    String? resume;
    if (run != null) {
      final st = (run['stage'] as int).clamp(0, stages.length - 1);
      final hero = heroes[(run['hero'] as int).clamp(0, heroes.length - 1)].name;
      resume = 'Màn ${st + 1}/${stages.length} • $hero • Lv ${(run['state'] as Map)['level']}';
    }
    return _Screen(
      color: const Color(0x8C070A16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('SLIME SLAYER',
              style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: _gold,
                  letterSpacing: 4,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
          const Text('Đấu trường diệt slime', style: TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 22),
          _bigButton('Chơi mới', _busy ? null : widget.game.openSelect),
          _bigButton('Tiếp tục', run == null || _busy ? null : _continue, color: const Color(0xFF1565C0)),
          if (resume != null) Text(resume, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          _bigButton('Cài đặt', widget.game.openSettings, color: const Color(0xFF1565C0)),
          _bigButton('Hướng dẫn', () => setState(() => _help = true), color: Colors.blueGrey.shade700),
          const SizedBox(height: 12),
          Text('Kỷ lục: màn ${_rec['bestStage']}/${stages.length}  •  ${_rec['kills']} quái đã diệt  •  ${_rec['wins']} lần thắng',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  static const _rows = [
    ('WASD / mũi tên / cần điều khiển', 'Di chuyển'),
    ('Space hoặc J', 'Đánh thường (attack 1)'),
    ('K hoặc 1', 'Kỹ năng 1 (attack 2)'),
    ('L hoặc 2', 'Kỹ năng 2 (attack 3)'),
    ('Shift giữ / R', 'Chạy (bật/tắt), chạy liên tục tốn MP'),
    ('X', 'Nhảy: né đòn (đòn đập đất của boss)'),
    ('H', 'Uống bình máu'),
    ('I / Q / B', 'Túi đồ / Nhiệm vụ / Cửa hàng'),
    ('Esc hoặc P', 'Tạm dừng'),
  ];

  @override
  Widget build(BuildContext context) => _Screen(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('HƯỚNG DẪN', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _gold)),
              const SizedBox(height: 10),
              const Text(
                  'Hạ đủ 10 x số màn quái để gọi boss, đánh bại boss rồi đi sang phải để qua màn. Lên cấp mỗi 20, 30, 40... quái (+15% chỉ số). '
                  'Hạ boss cuối để thắng. Hết máu có thể hồi sinh tối đa 2 lần mỗi lượt chơi.',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              for (final r in _rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 230, child: Text(r.$1, style: const TextStyle(color: _gold))),
                    Expanded(child: Text(r.$2)),
                  ]),
                ),
              const SizedBox(height: 6),
              const Text('Mẹo: vòng đỏ dưới chân boss là đòn đập đất, hãy nhảy (X) để né. '
                  'Trên sàn bay có quái và đòn đánh chỉ trúng quái cùng độ cao.',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 12),
              Center(child: _bigButton('Quay lại', onBack, color: Colors.blueGrey.shade700, width: 180)),
            ],
          ),
        ),
      );
}

class CharacterSelect extends StatefulWidget {
  const CharacterSelect({super.key, required this.game});

  final VillageGame game;

  @override
  State<CharacterSelect> createState() => _CharacterSelectState();
}

class _CharacterSelectState extends State<CharacterSelect> {
  int _picked = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _picked = widget.game.selectedHero;
  }

  @override
  Widget build(BuildContext context) {
    return _Screen(
      color: const Color(0xF2101626),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('CHỌN NHÂN VẬT', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _gold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [for (var i = 0; i < heroes.length; i++) _card(i)],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey.shade700),
                onPressed: widget.game.toMenu,
                child: const Text('Quay lại'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14)),
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _busy = true);
                        widget.game.startNew(_picked);
                      },
                child: Text('Vào game: ${heroes[_picked].name}', style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(int i) {
    final h = heroes[i];
    final sel = i == _picked;
    final image = widget.game.images.fromCache('${h.folder}/Idle.png');
    return GestureDetector(
      onTap: () => setState(() => _picked = i),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF2A3558) : _panelColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? _gold : Colors.white24, width: 3),
        ),
        child: Column(
          children: [
            SizedBox(width: 100, height: 100, child: _IdleHero(image: image, zoom: h.scale)),
            Text(h.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _gold)),
            const SizedBox(height: 3),
            Text(h.blurb, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
                'Tốc độ ${h.speed.round()} • ST x${h.dmgMul}'
                '${h.defBonus > 0 ? ' • Giáp +${h.defBonus}' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class PauseMenu extends StatelessWidget {
  const PauseMenu({super.key, required this.game});

  final VillageGame game;

  @override
  Widget build(BuildContext context) => _Screen(
        color: Colors.black54,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('TẠM DỪNG', style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: _gold)),
            const SizedBox(height: 14),
            _bigButton('Tiếp tục', game.closePause),
            ValueListenableBuilder<bool>(
              valueListenable: GameAudio.mutedNotifier,
              builder: (context, muted, _) => _bigButton(
                  muted ? 'Âm thanh: TẮT' : 'Âm thanh: BẬT', () => GameAudio.setMuted(!muted),
                  color: const Color(0xFF6A1B9A)),
            ),
            _bigButton('Cài đặt', game.openSettings, color: const Color(0xFF1565C0)),
            _bigButton('Về menu chính', game.toMenu, color: Colors.blueGrey.shade700),
            const Text('(Tiến độ được lưu ở đầu mỗi màn)', style: TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      );
}

class GameOverScreen extends StatelessWidget {
  const GameOverScreen({super.key, required this.game});

  final VillageGame game;

  @override
  Widget build(BuildContext context) {
    final left = game.revivesLeft;
    return _Screen(
      color: Colors.grey.withValues(alpha: .8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('GAME OVER',
              style: TextStyle(
                  fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 4, shadows: [Shadow(blurRadius: 8)])),
          const SizedBox(height: 6),
          Text('Màn ${game.stageIdx + 1}/${stages.length} • Lv ${game.state.level} • ${game.runKills} quái',
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 18),
          if (left > 0)
            _bigButton('Hồi sinh (còn $left lần)', game.revive)
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Đã hết lượt hồi sinh', style: TextStyle(color: Colors.white, fontSize: 15)),
            ),
          _bigButton('Về trang chủ', game.toMenu, color: Colors.blueGrey.shade700),
        ],
      ),
    );
  }
}

class VictoryScreen extends StatelessWidget {
  const VictoryScreen({super.key, required this.game});

  final VillageGame game;

  String get _time {
    final s = game.runTime.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => _Screen(
        color: const Color(0xE6102A18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CHIẾN THẮNG!',
                style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 3, shadows: [Shadow(blurRadius: 10)])),
            const SizedBox(height: 6),
            Text('${game.player.hero.name} đã quét sạch ${stages.length} màn!', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text('Cấp ${game.state.level} • ${game.runKills} quái • ${game.state.gold} vàng • Thời gian $_time',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 18),
            _bigButton('Chơi lại', game.openSelect),
            _bigButton('Về menu', game.toMenu, color: Colors.blueGrey.shade700),
          ],
        ),
      );
}

class _ShopItem {
  const _ShopItem(this.id, this.price);

  final ItemId id;
  final int price;
}

const _stock = [
  _ShopItem(ItemId.potion, 30),
  _ShopItem(ItemId.stone, 70),
  _ShopItem(ItemId.ironSword, 180),
  _ShopItem(ItemId.ninjaArmor, 180),
];

class ShopPanel extends StatefulWidget {
  const ShopPanel({super.key, required this.game});

  final VillageGame game;

  @override
  State<ShopPanel> createState() => _ShopPanelState();
}

class _ShopPanelState extends State<ShopPanel> {
  String _message = '';

  GameState get s => widget.game.state;

  void _buy(_ShopItem it) {
    if (s.gold < it.price) {
      _message = 'Không đủ vàng.';
    } else if (!s.addItem(it.id)) {
      _message = 'Túi đầy.';
    } else {
      s.gold -= it.price;
      s.touch();
      _message = 'Đã mua ${itemDefs[it.id]!.name}.';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _PanelFrame(
        title: 'Cửa hàng',
        onClose: widget.game.closePanel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vàng: ${s.gold}', style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final it in _stock)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  itemIcon(widget.game, it.id),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(itemDefs[it.id]!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(itemDefs[it.id]!.desc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                  FilledButton(
                      onPressed: s.gold >= it.price ? () => _buy(it) : null, child: Text('${it.price} vàng')),
                ]),
              ),
            if (_message.isNotEmpty) Text(_message, style: const TextStyle(color: _gold)),
          ],
        ),
      ),
    );
  }
}

/// Sound toggle and the entry to the button layout editor.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.game});

  final VillageGame game;

  @override
  Widget build(BuildContext context) => _Screen(
        color: const Color(0xE6101626),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CÀI ĐẶT', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: _gold)),
            const SizedBox(height: 14),
            ValueListenableBuilder<bool>(
              valueListenable: GameAudio.mutedNotifier,
              builder: (context, muted, _) => _bigButton(
                  muted ? 'Âm thanh: TẮT' : 'Âm thanh: BẬT', () => GameAudio.setMuted(!muted),
                  color: const Color(0xFF6A1B9A)),
            ),
            _bigButton('Tùy chỉnh giao diện nút', () => game.overlays.add('layout'), color: const Color(0xFF1565C0)),
            const SizedBox(height: 6),
            _bigButton('Đóng', game.closeSettings, color: Colors.blueGrey.shade700),
          ],
        ),
      );
}

/// Drag the on-screen buttons where you want them, then save. The layout is
/// stored on the device.
class LayoutEditor extends StatefulWidget {
  const LayoutEditor({super.key, required this.game});

  final VillageGame game;

  @override
  State<LayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends State<LayoutEditor> {
  late ButtonLayout _draft = widget.game.layout.copy();
  String? _drag;
  bool _saved = false;

  static const _w = 800.0, _h = 450.0;

  void _grab(Offset p) {
    String? best;
    var bestD = double.infinity;
    for (final e in _draft.pos.entries) {
      final d = (Offset(e.value.$1, e.value.$2) - p).distance;
      if (d < ButtonLayout.radius[e.key]! + 14 && d < bestD) {
        best = e.key;
        bestD = d;
      }
    }
    _drag = best;
  }

  void _move(Offset p) {
    final id = _drag;
    if (id == null) return;
    final r = ButtonLayout.radius[id]!;
    setState(() {
      _draft.pos[id] = (p.dx.clamp(r, _w - r).toDouble(), p.dy.clamp(r, _h - r).toDouble());
      _saved = false;
    });
  }

  Future<void> _save() async {
    widget.game.layout = _draft.copy();
    await widget.game.layout.save();
    widget.game.applyLayout();
    if (mounted) setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF2080C18),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                const Text('Kéo các nút đến vị trí mong muốn', style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                    onPressed: () => setState(() {
                          _draft = ButtonLayout({});
                          _saved = false;
                        }),
                    child: const Text('Mặc định', style: TextStyle(color: Colors.white70))),
                const SizedBox(width: 6),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                    onPressed: _save,
                    child: Text(_saved ? 'Đã lưu ✔' : 'Lưu')),
                const SizedBox(width: 6),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey.shade700),
                    onPressed: () => widget.game.overlays.remove('layout'),
                    child: const Text('Quay lại')),
              ]),
            ),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _w,
                    height: _h,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _grab(d.localPosition),
                      onPanUpdate: (d) => _move(d.localPosition),
                      onPanEnd: (_) => _drag = null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B2236),
                          border: Border.all(color: _gold, width: 2),
                        ),
                        child: Stack(children: [
                          const Positioned(
                              left: 36,
                              bottom: 36,
                              child: CircleAvatar(radius: 50, backgroundColor: Colors.white12, child: Text('Cần\nđiều khiển', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12)))),
                          for (final e in _draft.pos.entries) _circle(e.key, e.value),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(String id, (double, double) p) {
    final r = ButtonLayout.radius[id]!;
    const colors = {
      'attack': Color(0xFFE53935),
      'skill1': Color(0xFF1E88E5),
      'skill2': Color(0xFF7E57C2),
      'run': Color(0xFFF9A825),
      'jump': Color(0xFF00ACC1),
    };
    return Positioned(
      left: p.$1 - r,
      top: p.$2 - r,
      child: Container(
        width: r * 2,
        height: r * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors[id]!.withValues(alpha: .85),
          border: Border.all(color: _drag == id ? Colors.yellowAccent : Colors.white54, width: 3),
        ),
        child: Text(ButtonLayout.labels[id]!,
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
