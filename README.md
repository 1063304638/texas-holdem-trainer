# 德州扑克人机对战训练器（Flutter / Android）

一个**完全本地运行**的单挑德州扑克训练应用：你 vs 电脑 AI，虚拟筹码，无联网、无后端、无登录、无广告、无充值。

核心是**实时胜率计算器**：每一轮发牌结束后，立刻在后台用**蒙特卡洛模拟**算出
「你的底牌 + 桌面公共牌」对阵「电脑对手范围」的**胜 / 平 / 负**概率，
并列出当前局面下**所有有可能成型的牌型**、听牌与补牌数。

---

## 1. 功能一览

| 功能 | 说明 |
| --- | --- |
| 完整对战流程 | 发底牌 → 翻牌前下注 → 翻牌（3 张）→ 转牌 → 河牌 → 摊牌；含烧牌、大小盲、按钮位交替 |
| 玩家操作 | 弃牌 / 过牌 / 跟注 / 加注（滑杆 + ½ 池、¾ 池、底池快捷比例）/ 全下 |
| 电脑 AI | 自动决策：底池赔率 + 胜率阈值 + 少量诈唬与随机性；决策理由写入日志 |
| 实时胜率面板 | 胜率 / 平局 / 失败三条概率 + 堆叠条；标注模拟次数与耗时；运算在后台 isolate |
| 潜在牌型清单 | 穷举当前局面所有可成型牌型（高牌→同花顺共 9 类）并给出各自概率 |
| 听牌与补牌 | 已成牌型、同花听牌 / 顺子听牌 / 卡顺提示、单张补牌明细 |
| 对手范围 | 电脑不在作弊：胜率按「电脑范围」估算，范围随其下注动作收紧；电脑判断你时同理 |
| 竖屏 UI | 电脑底牌区（摊牌前隐藏）/ 公共牌区 / 玩家底牌区 / 操作区 / 独立信息面板 |
| 筹码 | 仅虚拟数字，双方各 1000 起步，盲注 10/20，输光自动重置 |

---

## 2. 目录结构与模块解耦

```
texas_holdem_trainer/
├── lib/
│   ├── main.dart                     # 入口：锁定竖屏 + 主题
│   ├── models/                       # 纯数据 / 纯算法（无 Flutter 依赖，可单独测试）
│   │   ├── cards.dart                # 牌的整数编码（0..51）
│   │   ├── hand_evaluator.dart       # 7 张取最优 5 张，返回可比较的整数评分
│   │   └── hand_analyzer.dart        # 可能牌型穷举、补牌、听牌标签
│   ├── engine/
│   │   ├── equity_calculator.dart    # ★ 胜率计算模块（蒙特卡洛 + 精确枚举），isolate 入口
│   │   ├── hand_range.dart           # 对手起手牌范围模型（Chen 公式 + 百分比）
│   │   ├── game_types.dart           # Street / ActionType
│   │   └── game_controller.dart      # 规则引擎 + 异步调度（ChangeNotifier）
│   ├── ai/
│   │   └── ai_player.dart            # 电脑决策模型（纯逻辑，可单测）
│   └── ui/
│       ├── table_screen.dart         # 主界面（竖屏区域划分 + AI 调度）
│       └── widgets/                  # 扑克牌 / 座位 / 公共牌 / 操作条 / 信息面板
├── test/                             # flutter test：评估器、范围、胜率
├── tool/                             # 离线自检脚本（Node 跑，不参与 App 运行）
│   ├── logic_reference_check.js       # 同一套算法的 JS 参考实现 + 35 项断言
│   ├── evaluator_bruteforce_check.js  # 与暴力枚举交叉验证牌力评估器
│   └── ai_decision_fuzz_check.js      # 模糊测试 AI 决策的合法性
├── pubspec.yaml                      # 零第三方依赖，只依赖 Flutter SDK
├── analysis_options.yaml
├── .gitignore                        # Flutter 常用忽略规则
└── .github/workflows/build-apk.yml   # 云构建：推送到 GitHub 后自动产出 APK
```

### 胜率模块为什么"解耦"

