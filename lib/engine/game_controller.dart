import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../ai/ai_player.dart';
import '../models/cards.dart';
import '../models/hand_analyzer.dart';
import '../models/hand_evaluator.dart';
import 'equity_calculator.dart';
import 'game_types.dart';
import 'hand_range.dart';

/// 游戏主控制器（单机人机对战）。
///
/// 职责划分：
///  * **规则引擎**：发牌、盲注、下注轮转、加注合法性、摊牌结算；
///  * **异步调度**：把蒙特卡洛胜率计算通过 `compute()` 丢到后台 isolate，
///    并把需要 AI 行动的时刻暴露成 [needsAiAction] 供界面触发；
///  * **状态广播**：继承 [ChangeNotifier]，界面用 AnimatedBuilder 监听重绘。
///
/// 与 UI 完全解耦：本文件不 import 任何 material/widget 代码。
class GameController extends ChangeNotifier {
  GameController({
    int startingStack = 1000,
    this.smallBlind = 10,
    this.bigBlind = 20,
  })  : _startingStack = startingStack,
        _ai = AiPlayer(seed: DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF);

  /// 每手开始时的筹码量。
  final int _startingStack;

  /// 小盲注。
  final int smallBlind;

  /// 大盲注。
  final int bigBlind;

  final AiPlayer _ai;
  final Random _random = Random();

  List<int> _deck = <int>[];

  /// 我方底牌。
  List<int> heroCards = <int>[];

  /// 电脑底牌（摊牌前界面不展示）。
  List<int> aiCards = <int>[];

  /// 公共牌。
  List<int> board = <int>[];

  /// 我方剩余筹码。
  int heroStack = 0;

  /// 电脑剩余筹码。
  int aiStack = 0;

  /// 当前轮次。
  Street street = Street.preflop;

  /// 已经进行到第几手。
  int handNumber = 0;

  /// 本街双方已投入的筹码。
  int heroCommitted = 0;
  int aiCommitted = 0;

  /// 本手双方已投入的筹码（用于底池与结算）。
  int heroTotalCommitted = 0;
  int aiTotalCommitted = 0;

  /// 我方是否弃牌 / 电脑是否弃牌。
  bool heroFolded = false;
  bool aiFolded = false;

  /// 我方是否已全下 / 电脑是否已全下。
  bool heroAllIn = false;
  bool aiAllIn = false;

  /// 本手是否已经结束。
  bool handOver = false;

  /// 是否公开电脑底牌（摊牌时才会亮牌）。
  bool revealAiCards = false;

  /// 本手结果描述。
  String handResult = '';

  /// 电脑正在思考中。
  bool aiThinking = false;

  /// 当前底池。
  int get pot => heroTotalCommitted + aiTotalCommitted;

  /// 当前每手最大下注额（本街）。
  int currentBet = 0;

  /// 最近一次加注的幅度（用于计算最小加注）。
  int lastRaiseSize = 0;

  /// 本手按钮位是否在我方（单挑时按钮位 = 小盲位）。
  bool buttonIsHero = true;

  /// 最近一次胜率计算结果。
  EquityResult? equity;

  /// 胜率是否正在后台计算。
  bool equityLoading = false;

  /// 当前局面的确定性分析（已成牌型 / 补牌 / 听牌 / 可能牌型）。
  HandInsight? insight;

  /// 界面展示用的操作日志（最新的在前）。
  final List<String> logs = <String>[];

  /// 我方视角下对"电脑起手牌范围"的估计（百分比）。
  double aiRangePercent = 45;

  /// 电脑视角下对"我方起手牌范围"的估计（百分比）。
  double heroRangePercent = 60;

  bool _heroActed = false;
  bool _aiActed = false;
  bool _heroToAct = false;
  bool _runOutInProgress = false;
  bool _disposed = false;
  int _equityToken = 0;

  /// 每开一手 +1，用于丢弃"上一手"遗留的异步任务结果。
  int _handToken = 0;

  // ---------------------------------------------------------------------------
  // 对外只读状态
  // ---------------------------------------------------------------------------

  /// 是否轮到我方行动。
  bool get isHeroTurn => !handOver && _heroToAct && !_runOutInProgress;

