import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/game_state.dart';
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
            _btn('Đổi nhân vật (C)', game.switchCharacter),
            _btn('Đổi map (M)', game.nextBackground),
            _btn('Bình máu (H) x${game.state.countOf(ItemId.potion)}',
                game.quickPotion),
            _btn('Túi đồ (I)', () => game.openPanel('inventory')),
            _btn('Nhiệm vụ (Q)${game.state.hasQuestAttention ? ' !' : ''}', () {
              game.questAtNpc = false;
              game.openPanel('quests');
            }),
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
    final atNpc = widget.game.questAtNpc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _PanelFrame(
        title: atNpc ? 'Làng trưởng' : 'Nhiệm vụ',
        onClose: widget.game.closePanel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (atNpc)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                    'Chào chiến binh! Slime đang quấy phá làng ta, '
                    'hãy giúp ta một tay nhé.',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('Đến gặp Làng trưởng để nhận và trả nhiệm vụ.',
                    style: TextStyle(color: Colors.white70)),
              ),
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
