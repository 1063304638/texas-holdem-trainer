import 'package:flutter/material.dart';

import '../../models/cards.dart';

/// 一张扑克牌（正面 / 背面 / 空位）。
///
/// 宽度由外部按可用空间计算，高度按 [aspect] 比例得出，
/// 这样在竖屏小尺寸手机上也不会撑破布局。
class PlayingCard extends StatelessWidget {
  const PlayingCard({
    super.key,
    required this.card,
    this.faceUp = true,
    this.width = 54,
    this.dimmed = false,
  });

  /// 牌的整数编码（0..51）；null 表示"空位"（还没发到这张牌）。
  final int? card;

  /// 是否正面朝上。
  final bool faceUp;

  /// 牌宽。
  final double width;

  /// 是否变暗（例如已弃牌）。
  final bool dimmed;

  /// 牌的高宽比。
  static const double aspect = 1.42;

  @override
  Widget build(BuildContext context) {
    final double height = width * aspect;
    final BorderRadius radius = BorderRadius.circular(width * 0.13);
    final int? value = card;

    if (value == null) {
      // 空位：虚线感的浅色占位框。
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: Colors.white24, width: 1.2),
          color: Colors.white10,
        ),
      );
    }

    if (!faceUp) {
      // 牌背。
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF1E3A8A), Color(0xFF0B1220)],
          ),
          border: Border.all(color: Colors.white30, width: 1),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.style,
            size: width * 0.5,
            color: Colors.white24,
          ),
        ),
      );
    }

    final bool red = Cards.isRed(value);
    final Color ink = red ? const Color(0xFFC62828) : const Color(0xFF1B1B1B);

    final Widget face = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: const Color(0xFFFCFCF7),
        border: Border.all(color: Colors.black26, width: 0.8),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(
              left: width * 0.09,
              right: width * 0.04,
              top: height * 0.04,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Cards.rankLabels[Cards.rankOf(value)],
                  style: TextStyle(
                    color: ink,
                    fontSize: width * 0.42,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                Cards.suitSymbols[Cards.suitOf(value)],
                style: TextStyle(
                  color: ink,
                  fontSize: width * 0.5,
                  height: 1.0,
                ),
              ),
            ),
          ),
          SizedBox(height: height * 0.06),
        ],
      ),
    );

    if (!dimmed) {
      return face;
    }
    return Opacity(opacity: 0.42, child: face);
  }
}
