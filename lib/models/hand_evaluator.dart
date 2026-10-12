import 'cards.dart';

/// 牌型强度，索引越大越强，且索引值与 [HandEvaluator.evaluate] 的评分高位一致。
enum HandCategory {
  highCard,
  pair,
  twoPair,
  trips,
  straight,
  flush,
  fullHouse,
  quads,
  straightFlush,
}

extension HandCategoryText on HandCategory {
  /// 中文名。
  String get cnName {
    switch (this) {
      case HandCategory.highCard:
        return '高牌';
      case HandCategory.pair:
        return '一对';
      case HandCategory.twoPair:
        return '两对';
      case HandCategory.trips:
        return '三条';
      case HandCategory.straight:
        return '顺子';
      case HandCategory.flush:
        return '同花';
      case HandCategory.fullHouse:
        return '葫芦';
      case HandCategory.quads:
        return '四条';
      case HandCategory.straightFlush:
        return '同花顺';
    }
    return '未知';
  }
}

/// 7 张牌（或 5/6 张）取最优 5 张的牌力评估器。
///
/// 设计要点：
///  * 纯 Dart 实现，不依赖 Flutter，可以在后台 isolate 中调用；
///  * 返回一个**可比较的整数评分**，避免在蒙特卡洛热循环里创建对象；
///  * 评分结构：`牌型(4bit) | 踢脚1(4bit) | 踢脚2(4bit) | 踢脚3(4bit) | 踢脚4(4bit) | 踢脚5(4bit)`，
///    其中 4bit 足够放下 0..12 的点数索引，因此直接比较整数即可比较牌力。
class HandEvaluator {
  HandEvaluator._();

  /// 牌型在评分中的位移量。
  static const int categoryShift = 20;

  /// 评估给定的 2~7 张牌，返回可比较的整数评分（越大越强）。
  static int evaluate(List<int> cards) {
    // 统计每种点数、每种花色的数量，以及每种花色包含了哪些点数。
    final List<int> rankCount = List<int>.filled(13, 0);
    final List<int> suitCount = List<int>.filled(4, 0);
    final List<int> suitRankMask = List<int>.filled(4, 0);
    int rankMask = 0;

    for (int i = 0; i < cards.length; i++) {
      final int card = cards[i];
      final int rank = card >> 2;
      final int suit = card & 3;
      rankCount[rank]++;
      suitCount[suit]++;
      suitRankMask[suit] |= 1 << rank;
      rankMask |= 1 << rank;
    }

    // 1) 同花：7 张牌里最多只会有一门花色达到 5 张。
    int flushSuit = -1;
    for (int s = 0; s < 4; s++) {
      if (suitCount[s] >= 5) {
        flushSuit = s;
      }
    }
    if (flushSuit >= 0) {
      final int straightFlushHigh = _straightHigh(suitRankMask[flushSuit]);
      if (straightFlushHigh >= 0) {
        return _pack(HandCategory.straightFlush.index, straightFlushHigh, 0, 0, 0, 0);
      }
    }

    // 2) 四条（7 张牌里最多出现一次）。
    for (int r = 12; r >= 0; r--) {
      if (rankCount[r] == 4) {
        final int kicker = _bestKicker(rankCount, r, -1, -1);
        return _pack(HandCategory.quads.index, r, kicker, 0, 0, 0);
      }
    }

    // 3) 统计三条与对子（按点数从大到小）。
    int trips1 = -1;
    int trips2 = -1;
    int pair1 = -1;
    int pair2 = -1;
    for (int r = 12; r >= 0; r--) {
      final int count = rankCount[r];
      if (count >= 3) {
        if (trips1 < 0) {
          trips1 = r;
        } else if (trips2 < 0) {
          trips2 = r;
        }
      } else if (count == 2) {
        if (pair1 < 0) {
          pair1 = r;
        } else if (pair2 < 0) {
          pair2 = r;
        }
      }
    }

    // 4) 葫芦：三条 + 一对（或两个三条）。
    if (trips1 >= 0 && (pair1 >= 0 || trips2 >= 0)) {
      final int pairRank = trips2 >= 0 ? trips2 : pair1;
      return _pack(HandCategory.fullHouse.index, trips1, pairRank, 0, 0, 0);
    }

    // 5) 同花：取该花色最大的 5 张。
    if (flushSuit >= 0) {
      final int mask = suitRankMask[flushSuit];
      int r0 = 0;
      int r1 = 0;
      int r2 = 0;
      int r3 = 0;
      int r4 = 0;
      int slot = 0;
      for (int r = 12; r >= 0 && slot < 5; r--) {
        if ((mask & (1 << r)) != 0) {
          if (slot == 0) {
            r0 = r;
          } else if (slot == 1) {
            r1 = r;
          } else if (slot == 2) {
            r2 = r;
          } else if (slot == 3) {
            r3 = r;
          } else {
            r4 = r;
          }
          slot++;
        }
      }
      return _pack(HandCategory.flush.index, r0, r1, r2, r3, r4);
    }

    // 6) 顺子。
    final int straightHigh = _straightHigh(rankMask);
    if (straightHigh >= 0) {
      return _pack(HandCategory.straight.index, straightHigh, 0, 0, 0, 0);
    }

    // 7) 三条。
    if (trips1 >= 0) {
      final int k1 = _bestKicker(rankCount, trips1, -1, -1);
      final int k2 = _bestKicker(rankCount, trips1, k1, -1);
      return _pack(HandCategory.trips.index, trips1, k1, k2, 0, 0);
    }

    // 8) 两对。
    if (pair1 >= 0 && pair2 >= 0) {
      final int kicker = _bestKicker(rankCount, pair1, pair2, -1);
      return _pack(HandCategory.twoPair.index, pair1, pair2, kicker, 0, 0);
    }

    // 9) 一对。
    if (pair1 >= 0) {
      final int k1 = _bestKicker(rankCount, pair1, -1, -1);
      final int k2 = _bestKicker(rankCount, pair1, k1, -1);
      final int k3 = _bestKicker(rankCount, pair1, k1, k2);
      return _pack(HandCategory.pair.index, pair1, k1, k2, k3, 0);
    }

    // 10) 高牌。
    int r0 = 0;
    int r1 = 0;
    int r2 = 0;
    int r3 = 0;
    int r4 = 0;
    int slot = 0;
    for (int r = 12; r >= 0 && slot < 5; r--) {
      if (rankCount[r] > 0) {
        if (slot == 0) {
          r0 = r;
        } else if (slot == 1) {
          r1 = r;
        } else if (slot == 2) {
          r2 = r;
        } else if (slot == 3) {
          r3 = r;
        } else {
          r4 = r;
        }
        slot++;
      }
    }
    return _pack(HandCategory.highCard.index, r0, r1, r2, r3, r4);
  }