* `EquityCalculator.run(EquityInput) -> EquityResult` 是**纯函数**，只依赖 `dart:math` 与 `models/`；
* 输入输出只使用 `int` / `List<int>` / `double` 等可跨 isolate 传递的原始类型，
  因此可以被 `compute()` 直接丢到后台 isolate（`equityIsolateEntry` 是顶层入口）；
* UI 只读取 `GameController.equity` / `equityLoading`，看不到任何计算细节；
* 想换成精确枚举、换迭代次数、换范围模型，都只改这一个文件，UI 无需改动。

### 算法说明

1. **蒙特卡洛**：从对手范围中随机取一手底牌 → 无放回补齐公共牌 → 比较双方 7 张牌的最优 5 张 → 累计胜负平。
   翻牌前默认 25,000 次、翻牌圈 20,000 次（标准误差约 0.3%）。
2. **精确枚举**：河牌圈组合数 = 对手范围组合数，转牌圈 = 范围 × 44 张，
   都不大，因此这两轮改为**精确枚举**（结果不是估计值，面板会显示"精确枚举"）。
3. **潜在牌型**：对"我方后续公共牌"做穷举（翻牌圈 1081 种、转牌圈 47 种）得到所有可成牌型；
   概率则取自模拟出的最终牌型分布。
4. **补牌**：把每一张未知牌逐一加进来重算牌型，只统计"牌型升级"（踢脚提升不算）。
5. **对手范围**：Chen 公式给 1326 个起手组合打分，取最强的前 N%；
   电脑加注 → 范围收紧，跟注/过牌 → 略微放宽（纯启发式，代码中有注释）。

---

## 3. 环境准备

### 3.1 到底要装什么

| 依赖 | 是否必需 | 说明与下载地址 |
| --- | --- | --- |
| **Flutter SDK** | ✅ 必需 | 下载最新 stable 压缩包解压即可（约 1.6 GB，解压后 2.5 GB+）。<br>官方手动安装文档：<https://docs.flutter.dev/install/manual><br>各版本直链归档：<https://docs.flutter.dev/release/archive?tab=windows><br>解压后把 `flutter\bin` 加进 PATH。**本项目要求 Flutter 3.16 以上**（代码本身兼容 Dart ≥ 2.19），当前 stable 远高于此，直接下最新版即可。 |
| **Git for Windows** | ✅ 必需 | Flutter 命令行依赖 git。<https://git-scm.com/downloads/win> |
| **Android Studio** | 推荐（= 下面三样一起装好） | 一站式提供 **SDK Manager + Android SDK + Build-Tools + Platform-Tools + 模拟器 + 内置 JDK**。<https://developer.android.com/studio> |
| **JDK 17** | 装了 Android Studio 就不用单独装 | Android Studio 自带 JetBrains Runtime（JDK 17/21），Flutter 会自动使用；只有"纯命令行、不装 Android Studio"时才需要单独装：<br>Temurin 17：<https://adoptium.net/temurin/releases/><br>Microsoft OpenJDK：<https://learn.microsoft.com/java/openjdk/download> |
| **Android SDK**（Platform + Build-Tools + Platform-Tools） | ✅ 必需（打包 APK 用） | 两条路线：<br>① 装了 Android Studio：`Tools → SDK Manager`，**SDK Platforms** 勾最新 API（当前文档推荐 API 36），**SDK Tools** 勾 Android SDK Build-Tools / Command-line Tools / Platform-Tools /（模拟器需要 Emulator）；<br>② 不装 Android Studio：只下 Command-line tools <https://developer.android.com/studio#command-line-tools-only>，然后用 `sdkmanager` 安装 <https://developer.android.com/tools/sdkmanager>：<br>`sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"` |
| 真机 / 模拟器 | 二选一 | 真机打开「开发者选项 + USB 调试」；模拟器由 Android Studio 的 Device Manager 创建 |

