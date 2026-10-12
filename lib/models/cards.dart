/// 牌面基础模型。
///
/// 全项目统一使用 0..51 的整数编码来表示一张牌，好处是：
///  * 在蒙特卡洛模拟的热循环里没有对象分配，速度更快；
///  * 整数可以在后台 isolate 之间自由传递。
///
/// 编码规则：`code = rank * 4 + suit`
///  * rank: 0 => '2' ... 8 => 'T' ... 12 => 'A'
///  * suit: 0 => ♠ 黑桃, 1 => ♥ 红桃, 2 => ♦ 方块, 3 => ♣ 梅花
class Cards {
  Cards._();

  /// 一副牌的张数。
  static const int deckSize = 52;

  /// 紧凑写法（用于日志、调试），10 用 'T' 表示。
  static const List<String> rankNames = <String>[
    '2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A',
  ];

  /// 牌面显示写法（10 用 '10' 表示）。
  static const List<String> rankLabels = <String>[
    '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A',
  ];

  /// 花色符号。
  static const List<String> suitSymbols = <String>['♠', '♥', '♦', '♣'];

  /// 花色中文名。
  static const List<String> suitNamesCn = <String>['黑桃', '红桃', '方块', '梅花'];

  /// 由点数与花色生成牌的编码。
  static int make(int rank, int suit) => rank * 4 + suit;

  /// 取点数（0..12）。
  static int rankOf(int card) => card >> 2;

  /// 取花色（0..3）。
  static int suitOf(int card) => card & 3;

  /// 是否是红色花色（红桃 / 方块），仅用于 UI 上色。
  static bool isRed(int card) {
    final int suit = suitOf(card);
    return suit == 1 || suit == 2;
  }

  /// 例如 "A♠"。
  static String label(int card) => '${rankNames[rankOf(card)]}${suitSymbols[suitOf(card)]}';

  /// 例如 "黑桃A"。
  static String labelWithSuitName(int card) =>
      '${suitNamesCn[suitOf(card)]}${rankLabels[rankOf(card)]}';

  /// 一整副未洗的牌。
  static List<int> fullDeck() => List<int>.generate(deckSize, (int i) => i);
}