  /// 从评分中取出牌型索引（0..8）。
  static int categoryOf(int score) => score >> categoryShift;

  /// 从评分中取出第 [index] 个踢脚（0 表示该位置为空）。
  static int tiebreakerOf(int score, int index) => (score >> (16 - 4 * index)) & 0xF;

  /// 把评分还原成点数列表，便于展示。
  static List<int> tiebreakersOf(int score, int count) {
    final List<int> result = <int>[];
    for (int i = 0; i < count; i++) {
      result.add(tiebreakerOf(score, i));
    }
    return result;
  }

  /// 生成中文牌型描述，例如 "葫芦（9 带 5）"。
  static String describe(int score) {
    final HandCategory category = HandCategory.values[categoryOf(score)];
    final String t0 = _rankText(tiebreakerOf(score, 0));
    final String t1 = _rankText(tiebreakerOf(score, 1));
    switch (category) {
      case HandCategory.straightFlush:
        return tiebreakerOf(score, 0) == 12 ? '皇家同花顺' : '同花顺（$t0 高）';
      case HandCategory.quads:
        return '四条（$t0）';
      case HandCategory.fullHouse:
        return '葫芦（$t0 带 $t1）';
      case HandCategory.flush:
        return '同花（$t0 高）';
      case HandCategory.straight:
        return '顺子（$t0 高）';
      case HandCategory.trips:
        return '三条（$t0）';
      case HandCategory.twoPair:
        return '两对（$t0 与 $t1）';
      case HandCategory.pair:
        return '一对（$t0）';
      case HandCategory.highCard:
        return '高牌（$t0）';
    }
    return '未知牌型';
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  /// 在 [rankMask] 中寻找最大的顺子高牌点数，找不到返回 -1。
  /// A2345（轮子）按 5 高处理，返回点数 3。
  static int _straightHigh(int rankMask) {
    for (int high = 12; high >= 4; high--) {
      final int need = 0x1F << (high - 4);
      if ((rankMask & need) == need) {
        return high;
      }
    }
    const int wheel = (1 << 12) | 0x0F; // A,2,3,4,5
    if ((rankMask & wheel) == wheel) {
      return 3;
    }
    return -1;
  }

  /// 找出除 [exclude1] / [exclude2] 之外最大的单张点数，没有则返回 0。
  static int _bestKicker(List<int> rankCount, int exclude1, int exclude2, int exclude3) {
    for (int r = 12; r >= 0; r--) {
      if (r == exclude1 || r == exclude2 || r == exclude3) {
        continue;
      }
      if (rankCount[r] > 0) {
        return r;
      }
    }
    return 0;
  }

  /// 把牌型与踢脚打包成可比较的整数评分。
  static int _pack(int category, int t0, int t1, int t2, int t3, int t4) {
    return (category << categoryShift) |
        ((t0 & 0xF) << 16) |
        ((t1 & 0xF) << 12) |
        ((t2 & 0xF) << 8) |
        ((t3 & 0xF) << 4) |
        (t4 & 0xF);
  }

  static String _rankText(int rank) {
    if (rank < 0 || rank >= Cards.rankLabels.length) {
      return '-';
    }
    return Cards.rankLabels[rank];
  }
}