> **平台版本不用纠结**：具体要哪个 `compileSdk` / Build-Tools，由 `flutter create` 生成的 Gradle 配置决定；
> 只要在 SDK Manager 里勾上最新的 Platform + Build-Tools，并在接受许可后让 Gradle 自动补下载缺失组件即可
> （首次构建会联网下载 Gradle 与依赖，需要能访问网络）。
>
> **Android 官方环境搭建文档（英文）**：<https://docs.flutter.dev/platform-integration/android/setup>

**如果你完全不想装这些**：可以把工程推到 GitHub，用 GitHub Actions 的 Flutter 工作流在云端构建 APK，
再把产物下载到手机安装（例如 `subosito/flutter-action` <https://github.com/subosito/flutter-action>），
或使用 Codemagic <https://codemagic.io/> 之类的托管构建。

### 3.2 国内网络加速（可选）

```bash
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```
（macOS / Linux 用 `export`）

Flutter SDK 也可以用镜像下载：<https://mirrors.tuna.tsinghua.edu.cn/flutter/flutter_infra_release/releases/stable/windows/>

### 3.3 验证环境

```bash
flutter doctor -v
```

`Android toolchain` 一栏必须是 ✓（若提示许可未接受或缺少 cmdline-tools，按提示执行
`flutter doctor --android-licenses`）。另外常用：

```bash
flutter config --android-sdk <SDK 路径>   # 自动找不到 SDK 时手动指定（等价于设 ANDROID_HOME）
flutter config --jdk-dir <JDK 路径>       # 需要指定 JDK 时使用
flutter devices                           # 确认手机 / 模拟器已被识别
```

---

## 4. 编译步骤

### 4.1 生成 Android 平台工程

交付包只包含 Dart 源码与配置（**没有** `android/` 目录，因为 `gradle-wrapper.jar`、图标等二进制文件必须由
Flutter 按你本机的版本生成）。**推荐做法：先生成骨架，再把源码拷进去**（顺序明确，不会有覆盖问题）：

```bash
# 1) 在任意空目录里生成一个标准 Flutter 工程骨架（只生成 android 平台）
flutter create --project-name texas_holdem_trainer --org com.example.pokertrainer --platforms=android holdem_app

# 2) 用交付源码替换骨架里的对应内容
#    - 删除 holdem_app/lib 目录，把交付包里的 lib/ 整个复制过去
#    - 用交付包里的 pubspec.yaml、analysis_options.yaml 覆盖同名文件
#    - 把交付包里的 test/、tool/ 复制过去（可选，用于跑测试/自检）
#    Windows 示例（PowerShell，在交付包目录下执行）：
#      Remove-Item -Recurse -Force ..\holdem_app\lib
#      Copy-Item -Recurse .\lib ..\holdem_app\lib
#      Copy-Item -Force .\pubspec.yaml, .\analysis_options.yaml ..\holdem_app\
#      Copy-Item -Recurse -Force .\test, .\tool ..\holdem_app\

# 3) 进入工程目录
cd holdem_app
```

> **快捷做法（可选）**：也可以在交付目录里直接执行
> `flutter create --project-name texas_holdem_trainer --org com.example.pokertrainer --platforms=android .`
> 它会补上 `android/` 等平台文件；此时若提示 `existing file, skipping`（表示 `lib/`、`pubspec.yaml` 被保留）
> 就符合预期。但为稳妥起见，建议先备份 `lib/`，或直接用上面的推荐做法。

平台工程生成后，**包名（applicationId）** 由 `--org` 决定（形如
`com.example.pokertrainer.texas_holdem_trainer`），可在 `android/app/build.gradle`（或 `.kts`）里改成你自己的。

### 4.2 云构建：用 GitHub Actions 直接产出 APK（本地无需装任何环境）

仓库里已经放好了工作流文件 **`.github/workflows/build-apk.yml`**，它会在云端自动完成
「装 JDK/Flutter → 生成 Android 平台工程 → 拷入本仓库源码 → 打包 Release APK → 上传产物」。
你只需要把代码推到 GitHub，然后下载 APK。

**第 1 步：在 GitHub 上建一个空仓库**

打开 <https://github.com/new>，填仓库名（例如 `texas-holdem-trainer`），
**不要**勾选 "Add a README file"（避免和本地文件冲突），创建后复制仓库地址。

