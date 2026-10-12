/*
 * 电脑决策合法性模糊测试：把 AiPlayer.decide 的 Dart 逻辑移植成 JS，
 * 在 30 万个随机局面下检查它返回的动作 / 金额永远是合法的。
 * （随项目一起提供，便于在没有 Dart/Flutter 的环境下核对 AI 决策是否始终合法。）
 */
const fs = require('fs');
const path = require('path');
eval(fs.readFileSync(path.join(__dirname, 'logic_reference_check.js'), 'utf8').split('// --------------------------- 断言')[0]);

function mulberry32b(seed) {
  let t = seed >>> 0;
  return function () {
    t = (t + 0x6D2B79F5) >>> 0;
    let x = Math.imul(t ^ (t >>> 15), 1 | t);
    x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x;
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

// 与 lib/ai/ai_player.dart 一一对应的移植
function decide(ctx, equity, rnd, aggression) {
  const base = equity < 0 ? 0 : equity > 1 ? 1 : equity;
  const jitter = (rnd() - 0.5) * 0.1 * aggression;
  let adjusted = base + jitter;
  adjusted = Math.max(0, Math.min(1, adjusted));
  const potOdds = ctx.toCall === 0 ? 0 : ctx.toCall / (ctx.pot + ctx.toCall);

  const raiseTarget = (fraction) => {
    const callLevel = ctx.myCommitted + ctx.toCall;
    const potAfterCall = ctx.pot + ctx.toCall;
    let target = callLevel + Math.round(potAfterCall * fraction);
    if (target < ctx.minRaiseTo) target = ctx.minRaiseTo;
    if (target > ctx.maxRaiseTo) target = ctx.maxRaiseTo;
    return target;
  };
  const canRaise = ctx.myStack > ctx.toCall && !ctx.opponentAllIn;
  const canCheck = ctx.toCall === 0;

  if (adjusted >= 0.86 && canRaise) {
    const target = raiseTarget(1.0);
    return { action: target >= ctx.maxRaiseTo ? 'allin' : canCheck ? 'bet' : 'raise', amount: target };
  }
  if (adjusted >= 0.72 && canRaise) {
    const target = raiseTarget(0.7);
    return { action: target >= ctx.maxRaiseTo ? 'allin' : canCheck ? 'bet' : 'raise', amount: target };
  }
  if (canCheck) {
    const bluff = adjusted < 0.4 && canRaise && ctx.pot >= ctx.bigBlind * 2 && rnd() < 0.12 * aggression;
    if (bluff) {
      const target = raiseTarget(0.5);
      if (target > ctx.myCommitted) {
        return { action: target >= ctx.maxRaiseTo ? 'allin' : 'bet', amount: target };
      }
    }
    return { action: 'check', amount: 0 };
  }
  const raiseForValue = canRaise && adjusted >= potOdds + 0.08 && adjusted > 0.55 && rnd() < 0.35 * aggression;
  if (raiseForValue) {
    const target = raiseTarget(0.8);
    return { action: target >= ctx.maxRaiseTo ? 'allin' : 'raise', amount: target };
  }
  if (adjusted >= potOdds + 0.02) return { action: 'call', amount: 0 };
  if (ctx.toCall <= ctx.myStack * 0.04 && rnd() < 0.5) return { action: 'call', amount: 0 };
  return { action: 'fold', amount: 0 };
}

const rnd = mulberry32b(4242);
const N = 300000;
let bad = 0;
let shortCall = 0;
const problems = [];
const actionCount = {};

for (let i = 0; i < N; i++) {
  const bigBlind = 20;
  const myStack = Math.floor(rnd() * 2000);
  const myCommitted = Math.floor(rnd() * 300);
  const opponentCommitted = Math.floor(rnd() * 300);
  const currentBet = Math.max(myCommitted, opponentCommitted);
  const lastRaiseSize = 20 + Math.floor(rnd() * 200);
  const allInTo = myStack + myCommitted;
  const minRaiseTo = currentBet === 0 ? Math.min(bigBlind, allInTo) : Math.min(currentBet + lastRaiseSize, allInTo);
  const maxRaiseTo = allInTo;
  const toCall = Math.max(0, opponentCommitted - myCommitted);
  const ctx = {
    street: Math.floor(rnd() * 4),
    pot: myCommitted + opponentCommitted + Math.floor(rnd() * 500),
    toCall,
    myStack,
    myCommitted,
    bigBlind,
    minRaiseTo,
    maxRaiseTo,
    // 约 1/5 的局面里对手已经全下（此时不允许加注，只能跟注或弃牌）
    opponentAllIn: rnd() < 0.2,
  };
  const decision = decide(ctx, rnd(), rnd, 1.0);
  actionCount[decision.action] = (actionCount[decision.action] || 0) + 1;

  const legalTarget = decision.amount >= minRaiseTo && decision.amount <= maxRaiseTo;
  let why = null;
  if (decision.action === 'check' && toCall !== 0) why = 'toCall != 0 时过牌';
  if (decision.action === 'call' && toCall === 0) why = 'toCall == 0 时跟注';
  if (decision.action === 'call' && toCall > myStack) shortCall++; // 合法：筹码不足时跟注全下
  if (decision.action === 'bet' && (toCall !== 0 || !legalTarget)) {
    why = '下注非法 target=' + decision.amount + ' [' + minRaiseTo + ',' + maxRaiseTo + ']';
  }
  if (decision.action === 'raise' && (toCall === 0 || !legalTarget)) {
    why = '加注非法 target=' + decision.amount + ' [' + minRaiseTo + ',' + maxRaiseTo + ']';
  }
  if (decision.action === 'allin' && maxRaiseTo <= myCommitted) why = '筹码为 0 时全下';
  if (['fold', 'check', 'call', 'bet', 'raise', 'allin'].indexOf(decision.action) < 0) why = '未知动作';
  if (why) {
    bad++;
    if (problems.length < 5) problems.push(why + ' | ' + JSON.stringify(ctx));
  }
}

console.log('电脑决策模糊测试：' + N + ' 个随机局面，非法动作 ' + bad + ' 个');
console.log('  其中「筹码不足时跟注（控制器会截断为全下跟注）」的合法情况：' + shortCall + ' 次');
Object.keys(actionCount).sort((a, b) => actionCount[b] - actionCount[a]).forEach((k) => {
  console.log('  ' + k.padEnd(6) + ' ' + actionCount[k]);
});
problems.forEach((p) => console.log('  x ' + p));
console.log(bad === 0 ? '\n结论：AI 返回的动作与金额在所有随机局面下都合法。' : '\n结论：存在非法动作，需要修复！');
process.exit(bad === 0 ? 0 : 1);
