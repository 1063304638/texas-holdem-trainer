/*
 * 校验脚本（不属于交付物，仅用于在没有 Dart/Flutter 的环境下验证算法逻辑）。
 * 这里把 Dart 侧的纯逻辑（牌力评估、局面分析、蒙特卡洛胜率、下注引擎）逐行移植成 JS，
 * 用 Node 跑一遍数值与流程断言。
 */

// ------------------------------ Cards ------------------------------
const RANK_NAMES = ['2','3','4','5','6','7','8','9','T','J','Q','K','A'];
function make(rank, suit) { return rank * 4 + suit; }
function rankOf(c) { return c >> 2; }
function suitOf(c) { return c & 3; }
function label(c) { return RANK_NAMES[rankOf(c)] + ['s','h','d','c'][suitOf(c)]; }
function fullDeck() { const d = []; for (let i = 0; i < 52; i++) d.push(i); return d; }

// --------------------------- HandEvaluator ---------------------------
const CAT_SHIFT = 20;
function pack(cat, t0, t1, t2, t3, t4) {
  return (cat << CAT_SHIFT) | ((t0 & 0xF) << 16) | ((t1 & 0xF) << 12) | ((t2 & 0xF) << 8) | ((t3 & 0xF) << 4) | (t4 & 0xF);
}
function categoryOf(score) { return score >> CAT_SHIFT; }
function tiebreakerOf(score, i) { return (score >> (16 - 4 * i)) & 0xF; }

function straightHigh(mask) {
  for (let high = 12; high >= 4; high--) {
    const need = 0x1F << (high - 4);
    if ((mask & need) === need) return high;
  }
  const wheel = (1 << 12) | 0x0F;
  if ((mask & wheel) === wheel) return 3;
  return -1;
}
function bestKicker(rankCount, e1, e2, e3) {
  for (let r = 12; r >= 0; r--) {
    if (r === e1 || r === e2 || r === e3) continue;
    if (rankCount[r] > 0) return r;
  }
  return 0;
}
function evaluate(cards) {
  const rankCount = new Array(13).fill(0);
  const suitCount = new Array(4).fill(0);
  const suitRankMask = new Array(4).fill(0);
  let rankMask = 0;
  for (const card of cards) {
    const r = card >> 2, s = card & 3;
    rankCount[r]++; suitCount[s]++; suitRankMask[s] |= 1 << r; rankMask |= 1 << r;
  }
  let flushSuit = -1;
  for (let s = 0; s < 4; s++) if (suitCount[s] >= 5) flushSuit = s;
  if (flushSuit >= 0) {
    const sf = straightHigh(suitRankMask[flushSuit]);
    if (sf >= 0) return pack(8, sf, 0, 0, 0, 0);
  }
  for (let r = 12; r >= 0; r--) {
    if (rankCount[r] === 4) return pack(7, r, bestKicker(rankCount, r, -1, -1), 0, 0, 0);
  }
  let trips1 = -1, trips2 = -1, pair1 = -1, pair2 = -1;
  for (let r = 12; r >= 0; r--) {
    const c = rankCount[r];
    if (c >= 3) { if (trips1 < 0) trips1 = r; else if (trips2 < 0) trips2 = r; }
    else if (c === 2) { if (pair1 < 0) pair1 = r; else if (pair2 < 0) pair2 = r; }
  }
  if (trips1 >= 0 && (pair1 >= 0 || trips2 >= 0)) {
    const pr = trips2 >= 0 ? trips2 : pair1;
    return pack(6, trips1, pr, 0, 0, 0);
  }
  if (flushSuit >= 0) {
    const mask = suitRankMask[flushSuit];
    const top = [];
    for (let r = 12; r >= 0 && top.length < 5; r--) if ((mask & (1 << r)) !== 0) top.push(r);
    while (top.length < 5) top.push(0);
    return pack(5, top[0], top[1], top[2], top[3], top[4]);
  }
  const sh = straightHigh(rankMask);
  if (sh >= 0) return pack(4, sh, 0, 0, 0, 0);
  if (trips1 >= 0) {
    const k1 = bestKicker(rankCount, trips1, -1, -1);
    const k2 = bestKicker(rankCount, trips1, k1, -1);
    return pack(3, trips1, k1, k2, 0, 0);
  }
  if (pair1 >= 0 && pair2 >= 0) {
    const k = bestKicker(rankCount, pair1, pair2, -1);
    return pack(2, pair1, pair2, k, 0, 0);
  }
  if (pair1 >= 0) {
    const k1 = bestKicker(rankCount, pair1, -1, -1);
    const k2 = bestKicker(rankCount, pair1, k1, -1);
    const k3 = bestKicker(rankCount, pair1, k1, k2);
    return pack(1, pair1, k1, k2, k3, 0);
  }
  const top = [];
  for (let r = 12; r >= 0 && top.length < 5; r--) if (rankCount[r] > 0) top.push(r);
  while (top.length < 5) top.push(0);
  return pack(0, top[0], top[1], top[2], top[3], top[4]);
}
function describe(score) {
  const cat = categoryOf(score);
  const t0 = RANK_NAMES[tiebreakerOf(score, 0)] || '-';
  const t1 = RANK_NAMES[tiebreakerOf(score, 1)] || '-';
  switch (cat) {
    case 8: return tiebreakerOf(score, 0) === 12 ? '皇家同花顺' : `同花顺（${t0} 高）`;
    case 7: return `四条（${t0}）`;
    case 6: return `葫芦（${t0} 带 ${t1}）`;
    case 5: return `同花（${t0} 高）`;
    case 4: return `顺子（${t0} 高）`;
    case 3: return `三条（${t0}）`;
    case 2: return `两对（${t0} 与 ${t1}）`;
    case 1: return `一对（${t0}）`;
    default: return `高牌（${t0}）`;
  }
}

