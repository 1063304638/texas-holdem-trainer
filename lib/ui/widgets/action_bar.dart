import 'package:flutter/material.dart';

import '../../engine/game_controller.dart';

/// 筹码与操作按钮区。
///
/// 布局（自上而下）：动作按钮 → 加注滑杆 → 快捷下注比例。
/// 一手牌结束后这里会变成"结算信息 + 开始下一手"。
class ActionBar extends StatefulWidget {
  const ActionBar({super.key, required this.controller});

  final GameController controller;

  @override
  State<ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<ActionBar> {
  /// 用户拖动滑杆设定的"加注到"金额；null 表示使用默认值（区间中点）。
  double? _raiseValue;

  @override
  Widget build(BuildContext context) {
    final GameController c = widget.controller;

    if (c.handOver) {
      return _buildResult(c);
    }

    final bool active = c.isHeroTurn;
    int minTo = c.minRaiseTo;
    int maxTo = c.maxRaiseTo;
    if (maxTo < minTo) {
      maxTo = minTo;
    }
    final double lo = minTo.toDouble();
    final double hi = maxTo.toDouble();
    final bool sliderEnabled = active && hi > lo;

    double value = _raiseValue ?? (hi > lo ? (lo + hi) / 2 : lo);
    if (value < lo) {
      value = lo;
    }
    if (value > hi) {
      value = hi;
    }
    final int raiseTo = value.round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 40,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _button(
                    label: '弃牌',
                    enabled: active,
                    color: const Color(0xFFB71C1C),
                    onPressed: c.heroFold,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _button(
                    label: c.toCall > 0 ? '跟注 ${c.toCall}' : '过牌',
                    enabled: active && (c.toCall > 0 ? c.canCall : c.canCheck),
                    color: const Color(0xFF1565C0),
                    onPressed: c.toCall > 0 ? c.heroCall : c.heroCheck,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _button(
                    label: c.currentBet == 0 ? '下注 $raiseTo' : '加注到 $raiseTo',
                    enabled: active && c.canRaise,
                    color: const Color(0xFF2E7D32),
                    onPressed: () => c.heroRaiseTo(raiseTo),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _button(
                    label: '全下',
                    enabled: active && c.canRaise,
                    color: const Color(0xFF6A1B9A),
                    onPressed: c.heroPushAllIn,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 30,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: const Color(0xFFFFD54F),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFFFD54F),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: value,
                min: lo,
                max: hi <= lo ? lo + 1 : hi,
                divisions: hi > lo ? (hi - lo) <= 20 ? (hi - lo).round() : 20 : null,
                onChanged: sliderEnabled
                    ? (double next) {
                        setState(() {
                          _raiseValue = next;
                        });
                      }
                    : null,
              ),
            ),
          ),
          SizedBox(
            height: 26,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _fractionChip('½ 池', 0.5, c, active),
                const SizedBox(width: 6),
                _fractionChip('¾ 池', 0.75, c, active),
                const SizedBox(width: 6),
                _fractionChip('底池', 1.0, c, active),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(GameController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF0E3B2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFD54F)),
            ),
            child: Text(
              c.handResult.isEmpty ? '本手结束' : c.handResult,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFD54F),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton(
              onPressed: c.startNewHand,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: const Color(0xFF1B1B1B),
              ),
              child: const Text('开始下一手', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fractionChip(
    String label,
    double fraction,
    GameController c,
    bool active,
  ) {
    return SizedBox(
      height: 24,
      child: OutlinedButton(
        onPressed: (!active || !c.canRaise)
            ? null
            : () => c.heroRaiseTo(
                  (c.currentBet + (c.pot + c.toCall) * fraction).round(),
                ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: const BorderSide(color: Color(0xFF3E8E6E)),
          foregroundColor: const Color(0xFFCFE9DA),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _button({
    required String label,
    required bool enabled,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 40,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF24483C),
          disabledForegroundColor: Colors.white38,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label),
        ),
      ),
    );
  }
}