  /// 是否需要界面去触发电脑行动（界面监听本字段来调度 [playAiTurn]）。
  bool get needsAiAction =>
      !handOver && !_heroToAct && !aiThinking && !_runOutInProgress;

  /// 我方需要跟注的筹码量（0 表示可以过牌）。
  int get toCall {
    final int need = aiCommitted - heroCommitted;
    return need > 0 ? need : 0;
  }

  /// 电脑需要跟注的筹码量。
  int get aiToCall {
    final int need = heroCommitted - aiCommitted;
    return need > 0 ? need : 0;
  }

  bool get canFold => isHeroTurn;
  bool get canCheck => isHeroTurn && toCall == 0;
  bool get canCall => isHeroTurn && toCall > 0;

  /// 是否可以加注：对手已经全下时只能跟注 / 弃牌（加注也没有人跟）。
  bool get canRaise => isHeroTurn && heroStack > toCall && !aiAllIn;

  /// 我方全下的目标金额。
  int get heroAllInTo => heroStack + heroCommitted;

  /// 合法的最小"加注到"金额。
  int get minRaiseTo => _minRaiseTo(heroStack, heroCommitted);

  /// 合法的最大"加注到"金额（全下）。
  int get maxRaiseTo => heroStack + heroCommitted;

  /// 电脑合法的最小"加注到"金额。
  int get aiMinRaiseTo => _minRaiseTo(aiStack, aiCommitted);

  /// 电脑合法的最大"加注到"金额。
  int get aiMaxRaiseTo => aiStack + aiCommitted;

  // ---------------------------------------------------------------------------
  // 开局 / 开新的一手
  // ---------------------------------------------------------------------------

  /// 开始新的一手牌。
  void startNewHand() {
    if (heroStack < bigBlind || aiStack < bigBlind) {
      heroStack = _startingStack;
      aiStack = _startingStack;
      _log('筹码不足，双方筹码重置为 $_startingStack');
    }

    handNumber++;
    _handToken++;
    _deck = Cards.fullDeck()..shuffle(_random);
    heroCards = <int>[_deck.removeLast(), _deck.removeLast()];
    aiCards = <int>[_deck.removeLast(), _deck.removeLast()];
    board = <int>[];

    street = Street.preflop;
    heroCommitted = 0;
    aiCommitted = 0;
    heroTotalCommitted = 0;
    aiTotalCommitted = 0;
    heroFolded = false;
    aiFolded = false;
    heroAllIn = false;
    aiAllIn = false;
    handOver = false;
    revealAiCards = false;
    handResult = '';
    aiThinking = false;
    _runOutInProgress = false;
    _heroActed = false;
    _aiActed = false;
    currentBet = bigBlind;
    lastRaiseSize = bigBlind;

    // 每手重新初始化范围估计：电脑默认偏松，人类玩家默认更松。
    aiRangePercent = 45;
    heroRangePercent = 60;

    buttonIsHero = handNumber.isOdd;
    if (buttonIsHero) {
      _postBlind(true, smallBlind);
      _postBlind(false, bigBlind);
    } else {
      _postBlind(false, smallBlind);
      _postBlind(true, bigBlind);
    }

    // 单挑规则：翻牌前由按钮位（小盲）先行动，翻牌后由大盲先行动。
    _heroToAct = buttonIsHero;

    _log('第 $handNumber 手开始 · 盲注 $smallBlind/$bigBlind · '
        '${buttonIsHero ? '你' : '电脑'}是按钮位（小盲）');

    // 极端情况（例如自定义了很小的初始筹码）：盲注就可能把某一方直接打成全下。
    // 全下的一方无法再行动，此时把行动权交给还能行动的一方；
    // 若双方都已经无需再投入，直接发完公共牌进入摊牌。
    if (heroAllIn || aiAllIn) {
      if (_roundComplete()) {
        _log('双方都无需再下注，直接发完公共牌');
        notifyListeners();
        _runOutBoard();
        return;
      }
      _heroToAct = !heroAllIn;
    }

    _refreshEquity();
    notifyListeners();
  }

