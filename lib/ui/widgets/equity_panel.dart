import 'package:flutter/material.dart';

import '../../engine/equity_calculator.dart';
import '../../engine/game_controller.dart';
import '../../engine/hand_range.dart';
import '../../models/hand_analyzer.dart';
import '../../models/hand_evaluator.dart';

/// 独立信息面板：实时胜率、可能成型的牌型、听牌与补牌、对手范围、行动日志。
///
/// 面板只读取 [GameController] 的公开状态，胜率的实际运算发生在后台 isolate
/// （见 GameController._refreshEquity），这里只负责展示，所以不会卡界面。
class EquityPanel extends StatelessWidget {
  const EquityPanel({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final GameController c = controller;
    final EquityResult? result = c.equity;
    final HandInsight? insight = c.insight;

    // 听牌 / 补牌：仅当已经拿到局面分析时展示。
    final List<Widget> drawSection = <Widget>[];
    if (insight != null) {
      final HandInsight value = insight;
      drawSection.addAll(<Widget>[
        const SizedBox(height: 8),
        _sectionTitle('听牌与补牌'),
        const SizedBox(height: 4),
        _drawChips(value),
      ]);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2E23),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F6B4F)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _header(c, result),
            const SizedBox(height: 6),
            _equityRow(result),
            const SizedBox(height: 8),
            _sectionTitle('可能成型的牌型'),
            const SizedBox(height: 4),
            _achievableChips(result),
            ...drawSection,
            const SizedBox(height: 8),
            _sectionTitle('对手范围'),
            const SizedBox(height: 2),
            Text(
              '当前估算：${HandRange.describePercent(c.aiRangePercent)}'
              '（电脑动作越激进，范围越收紧）',
              style: const TextStyle(color: Color(0xFFB9D9C6), fontSize: 11),
            ),
            const SizedBox(height: 8),
            _sectionTitle('行动日志'),
            const SizedBox(height: 2),
            _logList(c),
          ],
        ),
      ),
    );
  }

  Widget _header(GameController c, EquityResult? result) {
    final String meta;
    if (c.equityLoading) {
      meta = '计算中…';
    } else if (result == null) {
      meta = '等待发牌';
    } else if (result.exact) {
      meta = '精确枚举 ${result.iterationsRun} 次 · ${result.elapsedMs.toStringAsFixed(0)} ms';
    } else {
      meta = '蒙特卡洛 ${result.iterationsRun} 次 · ${result.elapsedMs.toStringAsFixed(0)} ms';
    }

    return Row(
      children: <Widget>[
        const Icon(Icons.analytics_outlined, size: 15, color: Color(0xFFFFD54F)),
        const SizedBox(width: 5),
        const Text(
          '实时胜率',
          style: TextStyle(
            color: Color(0xFFFFD54F),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            meta,
            style: const TextStyle(color: Color(0xFF8FBCA6), fontSize: 11),
          ),
        ),
        if (c.equityLoading)
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFD54F)),
          ),
      ],
    );
  }

  Widget _equityRow(EquityResult? result) {
    final double win = result?.winRate ?? 0.0;
    final double tie = result?.tieRate ?? 0.0;
    final double lose = result?.loseRate ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _statText('我方胜', win, const Color(0xFF66BB6A)),
            const SizedBox(width: 12),
            _statText('平局', tie, const Color(0xFFBDBDBD)),
            const SizedBox(width: 12),
            _statText('对手胜', lose, const Color(0xFFEF5350)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 9,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double width = constraints.maxWidth;
                return Row(
                  children: <Widget>[
                    Container(width: width * win, color: const Color(0xFF66BB6A)),
                    Container(width: width * tie, color: const Color(0xFF9E9E9E)),
                    Container(width: width * lose, color: const Color(0xFFEF5350)),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _statText(String label, double value, Color color) {
    return Row(
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Color(0xFFB9D9C6), fontSize: 11),
        ),
        const SizedBox(width: 3),
        Text(
          '${(value * 100).toStringAsFixed(1)}%',
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _achievableChips(EquityResult? result) {
    if (result == null) {
      return const Text(
        '发牌后自动列出所有可能成型的牌型。',
        style: TextStyle(color: Color(0xFF8FBCA6), fontSize: 11),
      );
    }

    final List<Widget> chips = <Widget>[];
    for (final int categoryIndex in result.achievableCategories) {
      final HandCategory category = HandCategory.values[categoryIndex];
      final double probability = categoryIndex < result.categoryProbability.length
          ? result.categoryProbability[categoryIndex]
          : 0.0;
      final String percent = probability >= 0.001
          ? '${(probability * 100).toStringAsFixed(1)}%'
          : '<0.1%';
      chips.add(_chip('${category.cnName} $percent'));
    }
    if (chips.isEmpty) {
      chips.add(_chip('暂无'));
    }
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _drawChips(HandInsight insight) {
    final List<Widget> chips = <Widget>[];
    chips.add(_chip(
      '当前牌型：${insight.madeCategory.cnName}',
      highlight: true,
    ));
    for (final String tag in insight.tags) {
      chips.add(_chip(tag, highlight: true));
    }
    for (final OutBreakdown breakdown in insight.outs) {
      chips.add(_chip('${breakdown.outs} 张可成${breakdown.category.cnName}'));
    }
    if (insight.outs.isEmpty) {
      chips.add(_chip('没有明确的补牌'));
    }
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _logList(GameController c) {
    if (c.logs.isEmpty) {
      return const Text('—', style: TextStyle(color: Color(0xFF8FBCA6), fontSize: 11));
    }
    final int count = c.logs.length < 8 ? c.logs.length : 8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List<Widget>.generate(count, (int index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            '· ${c.logs[index]}',
            style: const TextStyle(color: Color(0xFFA8C9B8), fontSize: 11, height: 1.25),
          ),
        );
      }),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFCFE9DA),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _chip(String text, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF1B5E43) : const Color(0xFF123A2C),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: highlight ? const Color(0xFF3E8E6E) : const Color(0xFF1F6B4F),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: highlight ? const Color(0xFFE8F5E9) : const Color(0xFFB9D9C6),
          fontSize: 11,
        ),
      ),
    );
  }
}
