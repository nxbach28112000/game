import 'dart:math';

import 'package:flutter/foundation.dart';

final _rng = Random();

enum ItemKind { consumable, weapon, armor, material }

enum ItemId { potion, woodSword, ironSword, clothArmor, ninjaArmor, stone, gel }

class ItemDef {
  final String name, icon, desc;
  final ItemKind kind;

  /// Weapon attack, armor defense, or potion heal amount.
  final int power;

  const ItemDef(this.name, this.icon, this.desc, this.kind, [this.power = 0]);

  bool get isEquip => kind == ItemKind.weapon || kind == ItemKind.armor;
  bool get stackable => !isEquip;
}

const itemDefs = <ItemId, ItemDef>{
  ItemId.potion: ItemDef('Bình máu', 'item_potion', 'Hồi 50 HP.',
      ItemKind.consumable, 50),
  ItemId.woodSword: ItemDef('Kiếm gỗ', 'item_sword_wood',
      'Thanh kiếm tập luyện.', ItemKind.weapon, 4),
  ItemId.ironSword: ItemDef('Kiếm sắt', 'item_sword_iron',
      'Sắc bén hơn nhiều so với kiếm gỗ.', ItemKind.weapon, 10),
  ItemId.clothArmor: ItemDef('Áo vải', 'item_armor_cloth',
      'Áo vải thô của dân làng.', ItemKind.armor, 1),
  ItemId.ninjaArmor: ItemDef('Áo ninja', 'item_armor_ninja',
      'Nhẹ và bền, dành cho chiến binh.', ItemKind.armor, 5),
  ItemId.stone: ItemDef('Đá nâng cấp', 'item_stone',
      'Dùng để cường hóa trang bị.', ItemKind.material),
  ItemId.gel: ItemDef('Thạch slime', 'item_gel',
      'Rơi ra từ quái slime.', ItemKind.material),
};

class Slot {
  final ItemId id;
  int count;
  int plus;

  Slot(this.id, [this.count = 1, this.plus = 0]);

  ItemDef get def => itemDefs[id]!;
  String get label => plus > 0 ? '${def.name} +$plus' : def.name;
}

enum QuestStatus { available, active, claimed }

class Quest {
  final String title, desc;
  final ItemId? collect; // null => kill quest
  final int need;
  final int rewardGold, rewardExp;
  final ItemId? rewardItem;
  final int rewardCount;
  QuestStatus status = QuestStatus.available;
  int kills = 0;

  Quest(this.title, this.desc, this.need,
      {this.collect,
      this.rewardGold = 0,
      this.rewardExp = 0,
      this.rewardItem,
      this.rewardCount = 1});

  String get rewardText {
    final parts = <String>[
      if (rewardGold > 0) '$rewardGold vàng',
      if (rewardExp > 0) '$rewardExp EXP',
      if (rewardItem != null)
        '${itemDefs[rewardItem]!.name}${rewardCount > 1 ? ' x$rewardCount' : ''}',
    ];
    return parts.join(', ');
  }
}

class GameState extends ChangeNotifier {
  static const bagSize = 20;
  static const maxPlus = 9;

  int level = 1, exp = 0, maxHp = 100, hp = 100, maxMp = 50, mp = 50;
  int gold = 0;
  final List<Slot> bag = [Slot(ItemId.potion, 3)];
  Slot weapon = Slot(ItemId.woodSword);
  Slot armor = Slot(ItemId.clothArmor);

  final List<Quest> quests = [
    Quest('Diệt quái', 'Tiêu diệt 5 con quái quanh làng.', 5,
        rewardGold: 100, rewardExp: 60, rewardItem: ItemId.potion, rewardCount: 2),
    Quest('Thu thập thạch', 'Mang cho ta 6 Thạch slime.', 6,
        collect: ItemId.gel,
        rewardGold: 150,
        rewardItem: ItemId.ironSword),
    Quest('Thợ săn', 'Tiêu diệt 12 con quái.', 12,
        rewardGold: 300,
        rewardExp: 150,
        rewardItem: ItemId.ninjaArmor),
    Quest('Nhà luyện kim', 'Tìm 3 Đá nâng cấp cho thợ rèn.', 3,
        collect: ItemId.stone,
        rewardGold: 200,
        rewardItem: ItemId.potion,
        rewardCount: 3),
  ];

  int get expToNext => level * 50;
  int get attack => 8 + level * 3 + weapon.def.power + weapon.plus * 3;
  int get defense => level + armor.def.power + armor.plus * 2;