  /// 重新开始整场比赛（双方筹码回到初始值，日志清空）。
  void restartMatch() {
    _handToken++;
    heroStack = _startingStack;
    aiStack = _startingStack;
    logs.clear();
    handNumber = 0;
    _log('重新开始对局，双方筹码 $_startingStack');
    startNewHand();
  }

  // ---------------------------------------------------------------------------
  // 我方操作
  // ---------------------------------------------------------------------------
  /// 我方弃牌。
  void heroFold() {
    if (!canFold) {
      return;
    }
    _applyAction(true, ActionType.fold, 0);
  }

  /// 我方过牌。
  void heroCheck() {
    if (!canCheck) {
      return;
    }
    _applyAction(true, ActionType.check, 0);
  }

  /// 我方跟注。
  void heroCall() {
    if (!canCall) {
      return;
    }
    _applyAction(true, ActionType.call, 0);
  }

  /// 我方加注/下注到 [amount]（会被自动夹到合法区间）。
  void heroRaiseTo(int amount) {
    if (!canRaise) {
      return;
    }
    final int lower = minRaiseTo;
    final int upper = maxRaiseTo;
    int target = amount;
    if (target < lower) {
      target = lower;
    }
    if (target > upper) {
      target = upper;
    }
    _applyAction(true, target >= upper ? ActionType.allIn : ActionType.raise, target);
  }

  /// 我方全下。
  ///
  /// 对手已经全下时不允许再加注（加了也没人跟，多出的筹码只会被退回），
  /// 此时想要把筹码全押进去应该用"跟注"（筹码不足时跟注会自动变成全下跟注）。
  void heroPushAllIn() {
    if (!isHeroTurn || !canRaise) {
      return;
    }
    _applyAction(true, ActionType.allIn, heroAllInTo);
  }

  // ---------------------------------------------------------------------------
  // 电脑行动（由界面在 [needsAiAction] 为真时调用）
  // ---------------------------------------------------------------------------

  /// 电脑思考并行动：先用后台 isolate 估算胜率，再按策略决策。
  Future<void> playAiTurn() async {
    if (_disposed || !needsAiAction) {
      return;
    }
    final int token = _handToken;
    aiThinking = true;
    notifyListeners();

    // 模拟一点思考时间，让对局节奏更像真人。
    final int delay = 450 + _random.nextInt(650);
    await Future<void>.delayed(Duration(milliseconds: delay));
    if (_disposed || handOver || token != _handToken) {
      aiThinking = false;
      return;
    }

    double aiEquity = 0.5;
    try {
      aiEquity = await _computeAiEquity();
    } catch (_) {
      aiEquity = 0.5; // 计算失败时退回"抛硬币"级别的决策
    }
    if (_disposed || handOver || token != _handToken) {
      aiThinking = false;
      return;
    }
    // 电脑思考期间局面可能已经变化（例如重新开局），行动权不在电脑身上就放弃这次决策。
    if (_heroToAct) {
      aiThinking = false;
      notifyListeners();
      return;
    }

    final AiContext context = AiContext(
      street: street,
      pot: pot,
      toCall: aiToCall,
      myStack: aiStack,
      myCommitted: aiCommitted,
      bigBlind: bigBlind,
      minRaiseTo: aiMinRaiseTo,
      maxRaiseTo: aiMaxRaiseTo,
      opponentAllIn: heroAllIn,
    );
    final AiDecision decision = _ai.decide(context, aiEquity);

    aiThinking = false;
    _log('电脑 ${decision.description}');
    _applyAction(false, decision.action, decision.amount);
  }

  // ---------------------------------------------------------------------------
  // 规则引擎内部实现
  // ---------------------------------------------------------------------------

  void _postBlind(bool isHero, int amount) {
    if (isHero) {
      final int pay = amount < heroStack ? amount : heroStack;
      heroStack -= pay;
      heroCommitted += pay;
      heroTotalCommitted += pay;
      if (heroStack == 0) {
        heroAllIn = true;
      }
    } else {
      final int pay = amount < aiStack ? amount : aiStack;
      aiStack -= pay;
      aiCommitted += pay;
      aiTotalCommitted += pay;
      if (aiStack == 0) {
        aiAllIn = true;
      }
    }
  }

