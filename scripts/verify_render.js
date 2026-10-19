// 图表真机渲染验证 —— plf-cli-agent 内置脚本
//
// 用法:
//   node verify_render.js <图表HTML绝对路径> <截图输出.png> [canvasId]
//
// 作用: 用本机已装的 Chrome 跑 headless，直接问 Chart.js
//       「你到底渲染了哪些横轴刻度」，并算出相邻标签的最小像素间距。
//       不靠肉眼截图判断重叠。
//
// 判据: renderedCount > 0 且 minGap > 40px

const { chromium } = require('playwright');

const FILE = process.argv[2];
const OUT = process.argv[3];
const CANVAS_ID = process.argv[4] || null;

const CHROME = process.env.CHROME_PATH ||
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

  const logs = [];
  page.on('console', m => logs.push(m.text()));
  page.on('pageerror', e => logs.push('PAGEERROR: ' + e.message));

  await page.goto('file:///' + FILE.replace(/\\/g, '/'), { waitUntil: 'networkidle' });
  await page.waitForTimeout(1200);

  // 关键: 调用户自己的 ticks.callback 求值，只保留非空结果 = 真实渲染的刻度
  const info = await page.evaluate((wantId) => {
    let canvas = wantId ? document.getElementById(wantId) : null;
    if (!canvas) canvas = document.querySelector('canvas');
    if (!canvas) return { error: 'no canvas found' };
    const c = window.Chart.getChart(canvas);
    if (!c) return { error: 'chart not found on ' + canvas.id };

    const sc = c.scales.x;
    const cb = c.options.scales.x.ticks.callback;
    const rendered = [];
    for (const t of sc.ticks) {
      const txt = (typeof cb === 'function')
        ? cb.call({ getLabelForValue: (x) => sc.getLabelForValue(x) }, t.value)
        : t.label;
      if (txt !== '' && txt != null) rendered.push({ idx: t.value, text: txt });
    }
    const wrap = canvas.closest('.wrap') || canvas.parentElement;
    return {
      canvasId: canvas.id,
      chartWidth: c.width,
      wrapWidth: wrap ? wrap.clientWidth : null,
      ticksTotal: sc.ticks.length,
      renderedCount: rendered.length,
      rendered: rendered.map(r => r.text),
      renderedIdx: rendered.map(r => r.idx),
      xLeft: sc.left,
      xRight: sc.right,
      hasYTitle: !!(c.options.scales.y && c.options.scales.y.title && c.options.scales.y.title.display)
    };
  }, CANVAS_ID);

  // 相邻标签索引差 → 真实像素间距，取最小值即重叠判据
  let minGap = null;
  if (info.renderedIdx && info.renderedIdx.length > 1) {
    const span = info.xRight - info.xLeft;
    const realSpan = info.renderedIdx[info.renderedIdx.length - 1] - info.renderedIdx[0];
    const gaps = [];
    for (let i = 1; i < info.renderedIdx.length; i++) {
      gaps.push(((info.renderedIdx[i] - info.renderedIdx[i - 1]) / realSpan) * span);
    }
    minGap = Math.round(Math.min(...gaps) * 10) / 10;
  }

  const verdict = [];
  if (info.error) verdict.push('FAIL ' + info.error);
  else {
    if (info.renderedCount === 0) verdict.push('FAIL no x-axis labels rendered');
    if (minGap !== null && minGap < 40) verdict.push('WARN minGap=' + minGap + 'px (<40, may touch)');
    if (info.hasYTitle) verdict.push('WARN y-axis title is displayed (can overlap 6-digit ticks)');
    if (verdict.length === 0) verdict.push('PASS');
  }

  await page.screenshot({ path: OUT, fullPage: false });
  await browser.close();
  console.log(JSON.stringify({ verdict, logs, info, minGap }, null, 2));
})().catch(e => { console.error('FATAL ' + e.stack); process.exit(1); });