**第 2 步：把交付包推上去**

```bash
cd texas_holdem_trainer
git init
git add .
git commit -m "德州扑克人机对战训练器（含胜率计算器）"
git branch -M main
git remote add origin https://github.com/<你的用户名>/texas-holdem-trainer.git
git push -u origin main
```

**第 3 步：等云端构建（或手动触发）**

* 推送后会自动开始构建：仓库页面 → **Actions** 标签 → 点进 `构建安卓 APK` 这一次运行。
* 想手动再跑一次：**Actions** → 左侧选 `构建安卓 APK` → 右侧 **Run workflow** → 选择分支 → 运行。
* 首次构建约 3～6 分钟（要下载 Flutter SDK 与 Gradle 依赖，缓存后第二次会快很多）。

**第 4 步：下载并安装**

在该次运行的页面底部 **Artifacts** 区域下载 `texas-holdem-trainer-apk`（一个 zip），
解压得到 `app-release.apk`，传到手机点击安装（允许"安装未知应用"）即可。

几点说明：

| 事项 | 说明 |
| --- | --- |
| 工作流为什么先 `flutter create` | 交付包不含 `android/` 目录（Gradle wrapper、图标等二进制要由 Flutter 生成），所以 CI 里先生成标准 Android 工程，再把 `lib/ test/ pubspec.yaml` 拷进去，产物在 runner 的 `ci_app/` 里，不会污染你的仓库 |
| `flutter analyze` / `flutter test` | 已设为 `continue-on-error: true`，只作为提示，**不会因为一个 lint 或测试提示导致拿不到 APK** |
| 签名 | 未配置签名时等于用 debug 密钥签名，**可以直接安装**，仅供自己训练使用；要正式签名请在 `android/app/build.gradle` 里配置 keystore（并把密钥放进 GitHub Secrets） |
| 体积 | 默认产出通用 APK（所有机型可用）。想要更小体积，把工作流里的 `flutter build apk --release` 改成 `flutter build apk --release --split-per-abi`，会产出 3 个分 ABI 的 APK |
| 版本与 JDK | 工作流用最新 stable Flutter + JDK 17；若日志报 Java 版本问题，把 `java-version` 改成 `'21'`；想固定 Flutter 版本，在 `subosito/flutter-action` 里加 `flutter-version: '3.24.5'` |
| 私有仓库额度 | 公开仓库 Actions 免费不限量；私有仓库每月有免费额度（Linux 约 2000 分钟），一次构建几分钟，足够用 |
| Artifacts 有效期 | 默认保留 30 天（文件里写的是 `retention-days: 30`），过期后重新跑一次即可 |
| 产物在哪 | `ci_app/build/app/outputs/flutter-apk/app-release.apk`（工作流最后一步已自动上传为 artifact） |

> 更省事的替代方案：**Codemagic** <https://codemagic.io/> 之类的托管 CI，连 YAML 都不用写，
> 授权 GitHub 仓库后选 Flutter 模板即可出包（有免费额度）。

### 4.3 拉依赖 & 静态检查 & 单测

```bash
flutter pub get
flutter analyze          # 可选：静态检查（应当 0 error）
flutter test             # 可选：牌力评估 / 范围 / 胜率单元测试
```

本项目**没有任何第三方依赖**，`pub get` 只需要 Flutter SDK 自带的内容。

### 4.4 真机/模拟器直接运行

```bash
flutter devices            # 确认设备已连接
flutter run                # 调试运行（热重载）
```

### 4.5 打包 Release APK

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk

# 想减小体积可以按 ABI 拆分：
flutter build apk --release --split-per-abi
# 产物：app-armeabi-v7a-release.apk / app-arm64-v8a-release.apk / app-x86_64-release.apk
```

> 未配置签名时，Flutter 会用 debug 签名打包 release APK，**可以直接安装**，
> 但只适合自己训练使用（不能上架）。要正式签名就在
> `android/app/build.gradle` 里配置 `signingConfigs` 与 keystore。

---

## 5. 安装到安卓手机

**A. 数据线 + adb（推荐）**

```bash
# 手机：设置 → 关于手机 → 连续点击"版本号"7 次开启开发者选项
#       开发者选项 → 打开"USB 调试"，用数据线连电脑并允许调试授权
adb devices                # 应能看到你的设备序列号
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