  int _minRaiseTo(int stack, int committed) {
    final int allInTo = stack + committed;
    if (currentBet == 0) {
      // 本轮还没有人下注：最小下注额为一个大盲。
      return bigBlind < allInTo ? bigBlind : allInTo;
    }
    final int target = currentBet + lastRaiseSize;
    return target < allInTo ? target : allInTo;
  }

  /// 执行一个动作并推进牌局。
  void _applyAction(bool isHero, ActionType type, int amount) {
    if (handOver) {
      return;
    }

    final int currentBetBefore = currentBet;
    final int lastRaiseSizeBefore = lastRaiseSize;
    int myCommitted = isHero ? heroCommitted : aiCommitted;
    int myStack = isHero ? heroStack : aiStack;
    final int opponentCommitted = isHero ? aiCommitted : heroCommitted;
    int paid = 0;
    bool allInNow = false;
    // 是否是"完整加注"（大于等于上一次加注幅度）；不足额的全下不算完整加注。
    bool fullRaiseAction = false;

    switch (type) {
      case ActionType.fold:
        if (isHero) {
          heroFolded = true;
          _log('你弃牌');
        } else {
          aiFolded = true;
        }
        break;

      case ActionType.check:
        // 电脑的动作会带理由，统一由 playAiTurn 记录，这里只记我方的动作。
        if (isHero) {
          _log('你过牌');
        }
        break;

      case ActionType.call:
        final int rawNeed = opponentCommitted - myCommitted;
        final int need = rawNeed > 0 ? rawNeed : 0;
        final int callPay = need < myStack ? need : myStack;
        myStack -= callPay;
        myCommitted += callPay;
        paid = callPay;
        allInNow = myStack == 0;
        if (isHero) {
          _log('你跟注 $callPay');
        }
        break;

      case ActionType.bet:
      case ActionType.raise:
      case ActionType.allIn:
        int target = type == ActionType.allIn ? myStack + myCommitted : amount;
        if (target > myStack + myCommitted) {
          target = myStack + myCommitted;
        }
        if (target < myCommitted) {
          target = myCommitted;
        }
        final int betPay = target - myCommitted;
        final int raiseSize = target - currentBetBefore;
        final bool fullRaise = raiseSize >= lastRaiseSizeBefore;
        myStack -= betPay;
        myCommitted = target;
        paid = betPay;
        allInNow = myStack == 0;
        if (raiseSize > 0) {
          // 需要跟注的金额一定会上涨；但只有完整加注才刷新"最小加注幅度"。
          currentBet = target;
          if (fullRaise) {
            lastRaiseSize = raiseSize;
          }
        }
        fullRaiseAction = raiseSize > 0 && fullRaise;
        if (isHero) {
          if (type == ActionType.bet) {
            _log('你下注到 $target');
          } else if (type == ActionType.allIn) {
            _log('你全下 $target');
          } else {
            _log('你加注到 $target');
          }
        }
        break;
    }

    if (isHero) {
      heroCommitted = myCommitted;
      heroStack = myStack;
      heroTotalCommitted += paid;
      heroAllIn = heroAllIn || allInNow;
      _heroActed = true;
    } else {
      aiCommitted = myCommitted;
      aiStack = myStack;
      aiTotalCommitted += paid;
      aiAllIn = aiAllIn || allInNow;
      _aiActed = true;
    }

    final bool isAggressive = type == ActionType.bet ||
        type == ActionType.raise ||
        type == ActionType.allIn;
    final bool raisedAboveCurrent = isAggressive && myCommitted > currentBetBefore;

    // 只有"完整加注"才会让对手重新获得行动权：不足额的全下加注不重开下注轮。
    if (raisedAboveCurrent && fullRaiseAction) {
      if (isHero) {
        _aiActed = false;
      } else {
        _heroActed = false;
      }
    }

    // 根据动作调整"范围"估计（用于胜率计算器的对手范围）。
    _updateRangeEstimate(isHero, type, fullRaiseAction);

    _heroToAct = false;

    if (heroFolded || aiFolded) {
      _finishByFold();
    } else if (_roundComplete()) {
      _advanceStreet();
    } else {
      _heroToAct = !isHero;
    }

    if (!handOver) {
      _refreshEquity();
    }
    notifyListeners();
  }

