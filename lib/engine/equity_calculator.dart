import 'dart:math';

import '../models/cards.dart';
import '../models/hand_analyzer.dart';
import '../models/hand_evaluator.dart';

/// 胜率计算模块的输入参数。
///
/// 之所以只使用 int / List<int> 这类原始类型，是为了能安全地通过
/// `compute()` 丢到后台 isolate 计算，完全不阻塞 UI 线程。
class EquityInput {
  EquityInput({
    required this.heroCard1,
    required this.heroCard2,
    required this.board,
    required this.villainCombos,
    this.iterations = 20000,
    this.seed = 20240501,
  });

  /// 我方第一张底牌。
  final int heroCard1;

  /// 我方第二张底牌。
  final int heroCard2;

  /// 已发出的公共牌（0~5 张）。
  final List<int> board;

  /// 对手范围的扁平化组合列表：[c1, c2, c1, c2, ...]。
  /// 传空列表表示"任意两张牌"（等价于 100% 范围）。
  final List<int> villainCombos;

  /// 蒙特卡洛迭代次数（公共牌已发完时会自动改用精确枚举）。
  final int iterations;

  /// 随机种子，保证同样的输入得到同样的输出，便于测试复现。
  final int seed;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'hero1': heroCard1,
      'hero2': heroCard2,
      'board': List<int>.of(board),
      'villain': List<int>.of(villainCombos),
      'iterations': iterations,
      'seed': seed,
    };
  }

  factory EquityInput.fromMap(Map<String, Object?> map) {
    return EquityInput(
      heroCard1: map['hero1'] as int,
      heroCard2: map['hero2'] as int,
      board: List<int>.from(map['board'] as List),
      villainCombos: List<int>.from(map['villain'] as List),
      iterations: map['iterations'] as int,
      seed: map['seed'] as int,
    );
  }
}

/// 胜率计算结果（同样只包含可跨 isolate 传递的类型）。
class EquityResult {
  EquityResult({
    required this.winRate,
    required this.tieRate,
    required this.loseRate,
    required this.categoryProbability,
    required this.achievableCategories,
    required this.iterationsRun,
    required this.exact,
    required this.elapsedMs,
  });

  /// 我方获胜概率 0..1。
  final double winRate;

  /// 平局（平分底池）概率 0..1。
  final double tieRate;

  /// 我方失败概率 0..1。
  final double loseRate;

  /// 我方最终牌型的概率分布，长度 9，下标对应 [HandCategory.index]。
  final List<double> categoryProbability;

  /// 所有可能做成的牌型（穷举得出，升序）。
  final List<int> achievableCategories;

  /// 实际进行的模拟次数（精确枚举时为枚举次数）。
  final int iterationsRun;

  /// 是否为精确枚举（河牌圈、转牌圈会走精确枚举）。
  final bool exact;

  /// 计算耗时（毫秒）。
  final double elapsedMs;

  /// 常用于决策的"底池权益"：胜率 + 平局的一半。
  double get equity => winRate + tieRate / 2.0;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'win': winRate,
      'tie': tieRate,
      'lose': loseRate,
      'cat': List<double>.of(categoryProbability),
      'achievable': List<int>.of(achievableCategories),
      'iterations': iterationsRun,
      'exact': exact,
      'elapsed': elapsedMs,
    };
  }

  factory EquityResult.fromMap(Map<String, Object?> map) {
    return EquityResult(
      winRate: (map['win'] as num).toDouble(),
      tieRate: (map['tie'] as num).toDouble(),
      loseRate: (map['lose'] as num).toDouble(),
      categoryProbability: List<double>.from(map['cat'] as List),
      achievableCategories: List<int>.from(map['achievable'] as List),
      iterationsRun: map['iterations'] as int,
      exact: map['exact'] as bool,
      elapsedMs: (map['elapsed'] as num).toDouble(),
    );
  }
}

