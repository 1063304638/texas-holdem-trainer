// 游戏流程中的基础类型（纯 Dart，不依赖 Flutter）。

/// 下注轮次。
enum Street { preflop, flop, turn, river }

extension StreetText on Street {
  /// 中文名。
  String get cnName {
    switch (this) {
      case Street.preflop:
        return '翻牌前';
      case Street.flop:
        return '翻牌圈';
      case Street.turn:
        return '转牌圈';
      case Street.river:
        return '河牌圈';
    }
    return '未知';
  }

  /// 该轮次应有的公共牌数量。
  int get boardCount {
    switch (this) {
      case Street.preflop:
        return 0;
      case Street.flop:
        return 3;
      case Street.turn:
        return 4;
      case Street.river:
        return 5;
    }
    return 0;
  }

  /// 下一轮次（河牌圈之后仍是河牌圈）。
  Street get next {
    switch (this) {
      case Street.preflop:
        return Street.flop;
      case Street.flop:
        return Street.turn;
      case Street.turn:
        return Street.river;
      case Street.river:
        return Street.river;
    }
  }
}

/// 玩家可以执行的动作类型。
enum ActionType { fold, check, call, bet, raise, allIn }

extension ActionTypeText on ActionType {
  /// 中文名。
  String get cnName {
    switch (this) {
      case ActionType.fold:
        return '弃牌';
      case ActionType.check:
        return '过牌';
      case ActionType.call:
        return '跟注';
      case ActionType.bet:
        return '下注';
      case ActionType.raise:
        return '加注';
      case ActionType.allIn:
        return '全下';
    }
    return '未知';
  }
}