// --------------------------- HandAnalyzer ---------------------------
function unseenCards(known) {
  const out = [];
  for (let c = 0; c < 52; c++) if (!known.includes(c)) out.push(c);
  return out;
}
function achievableCategories(hole, board) {
  const need = 5 - board.length;
  const result = new Set();
  if (need >= 3) {
    for (let i = 0; i < 9; i++) result.add(i);
  } else {
    const known = [...hole, ...board];
    const unseen = unseenCards(known);
    if (need <= 0) {
      result.add(categoryOf(evaluate(known)));
    } else if (need === 1) {
      for (const c of unseen) result.add(categoryOf(evaluate([...known, c])));
    } else {
      for (let i = 0; i < unseen.length; i++) {
        for (let j = i + 1; j < unseen.length; j++) {
          result.add(categoryOf(evaluate([...known, unseen[i], unseen[j]])));
        }
      }
    }
  }
  return [...result].sort((a, b) => a - b);
}
function analyze(hole, board) {
  const known = [...hole, ...board];
  const madeScore = evaluate(known);
  const made = categoryOf(madeScore);
  const unseen = unseenCards(known);
  const outsByCategory = new Array(9).fill(0);
  if (board.length < 5) {
    for (const c of unseen) {
      const cat = categoryOf(evaluate([...known, c]));
      if (cat > made) outsByCategory[cat]++;
    }
  }
  const outs = [];
  for (let i = 8; i >= 0; i--) if (outsByCategory[i] > 0) outs.push({ category: i, outs: outsByCategory[i] });
  outs.sort((a, b) => b.outs - a.outs);

  const tags = [];
  if (board.length < 5) {
    const suitCount = new Array(4).fill(0);
    for (const c of known) suitCount[suitOf(c)]++;
    for (let s = 0; s < 4; s++) {
      if (suitCount[s] === 4) {
        let live = 0;
        for (let r = 0; r < 13; r++) if (!known.includes(make(r, s))) live++;
        tags.push(`同花听牌（${live} 张补牌）`);
      }
    }
    const completing = new Set();
    for (const c of unseen) {
      const cat = categoryOf(evaluate([...known, c]));
      if (cat === 4 || cat === 8) completing.add(rankOf(c));
    }
    if (completing.size >= 2) tags.push(`顺子听牌（${completing.size} 种点数可成顺）`);
    else if (completing.size === 1) tags.push('卡顺听牌（仅 1 种点数可成顺）');
  }
  return { made, madeScore, outs, tags, totalOuts: outs.reduce((a, b) => a + b.outs, 0) };
}

