import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/game_controller.dart';
import '../engine/game_types.dart';
import 'widgets/action_bar.dart';
import 'widgets/board_panel.dart';
import 'widgets/equity_panel.dart';
import 'widgets/seat_panel.dart';

/// 主界面：手机竖屏布局。
///
/// 区域自上而下：
///  1. 顶部状态栏（手数 / 盲注 / 重开 / 规则）
///  2. 电脑底牌区（未摊牌时显示牌背）
///  3. 桌面公共牌区（翻牌 / 转牌 / 河牌）
///  4. 玩家底牌区
///  5. 筹码与操作按钮区
///  6. 独立信息面板（实时胜率 + 潜在牌型 + 补牌 + 日志）
class TableScreen extends StatefulWidget {
  const TableScreen({super.key});

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  final GameController _controller = GameController();

  /// 防止电脑行动被重复调度。
  bool _aiScheduled = false;

  static const double _topBarHeight = 38;
  static const double _actionBarHeight = 114;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.startNewHand();
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  /// 状态变化时检查是否需要让电脑行动。
  void _onControllerChanged() {
    if (!mounted || !_controller.needsAiAction || _aiScheduled) {
      return;
    }
    _aiScheduled = true;
    // 丢到事件循环里执行，避免在 notifyListeners 过程中再次触发通知。
    Future<void>(() async {
      try {
        if (!mounted) {
          return;
        }
        await _controller.playAiTurn();
      } finally {
        _aiScheduled = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07281E),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // 剩余空间按比例分配：电脑区 / 公共牌区 / 玩家区 / 信息面板。
                double flexible =
                    constraints.maxHeight - _topBarHeight - _actionBarHeight;
                if (flexible < 0.0) {
                  flexible = 0.0;
                }
                final double seatHeight = flexible * 0.20;
                final double boardHeight = flexible * 0.22;
                final double infoHeight = flexible * 0.38;

                return Column(
                  children: <Widget>[
                    SizedBox(height: _topBarHeight, child: _topBar(context)),
                    SizedBox(
                      height: seatHeight,
                      child: SeatPanel(
                        title: '电脑 AI',
                        stack: _controller.aiStack,
                        cards: _controller.aiCards,
                        faceUp: _controller.revealAiCards,
                        isTurn: !_controller.isHeroTurn && !_controller.handOver,
                        statusText: _villainStatus(),
                        maxHeight: seatHeight,
                        accent: const Color(0xFF6A1B9A),
                        committed: _controller.aiCommitted,
                        folded: _controller.aiFolded,
                        allIn: _controller.aiAllIn,
                      ),
                    ),
                    SizedBox(
                      height: boardHeight,
                      child: BoardPanel(
                        board: _controller.board,
                        streetName: _controller.street.cnName,
                        pot: _controller.pot,
                        maxHeight: boardHeight,
                      ),
                    ),
                    SizedBox(
                      height: seatHeight,
                      child: SeatPanel(
                        title: '你',
                        stack: _controller.heroStack,
                        cards: _controller.heroCards,
                        faceUp: true,
                        isTurn: _controller.isHeroTurn,
                        statusText: _heroStatus(),
                        maxHeight: seatHeight,
                        accent: const Color(0xFF1565C0),
                        committed: _controller.heroCommitted,
                        folded: _controller.heroFolded,
                        allIn: _controller.heroAllIn,
                      ),
                    ),
                    SizedBox(
                      height: _actionBarHeight,
                      child: ActionBar(controller: _controller),
                    ),
                    SizedBox(
                      height: infoHeight,
                      child: EquityPanel(controller: _controller),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _villainStatus() {
    final GameController c = _controller;
    if (c.aiFolded) {
      return '已弃牌';
    }
    if (c.handOver) {
      return c.revealAiCards ? '已摊牌' : '';
    }
    if (c.aiThinking) {
      return '思考中…';
    }
    if (c.isHeroTurn) {
      return '等待你行动';
    }
    return c.aiAllIn ? '已全下' : '准备行动';
  }

  String _heroStatus() {
    final GameController c = _controller;
    if (c.heroFolded) {
      return '你已弃牌';
    }
    if (c.handOver) {
      return c.handResult;
    }
    if (c.isHeroTurn) {
      return c.toCall > 0 ? '轮到你行动（需跟注 ${c.toCall}）' : '轮到你行动（可过牌）';
    }
    return c.heroAllIn ? '你已全下' : '等待电脑行动…';
  }

  Widget _topBar(BuildContext context) {
    final GameController c = _controller;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Text(
            '第 ${c.handNumber} 手',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '盲注 ${c.smallBlind}/${c.bigBlind}',
            style: const TextStyle(color: Color(0xFFB9D9C6), fontSize: 11),
          ),
          const Spacer(),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 18,
            color: const Color(0xFFCFE9DA),
            tooltip: '玩法与胜率说明',
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelp(context),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 18,
            color: const Color(0xFFCFE9DA),
            tooltip: '重新开始',
            icon: const Icon(Icons.refresh),
            onPressed: () => _confirmRestart(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showHelp(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0E3B2E),
          title: const Text('玩法与胜率说明', style: TextStyle(color: Color(0xFFFFD54F), fontSize: 16)),
          content: const SingleChildScrollView(
            child: Text(
              '1. 单挑德州扑克：你 vs 电脑 AI，盲注 10/20，双方各 1000 筹码。\n'
              '2. 流程：发底牌 → 翻牌前下注 → 翻牌 → 转牌 → 河牌 → 摊牌。\n'
              '3. 操作：弃牌 / 过牌 / 跟注 / 加注（滑杆或快捷比例）/ 全下。\n'
              '4. 胜率计算器：每一轮发牌后自动在后台用蒙特卡洛模拟计算'
              '「你的底牌 + 公共牌」对阵电脑范围 的胜、平、负概率；'
              '河牌圈与转牌圈组合数很少，会改用精确枚举。\n'
              '5. 潜在牌型：列出当前局面下所有可能做成的牌型及其概率，'
              '并给出听牌与补牌数（下一张牌能带来的升级）。\n'
              '6. 电脑范围：程序并不看你的底牌，它按你的下注动作估计你的起手牌范围；'
              '同理，胜率面板用的是电脑的"范围"而不是它的真实底牌。\n'
              '7. 全部为本机虚拟筹码，无联网、无充值、无广告。',
              style: TextStyle(color: Color(0xFFE8F5E9), fontSize: 12, height: 1.5),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmRestart(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0E3B2E),
          title: const Text('重新开始？', style: TextStyle(color: Color(0xFFFFD54F), fontSize: 16)),
          content: const Text(
            '双方筹码将重置为 1000，日志清空。',
            style: TextStyle(color: Color(0xFFE8F5E9), fontSize: 12),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('重新开始'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      _controller.restartMatch();
    }
  }
}
