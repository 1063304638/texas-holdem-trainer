import 'dart:math';

import '../engine/game_types.dart';

/// 电脑做决策时需要的局面信息（从控制器里打包出来，便于单独测试）。
class AiContext {
  const AiContext({
    required this.street,
    required this.pot,
    required this.toCall,
    required this.myStack,
    required this.myCommitted,
    required this.bigBlind,
    required this.minRaiseTo,
    required this.maxRaiseTo,
    this.opponentAllIn = false,
  });

  /// 当前轮次。
  final Street street;

  /// 当前底池（含双方本手已投入的全部筹码）。
  final int pot;

  /// 需要跟注的筹码量，0 表示可以过牌。
  final int toCall;

  /// 我方剩余筹码。
  final int myStack;

  /// 我方本街已投入的筹码。
  final int myCommitted;

  /// 大盲注大小（用于最小下注额）。
  final int bigBlind;

  /// 合法的最小加注到（raise-to）金额。
  final int minRaiseTo;

  /// 合法的最大加注到金额（即全下）。
  final int maxRaiseTo;

  /// 对手是否已经全下（此时加注没有意义，只能跟注或弃牌）。
  final bool opponentAllIn;

  /// 是否可以过牌。
  bool get canCheck => toCall == 0;

  /// 是否还有筹码可以加注（对手全下时不再允许加注）。
  bool get canRaise => myStack > toCall && !opponentAllIn;

  /// 跟注后还要再投入的总额（用于底池赔率）。
  double get potOdds => toCall == 0 ? 0.0 : toCall / (pot + toCall);
}

/// 电脑的决策结果。
class AiDecision {
  const AiDecision(this.action, this.amount, this.reason);

  /// 动作类型。
  final ActionType action;

  /// 目标金额（对 bet / raise 而言是"加注到"的总额，其它动作为 0）。
  final int amount;

  /// 决策理由，会写进操作日志，方便复盘学习。
  final String reason;

  String get description {
    switch (action) {
      case ActionType.bet:
        return '下注 $amount（$reason）';
      case ActionType.raise:
        return '加注到 $amount（$reason）';
      case ActionType.allIn:
        return '全下 $amount（$reason）';
      case ActionType.call:
        return '跟注（$reason）';
      case ActionType.check:
        return '过牌（$reason）';
      case ActionType.fold:
        return '弃牌（$reason）';
    }
    return '$reason';
  }
}

/// 电脑对手的决策模型。
///
/// 逻辑是"底池赔率 + 权益阈值 + 少量随机性"的简化版本：
///  * 胜率明显高于底池赔率 → 跟注/加注；
///  * 胜率极高 → 主动做大底池；
///  * 胜率极低 → 弃牌，但有很低概率进行诈唬（让训练更有对抗性）。
class AiPlayer {
  AiPlayer({int? seed, double aggression = 1.0})
      : _random = Random(seed),
        _aggression = aggression;

  final Random _random;

  /// 激进度：>1 更爱加注，<1 更保守。
  final double _aggression;

  /// 根据估算胜率 [equity]（0..1，已包含平局的一半权益）做出决策。
  AiDecision decide(AiContext context, double equity) {
    final double baseEquity = equity < 0.0 ? 0.0 : (equity > 1.0 ? 1.0 : equity);
    // 加入少量随机扰动，避免电脑的行为被完全算死。
    final double jitter = (_random.nextDouble() - 0.5) * 0.10 * _aggression;
    double adjusted = baseEquity + jitter;
    if (adjusted < 0.0) {
      adjusted = 0.0;
    }
    if (adjusted > 1.0) {
      adjusted = 1.0;
    }

    final double potOdds = context.potOdds;

    // 1) 极强牌：尽量做大底池。
    if (adjusted >= 0.86 && context.canRaise) {
      final int target = _raiseTarget(context, 1.0);
      return AiDecision(
        target >= context.maxRaiseTo
            ? ActionType.allIn
            : (context.toCall == 0 ? ActionType.bet : ActionType.raise),
        target,
        '牌力极强（估算胜率 ${_percent(adjusted)}）',
      );
    }

    // 2) 强牌：主动加注拿价值。
    if (adjusted >= 0.72 && context.canRaise) {
      final int target = _raiseTarget(context, 0.7);
      return AiDecision(
        target >= context.maxRaiseTo
            ? ActionType.allIn
            : (context.toCall == 0 ? ActionType.bet : ActionType.raise),
        target,
        '牌力领先（估算胜率 ${_percent(adjusted)}）',
      );
    }

    // 3) 无人下注时：过牌，偶尔诈唬。
    if (context.canCheck) {
      final bool bluff = adjusted < 0.40 &&
          context.canRaise &&
          context.pot >= context.bigBlind * 2 &&
          _random.nextDouble() < 0.12 * _aggression;
      if (bluff) {
        final int target = _raiseTarget(context, 0.5);
        if (target > context.myCommitted) {
          return AiDecision(
            target >= context.maxRaiseTo ? ActionType.allIn : ActionType.bet,
            target,
            '诈唬下注（估算胜率仅 ${_percent(adjusted)}）',
          );
        }
      }
      return const AiDecision(ActionType.check, 0, '过牌观望');
    }

    // 4) 面对下注：胜率高于底池赔率时跟注，明显领先时加注施压。
    final bool raiseForValue = context.canRaise &&
        adjusted >= potOdds + 0.08 &&
        adjusted > 0.55 &&
        _random.nextDouble() < 0.35 * _aggression;
    if (raiseForValue) {
      final int target = _raiseTarget(context, 0.8);
      return AiDecision(
        target >= context.maxRaiseTo ? ActionType.allIn : ActionType.raise,
        target,
        '胜率 ${_percent(adjusted)} 高于底池赔率 ${_percent(potOdds)}，加注施压',
      );
    }

    if (adjusted >= potOdds + 0.02) {
      return AiDecision(
        ActionType.call,
        0,
        '胜率 ${_percent(adjusted)} ≥ 底池赔率 ${_percent(potOdds)}',
      );
    }

    // 5) 很便宜跟注时偶尔看牌（增加缠打，避免电脑过于可预测）。
    if (context.toCall <= context.myStack * 0.04 && _random.nextDouble() < 0.5) {
      return const AiDecision(ActionType.call, 0, '小额跟注看牌');
    }

    return AiDecision(
      ActionType.fold,
      0,
      '胜率 ${_percent(adjusted)} 低于底池赔率 ${_percent(potOdds)}',
    );
  }

  /// 计算加注到的总额：先补齐跟注，再按底池比例加注，并夹在合法区间内。
  int _raiseTarget(AiContext context, double potFraction) {
    final int callLevel = context.myCommitted + context.toCall;
    final int potAfterCall = context.pot + context.toCall;
    int target = callLevel + (potAfterCall * potFraction).round();
    if (target < context.minRaiseTo) {
      target = context.minRaiseTo;
    }
    if (target > context.maxRaiseTo) {
      target = context.maxRaiseTo;
    }
    return target;
  }

  static String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
}
