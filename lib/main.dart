import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/table_screen.dart';

/// 应用入口。
///
/// 这是一个完全本地运行的德州扑克人机对战训练应用：
///  * 无联网、无后端、无登录、无广告、无充值；
///  * 筹码只是屏幕上的虚拟数字。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 锁定竖屏（手机竖屏布局）。
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const PokerTrainerApp());
}

class PokerTrainerApp extends StatelessWidget {
  const PokerTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1B5E20),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: '德州扑克人机对战',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF07281E),
      ),
      home: const TableScreen(),
    );
  }
}