或者直接：

```bash
flutter install            # 安装到当前唯一设备
flutter run --release      # 直接装并启动
```

**B. 不用数据线（APK 拷贝）**

1. 把 `app-release.apk` 通过微信/USB/网盘传到手机；
2. 手机上用文件管理器点开该 APK；
3. 按提示允许"安装未知应用"（设置 → 应用 → 特殊权限 → 安装未知应用）；
4. 安装完成后桌面会出现「德州扑克人机对战」图标。

> 应用不申请任何权限（不联网、不读存储、不读通讯录），
> 若系统提示"未知来源应用"，只是因为没有走应用商店，属于正常现象。

**C. 模拟器**

Android Studio 里创建 AVD 后 `flutter run` 即可；竖屏布局在 1080×1920 的模拟器上显示效果与真机一致。

---

## 6. 玩法与界面

```
┌───────────────────────────────┐
│ 第 N 手 · 盲注 10/20    ?  ↻   │  顶部状态栏
├───────────────────────────────┤
│ 电脑 AI   1000 筹码   [▨][▨]  │  电脑底牌区（摊牌前牌背）
├───────────────────────────────┤
│ 翻牌圈            底池 120     │
│  [A♠][K♥][7♦][ ][ ]           │  桌面公共牌区
├───────────────────────────────┤
│ 你        1000 筹码   [Q♠][J♠]│  玩家底牌区
├───────────────────────────────┤
│ 弃牌 │ 跟注 20 │ 加注到 60 │全下│  操作按钮区
│ ────────●──────────           │  加注滑杆
│  ½池   ¾池   底池              │  快捷比例
├───────────────────────────────┤
│ 实时胜率  蒙特卡洛 20000 次·14ms│
│ 我方胜 62.4%  平局 1.2%  对手 36.4%│
│ ███████████████░░░░░░          │  堆叠胜率条
│ 可能成型的牌型：一对 42.1% 两对 30% 顺子 8.4% ...│
│ 听牌与补牌：当前牌型 一对 / 同花听牌（9 张补牌）│
│ 对手范围：约 25% 起手牌（常规） │
│ 行动日志：…                     │  独立信息面板（可滚动）
└───────────────────────────────┘
```

* 右上角 `?` 是玩法与胜率说明，`↻` 是重新开始（筹码重置为 1000）。
* 面板里的"计算中…"表示后台 isolate 正在跑模拟，界面不会卡住。

### 规则细节（已按标准单挑规则实现）

* **行动顺序**：翻牌前按钮位/小盲先行动，翻牌后大盲（非按钮）先行动；大盲在翻牌前始终保留"加注选择权"。
* **最小加注**：最小加注到 = 当前注额 + 上一次完整加注幅度；筹码不足时全下即"不足额加注"。
* **不足额全下**：不算完整加注，不会重新开启下注轮（对手若已行动过，只需要补齐跟注或弃牌）。
* **一方全下后**：另一方只能跟注或弃牌（加注无从被跟，按钮会被禁用）。
* **未跟注的下注**：结算前自动退回（弃牌结算与摊牌结算都会退回），因此日志里的底池金额是真实可争夺的筹码。
* **平分底池**：奇数筹码不会丢失（余 1 枚给其中一方，另一方拿剩余）。

---

## 7. 算法自检（可选）

因为胜率模块是纯计算，仓库里附带了三份**同算法的 JS 参考实现**，不装 Flutter 也能核对数值
（它们只用于验证，不参与 App 运行）：

```bash
node tool/logic_reference_check.js          # 35 项断言：牌型评估 / 范围 / 胜率 / 下注引擎压力测试
node tool/evaluator_bruteforce_check.js     # 20 万手随机 7 张牌，与暴力枚举交叉验证
node tool/ai_decision_fuzz_check.js         # 30 万个随机局面，检查 AI 决策是否始终合法
```

