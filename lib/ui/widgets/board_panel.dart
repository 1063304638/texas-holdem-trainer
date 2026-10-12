import 'package:flutter/material.dart';

import 'playing_card.dart';

/// 桌面公共牌区：阶段标签 + 5 张公共牌 + 底池。
class BoardPanel extends StatelessWidget {
  const BoardPanel({
    super.key,
    required this.board,
    required this.streetName,
    required this.pot,
    required this.maxHeight,
  });

  /// 已发出的公共牌。
  final List<int> board;

  /// 当前轮次名称。
  final String streetName;

  /// 当前底池。
  final int pot;

  /// 可用高度（由父级 Expanded 决定）。
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    // 5 张牌 + 4 个间距，按高度反推牌宽，保证不会溢出。
    final double byHeight = (maxHeight - 46) / PlayingCard.aspect;
    final double byWidth = (MediaQuery.of(context).size.width - 60) / 5;
    double cardWidth = byHeight < byWidth ? byHeight : byWidth;
    if (cardWidth > 62) {
      cardWidth = 62;
    }
    if (cardWidth < 22) {
      cardWidth = 22;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF0E3B2E),
          border: Border.all(color: const Color(0xFF1F6B4F)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  streetName,
                  style: const TextStyle(
                    color: Color(0xFF9CCC9C),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '底池 $pot',
                  style: const TextStyle(
                    color: Color(0xFFFFD54F),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(5, (int index) {
                final bool dealt = index < board.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: PlayingCard(
                    card: dealt ? board[index] : null,
                    width: cardWidth,
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
