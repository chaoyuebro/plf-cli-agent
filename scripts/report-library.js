// Local report archiving only. Never connects to EJClient or submits a backtest.
// node report-library.js <entry.json> [library-base] [mirror-base] [--window-id <id>] [--update-presentation]
// With no library-base, use THIS skill copy's usr/work-reports/backtests only.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const LABELS = require('../assets/report-labels.json');

const CSS = `
:root{color-scheme:light;font:15px/1.65 "Microsoft YaHei",system-ui,sans-serif;color:#202d3a;background:#f3f5f7}
*{box-sizing:border-box}body{margin:0}main{max-width:1360px;margin:auto;padding:32px 28px}
h1{font-size:28px;margin:0 0 8px}h2{font-size:20px;margin:28px 0 12px}h3{font-size:16px;margin:18px 0 8px}
p{margin:8px 0}.muted{color:#637487}.panel{background:white;border:1px solid #dce3ea;border-radius:12px;padding:22px;margin:18px 0}
.filters{display:flex;gap:12px;flex-wrap:wrap}input,select,button{font:inherit;padding:9px 12px;border:1px solid #bbc8d4;border-radius:7px;background:white;color:inherit}
input{flex:1;min-width:220px}button{cursor:pointer;color:#17635e}button:hover{background:#edf8f5}a{color:#17635e}
.scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-size:14px}th,td{padding:10px 12px;border-bottom:1px solid #e4e9ee;text-align:left;vertical-align:top}th{background:#f6f8fa;white-space:nowrap}
td{overflow-wrap:anywhere}ul{padding-left:22px;margin:8px 0}.rule{border-left:3px solid #3b8276;padding-left:16px;margin:16px 0}
.metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(155px,1fr));gap:12px}.metric{background:#f5f8fa;padding:14px;border-radius:8px}.metric strong{display:block;font-size:21px;margin-top:5px}
pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}details{margin:12px 0}summary{cursor:pointer}.warning{background:#fff4d9;padding:12px;border-radius:7px}
dialog{width:min(1200px,96vw);max-height:94vh;border:1px solid #ccd6df;border-radius:12px;padding:0}dialog::backdrop{background:#14233399}
.dialog-bar{position:sticky;top:0;background:#fff;z-index:1;padding:10px 22px;border-bottom:1px solid #dce3ea}.report-content{padding:6px 24px 24px}
iframe{width:100%;height:760px;border:0}code{overflow-wrap:anywhere}@media(max-width:650px){main{padding:20px 12px}.panel{padding:15px}.report-content{padding:4px 15px 20px}h1{font-size:23px}}
.equity-chart{display:block;width:100%;min-width:640px;height:auto;background:white}.equity-chart text{font:12px "Microsoft YaHei",sans-serif;fill:#526475}.equity-caption{font-size:13px;color:#637487}.nested{min-width:230px}td .scroll{max-height:550px}
.report-list{display:grid;gap:10px;margin-top:20px}.report-entry{display:flex;align-items:center;justify-content:space-between;gap:18px;width:100%;padding:20px 22px;text-align:left;color:#202d3a;background:white;border:1px solid #dce3ea;border-radius:10px}.report-entry:hover{background:#f7fbfa;border-color:#8db5ac}.report-entry:focus-visible{outline:2px solid #3b8276;outline-offset:3px}.report-entry-line{display:flex;align-items:baseline;flex-wrap:wrap;gap:6px 12px}.report-entry-title{font-size:17px;font-weight:600}.report-entry-meta{font-size:14px;color:#637487}.report-entry-arrow{color:#82958f;font-size:24px;flex-shrink:0}
`;

