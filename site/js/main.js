// What changed when the rules changed? Scrollytelling interrupted time series.
// Colours live in css/style.css (theme tokens), so the chart follows the light/dark switch.

(function () {
  // ---------------- Theme toggle ----------------
  const root = document.documentElement;
  const toggle = document.getElementById('theme-toggle');
  function syncToggle() {
    const dark = root.getAttribute('data-theme') === 'dark';
    toggle.textContent = dark ? 'Light' : 'Dark';
    toggle.setAttribute('aria-label', dark ? 'Switch to light theme' : 'Switch to dark theme');
  }
  toggle.addEventListener('click', () => {
    const next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('theme', next); } catch (e) { /* storage unavailable: theme still switches */ }
    syncToggle();
  });
  syncToggle();

  // ---------------- Motion ----------------
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let DUR = reduce ? 0 : 900;

  // ---------------- Data ----------------
  // TODO: replace simulateData() with d3.csv('data/its.csv') once the R analysis exports real results.
  function mulberry32(a) {
    return function () {
      a |= 0; a = a + 0x6D2B79F5 | 0;
      let t = Math.imul(a ^ a >>> 15, 1 | a);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }
  function simulateData(N, P) {
    const rand = mulberry32(11);
    const gauss = () => { let u = 0; while (!u) u = rand(); const v = rand(); return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v); };
    return d3.range(N).map(i => {
      const s = Math.sin(2 * Math.PI * i / 12), c = Math.cos(2 * Math.PI * i / 12);
      let y = 100 + 0.35 * i + 3.2 * s + 1.4 * c + gauss() * 1.5;
      if (i >= P) y += -5 - 0.22 * (i - P);
      return { i, date: new Date(2015, 3 + i, 1), y, x: [1, i, s, c] };
    });
  }

  const N = 108, P = 48; // April 2015 to March 2024; change at April 2019
  const data = simulateData(N, P);

  // ---------------- Least squares on the pre-period ----------------
  function invert(M) {
    const n = M.length, A = M.map((r, i) => [...r, ...M.map((_, j) => (i === j ? 1 : 0))]);
    for (let i = 0; i < n; i++) {
      let p = i;
      for (let k = i + 1; k < n; k++) if (Math.abs(A[k][i]) > Math.abs(A[p][i])) p = k;
      [A[i], A[p]] = [A[p], A[i]];
      const d = A[i][i];
      for (let j = 0; j < 2 * n; j++) A[i][j] /= d;
      for (let k = 0; k < n; k++) if (k !== i) { const f = A[k][i]; for (let j = 0; j < 2 * n; j++) A[k][j] -= f * A[i][j]; }
    }
    return A.map(r => r.slice(n));
  }
  const dot = (a, b) => d3.sum(a, (v, j) => v * b[j]);
  const pre = data.slice(0, P), K = 4;
  const XtX = d3.range(K).map(a => d3.range(K).map(b => d3.sum(pre, d => d.x[a] * d.x[b])));
  const XtY = d3.range(K).map(a => d3.sum(pre, d => d.x[a] * d.y));
  const inv = invert(XtX);
  const beta = inv.map(r => dot(r, XtY));
  const sigma = Math.sqrt(d3.sum(pre, d => (d.y - dot(d.x, beta)) ** 2) / (P - K));
  data.forEach(d => {
    d.mu = dot(d.x, beta);
    const se = sigma * Math.sqrt(1 + dot(d.x, inv.map(r => dot(r, d.x))));
    d.lo = d.mu - 1.96 * se; d.hi = d.mu + 1.96 * se;
  });

  const post = data.slice(P);
  const pct = 100 * d3.sum(post, d => d.y - d.mu) / d3.sum(post, d => d.mu);
  const pctLast = 100 * d3.mean(post.slice(-12), d => (d.y - d.mu) / d.mu);
  const fmt = v => Math.abs(v).toFixed(0);
  document.getElementById('effect-text').innerHTML =
    `Over five years, about <span class="hl">${fmt(pct)}% fewer items</span> were dispensed than expected. By the final year the gap was ${fmt(pctLast)}%.`;

  // Placeholder quintile estimates (% change vs expected, 95% CI)
  const quint = [
    { q: '1 · most deprived', v: -15.8, lo: -19.6, hi: -12.0 },
    { q: '2', v: -12.4, lo: -16.1, hi: -8.7 },
    { q: '3', v: -10.1, lo: -13.9, hi: -6.3 },
    { q: '4', v: -7.6, lo: -11.5, hi: -3.7 },
    { q: '5 · least deprived', v: -5.2, lo: -9.2, hi: -1.2 }
  ];

  const heads = [
    ['Prescribing was rising steadily', 'Items dispensed per month, index (April 2015 = 100)'],
    ['Then the rules changed', 'Items dispensed per month, index (April 2015 = 100)'],
    ['Without the change, the climb would have continued', 'Dashed line: expected path with 95% prediction interval'],
    ['Instead, prescribing fell below the expected path', 'Observed (solid) against expected (dashed)'],
    [`About ${fmt(pct)}% fewer items than expected`, 'Shaded area: estimated effect of the reclassification'],
    ['Did the change reach every community equally?', 'Change against expected by SIMD quintile, % with 95% CI'],
    ['Did the change reach every community equally?', 'Causal only if its assumptions hold (see left)']
  ];

  // ---------------- Chart ----------------
  const svg = d3.select('#chart');
  let current = 0;
  const g = {};

  function build() {
    svg.selectAll('*').remove();
    const box = svg.node().getBoundingClientRect();
    const W = Math.max(300, box.width), H = Math.max(260, box.height);
    const narrow = W < 560;
    const m = { t: 20, r: narrow ? 20 : 120, b: 34, l: 44 };
    svg.attr('viewBox', `0 0 ${W} ${H}`);

    const x = d3.scaleTime().domain(d3.extent(data, d => d.date)).range([m.l, W - m.r]);
    const y = d3.scaleLinear()
      .domain([d3.min(data, d => Math.min(d.y, d.lo)) - 3, d3.max(data, d => Math.max(d.y, d.hi)) + 3])
      .nice().range([H - m.b, m.t]);

    // Line chart view
    const L = svg.append('g');
    L.append('g').attr('class', 'axis').attr('transform', `translate(0,${H - m.b})`)
      .call(d3.axisBottom(x).ticks(narrow ? 4 : 8).tickSize(0).tickPadding(10));
    L.append('g').attr('class', 'axis').attr('transform', `translate(${m.l},0)`)
      .call(d3.axisLeft(y).ticks(5).tickSize(-(W - m.l - m.r)).tickPadding(8));

    const cfData = data.slice(P - 1);
    const curve = d3.curveMonotoneX;
    g.band = L.append('path').datum(cfData).attr('class', 'band').attr('opacity', 0)
      .attr('d', d3.area().x(d => x(d.date)).y0(d => y(d.lo)).y1(d => y(d.hi)).curve(curve));
    g.gap = L.append('path').datum(cfData).attr('class', 'gap').attr('opacity', 0)
      .attr('d', d3.area().x(d => x(d.date)).y0(d => y(d.mu)).y1(d => y(d.y)).curve(curve));
    g.cf = L.append('path').datum(cfData).attr('class', 'cf').attr('opacity', 0)
      .attr('d', d3.line().x(d => x(d.date)).y(d => y(d.mu)).curve(curve));
    const line = d3.line().x(d => x(d.date)).y(d => y(d.y)).curve(curve);
    g.pre = L.append('path').datum(data.slice(0, P)).attr('class', 'obs').attr('d', line);
    g.post = L.append('path').datum(data.slice(P - 1)).attr('class', 'obs').attr('d', line);
    [g.pre, g.post].forEach(p => {
      const len = p.node().getTotalLength();
      p.style('stroke-dasharray', `${len} ${len}`).style('stroke-dashoffset', len).property('len', len);
    });

    const px = x(data[P].date);
    g.policy = L.append('g').attr('opacity', 0);
    g.policy.append('line').attr('class', 'policy-line').attr('x1', px).attr('x2', px).attr('y1', m.t).attr('y2', H - m.b);
    g.policy.append('text').attr('class', 'lbl-strong').attr('x', px + 8).attr('y', m.t + 14).text('April 2019');
    g.policy.append('text').attr('class', 'lbl-muted').attr('x', px + 8).attr('y', m.t + 30).text('Reclassified');

    const last = data[N - 1];
    g.lblObs = L.append('text').attr('class', 'lbl-obs').attr('opacity', 0).text('Observed');
    g.lblCf = L.append('text').attr('class', 'lbl-cf').attr('opacity', 0).text('Expected');
    if (!narrow) {
      g.lblObs.attr('x', x(last.date) + 8).attr('y', y(last.y) + 4);
      g.lblCf.attr('x', x(last.date) + 8).attr('y', y(last.mu) + 4);
    } else {
      g.lblObs.attr('x', x(last.date) - 4).attr('y', y(last.y) + 18).attr('text-anchor', 'end');
      g.lblCf.attr('x', x(last.date) - 4).attr('y', y(last.hi) - 8).attr('text-anchor', 'end');
    }
    g.lblPre = L.append('text').attr('class', 'lbl-obs').attr('opacity', 0).attr('text-anchor', 'end')
      .attr('x', x(data[P - 1].date) - 6).attr('y', y(data[P - 1].y) - 12).text('Observed');

    g.ann = L.append('g').attr('opacity', 0);
    const ax = x(last.date) - (narrow ? 4 : 0);
    g.ann.append('line').attr('class', 'ann-line').attr('x1', ax).attr('x2', ax).attr('y1', y(last.mu)).attr('y2', y(last.y));
    g.ann.append('text').attr('class', 'lbl-big').attr('text-anchor', 'end')
      .attr('x', ax - 8).attr('y', (y(last.mu) + y(last.y)) / 2 + 6)
      .style('font-size', narrow ? '16px' : '20px').text(`−${fmt(pctLast)}%`);
    g.line = L;

    // Bar chart view
    const B = svg.append('g').attr('opacity', 0).style('pointer-events', 'none');
    const bm = { t: 30, r: narrow ? 44 : 70, b: 40, l: narrow ? 110 : 150 };
    const bx = d3.scaleLinear().domain([d3.min(quint, d => d.lo) - 2, 0]).range([bm.l, W - bm.r]);
    const by = d3.scaleBand().domain(quint.map(d => d.q)).range([bm.t, H - bm.b]).padding(.38);
    B.append('g').attr('class', 'axis').attr('transform', `translate(0,${H - bm.b})`)
      .call(d3.axisBottom(bx).ticks(5).tickFormat(d => d + '%').tickSize(-(H - bm.t - bm.b)).tickPadding(10));
    B.append('line').attr('class', 'zero').attr('x1', bx(0)).attr('x2', bx(0)).attr('y1', bm.t - 10).attr('y2', H - bm.b);
    const row = B.selectAll('.row').data(quint).join('g').attr('class', 'row');
    row.append('text').attr('class', (d, i) => 'bar-label' + (i === 0 ? ' focus' : ''))
      .attr('x', bm.l - 12).attr('y', d => by(d.q) + by.bandwidth() / 2 + 4).attr('text-anchor', 'end').text(d => d.q);
    g.bar = row.append('rect').attr('class', (d, i) => 'bar' + (i === 0 ? ' focus' : ''))
      .attr('y', d => by(d.q)).attr('height', by.bandwidth()).attr('rx', 3).attr('x', bx(0)).attr('width', 0);
    g.ci = row.append('line').attr('class', 'ci').attr('opacity', 0)
      .attr('y1', d => by(d.q) + by.bandwidth() / 2).attr('y2', d => by(d.q) + by.bandwidth() / 2)
      .attr('x1', d => bx(d.lo)).attr('x2', d => bx(d.hi));
    g.val = row.append('text').attr('class', 'bar-value').attr('opacity', 0).attr('text-anchor', 'end')
      .attr('x', d => bx(d.lo) - 8).attr('y', d => by(d.q) + by.bandwidth() / 2 + 4).text(d => d.v.toFixed(1) + '%');
    g.bx = bx; g.bars = B;
  }

  function fade(sel, on) { sel.transition().duration(DUR).attr('opacity', on ? 1 : 0); }
  function draw(p, on) {
    p.transition().duration(on ? DUR * 1.6 : DUR * .6).ease(d3.easeCubicInOut)
      .style('stroke-dashoffset', on ? 0 : p.property('len'));
  }

  function setStep(s) {
    current = s;
    document.getElementById('chart-title').textContent = heads[s][0];
    document.getElementById('chart-sub').textContent = heads[s][1];
    const lineView = s <= 4;
    fade(g.line, lineView);
    fade(g.bars, !lineView);
    draw(g.pre, true);
    fade(g.lblPre, s < 3);
    fade(g.policy, s >= 1);
    fade(g.band, s >= 2); fade(g.cf, s >= 2); fade(g.lblCf, s >= 2);
    draw(g.post, s >= 3); fade(g.lblObs, s >= 3);
    fade(g.gap, s >= 4); fade(g.ann, s >= 4);
    const bOn = !lineView;
    g.bar.transition().duration(DUR).delay((d, i) => (bOn ? i * 90 : 0))
      .attr('x', d => (bOn ? g.bx(d.v) : g.bx(0)))
      .attr('width', d => (bOn ? g.bx(0) - g.bx(d.v) : 0));
    fade(g.ci, bOn); fade(g.val, bOn);
  }

  build();
  setStep(0);

  // ---------------- Scroll triggers ----------------
  const steps = document.querySelectorAll('.step');
  const io = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      steps.forEach(st => st.classList.remove('active'));
      e.target.classList.add('active');
      const s = +e.target.dataset.step;
      if (s !== current) setStep(s);
    });
  }, { rootMargin: '-45% 0px -45% 0px' });
  steps.forEach(st => io.observe(st));
  steps[0].classList.add('active');

  let rt;
  window.addEventListener('resize', () => {
    clearTimeout(rt);
    rt = setTimeout(() => { const keep = DUR; DUR = 0; build(); setStep(current); DUR = keep; }, 200);
  });
})();