`logic_reference_check.js` 覆盖：牌型大小顺序与踢脚、轮子顺、同花听牌与补牌、Chen 范围过滤、
蒙特卡洛胜率、精确枚举路径，以及 **2000 手随机对局的筹码守恒与收敛性压力测试**（每时每刻筹码守恒、
无负筹码、无死循环）。

`evaluator_bruteforce_check.js` 用一份独立编写的 5 张牌评估器，对 20 万手随机 7 张牌做
`C(7,5)=21` 种组合的暴力取最优，与项目的评估器逐位比较。本机实测：**不一致 0 手**，
牌型分布也与公开的 7 张牌成牌频率一致：

`ai_decision_fuzz_check.js` 在 30 万个随机局面（随机筹码、随机底池、随机最小加注额）下检查 AI 返回的
动作与金额：**非法动作 0 个**，动作分布为 过牌 34% / 跟注 25% / 下注或加注 24% / 弃牌 8% / 全下 8%。

| 牌型 | 理论频率 | 实测（20 万手） |
| --- | --- | --- |
| 同花顺 | 0.031% | 0.034% |
| 四条 | 0.168% | 0.176% |
| 葫芦 | 2.60% | 2.662% |
| 同花 | 3.03% | 3.018% |
| 顺子 | 4.62% | 4.607% |
| 三条 | 4.83% | 4.862% |
| 两对 | 23.5% | 23.388% |
| 一对 | 43.8% | 43.938% |
| 高牌 | 17.4% | 17.316% |

胜率基准对照（对手为随机牌，200 万次模拟）：

| 手牌 | 胜 | 平 | 负 | 权益 |
| --- | --- | --- | --- | --- |
| AA | 84.94% | 0.54% | 14.52% | **85.21%** |
| KK | 82.12% | 0.55% | 17.32% | **82.40%** |
| AKs | 66.21% | 1.65% | 32.13% | **67.04%** |
| 72o | 31.72% | 5.75% | 62.52% | **34.60%** |
| 22 | 49.36% | 1.88% | 48.76% | **50.30%** |

（与公开基准值一致：AA≈85.2%、KK≈82.4%、AKs≈67%、72o≈34.6%、22≈50.3%。）

性能参考：翻牌圈 20,000 次模拟（含 45% 范围）≈ 12 ms，翻牌前 25,000 次 ≈ 16 ms（桌面 CPU），
手机上会慢一些，但因为跑在后台 isolate，界面依然流畅。

---

## 8. 常见问题

| 现象 | 处理 |
| --- | --- |
| `flutter create` 提示 existing file | 正常：`lib/` 等被保留，平台文件已补齐 |
| `Gradle task assembleDebug failed` / 卡在下载 | 首次编译要下 Gradle 与依赖，需要网络；可配置 Gradle 国内镜像（改 `android/gradle/wrapper/gradle-wrapper.properties` 的 distributionUrl） |
| `Unsupported class file major version` | JDK 版本不匹配，装 JDK 17 并 `flutter config --jdk-dir <路径>` |
| 设备不识别 | `flutter doctor`、`adb kill-server && adb start-server`、手机上确认"允许 USB 调试" |
| 想改成 6 人桌 / 换盲注 | `GameController(smallBlind:, bigBlind:, startingStack:)` 是构造参数；加人需要扩展 `game_controller.dart` 的轮转逻辑 |
| 想调胜率精度 | `EquityCalculator.recommendedIterations(boardCount)` 与 `GameController._computeAiEquity()` 里的 `iterations` |
| 想换对手范围模型 | 只改 `engine/hand_range.dart`，或在 `GameController` 里传入别的 `villainCombos` |

---

## 9. 合规说明

* 不含任何真实货币、充值、支付、广告、登录、统计 SDK；
* 不联网、不上传数据，所有牌局与计算都在手机本地完成；
* 筹码为纯虚拟数字，仅用于练习决策（pot odds / 胜率 / 范围思维）。
