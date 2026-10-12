import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/equity_calculator.dart';
import '../lib/models/cards.dart';

int card(String text) {
  const Map<String, int> ranks = <String, int>{
    '2': 0, '3': 1, '4': 2, '5': 3, '6': 4, '7': 5, '8': 6, '9': 7,
    'T': 8, 'J': 9, 'Q': 10, 'K': 11, 'A': 12,
  };
  const Map<String, int> suits = <String, int>{
    's': 0, 'h': 1, 'd': 2, 'c': 3,
  };
  final String rank = text.substring(0, 1).toUpperCase();
  final String suit = text.substring(1, 2).toLowerCase();
  return Cards.make(ranks[rank]!, suits[suit]!);
}

List<int> cards(String text) =>
    text.split(' ').where((String part) => part.isNotEmpty).map(card).toList();

void main() {
  group('蒙特卡洛胜率计算器', () {
    test('翻牌前 AA 对阵随机牌的胜率约 85%', () {
      final EquityResult result = EquityCalculator.run(
        EquityInput(
          heroCard1: card('As'),
          heroCard2: card('Ah'),
          board: <int>[],
          villainCombos: <int>[], // 空 = 任意两张牌
          iterations: 20000,
          seed: 7,
        ),
      );
      expect(result.exact, isFalse);
      expect(result.winRate, greaterThan(0.78));
      expect(result.winRate, lessThan(0.92));
      expect(result.winRate + result.tieRate + result.loseRate, closeTo(1.0, 1e-9));
    });

    test('KK 对阵唯一范围 AA 时明显落后（验证范围过滤）', () {
      final List<int> aces = cards('As Ah Ad Ac');
      final List<int> aaCombos = <int>[];
      for (int i = 0; i < aces.length; i++) {
        for (int j = i + 1; j < aces.length; j++) {
          aaCombos.add(aces[i]);
          aaCombos.add(aces[j]);
        }
      }
      final EquityResult result = EquityCalculator.run(
        EquityInput(
          heroCard1: card('Ks'),
          heroCard2: card('Kh'),
          board: <int>[],
          villainCombos: aaCombos,
          iterations: 20000,
          seed: 11,
        ),
      );
      expect(result.equity, lessThan(0.30));
      expect(result.equity, greaterThan(0.05));
    });

    test('河牌圈四条 A 必胜，并且使用精确枚举', () {
      final EquityResult result = EquityCalculator.run(
        EquityInput(
          heroCard1: card('Ah'),
          heroCard2: card('Ad'),
          board: cards('As Ac Kh 2d 3c'),
          villainCombos: <int>[],
          seed: 3,
        ),
      );
      expect(result.exact, isTrue);
      expect(result.winRate, 1.0);
      expect(result.loseRate, 0.0);
    });

    test('转牌圈也是精确枚举，且牌型概率之和为 1', () {
      final EquityResult result = EquityCalculator.run(
        EquityInput(
          heroCard1: card('As'),
          heroCard2: card('Ks'),
          board: cards('Qs Js 9s 2h'),
          villainCombos: <int>[],
          seed: 5,
        ),
      );
      expect(result.exact, isTrue);
      expect(result.winRate, greaterThan(0.90));

      double sum = 0.0;
      for (final double probability in result.categoryProbability) {
        sum += probability;
      }
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('翻牌圈列出所有可能成型的牌型', () {
      final EquityResult result = EquityCalculator.run(
        EquityInput(
          heroCard1: card('As'),
          heroCard2: card('Ks'),
          board: cards('Qs 7s 2h'),
          villainCombos: <int>[],
          iterations: 5000,
          seed: 13,
        ),
      );
      // 同花听牌 + 卡顺听牌，至少能做成同花、顺子、两对等牌型。
      expect(result.achievableCategories.length, greaterThanOrEqualTo(5));
      // 黑桃同花一定在可能牌型里。
      expect(result.achievableCategories.contains(5), isTrue);
      expect(result.iterationsRun, greaterThan(0));
    });
  });
}