// --------------------------- HandRange ---------------------------
function chenScore(a, b) {
  const r1 = rankOf(a), r2 = rankOf(b);
  const suited = suitOf(a) === suitOf(b);
  const hi = Math.max(r1, r2), lo = Math.min(r1, r2);
  let score;
  if (hi === 12) score = 10; else if (hi === 11) score = 8; else if (hi === 10) score = 7; else if (hi === 9) score = 6;
  else score = (hi + 2) / 2;
  if (hi === lo) { score *= 2; return score < 5 ? 5 : score; }
  if (suited) score += 2;
  const gap = hi - lo - 1;
  if (gap === 1) score -= 1; else if (gap === 2) score -= 2; else if (gap === 3) score -= 4; else if (gap >= 4) score -= 5;
  if (gap <= 1 && hi < 10) score += 1;
  return score;
}
function rangeCombos(percent, deadCards) {
  const dead = new Set(deadCards);
  const cards = [];
  for (let c = 0; c < 52; c++) if (!dead.has(c)) cards.push(c);
  const all = [];
  for (let i = 0; i < cards.length; i++) {
    for (let j = i + 1; j < cards.length; j++) {
      all.push({ a: cards[i], b: cards[j], score: chenScore(cards[i], cards[j]) });
    }
  }
  all.sort((x, y) => (y.score - x.score) || ((x.a * 52 + x.b) - (y.a * 52 + y.b)));
  const clamped = Math.min(100, Math.max(1, percent));
  let take = Math.round(all.length * clamped / 100);
  take = Math.min(all.length, Math.max(1, take));
  const out = [];
  for (let i = 0; i < take; i++) { out.push(all[i].a); out.push(all[i].b); }
  return out;
}

