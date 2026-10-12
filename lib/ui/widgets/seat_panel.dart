import 'package:flutter/material.dart';

import 'playing_card.dart';

/// 一个座位（我方或电脑）：名字、筹码、状态标签与底牌。
class SeatPanel extends StatelessWidget {
  const SeatPanel({
    super.key,
    required this.title,
    required this.stack,
    required this.cards,
    required this.faceUp,
    required this.isTurn,
    required this.statusText,
    required this.maxHeight,
    required this.accent,
    this.committed = 0,
    this.folded = false,
    this.allIn = false,
  });

  /// 座位名称。
  final String title;

  /// 剩余筹码。
  final int stack;

  /// 底牌。
  final List<int> cards;

  /// 是否亮牌（电脑摊牌前为 false）。
  final bool faceUp;

  /// 是否轮到该座位行动。
  final bool isTurn;

  /// 状态文字（如"思考中…"、"已弃牌"、"全下"）。
  final String statusText;

  /// 可用高度。
  final double maxHeight;

  /// 主题色。
  final Color accent;

  /// 本街已投入的筹码。
  final int committed;

  /// 是否已弃牌。
  final bool folded;

  /// 是否已全下。
  final bool allIn;

  @override
  Widget build(BuildContext context) {
    double cardWidth = (maxHeight - 30) / PlayingCard.aspect;
    if (cardWidth > 52) {
      cardWidth = 52;
    }
    if (cardWidth < 20) {
      cardWidth = 20;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isTurn ? const Color(0xFF14503C) : const Color(0xFF0E3B2E),
          border: Border.all(
            color: isTurn ? const Color(0xFFFFD54F) : const Color(0xFF1F6B4F),
            width: isTurn ? 1.6 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 15,
              backgroundColor: accent,
              child: Text(
                title.substring(0, 1),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$stack 筹码${committed > 0 ? ' · 本街 $committed' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFB9D9C6), fontSize: 10),
                  ),
                  if (statusText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isTurn
                              ? const Color(0xFFFFD54F)
                              : (allIn
                                  ? const Color(0xFFFF8A65)
                                  : const Color(0xFF8FBCA6)),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (folded)
              const Opacity(
                opacity: 0.5,
                child: Text('弃牌', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            for (int i = 0; i < cards.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: PlayingCard(
                  card: cards[i],
                  faceUp: faceUp,
                  width: cardWidth,
                  dimmed: folded,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