  void touch() => notifyListeners();

  // ---- progression ----
  /// Returns true if the player levelled up.
  bool gainExp(int v) {
    exp += v;
    var up = false;
    while (exp >= expToNext) {
      exp -= expToNext;
      level++;
      maxHp += 20;
      maxMp += 10;
      hp = maxHp;
      mp = maxMp;
      up = true;
    }
    notifyListeners();
    return up;
  }

  // ---- bag ----
  int countOf(ItemId id) =>
      bag.where((s) => s.id == id).fold(0, (a, s) => a + s.count);

  bool addItem(ItemId id, [int n = 1, int plus = 0]) {
    final def = itemDefs[id]!;
    if (def.stackable) {
      for (final s in bag) {
        if (s.id == id) {
          s.count += n;
          notifyListeners();
          return true;
        }
      }
    }
    if (bag.length >= bagSize) return false;
    bag.add(Slot(id, n, plus));
    notifyListeners();
    return true;
  }

  void consume(ItemId id, int n) {
    for (final s in List<Slot>.from(bag)) {
      if (s.id != id || n <= 0) continue;
      final take = min(n, s.count);
      s.count -= take;
      n -= take;
      if (s.count == 0) bag.remove(s);
    }
    notifyListeners();
  }

  bool usePotion() {
    final s = bag.where((s) => s.id == ItemId.potion).firstOrNull;
    if (s == null || hp >= maxHp) return false;
    hp = min(maxHp, hp + s.def.power);
    consume(ItemId.potion, 1);
    return true;
  }

  String use(Slot s) {
    if (s.id == ItemId.potion) {
      return usePotion() ? 'Đã hồi máu.' : 'HP đã đầy.';
    }
    return 'Không thể sử dụng.';
  }

  void equip(Slot s) {
    final i = bag.indexOf(s);
    if (i < 0) return;
    if (s.def.kind == ItemKind.weapon) {
      bag[i] = weapon;
      weapon = s;
    } else if (s.def.kind == ItemKind.armor) {
      bag[i] = armor;
      armor = s;
    }
    notifyListeners();
  }

  // ---- upgrade ----
  int stonesFor(Slot s) => s.plus + 1;
  int goldFor(Slot s) => 30 * (s.plus + 1);
  double chanceFor(Slot s) => max(.3, 1 - .1 * s.plus);

  String upgrade(Slot s) {
    if (!s.def.isEquip) return 'Vật phẩm này không thể nâng cấp.';
    if (s.plus >= maxPlus) return 'Đã đạt cấp tối đa.';
    final st = stonesFor(s), g = goldFor(s);
    if (countOf(ItemId.stone) < st) return 'Cần $st Đá nâng cấp.';
    if (gold < g) return 'Cần $g vàng.';
    consume(ItemId.stone, st);
    gold -= g;
    final ok = _rng.nextDouble() < chanceFor(s);
    if (ok) s.plus++;
    notifyListeners();
    return ok
        ? 'Thành công! ${s.label}'
        : 'Thất bại... nguyên liệu đã mất.';
  }

  // ---- quests ----
  int progress(Quest q) => q.collect == null
      ? min(q.kills, q.need)
      : min(countOf(q.collect!), q.need);

  bool isReady(Quest q) =>
      q.status == QuestStatus.active && progress(q) >= q.need;

  bool get hasQuestAttention => quests.any(
      (q) => q.status == QuestStatus.available || isReady(q));

  void acceptQuest(Quest q) {
    q.status = QuestStatus.active;
    q.kills = 0;
    notifyListeners();
  }

  String claimQuest(Quest q) {
    if (!isReady(q)) return 'Chưa hoàn thành.';
    if (q.rewardItem != null &&
        itemDefs[q.rewardItem]!.stackable == false &&
        bag.length >= bagSize) {
      return 'Túi đầy, hãy dọn chỗ trống.';
    }
    if (q.collect != null) consume(q.collect!, q.need);
    gold += q.rewardGold;
    if (q.rewardItem != null) addItem(q.rewardItem!, q.rewardCount);
    if (q.rewardExp > 0) gainExp(q.rewardExp);
    q.status = QuestStatus.claimed;
    notifyListeners();
    return 'Nhận thưởng: ${q.rewardText}';
  }

  void onKill() {
    for (final q in quests) {
      if (q.status == QuestStatus.active && q.collect == null) q.kills++;
    }
    notifyListeners();
  }
}