  /// 用对手的动作粗略收紧 / 放宽其范围（纯启发式，用于胜率估算）。
  ///
  /// [fullRaise] 为真表示对手做了一次完整加注（范围明显更强）。
  void _updateRangeEstimate(bool isHero, ActionType type, bool fullRaise) {
    if (isHero) {
      if (fullRaise) {
        heroRangePercent = max<double>(8.0, heroRangePercent * 0.5);
      } else if (type == ActionType.call) {
        heroRangePercent = min<double>(70.0, heroRangePercent * 0.95);
      } else if (type == ActionType.check) {
        heroRangePercent = min<double>(95.0, heroRangePercent * 1.05);
      }
    } else {
      if (fullRaise) {
        aiRangePercent = max<double>(8.0, aiRangePercent * 0.55);
      } else if (type == ActionType.call) {
        aiRangePercent = min<double>(70.0, aiRangePercent * 0.95);
      } else if (type == ActionType.check) {
        aiRangePercent = min<double>(80.0, aiRangePercent * 1.1);
      }
    }
  }

  /// 判断当前下注轮是否结束。
  bool _roundComplete() {
    if (heroFolded || aiFolded) {
      return true;
    }
    final bool heroDone = heroAllIn || (_heroActed && aiCommitted <= heroCommitted);
    final bool aiDone = aiAllIn || (_aiActed && heroCommitted <= aiCommitted);
    return heroDone && aiDone;
  }

  /// 进入下一轮：清空本街投入、发新的公共牌。
  void _advanceStreet() {
    heroCommitted = 0;
    aiCommitted = 0;
    _heroActed = false;
    _aiActed = false;
    currentBet = 0;
    lastRaiseSize = bigBlind;

    if (street == Street.river) {
      _showdown();
      return;
    }

    street = street.next;
    if (street == Street.flop) {
      _dealBoard(3);
    } else {
      _dealBoard(1);
    }
    _log('—— ${street.cnName}：${board.map(Cards.label).join(' ')} ——');

    if (heroAllIn || aiAllIn) {
      // 已经有人全下，不会再产生下注，直接发完剩下的牌再摊牌。
      _runOutBoard();
      return;
    }

    // 翻牌后由大盲位（非按钮位）先行动。
    _heroToAct = !buttonIsHero;
    _refreshEquity();
  }

  /// 发公共牌（先烧一张，再发 [count] 张）。
  void _dealBoard(int count) {
    if (_deck.isNotEmpty) {
      _deck.removeLast(); // 烧牌
    }
    for (int i = 0; i < count && _deck.isNotEmpty; i++) {
      board.add(_deck.removeLast());
    }
  }

  /// 双方都无法再下注时，把剩余的公共牌逐轮发完，然后摊牌。
  Future<void> _runOutBoard() async {
    _runOutInProgress = true;
    final int token = _handToken;
    notifyListeners();

    while (board.length < 5 && !_disposed && token == _handToken) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (_disposed || token != _handToken) {
        return;
      }
      if (street == Street.river) {
        break;
      }
      street = street.next;
      // 公共牌：翻牌圈一次发 3 张，转牌/河牌各 1 张。
      _dealBoard(street == Street.flop ? 3 : 1);
      _log('—— ${street.cnName}：${board.map(Cards.label).join(' ')} ——');
      notifyListeners();
    }

