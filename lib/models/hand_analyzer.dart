import 'cards.dart';
import 'hand_evaluator.dart';

/// 补牌统计：某种牌型可以由多少张牌补成。
class OutBreakdown {
  const OutBreakdown(this.category, this.outs);

  final HandCategory category;
  final int outs;
}

/// 对"我方底牌 + 当前公共牌"的确定性分析结果。
///
/// 这里的结论全部由穷举得出（不依赖随机模拟），因此可以稳定展示：
///  * 已经做成的牌型；
///  * 所有**有可能**做成的牌型清单；
///  * 下一张牌能带来哪些提升（补牌数）与听牌标签。
class HandInsight {
  HandInsight({
    required this.madeScore,
    required this.madeCategory,
    required this.achievableCategories,
    required this.outs,
    required this.tags,
    required this.totalOuts,
    required this.unseenCount,
  });

  /// 当前已成牌型的评分。
  final int madeScore;

  /// 当前已成牌型。
  final HandCategory madeCategory;

  /// 所有可能做成的牌型（升序）。
  final List<HandCategory> achievableCategories;

  /// 单张补牌可以提升到的牌型统计（按补牌数从多到少）。
  final List<OutBreakdown> outs;

  /// 听牌标签，例如 "同花听牌（9 张补牌）"。
  final List<String> tags;

  /// 补牌总数（仅统计"牌型升级"，不含踢脚提升）。
  final int totalOuts;

  /// 未知牌数量（用于展示"还剩多少张没看到"）。
  final int unseenCount;
}

/// 牌面分析工具（纯 Dart，可在 isolate 中调用）。
class HandAnalyzer {
  HandAnalyzer._();

  /// 列出当前局面下所有可能做成的牌型。
  ///
  /// 做法是对"后续公共牌"做穷举：
  ///  * 翻牌圈：C(47,2) = 1081 种；
  ///  * 转牌圈：47 种；
  ///  * 河牌圈：已经确定，只有 1 种；
  ///  * 翻牌前：需要补 5 张公共牌（C(50,5) 太大），直接返回全部 9 种牌型
  ///    （任意两张底牌理论上都能做成所有牌型）。
  static List<HandCategory> achievableCategories(List<int> hole, List<int> board) {
    final int need = 5 - board.length;
    final Set<HandCategory> result = <HandCategory>{};

    if (need >= 3) {
      for (final HandCategory category in HandCategory.values) {
        result.add(category);
      }
    } else {
      final List<int> known = <int>[];
      known.addAll(hole);
      known.addAll(board);
      final List<int> unseen = _unseenCards(known);

      if (need <= 0) {
        result.add(HandCategory.values[HandEvaluator.categoryOf(HandEvaluator.evaluate(known))]);
      } else if (need == 1) {
        for (int i = 0; i < unseen.length; i++) {
          final List<int> seven = <int>[];
          seven.addAll(known);
          seven.add(unseen[i]);
          result.add(HandCategory.values[HandEvaluator.categoryOf(HandEvaluator.evaluate(seven))]);
        }
      } else {
        for (int i = 0; i < unseen.length; i++) {
          for (int j = i + 1; j < unseen.length; j++) {
            final List<int> seven = <int>[];
            seven.addAll(known);
            seven.add(unseen[i]);
            seven.add(unseen[j]);
            result.add(HandCategory.values[HandEvaluator.categoryOf(HandEvaluator.evaluate(seven))]);
          }
        }
      }
    }

    final List<HandCategory> list = result.toList();
    list.sort((HandCategory a, HandCategory b) => a.index.compareTo(b.index));
    return list;
  }

  /// 分析当前局面：已成牌型、补牌、听牌标签、可能牌型。
  static HandInsight analyze(List<int> hole, List<int> board) {
    final List<int> known = <int>[];
    known.addAll(hole);
    known.addAll(board);

    final int madeScore = HandEvaluator.evaluate(known);
    final HandCategory madeCategory =
        HandCategory.values[HandEvaluator.categoryOf(madeScore)];
    final List<int> unseen = _unseenCards(known);

    // 单张补牌能提升到哪些牌型（只统计"牌型升级"，踢脚提升不算）。
    final List<int> outsByCategory = List<int>.filled(9, 0);
    if (board.length < 5) {
      for (int i = 0; i < unseen.length; i++) {
        final List<int> next = <int>[];
        next.addAll(known);
        next.add(unseen[i]);
        final HandCategory category =
            HandCategory.values[HandEvaluator.categoryOf(HandEvaluator.evaluate(next))];
        if (category.index > madeCategory.index) {
          outsByCategory[category.index]++;
        }
      }
    }

    final List<OutBreakdown> outs = <OutBreakdown>[];
    int totalOuts = 0;
    for (int i = 8; i >= 0; i--) {
      if (outsByCategory[i] > 0) {
        outs.add(OutBreakdown(HandCategory.values[i], outsByCategory[i]));
        totalOuts += outsByCategory[i];
      }
    }
    outs.sort((OutBreakdown a, OutBreakdown b) => b.outs.compareTo(a.outs));

    return HandInsight(
      madeScore: madeScore,
      madeCategory: madeCategory,
      achievableCategories: achievableCategories(hole, board),
      outs: outs,
      tags: _drawTags(known, unseen, board),
      totalOuts: totalOuts,
      unseenCount: unseen.length,
    );
  }

  /// 生成听牌标签。
  static List<String> _drawTags(List<int> known, List<int> unseen, List<int> board) {
    final List<String> tags = <String>[];
    if (board.length >= 5) {
      return tags;
    }

    // 同花听牌：某一门花色已经看到 4 张。
    final List<int> suitCount = List<int>.filled(4, 0);
    for (int i = 0; i < known.length; i++) {
      suitCount[Cards.suitOf(known[i])]++;
    }
    for (int s = 0; s < 4; s++) {
      if (suitCount[s] == 4) {
        int live = 0;
        for (int r = 0; r < 13; r++) {
          final int card = Cards.make(r, s);
          if (!known.contains(card)) {
            live++;
          }
        }
        tags.add('同花听牌（${live} 张补牌）');
      }
    }

    // 顺子听牌：统计有多少个**不同点数**可以补成顺子（或同花顺）。
    final Set<int> completingRanks = <int>{};
    for (int i = 0; i < unseen.length; i++) {
      final List<int> next = <int>[];
      next.addAll(known);
      next.add(unseen[i]);
      final int category = HandEvaluator.categoryOf(HandEvaluator.evaluate(next));
      if (category == HandCategory.straight.index ||
          category == HandCategory.straightFlush.index) {
        completingRanks.add(Cards.rankOf(unseen[i]));
      }
    }
    if (completingRanks.length >= 2) {
      tags.add('顺子听牌（${completingRanks.length} 种点数可成顺）');
    } else if (completingRanks.length == 1) {
      tags.add('卡顺听牌（仅 1 种点数可成顺）');
    }

    return tags;
  }

  /// 计算"未知牌"：52 张里去掉已知的底牌与公共牌。
  static List<int> _unseenCards(List<int> known) {
    final List<int> result = <int>[];
    for (int card = 0; card < Cards.deckSize; card++) {
      if (!known.contains(card)) {
        result.add(card);
      }
    }
    return result;
  }
}