/// 顶层入口函数，供 `compute()` 在后台 isolate 中调用。
Map<String, Object?> equityIsolateEntry(Map<String, Object?> payload) {
  final EquityInput input = EquityInput.fromMap(payload);
  return EquityCalculator.run(input).toMap();
}

/// 蒙特卡洛胜率计算器。
///
/// 算法说明：
///  1. 从对手范围里等概率抽取一手底牌（范围外的组合已被剔除）；
///  2. 从剩余牌堆里随机补完公共牌（无放回抽样，使用 Fisher-Yates 交换实现）；
///  3. 用 [HandEvaluator] 比较双方 7 张牌的最优 5 张，累计胜负平；
///  4. 河牌圈 / 转牌圈改用**精确枚举**（把对手范围与剩余公共牌全部跑一遍），
///     因为这两种情况的总组合数很小，可以得到精确值而不是估计值。
///
/// 该计算过程与 UI 完全解耦，只依赖 dart:math 与纯 Dart 的模型层。
class EquityCalculator {
  EquityCalculator._();

  /// 精确枚举的组合上限，超过则退回蒙特卡洛。
  static const int exactEnumerationCap = 400000;

  /// 根据公共牌数量推荐迭代次数（兼顾精度与速度）。
  static int recommendedIterations(int boardCount) {
    if (boardCount >= 4) {
      return 0; // 走精确枚举
    }
    if (boardCount == 3) {
      return 20000;
    }
    return 25000; // 翻牌前
  }

  /// 执行一次胜率计算（同步、纯计算，可在任意 isolate 中调用）。
  static EquityResult run(EquityInput input) {
    final Stopwatch stopwatch = Stopwatch()..start();

    final List<int> board = List<int>.of(input.board);
    final int heroCard1 = input.heroCard1;
    final int heroCard2 = input.heroCard2;

    // 已知牌：我方底牌 + 公共牌（对手底牌对"我方视角"是未知的，所以不能算进来）。
    final Set<int> known = <int>{heroCard1, heroCard2};
    for (int i = 0; i < board.length; i++) {
      known.add(board[i]);
    }

    // 剩余牌堆。
    final List<int> deck = <int>[];
    for (int card = 0; card < Cards.deckSize; card++) {
      if (!known.contains(card)) {
        deck.add(card);
      }
    }

    // 对手范围：剔除与已知牌冲突的组合；范围为空时退化为"任意两张牌"。
    List<int> combos = _filterCombos(input.villainCombos, known);
    if (combos.isEmpty) {
      combos = _allCombos(deck);
    }
    final int comboCount = combos.length ~/ 2;

    int heroWins = 0;
    int ties = 0;
    int villainWins = 0;
    final List<int> categoryCounts = List<int>.filled(9, 0);

    // 复用同一份 7 张牌缓冲区，避免在热循环里反复分配。
    final List<int> heroSeven = List<int>.filled(7, 0);
    final List<int> villainSeven = List<int>.filled(7, 0);
    heroSeven[0] = heroCard1;
    heroSeven[1] = heroCard2;
    for (int i = 0; i < board.length; i++) {
      heroSeven[2 + i] = board[i];
      villainSeven[2 + i] = board[i];
    }

    void tally() {
      final int heroScore = HandEvaluator.evaluate(heroSeven);
      final int villainScore = HandEvaluator.evaluate(villainSeven);
      categoryCounts[HandEvaluator.categoryOf(heroScore)]++;
      if (heroScore > villainScore) {
        heroWins++;
      } else if (heroScore < villainScore) {
        villainWins++;
      } else {
        ties++;
      }
    }

    final int missingBoardCards = 5 - board.length;
    final int exactIterations =
        comboCount * (missingBoardCards == 0 ? 1 : _powInt(deck.length, missingBoardCards));
    final bool useExact = missingBoardCards <= 1 && exactIterations <= exactEnumerationCap;

    if (useExact) {
      // ---- 精确枚举：河牌圈（0 张待发）与转牌圈（1 张待发） ----
      for (int i = 0; i < combos.length; i += 2) {
        final int v1 = combos[i];
        final int v2 = combos[i + 1];
        villainSeven[0] = v1;
        villainSeven[1] = v2;
        if (missingBoardCards == 0) {
          tally();
        } else {
          for (int d = 0; d < deck.length; d++) {
            final int card = deck[d];
            if (card == v1 || card == v2) {
              continue;
            }
            heroSeven[6] = card;
            villainSeven[6] = card;
            tally();
          }
        }
      }
    } else {
      // ---- 蒙特卡洛模拟 ----
      // buffer 始终是剩余牌堆的一个排列，配合移动的下标即可做到无放回抽样。
      final List<int> buffer = List<int>.of(deck);
      final Random random = Random(input.seed);
      final int iterations = input.iterations > 0 ? input.iterations : 20000;
      for (int iter = 0; iter < iterations; iter++) {
        int cursor = 0;
        final int pick = random.nextInt(comboCount) * 2;
        final int v1 = combos[pick];
        final int v2 = combos[pick + 1];
        villainSeven[0] = v1;
        villainSeven[1] = v2;
        for (int i = board.length; i < 5; i++) {
          int card;
          do {
            card = _draw(buffer, cursor, random);
            cursor++;
          } while (card == v1 || card == v2);
          heroSeven[2 + i] = card;
          villainSeven[2 + i] = card;
        }
        tally();
      }
    }

    final int total = heroWins + villainWins + ties;
    final double denominator = total == 0 ? 1.0 : total.toDouble();
    final List<double> categoryProbability = List<double>.generate(
      9,
      (int index) => categoryCounts[index] / denominator,
    );

    // 可能做成的牌型（穷举我方后续公共牌，与对手范围无关）。
    final List<HandCategory> achievable = HandAnalyzer.achievableCategories(
      <int>[heroCard1, heroCard2],
      board,
    );

    stopwatch.stop();
    return EquityResult(
      winRate: heroWins / denominator,
      tieRate: ties / denominator,
      loseRate: villainWins / denominator,
      categoryProbability: categoryProbability,
      achievableCategories: achievable.map((HandCategory c) => c.index).toList(),
      iterationsRun: total,
      exact: useExact,
      elapsedMs: stopwatch.elapsedMicroseconds / 1000.0,
    );
  }