function esc(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function strategyName(entry) {
    return entry.strategy_name.replace('(' + entry.strategy + ')', '').replace('（' + entry.strategy + '）', '').trim();
}

function roundLabel(entry) {
    const label = entry.round_label.trim();
    if (/^(基准轮|初始轮|baseline)$/i.test(label)) return '基准轮';
    if (/[-负]\s*\d|\d\.\d/.test(label)) return label;
    const kind = /修改|修订|modification|revision/i.test(label) ? '修改' : /优化|调参|optimi[sz]|tuning/i.test(label) ? '优化' : '';
    const match = label.match(/(?:第\s*)?(\d+|[一二三四五六七八九十]+)\s*[轮次]/) || label.match(/round\s+(\d+)/i);
    if (!kind || !match) return label;
    let number = match[1];
    if (/^\d+$/.test(number)) {
        const n = Number(number), digits = '零一二三四五六七八九';
        if (n <= 0) return label;
        number = n < 10 ? digits[n] : n < 20 ? '十' + (n % 10 ? digits[n % 10] : '') : n < 100 ? digits[Math.floor(n / 10)] + '十' + (n % 10 ? digits[n % 10] : '') : String(n);
    }
    return kind + '第' + number + '轮';
}

function reportTitle(entry) {
    const name = strategyName(entry), suffix = '（' + roundLabel(entry) + '）';
    return name.endsWith(suffix) ? name : name + suffix;
}

function periodName(value) {
    return ({'1d':'日线','1w':'周线','1mo':'月线'})[value] || String(value).replace(/^(\d+)m$/, '$1分钟').replace(/^(\d+)h$/, '$1小时');
}

function chineseText(value, entry = {}) {
    let text = String(value == null ? '' : value);
    const stride = entry.report?.equity_curve_meta?.stride;
    if (typeof stride === 'number' && Number.isFinite(stride)) text = text.replace(/\bstride\s*=\s*\d+/g, 'stride=' + stride);
    const replacements = {...LABELS.fields,...LABELS.text,...LABELS.parameters,...entry.parameter_labels,...entry.text_labels};
    if (entry.contract_key) replacements[entry.contract_key] = entry.contract_name;
    if (entry.strategy) replacements[entry.strategy] = strategyName(entry);
    for (const key of Object.keys(replacements).sort((a, b) => b.length - a.length)) {
        const token = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        text = text.replace(new RegExp('(?<![A-Za-z0-9_])' + token + '(?![A-Za-z0-9_])', 'g'), () => replacements[key]);
    }
    if (entry.contract_name) text = text.split(entry.contract_name + '（' + entry.contract_name + '）').join(entry.contract_name);
    return text.replace(/(?<![\w.])[-+]?\d+\.\d+(?:[eE][+-]?\d+)?/g, n => fixed(Number(n)));
}

function fixed(value) {
    return (Math.abs(value) < 0.005 ? 0 : value).toFixed(2);
}

function fieldLabel(key, entry = {}) {
    if (entry.field_labels && entry.field_labels[key]) return entry.field_labels[key];
    if (LABELS.fields[key]) return LABELS.fields[key];
    const prefix = /^(all|win|lose)_(.+)$/.exec(key);
    if (prefix && LABELS.fields[prefix[2]]) return ({all:'全部交易',win:'盈利交易',lose:'亏损交易'})[prefix[1]] + ' · ' + LABELS.fields[prefix[2]];
    return /[\u3400-\u9fff]/.test(key) ? key : '其他指标（含义未确认）';
}

function parameterLabel(key, entry) {
    return (entry.parameter_labels && entry.parameter_labels[key]) || LABELS.parameters[key] || '参数（含义未确认）';
}

function beijingTime(value, dateOnly = false) {
    const text = String(value);
    if (/^\d{8}$/.test(text)) return text.slice(0, 4) + '-' + text.slice(4, 6) + '-' + text.slice(6);
    const date = new Date(typeof value === 'number' ? value * (Math.abs(value) < 1e11 ? 1000 : 1) : value);
    if (!Number.isFinite(date.getTime())) return text;
    const parts = new Intl.DateTimeFormat('zh-CN', {timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit',...(dateOnly ? {} : {hour:'2-digit',minute:'2-digit',hourCycle:'h23'})}).formatToParts(date);
    const part = name => parts.find(p => p.type === name).value;
    return part('year') + '-' + part('month') + '-' + part('day') + (dateOnly ? '' : ' ' + part('hour') + ':' + part('minute'));
}

function display(value, key = '', entry = {}) {
    if (value == null) return '未提供';
    if (typeof value === 'boolean') return key === 'long' ? (value ? '多头' : '空头') : (value ? '是' : '否');
    if ((key === 'time' || key.endsWith('_time')) && !['hold_time','total_trade_time'].includes(key)) return beijingTime(value);
    if (/交易日|日期/.test(key) && /^\d{8}$/.test(String(value))) return beijingTime(value, true);
    if (typeof value === 'number' || (typeof value === 'string' && /^[-+]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?%?$/.test(value))) {
        const percentage = typeof value === 'string' && value.endsWith('%');
        const number = Number(percentage ? value.slice(0, -1) : value);
        if (!Number.isFinite(number)) return '未提供';
        if (percentage || LABELS.percent_fields.includes(key)) return fixed(percentage ? number : number * 100) + '%';
        if ((LABELS.integer_fields.includes(key) || key === 'parameter' || /根数|窗口数|点数|记录数|笔数|次数|手数|天数/.test(key)) && Number.isInteger(number)) return String(number);
        return fixed(number);
    }
    return chineseText(value, entry);
}

function parameterSummary(entry) {
    return Object.entries({...entry.defaults,...entry.overrides}).map(([key, value]) => parameterLabel(key, entry) + '：' + display(value, 'parameter', entry)).join('；') || '无参数';
}

function table(value, entry = {}) {
    if (value == null) return '<p class="muted">未提供</p>';
    if (Array.isArray(value)) {
        if (!value.length) return '<p class="muted">无记录</p>';
        if (!value.every(row => row && typeof row === 'object' && !Array.isArray(row))) {
            return '<ul>' + value.map(item => '<li>' + esc(display(item, '', entry)) + '</li>').join('') + '</ul>';
        }
        const keys = [...new Set(value.flatMap(row => Object.keys(row)))];
        return '<div class="scroll"><table><thead><tr>' + keys.map(k => '<th title="' + esc(k) + '">' + esc(fieldLabel(k, entry)) + '</th>').join('') +
            '</tr></thead><tbody>' + value.map(row => '<tr>' + keys.map(k => '<td>' + (row[k] && typeof row[k] === 'object' ? table(row[k], entry) : esc(display(row[k], k, entry))) + '</td>').join('') + '</tr>').join('') + '</tbody></table></div>';
    }
    if (typeof value !== 'object') return '<p>' + esc(display(value, '', entry)) + '</p>';
    return '<div class="scroll"><table><tbody>' + Object.entries(value).map(([k, v]) =>
        '<tr><th title="' + esc(k) + '">' + esc(fieldLabel(k, entry)) + '</th><td>' + (v && typeof v === 'object' ? '<div class="nested">' + table(v, entry) + '</div>' : esc(display(v, k, entry))) + '</td></tr>').join('') + '</tbody></table></div>';
}

function curveControls(values) {
    const controls = [{x:0,y:values[0]}];
    for (let start = 0; start < values.length;) {
        let end = start;
        while (end + 1 < values.length && values[end + 1] === values[start]) end++;
        const x = (start + end) / 2;
        if (x > controls[controls.length - 1].x) controls.push({x,y:values[start]});
        start = end + 1;
    }
    if (controls[controls.length - 1].x !== values.length - 1) controls.push({x:values.length - 1,y:values[values.length - 1]});
    const slopes = controls.slice(1).map((p, i) => (p.y - controls[i].y) / (p.x - controls[i].x));
    const tangents = controls.map((p, i) => i === 0 ? slopes[0] : i === controls.length - 1 ? slopes[i - 1] : (slopes[i - 1] + slopes[i]) / 2);
    for (let i = 0; i < slopes.length; i++) {
        if (slopes[i] === 0) { tangents[i] = 0; tangents[i + 1] = 0; continue; }
        if (tangents[i] / slopes[i] < 0) tangents[i] = 0;
        if (tangents[i + 1] / slopes[i] < 0) tangents[i + 1] = 0;
        const norm = Math.hypot(tangents[i] / slopes[i], tangents[i + 1] / slopes[i]);
        if (norm > 3) { tangents[i] *= 3 / norm; tangents[i + 1] *= 3 / norm; }
    }
    return {controls,tangents};
}

function equityCurve(entry) {
    const report = entry.report;
    const points = report.equity_curve;
    if (report.headless_report_available !== true || !Array.isArray(points) || points.length < 2) {
        return '<p class="warning">资金曲线不可用：' + esc(chineseText(report.headless_report_error?.message || '有效资金记录不足两条。', entry)) + '</p>';
    }
    if (!points.every(p => typeof p.static_equity === 'number' && Number.isFinite(p.static_equity))) return '<p class="warning">资金曲线包含无效数值，未绘制。</p>';
    const values = points.map(p => p.static_equity);
    const times = points.map(p => p.time);
    const initial = report.profit.start_fund;
    if (typeof initial === 'number' && Number.isFinite(initial)) { values.unshift(initial); times.unshift(entry.start_date); }
    const low = Math.min(...values), high = Math.max(...values);
    const padding = (high - low || Math.abs(low) * 0.01 || 1) * 0.1;
    const left = 100, right = 976, top = 25, bottom = 300;
    const x = i => left + i / (values.length - 1) * (right - left);
    const y = v => bottom - (v - low + padding) / (high - low + padding * 2) * (bottom - top);
    const {controls,tangents} = curveControls(values);
    let d = 'M ' + x(0) + ' ' + y(values[0]);
    for (let i = 0; i + 1 < controls.length; i++) {
        const a = controls[i], b = controls[i + 1], step = (b.x - a.x) / 3;
        d += ' C ' + x(a.x + step) + ' ' + y(a.y + tangents[i] * step) + ' ' + x(b.x - step) + ' ' + y(b.y - tangents[i + 1] * step) + ' ' + x(b.x) + ' ' + y(b.y);
    }
    const labels = times.map(t => beijingTime(t, true));
    const longSpan = labels[0].slice(0, 7) !== labels[labels.length - 1].slice(0, 7);
    const tickText = i => longSpan ? labels[i].slice(0, 7).replace('-', '/') : beijingTime(times[i]).slice(5);
    const candidates = [0];
    for (let i = 1; i < values.length - 1; i++) if (tickText(i) !== tickText(i - 1)) candidates.push(i);
    candidates.push(values.length - 1);
    const minimumWidth = 640, minimumGap = 74;
    const capacity = Math.max(2, Math.floor((right - left) / 1000 * minimumWidth / minimumGap));
    const selected = [0];
    const gap = minimumGap / ((right - left) / 1000 * minimumWidth) * (values.length - 1);
    for (let i = 1; i < capacity - 1; i++) {
        const target = (values.length - 1) * i / (capacity - 1);
        const available = candidates.filter(c => c - selected[selected.length - 1] >= gap && values.length - 1 - c >= gap);
        if (available.length) selected.push(available.reduce((a, b) => Math.abs(a - target) < Math.abs(b - target) ? a : b));
    }
    selected.push(values.length - 1);
    let svg = '<div class="scroll"><svg class="equity-chart" viewBox="0 0 1000 380" role="img" aria-label="资金曲线（已实现权益）" data-point-count="' + values.length + '" data-raw-min="' + low + '" data-raw-max="' + high + '" data-left="' + left + '" data-right="' + right + '" data-top="' + y(high) + '" data-bottom="' + y(low) + '">';
    for (let i = 0; i <= 4; i++) {
        const value = low - padding + (high - low + padding * 2) * i / 4;
        svg += '<line x1="' + left + '" x2="' + right + '" y1="' + y(value) + '" y2="' + y(value) + '" stroke="#e5eaf0"/><text x="' + (left - 8) + '" y="' + (y(value) + 4) + '" text-anchor="end">' + fixed(value) + '</text>';
    }
    if (typeof initial === 'number' && Number.isFinite(initial)) svg += '<line x1="' + left + '" x2="' + right + '" y1="' + y(initial) + '" y2="' + y(initial) + '" stroke="#8595a5" stroke-dasharray="5 5"/>';
    svg += '<path class="equity-line" d="' + d + '" fill="none" stroke="#ce363b" stroke-width="2.4" vector-effect="non-scaling-stroke"/>';
    svg += selected.map(i => '<text class="equity-tick" data-index="' + i + '" x="' + x(i) + '" y="326" text-anchor="' + (i === 0 ? 'start' : i === values.length - 1 ? 'end' : 'middle') + '">' + esc(tickText(i)) + '</text>').join('');
    svg += '<text x="538" y="359" text-anchor="middle">资金记录顺序（刻度为北京时间）</text></svg></div>';
    const meta = report.equity_curve_meta || {};
    return '<p>资金曲线（已实现权益），单位：元。灰色虚线为初始资金。' +
        (meta.sampled === true ? '抽样数据：原始记录 ' + display(meta.source_record_count, 'source_record_count') + ' 条，返回 ' + points.length + ' 点，采样步长 ' + display(meta.stride, 'stride') + '。' : '') +
        '</p>' + svg;
}

function reportBody(entry) {
    const labels = {net_profit:'净利润',max_drawdown:'最大回撤（含浮盈）',trades:'交易次数',win_rate:'胜率',win_lose_ratio:'盈亏比'};
    const effective = {...entry.defaults, ...entry.overrides};
    const params = Object.keys(effective).map(name => ({'参数':parameterLabel(name, entry),'源码默认值':display(entry.defaults[name], 'parameter', entry),'本轮实际值':display(effective[name], 'parameter', entry)}));
    const sections = {profit:'收益明细',statistics:'统计明细',trade_pairs:'成交明细',trade_parse:'交易分析',monthly:'月度统计',yearly:'年度统计',open_positions:'期末持仓',equity_curve_meta:'资金曲线采样信息'};
    let html = '<header><h1>' + esc(reportTitle(entry)) + ' · 回测报告</h1><p class="muted">' +
        esc(entry.contract_name) + ' · ' + esc(periodName(entry.period)) + ' · ' + esc(beijingTime(entry.start_date, true)) + ' 至 ' + esc(beijingTime(entry.end_date, true)) +
        ' · ' + esc(roundLabel(entry)) + '</p></header>';
    html += '<section aria-label="策略规则"><h2>策略规则</h2>' + entry.rules.map(rule =>
        '<div class="rule"><h3>' + esc(chineseText(rule.title, entry)) + '</h3><ul>' + rule.items.map(item => '<li>' + esc(chineseText(item, entry)) + '</li>').join('') + '</ul></div>').join('') + '</section>';
    html += '<section><h2>本轮参数与运行口径</h2>' + (params.length ? table(params, entry) : '<p>公式没有声明参数。</p>') +
        table(Object.fromEntries(Object.entries(entry.context).filter(([key]) => !/sha256/i.test(key))), entry) + '<p class="muted">运行时间：' + esc(beijingTime(entry.created_at)) +
        '；策略版本：<code>' + esc(entry.source_sha256.slice(0, 8)) + '</code></p></section>';
    html += '<section><h2>回测结果</h2><div class="metrics">' + Object.entries(labels).map(([key, label]) =>
        '<div class="metric">' + label + '<strong>' + esc(display(entry.metrics[key], key, entry)) + '</strong></div>').join('') + '</div>' +
        '<p>' + esc(chineseText(entry.analysis, entry)) + '</p>' + entry.warnings.map(w => '<p class="warning">' + esc(chineseText(w, entry)) + '</p>').join('') + '</section>';
    if (entry.chart_html) html += '<section><h2>资金曲线</h2><iframe title="资金曲线" sandbox="allow-scripts" srcdoc="' + esc(entry.chart_html) + '"></iframe></section>';
    else html += '<section><h2>资金曲线</h2>' + equityCurve(entry) + '</section>';
    html += '<section><h2>完整报告明细</h2>' + Object.entries(sections).filter(([key]) => entry.report[key] != null).map(([key, label]) =>
        '<details><summary>' + label + '</summary>' + table(entry.report[key], entry) + '</details>').join('') + '</section>';
    return html;
}

function documentHtml(title, body, script = '') {
    return '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' +
        esc(title) + '</title><style>' + CSS + '</style></head><body>' + body + script + '</body></html>';
}

function libraryClient() {
    const entries = JSON.parse(document.getElementById('entries').textContent);
    const search = document.getElementById('search');
    const filters = ['strategy', 'contract_key', 'period'];
    const names = {strategy:'strategy_name',contract_key:'contract_name',period:'period'};
    const groupRoot = document.getElementById('groups');
    const dialog = document.getElementById('report-dialog');
    for (const key of filters) {
        const seen = new Map(entries.map(entry => [entry[key], entry[names[key]]]));
        for (const [value, label] of [...seen].sort((a, b) => a[1].localeCompare(b[1], 'zh-CN'))) {
            const option = document.createElement('option');
            option.value = value;
            option.textContent = key === 'period' ? periodName(label) : key === 'strategy' ? strategyName(entries.find(e => e.strategy === value)) : label;
            document.getElementById(key).append(option);
        }
        document.getElementById(key).addEventListener('change', render);
    }
    function render() {
        const terms = search.value.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
        const matches = entries.filter(entry => filters.every(key => !document.getElementById(key).value || document.getElementById(key).value === entry[key]) &&
            terms.every(term => [entry.strategy_name,entry.strategy,entry.source_sha256,entry.contract_name,entry.contract_key,entry.period,periodName(entry.period),entry.start_date,entry.end_date,entry.created_at,entry.round_label,roundLabel(entry),parameterSummary(entry),JSON.stringify({...entry.defaults,...entry.overrides})].join(' ').toLocaleLowerCase().includes(term)));
        document.getElementById('count').textContent = '显示 ' + matches.length + ' / ' + entries.length + ' 份报告 · 最新结果在前';
        groupRoot.innerHTML = matches.length ? '<div class="report-list">' + matches.map(entry =>
            '<button class="report-entry" data-report="' + esc(entry.report_id) + '"><span class="report-entry-line"><span class="report-entry-title">' +
            esc(reportTitle(entry)) + '</span><span class="report-entry-meta">' +
            esc([entry.contract_name,periodName(entry.period),beijingTime(entry.created_at),'版本 ' + entry.source_sha256.slice(0, 8)].join(' · ')) +
            '</span></span><span class="report-entry-arrow" aria-hidden="true">›</span></button>').join('') + '</div>' : '<p class="panel">没有符合条件的报告。</p>';
    }
    groupRoot.addEventListener('click', event => {
        const button = event.target.closest('button[data-report]');
        if (!button) return;
        const entry = entries.find(item => item.report_id === button.dataset.report);
        document.getElementById('report-content').innerHTML = reportBody(entry);
        dialog.showModal();
        dialog.scrollTop = 0;
    });
    document.getElementById('close').addEventListener('click', () => dialog.close());
    search.addEventListener('input', render);
    render();
}

function indexHtml(entries) {
    // The index contains its report details; file:// and standalone previews both work.
    const payload = JSON.stringify(entries).replace(/</g, '\\u003c');
    const body = '<main><header><h1>回测报告总览</h1><p class="muted">本窗口的报告合集。选择一份报告，查看完整规则、参数、结果和资金曲线。</p></header>' +
        '<section class="panel"><div class="filters"><input id="search" type="search" aria-label="搜索报告" placeholder="搜索策略、合约、日期、参数或版本">' +
        '<select id="strategy" aria-label="策略"><option value="">全部策略</option></select><select id="contract_key" aria-label="合约"><option value="">全部合约</option></select><select id="period" aria-label="周期"><option value="">全部周期</option></select></div><p id="count" class="muted" aria-live="polite"></p></section>' +
        '<div id="groups"></div><dialog id="report-dialog"><div class="dialog-bar"><button id="close">返回报告总览</button></div><article id="report-content" class="report-content"></article></dialog></main>';
    return documentHtml('回测报告总览', body, '<script id="entries" type="application/json">' + payload + '</script><script>' +
        'const LABELS = ' + JSON.stringify(LABELS).replace(/</g, '\\u003c') + ';\n' +
        [esc,strategyName,roundLabel,reportTitle,periodName,chineseText,fixed,fieldLabel,parameterLabel,beijingTime,display,parameterSummary,table,curveControls,equityCurve,reportBody,libraryClient].map(fn => fn.toString()).join('\n') + '\nlibraryClient();</script>');
}

function validateChineseProse(value, key, entry) {
    const text = chineseText(value, entry);
    const technical = new Set(['ATR','K','CLI','DLL','JSON','CSV','HTML','SVG','SHA','UTF','IPC','PID','ID','OHLC','QDC','EJClient','Fritsch','Carlson']);
    const words = (text.match(/[A-Za-z]+(?:['-][A-Za-z]+)*/g) || []).filter(word => word.length > 1 && !technical.has(word));
    if (words.length) throw new Error('REPORT_CHINESE_REQUIRED: translate ' + key + ' into Chinese before archiving (' + [...new Set(words)].slice(0, 8).join(', ') + ')');
}

function validate(entry) {
    const required = ['report_id','created_at','strategy','strategy_name','source_sha256','contract_key','contract_name','period','start_date','end_date','round_label','analysis','equity_analysis'];
    for (const key of required) if (typeof entry[key] !== 'string' || !entry[key].trim()) throw new Error('Missing text field: ' + key);
    if (!/^[a-zA-Z0-9_-]+$/.test(entry.report_id)) throw new Error('report_id must use ASCII letters, digits, underscores or hyphens');
    if (!/^[a-fA-F0-9]{64}$/.test(entry.source_sha256)) throw new Error('source_sha256 must identify the formula used for this run');
    if (!Number.isFinite(Date.parse(entry.created_at)) || !/(Z|[+-]\d{2}:\d{2})$/.test(entry.created_at)) throw new Error('created_at needs an ISO date and timezone');
    if (!Array.isArray(entry.rules) || !entry.rules.length || !entry.rules.every(rule => typeof rule.title === 'string' && rule.title.trim() && Array.isArray(rule.items) && rule.items.length && rule.items.every(item => typeof item === 'string' && item.trim()))) throw new Error('Nonempty strategy rules are required');
    for (const key of ['defaults','overrides','context','metrics','report']) if (!entry[key] || typeof entry[key] !== 'object' || Array.isArray(entry[key])) throw new Error('Missing object: ' + key);
    for (const key of ['profit','statistics']) if (!entry.report[key] || typeof entry.report[key] !== 'object' || Array.isArray(entry.report[key])) throw new Error('Incomplete report: ' + key);
    for (const key of Object.keys(entry.overrides)) if (!Object.hasOwn(entry.defaults, key)) throw new Error('Undeclared override: ' + key);
    if (!Array.isArray(entry.warnings) || !entry.warnings.every(item => typeof item === 'string')) throw new Error('warnings must be a string array');
    if (entry.chart_html != null && typeof entry.chart_html !== 'string') throw new Error('chart_html must be an HTML string');
    for (const key of ['parameter_labels','field_labels','text_labels']) {
        if (entry[key] != null && (typeof entry[key] !== 'object' || Array.isArray(entry[key]) || !Object.values(entry[key]).every(v => typeof v === 'string' && /[\u3400-\u9fff]/.test(v)))) throw new Error(key + ' must map codes to Chinese labels');
    }
    for (const key of Object.keys(entry.defaults)) if (!(entry.parameter_labels && entry.parameter_labels[key]) && !LABELS.parameters[key]) throw new Error('Missing Chinese parameter label: ' + key);
    if (!/^(基准轮|(?:优化|修改)第(?:[一二三四五六七八九十百]+|[1-9]\d*)轮)$/.test(roundLabel(entry))) throw new Error('REPORT_ROUND_REQUIRED: round_label must identify baseline, optimization or user modification and its round number');
    validateChineseProse(entry.analysis, 'analysis', entry);
    entry.warnings.forEach((warning, i) => validateChineseProse(warning, 'warnings[' + i + ']', entry));
}

function reportData(entry) {
    const data = {...entry};
    for (const key of ['round_label','analysis','warnings']) delete data[key];
    return JSON.stringify(data);
}

function segment(value) {
    const clean = value.replace(/[<>:"/\\|?*\x00-\x1f]/g, '_').replace(/[. ]+$/g, '').slice(0, 55) || 'report';
    return clean + '_' + crypto.createHash('sha256').update(value).digest('hex').slice(0, 8);
}

function atomicWrite(file, text) {
    const temporary = file + '.' + crypto.randomUUID() + '.tmp';
    try {
        fs.writeFileSync(temporary, text, {encoding:'utf8', flag:'wx'});
        fs.renameSync(temporary, file);
    } finally {
        if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
    }
}

function resolveWindowId(explicit) {
    const id = explicit || (process.env.CODEX_THREAD_ID ? 'codex:' + process.env.CODEX_THREAD_ID : '') ||
        (process.env.CODEX_SESSION_ID ? 'codex-session:' + process.env.CODEX_SESSION_ID : '');
    if (typeof id !== 'string' || !id.trim()) throw new Error('WINDOW_ID_REQUIRED: provide the current conversation ID with --window-id');
    return id.trim();
}

function windowRoot(base, windowId) {
    const key = 'window-' + crypto.createHash('sha256').update(windowId).digest('hex').slice(0, 20);
    return path.join(path.resolve(base), 'windows', key);
}

function archive(entry, root, windowId, updatePresentation = false) {
    if (entry.window_id != null && entry.window_id !== windowId) throw new Error('REPORT_WINDOW_MISMATCH: entry belongs to another window');
    fs.mkdirSync(root, {recursive:true});
    const lockPath = path.join(root, '.report-library.lock');
    const lock = fs.openSync(lockPath, 'wx');
    try {
        const manifestPath = path.join(root, 'report-library.json');
        const manifest = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8').replace(/^\uFEFF/, '')) : {schema_version:2, window_id:windowId, entries:[]};
        if (manifest.window_id !== windowId) throw new Error('REPORT_WINDOW_MISMATCH: library belongs to another window');
        if (manifest.schema_version !== 2 || !Array.isArray(manifest.entries)) throw new Error('Unsupported report library');
        const oldIndex = manifest.entries.findIndex(item => item.report_id === entry.report_id);
        const old = manifest.entries[oldIndex];
        if (updatePresentation && !old) throw new Error('Presentation update requires an existing report');
        if (old && (updatePresentation ? reportData(old) !== reportData(entry) : JSON.stringify(old) !== JSON.stringify(entry))) throw new Error('report_id already belongs to a different report; presentation updates cannot change backtest data');
        const folder = path.join(root, 'archive', segment(entry.strategy + '_' + entry.source_sha256.slice(0, 8)), segment(entry.contract_key), segment(entry.period));
        fs.mkdirSync(folder, {recursive:true});
        const output = path.join(folder, entry.report_id + '.html');
        const jsonPath = path.join(folder, entry.report_id + '.json');
        const json = JSON.stringify(entry, null, 2);
        if (fs.existsSync(jsonPath)) {
            const archived = fs.readFileSync(jsonPath, 'utf8');
            if (updatePresentation ? reportData(JSON.parse(archived)) !== reportData(entry) : archived !== json) throw new Error('Archived report differs from this entry');
        }
        atomicWrite(jsonPath, json);
        atomicWrite(output, documentHtml(reportTitle(entry) + ' · 回测报告', '<main><p><a href="../../../../index.html">返回报告总览</a></p><article class="panel">' + reportBody(entry) + '</article></main>'));
        if (!old) manifest.entries.push(entry);
        else if (updatePresentation) manifest.entries[oldIndex] = entry;
        manifest.entries.sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) || b.report_id.localeCompare(a.report_id));
        atomicWrite(manifestPath, JSON.stringify(manifest, null, 2));
        atomicWrite(path.join(root, 'index.html'), indexHtml(manifest.entries));
        return {window_id:windowId,index:path.join(root, 'index.html'), report:output, total:manifest.entries.length};
    } finally {
        fs.closeSync(lock);
        fs.unlinkSync(lockPath);
    }
}

try {
    const args = process.argv.slice(2);
    const updateIndex = args.indexOf('--update-presentation');
    const updatePresentation = updateIndex >= 0;
    if (updatePresentation) args.splice(updateIndex, 1);
    const option = args.indexOf('--window-id');
    let explicitWindow;
    if (option >= 0) {
        if (!args[option + 1] || args[option + 1].startsWith('--') || args.indexOf('--window-id', option + 1) >= 0) throw new Error('Invalid --window-id');
        explicitWindow = args[option + 1];
        args.splice(option, 2);
    }
    const [input, root = path.join(__dirname, '..', 'usr', 'work-reports', 'backtests'), mirror] = args;
    if (!input || !root || args.length > 3) throw new Error('Usage: node report-library.js <entry.json> [library-base] [mirror-base] [--window-id <id>] [--update-presentation]');
    const windowId = resolveWindowId(explicitWindow);
    const entry = JSON.parse(fs.readFileSync(input, 'utf8').replace(/^\uFEFF/, ''));
    validate(entry);
    const result = archive(entry, windowRoot(root, windowId), windowId, updatePresentation);
    if (mirror && path.resolve(mirror).toLowerCase() !== path.resolve(root).toLowerCase()) result.mirror = archive(entry, windowRoot(mirror, windowId), windowId, updatePresentation);
    console.log(JSON.stringify({success:true,...result}));
} catch (error) {
    console.error(JSON.stringify({success:false,error:error.message}));
    process.exitCode = 1;
}
