/*
 * 交叉验证：用"独立的 5 张牌暴力评估器"去核对 7 张牌评估器。
 * 对 20 万手随机 7 张牌，比较「直接评估」与「C(7,5)=21 种组合暴力取最优」的结果是否完全一致，
 * 并打印牌型分布与公开的 7 张牌成牌频率做对照。
 *
 * 用法：node tool/evaluator_bruteforce_check.js
 */
const fs = require('fs');
const path = require('path');

// 复用同目录下的参考实现（只取工具函数部分，跳过其中的断言）。
const src = fs.readFileSync(path.join(__dirname, 'logic_reference_check.js'), 'utf8');
eval(src.split('// --------------------------- 断言')[0]);

// ---- 独立实现的 5 张牌评估器：返回可比较的数组 [类别, 踢脚...] ----
function eval5(cs) {
  const ranks = cs.map(rankOf).sort((a, b) => b - a);
  const flush = cs.every((c) => suitOf(c) === suitOf(cs[0]));
  const counts = new Map();
  for (const r of ranks) counts.set(r, (counts.get(r) || 0) + 1);
  const groups = [...counts.entries()].map(([r, n]) => [r, n]);
  groups.sort((a, b) => b[1] - a[1] || b[0] - a[0]);
  const uniq = [...new Set(ranks)].sort((a, b) => b - a);

  let straightHigh = -1;
  if (uniq.length === 5) {
    if (uniq[0] - uniq[4] === 4) straightHigh = uniq[0];
    else if (uniq[0] === 12 && uniq[1] === 3) straightHigh = 3; // A,5,4,3,2
  }
  if (flush && straightHigh >= 0) return [8, straightHigh];
  if (groups[0][1] === 4) return [7, groups[0][0], groups[1][0]];
  if (groups[0][1] === 3 && groups[1][1] === 2) return [6, groups[0][0], groups[1][0]];
  if (flush) return [5].concat(ranks);
  if (straightHigh >= 0) return [4, straightHigh];
  if (groups[0][1] === 3) return [3, groups[0][0], groups[1][0], groups[2][0]];
  if (groups[0][1] === 2 && groups[1][1] === 2) return [2, groups[0][0], groups[1][0], groups[2][0]];
  if (groups[0][1] === 2) return [1, groups[0][0], groups[1][0], groups[2][0], groups[3][0]];
  return [0].concat(ranks);
}

function compareTuples(a, b) {
  const n = Math.max(a.length, b.length);
  for (let i = 0; i < n; i++) {
    const x = a[i] === undefined ? 0 : a[i];
    const y = b[i] === undefined ? 0 : b[i];
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

function pad(t) {
  const out = t.slice();
  while (out.length < 6) out.push(0);
  return out.slice(0, 6);
}

const combosOf5 = (() => {
  const list = [];
  for (let a = 0; a < 7; a++)
    for (let b = a + 1; b < 7; b++)
      for (let c = b + 1; c < 7; c++)
        for (let d = c + 1; d < 7; d++)
          for (let e = d + 1; e < 7; e++) list.push([a, b, c, d, e]);
  return list;
})();

function bruteForce7(cards7) {
  let best = null;
  for (const idx of combosOf5) {
    const t = eval5(idx.map((i) => cards7[i]));
    if (best === null || compareTuples(t, best) > 0) best = t;
  }
  return best;
}

function directTuple(cards7) {
  const score = evaluate(cards7);
  return [
    categoryOf(score),
    tiebreakerOf(score, 0),
    tiebreakerOf(score, 1),
    tiebreakerOf(score, 2),
    tiebreakerOf(score, 3),
    tiebreakerOf(score, 4),
  ];
}

const rnd = mulberry32(20240607);
const N = 200000;
const catNames = ['高牌', '一对', '两对', '三条', '顺子', '同花', '葫芦', '四条', '同花顺'];
const catCount = new Array(9).fill(0);
let mismatch = 0;
const examples = [];

for (let iter = 0; iter < N; iter++) {
  const deck = fullDeck();
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    const t = deck[i]; deck[i] = deck[j]; deck[j] = t;
  }
  const hand = deck.slice(0, 7);
  const direct = directTuple(hand);
  const brute = pad(bruteForce7(hand));
  catCount[direct[0]]++;
  if (compareTuples(direct, brute) !== 0) {
    mismatch++;
    if (examples.length < 5) {
      examples.push(
        `${hand.map(label).join(' ')} 直接=${catNames[direct[0]]}${direct.slice(1)} 暴力=${catNames[brute[0]]}${brute.slice(1)}`
      );
    }
  }
}

console.log(`随机 7 张牌交叉验证：${N} 手，不一致 ${mismatch} 手`);
if (examples.length) examples.forEach((e) => console.log('  ' + e));
console.log('牌型分布（直接评估器）：');
for (let i = 8; i >= 0; i--) {
  const pct = ((catCount[i] / N) * 100).toFixed(3);
  console.log(`  ${catNames[i]}  ${String(catCount[i]).padStart(7)}  ${pct}%`);
}
console.log(mismatch === 0 ? '\n结论：7 张取最优 5 张的实现与暴力枚举完全一致。' : '\n结论：存在不一致，需要修复！');
process.exit(mismatch === 0 ? 0 : 1);