    if (_disposed || token != _handToken) {
      return;
    }
    _runOutInProgress = false;
    _refreshEquity();
    _showdown();
    notifyListeners();
  }

  /// 退还未被跟注的多余下注（一方投入多于另一方时，多出的部分本来就不属于底池）。
  ///
  /// 弃牌结算与摊牌结算都会先调用它，保证底池金额与文案一致，筹码也不会算错。
  void _refundUncalledBet() {
    final int diff = heroTotalCommitted - aiTotalCommitted;
    if (diff > 0) {
      heroStack += diff;
      heroTotalCommitted -= diff;
      _log('退回你未被跟注的 $diff 筹码');
    } else if (diff < 0) {
      aiStack += -diff;
      aiTotalCommitted -= -diff;
      _log('退回电脑未被跟注的 ${-diff} 筹码');
    }
  }

  /// 一方弃牌，直接结算。
  void _finishByFold() {
    _refundUncalledBet();
    final int total = pot;
    if (aiFolded) {
      heroStack += total;
      handResult = '电脑弃牌，你赢得底池 $total 筹码';
    } else {
      aiStack += total;
      handResult = '你弃牌，电脑赢得底池 $total 筹码';
    }
    handOver = true;
    _heroToAct = false;
    revealAiCards = false;
    _log(handResult);
  }

  /// 摊牌比大小。
  void _showdown() {
    revealAiCards = true;

    // 退还未被跟注的多余下注（一方全下金额较少时会发生）。
    _refundUncalledBet();

    final int total = pot;
    final int heroScore = HandEvaluator.evaluate(<int>[...heroCards, ...board]);
    final int aiScore = HandEvaluator.evaluate(<int>[...aiCards, ...board]);

    _log('摊牌：你 ${HandEvaluator.describe(heroScore)}；'
        '电脑 ${HandEvaluator.describe(aiScore)}');

    if (heroScore > aiScore) {
      heroStack += total;
      handResult = '你赢了 $total 筹码';
    } else if (aiScore > heroScore) {
      aiStack += total;
      handResult = '电脑赢了 $total 筹码';
    } else {
      final int half = total ~/ 2;
      heroStack += half;
      aiStack += total - half;
      handResult = '平分底池（$total 筹码）';
    }

    handOver = true;
    _heroToAct = false;
    _log(handResult);
  }

  // ---------------------------------------------------------------------------
  // 胜率计算（后台 isolate）
  // ---------------------------------------------------------------------------

  /// 重新计算"我方 vs 电脑范围"的胜率，并刷新局面分析。
  ///
  /// 计算在后台 isolate 中进行，UI 只会看到 [equityLoading] 变成 true，
  /// 因此不会卡界面。
  Future<void> _refreshEquity() async {
    if (_disposed || heroCards.length < 2) {
      return;
    }
    final int token = ++_equityToken;

    // 局面分析是确定性的小计算（穷举几十~一千次），放在主线程即可。
    insight = HandAnalyzer.analyze(heroCards, board);

    equityLoading = true;
    notifyListeners();

    final List<int> known = <int>[...heroCards, ...board];
    final EquityInput input = EquityInput(
      heroCard1: heroCards[0],
      heroCard2: heroCards[1],
      board: List<int>.of(board),
      villainCombos: HandRange.combos(aiRangePercent, known),
      iterations: EquityCalculator.recommendedIterations(board.length),
      seed: 20240501 + handNumber,
    );

    Map<String, Object?> raw;
    try {
      raw = await compute(equityIsolateEntry, input.toMap());
    } catch (_) {
      if (!_disposed && token == _equityToken) {
        equityLoading = false;
        notifyListeners();
      }
      return;
    }

    if (_disposed || token != _equityToken) {
      return; // 局面已经变化，丢弃这次结果
    }
    equity = EquityResult.fromMap(raw);
    equityLoading = false;
    notifyListeners();
  }

  /// 电脑自己的胜率估算（对手范围取"我方范围估计"）。
  ///
  /// 注意：这里刻意**不使用我方的真实底牌**，只用电脑自己的底牌 + 公共牌，
  /// 否则电脑就等于在作弊。
  Future<double> _computeAiEquity() async {
    final List<int> known = <int>[...aiCards, ...board];
    final EquityInput input = EquityInput(
      heroCard1: aiCards[0],
      heroCard2: aiCards[1],
      board: List<int>.of(board),
      villainCombos: HandRange.combos(heroRangePercent, known),
      iterations: 8000,
      seed: 777 + handNumber,
    );
    final Map<String, Object?> raw = await compute(equityIsolateEntry, input.toMap());
    final EquityResult result = EquityResult.fromMap(raw);
    return result.equity;
  }

  // ---------------------------------------------------------------------------
  // 杂项
  // ---------------------------------------------------------------------------

  void _log(String message) {
    logs.insert(0, message);
    if (logs.length > 60) {
      logs.removeRange(60, logs.length);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _equityToken++;
    super.dispose();
  }
}
