import '../models/cards.dart';

/// 对手范围的风格档位（仅用于展示与默认百分比）。
enum RangeStyle { veryTight, tight, normal, loose, anyTwo }

extension RangeStyleText on RangeStyle {
  String get cnName {
    switch (this) {
      case RangeStyle.veryTight:
        return '极紧';
      case RangeStyle.tight:
        return '紧凶';
      case RangeStyle.normal:
        return '常规';
      case RangeStyle.loose:
        return '松散';
      case RangeStyle.anyTwo:
        return '任意两张';
    }
    return '未知';
  }

  /// 该风格对应的范围百分比（占全部起手组合的比例）。
  double get percent {
    switch (this) {
      case RangeStyle.veryTight:
        return 8;
      case RangeStyle.tight:
        return 15;
      case RangeStyle.normal:
        return 25;
      case RangeStyle.loose:
        return 40;
      case RangeStyle.anyTwo:
        return 100;
    }
    return 50;
  }
}

/// 起手牌范围模型（启发式实现）。
///
/// 采用扑克圈常用的 **Chen 公式** 给全部 1326 个起手组合打分，
/// 再按分数从高到低取最强的 [percent]%。这样：
///  * 无需手工维护 169 个起手牌类别的表格，代码短小、易于检查；
///  * 范围的紧松程度用一个百分比就能表达，方便随着对手的动作动态收紧。
///
/// 注意：这是一个工程近似（用于估算胜率足够），并非 GTO 范围表。
class HandRange {
  HandRange._();

  /// 返回范围内的所有组合，扁平存放：[c1, c2, c1, c2, ...]。
  ///
  /// [deadCards] 是必须排除的已知牌（例如我方底牌与公共牌）。
  static List<int> combos(double percent, List<int> deadCards) {
    final Set<int> dead = deadCards.toSet();
    final List<int> cards = <int>[];
    for (int card = 0; card < Cards.deckSize; card++) {
      if (!dead.contains(card)) {
        cards.add(card);
      }
    }

    final List<_Combo> all = <_Combo>[];
    for (int i = 0; i < cards.length; i++) {
      for (int j = i + 1; j < cards.length; j++) {
        final int a = cards[i];
        final int b = cards[j];
        all.add(_Combo(a, b, chenScore(a, b)));
      }
    }

    all.sort((_Combo x, _Combo y) {
      final int byScore = y.score.compareTo(x.score);
      if (byScore != 0) {
        return byScore;
      }
      // 分数相同时用牌面编码做稳定的次序，保证结果可复现。
      return (x.a * 52 + x.b).compareTo(y.a * 52 + y.b);
    });

    final double clamped = percent < 1.0 ? 1.0 : (percent > 100.0 ? 100.0 : percent);
    int take = (all.length * clamped / 100.0).round();
    if (take < 1) {
      take = 1;
    }
    if (take > all.length) {
      take = all.length;
    }

    final List<int> result = <int>[];
    for (int i = 0; i < take; i++) {
      result.add(all[i].a);
      result.add(all[i].b);
    }
    return result;
  }

  /// Chen 公式评分（分数越高代表起手牌越强）。
  static double chenScore(int cardA, int cardB) {
    final int rankA = Cards.rankOf(cardA);
    final int rankB = Cards.rankOf(cardB);
    final bool suited = Cards.suitOf(cardA) == Cards.suitOf(cardB);
    final int high = rankA > rankB ? rankA : rankB;
    final int low = rankA > rankB ? rankB : rankA;

    double score;
    if (high == 12) {
      score = 10; // A
    } else if (high == 11) {
      score = 8; // K
    } else if (high == 10) {
      score = 7; // Q
    } else if (high == 9) {
      score = 6; // J
    } else {
      score = (high + 2) / 2.0; // 按点数一半计分
    }

    if (high == low) {
      // 对子：分数翻倍，最低 5。
      score = score * 2;
      return score < 5.0 ? 5.0 : score;
    }

    if (suited) {
      score += 2;
    }

    final int gap = high - low - 1;
    if (gap == 1) {
      score -= 1;
    } else if (gap == 2) {
      score -= 2;
    } else if (gap == 3) {
      score -= 4;
    } else if (gap >= 4) {
      score -= 5;
    }

    // 两张都比 Q 小且相连（或隔一张）时额外 +1。
    if (gap <= 1 && high < 10) {
      score += 1;
    }

    return score;
  }

  /// 把百分比翻译成人类可读的描述，例如 "约 25% 起手牌（常规）"。
  static String describePercent(double percent) {
    final String rounded = percent.toStringAsFixed(0);
    return '约 $rounded% 起手牌（${styleOf(percent).cnName}）';
  }

  /// 按百分比找最接近的风格档位。
  static RangeStyle styleOf(double percent) {
    RangeStyle best = RangeStyle.normal;
    double bestDistance = double.infinity;
    for (final RangeStyle style in RangeStyle.values) {
      final double distance = (style.percent - percent).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = style;
      }
    }
    return best;
  }
}

class _Combo {
  const _Combo(this.a, this.b, this.score);

  final int a;
  final int b;
  final double score;
}
