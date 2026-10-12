import 'package:flutter_test/flutter_test.dart';

import '../lib/models/cards.dart';
import '../lib/models/hand_analyzer.dart';
import '../lib/models/hand_evaluator.dart';

/// 把 "As Kh" 这样的文本转成牌的整数编码，方便写测试。
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
  group('牌力评估器', () {
    test('皇家同花顺被识别为同花顺', () {
      final int score = HandEvaluator.evaluate(cards('As Ks Qs Js Ts'));
      expect(HandEvaluator.categoryOf(score), HandCategory.straightFlush.index);
      expect(HandEvaluator.describe(score), '皇家同花顺');
    });

    test('7 张牌里取最优的 5 张', () {
      final int score = HandEvaluator.evaluate(cards('As Ks Qs Js Ts 2h 3d'));
      expect(HandEvaluator.categoryOf(score), HandCategory.straightFlush.index);
    });

    test('A2345 按 5 高顺子处理，且小于 6 高顺子', () {
      final int wheel = HandEvaluator.evaluate(cards('As 2h 3d 4c 5s'));
      final int sixHigh = HandEvaluator.evaluate(cards('2h 3d 4c 5s 6h'));
      expect(HandEvaluator.categoryOf(wheel), HandCategory.straight.index);
      expect(wheel < sixHigh, isTrue);
    });

    test('牌型大小顺序：葫芦 > 同花 > 顺子 > 三条 > 两对 > 一对 > 高牌', () {
      final int fullHouse = HandEvaluator.evaluate(cards('9h 9d 9c 5s 5h'));
      final int flush = HandEvaluator.evaluate(cards('Ah Kh 9h 5h 2h'));
      final int straight = HandEvaluator.evaluate(cards('9h 8d 7c 6s 5h'));
      final int trips = HandEvaluator.evaluate(cards('9h 9d 9c Ks 5h'));
      final int twoPair = HandEvaluator.evaluate(cards('9h 9d 5c 5s Kh'));
      final int pair = HandEvaluator.evaluate(cards('9h 9d Ac Ks 5h'));
      final int highCard = HandEvaluator.evaluate(cards('Ah Kd 9c 7s 5h'));

      expect(fullHouse > flush, isTrue);
      expect(flush > straight, isTrue);
      expect(straight > trips, isTrue);
      expect(trips > twoPair, isTrue);
      expect(twoPair > pair, isTrue);
      expect(pair > highCard, isTrue);
    });

    test('踢脚（kicker）参与比较', () {
      final int aceKing = HandEvaluator.evaluate(cards('As Ah Kd 9c 4h'));
      final int aceQueen = HandEvaluator.evaluate(cards('Ac Ad Qd 9s 4c'));
      expect(aceKing > aceQueen, isTrue);
    });

    test('A 高同花大于 K 高同花', () {
      final int aceHigh = HandEvaluator.evaluate(cards('As 9s 7s 5s 3s'));
      final int kingHigh = HandEvaluator.evaluate(cards('Ks 9s 7s 5s 3s'));
      expect(aceHigh > kingHigh, isTrue);
    });
  });

  group('局面分析', () {
    test('翻牌前返回全部 9 种可能牌型', () {
      final List<HandCategory> achievable =
          HandAnalyzer.achievableCategories(cards('As Kh'), <int>[]);
      expect(achievable.length, 9);
    });

    test('河牌圈只剩当前这一种牌型', () {
      final List<HandCategory> achievable = HandAnalyzer.achievableCategories(
        cards('As Kh'),
        cards('Qs Js Ts 2d 3c'),
      );
      expect(achievable.length, 1);
      expect(achievable.first, HandCategory.straight);
    });

    test('同花听牌能被识别出来', () {
      final HandInsight insight =
          HandAnalyzer.analyze(cards('As Ks'), cards('Qs 7s 2h'));
      // 黑桃已看到 4 张：As Ks Qs 7s，因此是同花听牌（剩余 9 张黑桃）。
      expect(insight.tags.any((String tag) => tag.contains('同花听牌')), isTrue);
      expect(insight.tags.any((String tag) => tag.contains('9 张补牌')), isTrue);
    });
  });
}