// --------------------------- EquityCalculator ---------------------------
function mulberry32(seed) {
  let t = seed >>> 0;
  return function () {
    t = (t + 0x6D2B79F5) >>> 0;
    let x = Math.imul(t ^ (t >>> 15), 1 | t);
    x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x;
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}
function equityRun(input) {
  const started = Date.now();
  const board = input.board.slice();
  const known = new Set([input.heroCard1, input.heroCard2, ...board]);
  const deck = [];
  for (let c = 0; c < 52; c++) if (!known.has(c)) deck.push(c);

  let combos = [];
  for (let i = 0; i + 1 < input.villainCombos.length; i += 2) {
    const a = input.villainCombos[i], b = input.villainCombos[i + 1];
    if (a === b || known.has(a) || known.has(b)) continue;
    combos.push(a, b);
  }
  if (combos.length === 0) {
    for (let i = 0; i < deck.length; i++) for (let j = i + 1; j < deck.length; j++) combos.push(deck[i], deck[j]);
  }
  const comboCount = combos.length / 2;

  let heroWins = 0, ties = 0, villainWins = 0;
  const categoryCounts = new Array(9).fill(0);
  const heroSeven = new Array(7).fill(0);
  const villainSeven = new Array(7).fill(0);
  heroSeven[0] = input.heroCard1; heroSeven[1] = input.heroCard2;
  for (let i = 0; i < board.length; i++) { heroSeven[2 + i] = board[i]; villainSeven[2 + i] = board[i]; }
  function tally() {
    const hs = evaluate(heroSeven), vs = evaluate(villainSeven);
    categoryCounts[categoryOf(hs)]++;
    if (hs > vs) heroWins++; else if (hs < vs) villainWins++; else ties++;
  }

  const missing = 5 - board.length;
  let pow = 1;
  for (let i = 0; i < missing; i++) pow *= deck.length;
  const exactIterations = comboCount * (missing === 0 ? 1 : pow);
  const useExact = missing <= 1 && exactIterations <= 400000;

  if (useExact) {
    for (let i = 0; i < combos.length; i += 2) {
      const v1 = combos[i], v2 = combos[i + 1];
      villainSeven[0] = v1; villainSeven[1] = v2;
      if (missing === 0) tally();
      else {
        for (const card of deck) {
          if (card === v1 || card === v2) continue;
          heroSeven[6] = card; villainSeven[6] = card; tally();
        }
      }
    }
  } else {
    const buffer = deck.slice();
    const rnd = mulberry32(input.seed);
    const iterations = input.iterations > 0 ? input.iterations : 20000;
    for (let iter = 0; iter < iterations; iter++) {
      let cursor = 0;
      const pick = Math.floor(rnd() * comboCount) * 2;
      const v1 = combos[pick], v2 = combos[pick + 1];
      villainSeven[0] = v1; villainSeven[1] = v2;
      for (let i = board.length; i < 5; i++) {
        let card;
        do {
          const remaining = buffer.length - cursor;
          const idx = cursor + (remaining <= 0 ? 0 : Math.floor(rnd() * remaining));
          card = buffer[idx]; buffer[idx] = buffer[cursor]; buffer[cursor] = card;
          cursor++;
        } while (card === v1 || card === v2);
        heroSeven[2 + i] = card; villainSeven[2 + i] = card;
      }
      tally();
    }
  }

  const total = heroWins + villainWins + ties;
  const denom = total === 0 ? 1 : total;
  return {
    winRate: heroWins / denom,
    tieRate: ties / denom,
    loseRate: villainWins / denom,
    equity: (heroWins + ties / 2) / denom,
    categoryProbability: categoryCounts.map((c) => c / denom),
    achievableCategories: achievableCategories([input.heroCard1, input.heroCard2], board),
    iterationsRun: total,
    exact: useExact,
    elapsedMs: Date.now() - started,
  };
}

// --------------------------- 下注引擎（镜像 GameController 规则） ---------------------------
function playHands(handCount, seed) {
  const rnd = mulberry32(seed);
  let heroStack = 1000, aiStack = 1000;
  const smallBlind = 10, bigBlind = 20;
  let actionCount = 0;

  for (let hand = 1; hand <= handCount; hand++) {
    if (heroStack < bigBlind || aiStack < bigBlind) { heroStack = 1000; aiStack = 1000; }
    const deck = fullDeck();
    for (let i = deck.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [deck[i], deck[j]] = [deck[j], deck[i]]; }
    const heroCards = [deck.pop(), deck.pop()];
    const aiCards = [deck.pop(), deck.pop()];
    const board = [];
    let street = 0; // 0 preflop 1 flop 2 turn 3 river
    let heroCommitted = 0, aiCommitted = 0, heroTotal = 0, aiTotal = 0;
    let heroFolded = false, aiFolded = false, heroAllIn = false, aiAllIn = false;
    let heroActed = false, aiActed = false, currentBet = bigBlind, lastRaiseSize = bigBlind;
    let handOver = false, result = '';
    const buttonIsHero = hand % 2 === 1;
    let heroToAct = buttonIsHero;

    function postBlind(isHero, amount) {
      if (isHero) { const pay = Math.min(amount, heroStack); heroStack -= pay; heroCommitted += pay; heroTotal += pay; if (heroStack === 0) heroAllIn = true; }
      else { const pay = Math.min(amount, aiStack); aiStack -= pay; aiCommitted += pay; aiTotal += pay; if (aiStack === 0) aiAllIn = true; }
    }
    if (buttonIsHero) { postBlind(true, smallBlind); postBlind(false, bigBlind); }
    else { postBlind(false, smallBlind); postBlind(true, bigBlind); }

    const minRaiseTo = (stack, committed) => {
      const allInTo = stack + committed;
      if (currentBet === 0) return Math.min(bigBlind, allInTo);
      return Math.min(currentBet + lastRaiseSize, allInTo);
    };
    function pot() { return heroTotal + aiTotal; }
    function roundComplete() {
      if (heroFolded || aiFolded) return true;
      const heroDone = heroAllIn || (heroActed && aiCommitted <= heroCommitted);
      const aiDone = aiAllIn || (aiActed && heroCommitted <= aiCommitted);
      return heroDone && aiDone;
    }
    function dealBoard(n) { if (deck.length) deck.pop(); for (let i = 0; i < n && deck.length; i++) board.push(deck.pop()); }
    function showdown() {
      let diff = heroTotal - aiTotal;
      if (diff > 0) { heroStack += diff; heroTotal -= diff; } else if (diff < 0) { aiStack += -diff; aiTotal -= -diff; }
      const p = pot();
      const hs = evaluate([...heroCards, ...board]);
      const as = evaluate([...aiCards, ...board]);
      if (hs > as) { heroStack += p; result = 'hero'; }
      else if (as > hs) { aiStack += p; result = 'ai'; }
      else { const half = Math.floor(p / 2); heroStack += half; aiStack += p - half; result = 'split'; }
      handOver = true;
    }
    function finishByFold() {
      // 先退还未被跟注的多余投入，再分配底池
      const d = heroTotal - aiTotal;
      if (d > 0) { heroStack += d; heroTotal -= d; } else if (d < 0) { aiStack += -d; aiTotal -= -d; }
      const p = pot();
      if (aiFolded) { heroStack += p; result = 'hero(fold)'; } else { aiStack += p; result = 'ai(fold)'; }
      handOver = true;
    }
    function advanceStreet() {
      heroCommitted = 0; aiCommitted = 0; heroActed = false; aiActed = false;
      currentBet = 0; lastRaiseSize = bigBlind;
      if (street === 3) { showdown(); return; }
      street += 1;
      dealBoard(street === 1 ? 3 : 1);
      if (heroAllIn || aiAllIn) {
        while (board.length < 5) { street += 1; dealBoard(1); }
        showdown();
        return;
      }
      heroToAct = !buttonIsHero;
    }
    function applyAction(isHero, type, amount) {
      const currentBetBefore = currentBet;
      const lastRaiseSizeBefore = lastRaiseSize;
      let myCommitted = isHero ? heroCommitted : aiCommitted;
      let myStack = isHero ? heroStack : aiStack;
      const oppCommitted = isHero ? aiCommitted : heroCommitted;
      let paid = 0, allInNow = false, fullRaiseAction = false;
      if (type === 'fold') { if (isHero) heroFolded = true; else aiFolded = true; }
      else if (type === 'check') { /* nothing */ }
      else if (type === 'call') {
        const need = Math.max(0, oppCommitted - myCommitted);
        const pay = Math.min(need, myStack);
        myStack -= pay; myCommitted += pay; paid = pay; allInNow = myStack === 0;
      } else {
        let target = type === 'allin' ? myStack + myCommitted : amount;
        target = Math.min(target, myStack + myCommitted);
        target = Math.max(target, myCommitted);
        const pay = target - myCommitted;
        const raiseSize = target - currentBetBefore;
        const fullRaise = raiseSize >= lastRaiseSizeBefore;
        myStack -= pay; myCommitted = target; paid = pay; allInNow = myStack === 0;
        if (raiseSize > 0) {
          currentBet = target;
          if (fullRaise) lastRaiseSize = raiseSize;
        }
        fullRaiseAction = raiseSize > 0 && fullRaise;
      }
      if (isHero) { heroCommitted = myCommitted; heroStack = myStack; heroTotal += paid; heroAllIn = heroAllIn || allInNow; heroActed = true; }
      else { aiCommitted = myCommitted; aiStack = myStack; aiTotal += paid; aiAllIn = aiAllIn || allInNow; aiActed = true; }
      const aggressive = type === 'bet' || type === 'raise' || type === 'allin';
      const raisedAbove = aggressive && myCommitted > currentBetBefore;
      // 只有"完整加注"才重开下注轮（不足额的全下加注不算）
      if (raisedAbove && fullRaiseAction) { if (isHero) aiActed = false; else heroActed = false; }

      heroToAct = false;
      if (heroFolded || aiFolded) finishByFold();
      else if (roundComplete()) advanceStreet();
      else heroToAct = !isHero;
    }

    // 随机但合法的行动，用于压力测试状态机
    let safety = 0;
    while (!handOver) {
      if (++safety > 200) throw new Error(`第 ${hand} 手下注轮没有收敛（可能死循环）`);
      const isHero = heroToAct;
      const myStack = isHero ? heroStack : aiStack;
      const myCommitted = isHero ? heroCommitted : aiCommitted;
      const oppCommitted = isHero ? aiCommitted : heroCommitted;
      const opponentAllIn = isHero ? aiAllIn : heroAllIn;
      const toCall = Math.max(0, oppCommitted - myCommitted);
      const minTo = minRaiseTo(myStack, myCommitted);
      const maxTo = myStack + myCommitted;
      const canRaise = myStack > toCall && !opponentAllIn; // 对手全下时不允许加注
      const roll = rnd();
      if (toCall === 0) {
        if (canRaise && roll < 0.35) applyAction(isHero, 'raise', Math.min(maxTo, Math.max(minTo, Math.round((pot() + 1) / 2) + myCommitted)));
        else applyAction(isHero, 'check', 0);
      } else if (roll < 0.15) {
        applyAction(isHero, 'fold', 0);
      } else if (roll < 0.55 && canRaise) {
        applyAction(isHero, 'raise', Math.min(maxTo, Math.max(minTo, myCommitted + toCall + Math.round(pot() * 0.6))));
      } else if (roll < 0.95) {
        applyAction(isHero, 'call', 0);
      } else {
        applyAction(isHero, 'allin', maxTo);
      }
      actionCount++;
      // 手牌进行中：筹码必须守恒（未结算的投入都算在底池里）
      const conserved = heroStack + aiStack + heroTotal + aiTotal;
      if (!handOver && conserved !== 2000) {
        throw new Error(`手中筹码不守恒：${heroStack}+${aiStack}+${heroTotal}+${aiTotal}=${conserved}`);
      }
      if (handOver && heroStack + aiStack !== 2000) {
        throw new Error(`结算后筹码不守恒：${heroStack}+${aiStack}=${heroStack + aiStack}`);
      }
    }
    if (heroStack < 0 || aiStack < 0) throw new Error('出现负筹码');
  }
  return { heroStack, aiStack, actionCount };
}

// --------------------------- 断言 ---------------------------
let passed = 0, failed = 0;
function check(name, condition, extra) {
  if (condition) { passed++; console.log(`  ✓ ${name}`); }
  else { failed++; console.log(`  ✗ ${name}${extra !== undefined ? ' -> ' + extra : ''}`); }
}
function card(text) {
  const ranks = { '2':0,'3':1,'4':2,'5':3,'6':4,'7':5,'8':6,'9':7,'T':8,'J':9,'Q':10,'K':11,'A':12 };
  const suits = { s:0, h:1, d:2, c:3 };
  return make(ranks[text[0].toUpperCase()], suits[text[1].toLowerCase()]);
}
function cards(text) { return text.split(' ').filter(Boolean).map(card); }

console.log('== 牌力评估器 ==');
check('皇家同花顺', categoryOf(evaluate(cards('As Ks Qs Js Ts'))) === 8);
check('皇家同花顺描述', describe(evaluate(cards('As Ks Qs Js Ts'))) === '皇家同花顺', describe(evaluate(cards('As Ks Qs Js Ts'))));
check('7 张取最优 5 张', categoryOf(evaluate(cards('As Ks Qs Js Ts 2h 3d'))) === 8);
check('轮子是顺子', categoryOf(evaluate(cards('As 2h 3d 4c 5s'))) === 4);
check('轮子 < 6 高顺子', evaluate(cards('As 2h 3d 4c 5s')) < evaluate(cards('2h 3d 4c 5s 6h')));
check('葫芦 > 同花', evaluate(cards('9h 9d 9c 5s 5h')) > evaluate(cards('Ah Kh 9h 5h 2h')));
check('同花 > 顺子', evaluate(cards('Ah Kh 9h 5h 2h')) > evaluate(cards('9h 8d 7c 6s 5h')));
check('顺子 > 三条', evaluate(cards('9h 8d 7c 6s 5h')) > evaluate(cards('9h 9d 9c Ks 5h')));
check('三条 > 两对', evaluate(cards('9h 9d 9c Ks 5h')) > evaluate(cards('9h 9d 5c 5s Kh')));
check('两对 > 一对', evaluate(cards('9h 9d 5c 5s Kh')) > evaluate(cards('9h 9d Ac Ks 5h')));
check('一对 > 高牌', evaluate(cards('9h 9d Ac Ks 5h')) > evaluate(cards('Ah Kd 9c 7s 5h')));
check('踢脚比较', evaluate(cards('As Ah Kd 9c 4h')) > evaluate(cards('Ac Ad Qd 9s 4c')));
check('A 高同花 > K 高同花', evaluate(cards('As 9s 7s 5s 3s')) > evaluate(cards('Ks 9s 7s 5s 3s')));
check('两对踢脚比较', evaluate(cards('9h 9d 5c 5s Ah')) > evaluate(cards('9s 9c 5h 5d Ks')));
check('三条识别', categoryOf(evaluate(cards('9h 9d 9c Ks 5h'))) === 3);
check('四条识别', categoryOf(evaluate(cards('9h 9d 9c 9s 5h'))) === 7);

console.log('== 局面分析 ==');
check('翻牌前 9 种可能牌型', achievableCategories(cards('As Kh'), []).length === 9);
check('河牌圈只有 1 种', achievableCategories(cards('As Kh'), cards('Qs Js Ts 2d 3c')).length === 1);
const insight = analyze(cards('As Ks'), cards('Qs 7s 2h'));
check('识别同花听牌', insight.tags.some((t) => t.includes('同花听牌')), insight.tags.join('|'));
check('同花听牌 9 张补牌', insight.tags.some((t) => t.includes('9 张补牌')), insight.tags.join('|'));
const insight2 = analyze(cards('9h 8d'), cards('7c 6s 2h'));
check('识别顺子听牌', insight2.tags.some((t) => t.includes('顺子听牌')), insight2.tags.join('|'));
const flopAchievable = achievableCategories(cards('As Ks'), cards('Qs 7s 2h'));
check('翻牌圈可能牌型 >= 5 且含同花', flopAchievable.length >= 5 && flopAchievable.includes(5), flopAchievable.join(','));

console.log('== 范围模型 ==');
const tight = rangeCombos(15, []);
check('15% 范围含 AA', (() => { for (let i = 0; i + 1 < tight.length; i += 2) { if (rankOf(tight[i]) === 12 && rankOf(tight[i + 1]) === 12) return true; } return false; })());
check('15% 范围不含 72o', (() => { for (let i = 0; i + 1 < tight.length; i += 2) { const r = [rankOf(tight[i]), rankOf(tight[i + 1])].sort((a, b) => a - b); if (r[0] === 0 && r[1] === 5) return false; } return true; })());
check('100% 范围 = 1326 组合', rangeCombos(100, []).length / 2 === 1326);
check('剔除已知牌后组合减少', rangeCombos(100, cards('As Ah Kd')).length / 2 === 1176, rangeCombos(100, cards('As Ah Kd')).length / 2);
check('Chen: AA > AKs > 72o', chenScore(card('As'), card('Ah')) > chenScore(card('As'), card('Ks')) && chenScore(card('As'), card('Ks')) > chenScore(card('7s'), card('2h')));

console.log('== 蒙特卡洛胜率 ==');
const aa = equityRun({ heroCard1: card('As'), heroCard2: card('Ah'), board: [], villainCombos: [], iterations: 20000, seed: 7 });
check(`AA vs 随机 ≈ 85%（实测 ${(aa.winRate * 100).toFixed(2)}%）`, aa.winRate > 0.78 && aa.winRate < 0.92);
check('概率之和 = 1', Math.abs(aa.winRate + aa.tieRate + aa.loseRate - 1) < 1e-9);
const aces = cards('As Ah Ad Ac');
const aaCombos = [];
for (let i = 0; i < 4; i++) for (let j = i + 1; j < 4; j++) { aaCombos.push(aces[i]); aaCombos.push(aces[j]); }
const kk = equityRun({ heroCard1: card('Ks'), heroCard2: card('Kh'), board: [], villainCombos: aaCombos, iterations: 20000, seed: 11 });
check(`KK vs AA ≈ 18%（实测 ${(kk.equity * 100).toFixed(2)}%）`, kk.equity > 0.05 && kk.equity < 0.30);
const quads = equityRun({ heroCard1: card('Ah'), heroCard2: card('Ad'), board: cards('As Ac Kh 2d 3c'), villainCombos: [], seed: 3 });
check('河牌四条必胜 + 精确枚举', quads.exact === true && quads.winRate === 1.0, `${quads.winRate} exact=${quads.exact}`);
const turn = equityRun({ heroCard1: card('As'), heroCard2: card('Ks'), board: cards('Qs Js 9s 2h'), villainCombos: [], seed: 5 });
check('转牌精确枚举 & 坚果同花领先', turn.exact === true && turn.winRate > 0.90, `${turn.winRate} exact=${turn.exact} iters=${turn.iterationsRun}`);
check('牌型概率之和 = 1', Math.abs(turn.categoryProbability.reduce((a, b) => a + b, 0) - 1) < 1e-9);
const comboCheck = equityRun({ heroCard1: card('7s'), heroCard2: card('2h'), board: [], villainCombos: [], iterations: 20000, seed: 21 });
check(`72o vs 随机 ≈ 35%（实测 ${(comboCheck.winRate * 100).toFixed(2)}%）`, comboCheck.winRate > 0.28 && comboCheck.winRate < 0.42);

console.log('== 胜率计算性能 ==');
const t0 = Date.now();
equityRun({ heroCard1: card('As'), heroCard2: card('Ks'), board: cards('Qs 7s 2h'), villainCombos: rangeCombos(45, cards('As Ks Qs 7s 2h')), iterations: 20000, seed: 1 });
console.log(`  翻牌圈 20000 次模拟（含范围 45%）耗时 ${Date.now() - t0} ms`);
const t1 = Date.now();
equityRun({ heroCard1: card('As'), heroCard2: card('Ks'), board: [], villainCombos: rangeCombos(45, cards('As Ks')), iterations: 25000, seed: 1 });
console.log(`  翻牌前 25000 次模拟（含范围 45%）耗时 ${Date.now() - t1} ms`);

console.log('== 下注引擎压力测试（2000 手随机对局） ==');
try {
  const sim = playHands(2000, 99);
  check(`2000 手全部收敛，筹码守恒（最终 ${sim.heroStack} / ${sim.aiStack}，共 ${sim.actionCount} 个动作）`, true);
} catch (e) {
  check('2000 手全部收敛，筹码守恒', false, e.message);
}

console.log(`\n结果：通过 ${passed} 项，失败 ${failed} 项`);
process.exit(failed === 0 ? 0 : 1);