  /// 从缓冲区中无放回地抽出一张牌。
  ///
  /// buffer 始终是"尚未抽出的牌"的一个排列，因此把 cursor 位置与
  /// [cursor, end) 中的随机位置交换后返回 cursor 位置，等价于均匀无放回抽样。
  static int _draw(List<int> buffer, int cursor, Random random) {
    final int remaining = buffer.length - cursor;
    final int offset = remaining <= 0 ? 0 : random.nextInt(remaining);
    final int index = cursor + offset;
    final int card = buffer[index];
    buffer[index] = buffer[cursor];
    buffer[cursor] = card;
    return card;
  }

  /// 剔除与已知牌冲突的对手组合。
  static List<int> _filterCombos(List<int> combos, Set<int> known) {
    final List<int> result = <int>[];
    for (int i = 0; i + 1 < combos.length; i += 2) {
      final int a = combos[i];
      final int b = combos[i + 1];
      if (a == b) {
        continue;
      }
      if (known.contains(a) || known.contains(b)) {
        continue;
      }
      result.add(a);
      result.add(b);
    }
    return result;
  }

  /// 生成"任意两张牌"的全部组合。
  static List<int> _allCombos(List<int> deck) {
    final List<int> result = <int>[];
    for (int i = 0; i < deck.length; i++) {
      for (int j = i + 1; j < deck.length; j++) {
        result.add(deck[i]);
        result.add(deck[j]);
      }
    }
    return result;
  }

  static int _powInt(int base, int exponent) {
    int value = 1;
    for (int i = 0; i < exponent; i++) {
      value *= base;
    }
    return value;
  }
}
