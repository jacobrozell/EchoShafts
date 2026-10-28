#!/usr/bin/env node
// Plays the Echo Shafts Debug build. The app listens on 127.0.0.1:4771.

const PORT = process.env.ECHOSHAFTS_AGENT_PORT || '4771';
const BASE = `http://127.0.0.1:${PORT}`;

const TOOLS = [
  {
    name: 'ping',
    description: 'Check that the Echo Shafts Debug build is listening.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'look',
    description: 'What a player can see: screen, life, nearby foes, the camp prompt, and the longevity report.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'stick',
    description: 'Hold the stick and buttons the way a finger would. Melee and Ranged stay down. Draught is a press. mx and my are -1 to 1.',
    inputSchema: {
      type: 'object',
      properties: {
        mx: { type: 'number' },
        my: { type: 'number' },
        melee: { type: 'boolean' },
        ranged: { type: 'boolean' },
        draught: { type: 'boolean' },
        lock: { type: 'number' },
        seconds: { type: 'number' },
      },
    },
  },
  {
    name: 'tap',
    description: 'Tap a button. button is origin, station, descend, vein, again, back, equip, dismiss, leave, hint, hand, wear, buy, refund, reset, silvarium, cataracta, or plate. wear and buy take id. reset starts a fresh agent save and does not touch the phone warden.',
    inputSchema: {
      type: 'object',
      properties: {
        button: { type: 'string' },
        id: { type: 'string' },
      },
      required: ['button'],
    },
  },
  {
    name: 'play',
    description: 'Let the player brain hold the stick and buttons until the timer ends, the shaft ends, or camp is reached. fresh uses a separate save.',
    inputSchema: {
      type: 'object',
      properties: {
        seconds: { type: 'number' },
        until: { type: 'string', enum: ['time', 'shaft', 'camp'] },
        origin: { type: 'string', enum: ['plate', 'silvarium', 'cataracta'] },
        style: { type: 'string', enum: ['echo', 'vein', 'mix'] },
        fresh: { type: 'boolean' },
      },
    },
  },
  {
    name: 'longevity',
    description: 'Play a long session on a fresh agent save and return the run report. style echo stays in practice then echo shafts. vein enters Deep Vein. mix does both. Does not replace the phone warden.',
    inputSchema: {
      type: 'object',
      properties: {
        seconds: { type: 'number' },
        origin: { type: 'string', enum: ['plate', 'silvarium', 'cataracta'] },
        style: { type: 'string', enum: ['echo', 'vein', 'mix'] },
      },
    },
  },
  {
    name: 'stop',
    description: 'Stop the player brain. Restores the phone warden if the session used an agent save.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'report',
    description: 'Longevity totals without starting a session.',
    inputSchema: { type: 'object', properties: {} },
  },
];

function write(msg) {
  const json = JSON.stringify(msg);
  process.stdout.write(`Content-Length: ${Buffer.byteLength(json)}\r\n\r\n${json}`);
}

function extractJson(s, from = 0) {
  const start = s.indexOf('{', from);
  if (start === -1) return null;
  let depth = 0;
  let inStr = false;
  let esc = false;
  for (let i = start; i < s.length; i++) {
    const ch = s[i];
    if (inStr) {
      if (esc) { esc = false; continue; }
      if (ch === '\\') { esc = true; continue; }
      if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') { inStr = true; continue; }
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) return { json: s.slice(start, i + 1), end: i + 1 };
    }
  }
  return null;
}

function takeMessage(buf) {
  const crlf = buf.indexOf('\r\n\r\n');
  const lf = buf.indexOf('\n\n');
  const headerEnd = crlf !== -1 ? crlf : lf;
  const sepLen = crlf !== -1 ? 4 : lf !== -1 ? 2 : 0;
  if (headerEnd !== -1 && sepLen) {
    const header = buf.subarray(0, headerEnd).toString('utf8');
    const m = /Content-Length:\s*(\d+)/i.exec(header);
    if (m) {
      const len = Number(m[1]);
      const start = headerEnd + sepLen;
      if (buf.length < start + len) return null;
      return { msg: JSON.parse(buf.subarray(start, start + len).toString('utf8')), rest: buf.subarray(start + len) };
    }
  }
  const s = buf.toString('utf8');
  const extracted = extractJson(s);
  if (!extracted) return null;
  return { msg: JSON.parse(extracted.json), rest: Buffer.from(s.slice(extracted.end)) };
}

async function call(method, path, body, timeout = 5000) {
  let res;
  try {
    res = await fetch(`${BASE}${path}`, {
      method,
      headers: body ? { 'content-type': 'application/json' } : undefined,
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(timeout),
    });
  } catch {
    throw new Error(`Echo Shafts is not listening on ${BASE}. Run the Debug scheme in the simulator.`);
  }
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(text.slice(0, 180) || `empty response from ${path}`);
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function format(state) {
  if (!state || state.ok === false) return state?.error || 'No answer from Echo Shafts.';
  const lines = [];
  const who = state.origin ? state.origin : 'no origin';
  lines.push(`${state.screen} · ${state.mode} · ${who} · Lv ${state.level} · Flesh ${state.flesh} · tutorial ${state.tutorial}`);
  if (state.player) {
    const p = state.player;
    lines.push(`You ${p.x}, ${p.y} · ${Math.round(p.hp)}/${Math.round(p.maxHp)} · draught ${p.potion}s`);
  }
  if (state.prompt) lines.push(`Prompt: ${state.prompt}`);
  if (state.note) lines.push(state.note);
  if (state.hint) lines.push(`Hint: ${state.hint}`);
  if (state.nearest) lines.push(`Nearest ${state.nearest.id} (${state.nearest.d})`);
  if (state.offer) lines.push(`Offer: ${state.offer}`);
  if (state.shaft) {
    const s = state.shaft;
    lines.push(`${s.kind} depth ${s.depth} · ${s.time}s · echo ${s.echo}/${s.need} · ${s.vessel} · alive ${s.alive} · seed ${s.seed}`);
  }
  if (state.foes?.length) {
    lines.push(state.foes.map((f) => `${f.name} ${f.d} ${Math.round(f.hp)}/${Math.round(f.maxHp)}`).join(' · '));
  }
  if (state.report) lines.push(formatReport(state.report));
  if (!state.listening) lines.push(state.error || 'The listener is not ready.');
  return lines.join('\n');
}

function formatReport(report) {
  const lines = [];
  lines.push(`Report ${report.runs} runs · ${report.clears} clears · ${report.deaths} deaths · ${report.timeouts} timeouts · ${report.abandoned} left · ${report.stalls} stalls · ${report.elapsed}s`);
  if (report.end) lines.push(`Ended: ${report.end}`);
  if (report.left) lines.push(`Left: ${report.left}s`);
  if (report.endLevel) lines.push(`Agent ended Lv ${report.endLevel} · Flesh ${report.endFlesh} · tutorial ${report.endTutorial}${report.endVein ? ` · vein ${report.endVein}` : ''}`);
  for (const issue of report.issues || []) lines.push(`Issue: ${issue}`);
  for (const run of report.recent || []) {
    lines.push(`${run.kind} ${run.outcome} depth ${run.depth} ${run.seconds}s echo ${run.echo}/${run.need} Lv ${run.level} flesh ${run.flesh} seed ${run.seed}${run.cut ? ' cut' : ''}${run.stalls ? ` stalls ${run.stalls}` : ''}`);
  }
  return lines.join('\n');
}

async function waitPlay(seconds) {
  const cap = (Math.min(620, Math.max(1, seconds) + 20)) * 1000;
  const start = Date.now();
  let last = null;
  let misses = 0;
  while (Date.now() - start < cap) {
    try {
      last = await call('GET', '/state');
      misses = 0;
      if (last.mode !== 'play' && last.mode !== 'hold') return last;
    } catch (err) {
      misses += 1;
      last = { ok: false, error: err instanceof Error ? err.message : String(err) };
      if (misses >= 3) return last;
    }
    await sleep(1000);
  }
  if (last && last.ok !== false) {
    last.report = last.report || {};
    last.report.issues = [...(last.report.issues || []), 'the longevity call returned before the session ended'];
  }
  return last;
}

function text(body, isError = false) {
  return { content: [{ type: 'text', text: body }], ...(isError ? { isError: true } : {}) };
}

async function tool(name, args) {
  if (name === 'ping') return text(format(await call('GET', '/health')));
  if (name === 'look' || name === 'report') return text(format(await call('GET', '/state')));
  if (name === 'stop') return text(format(await call('POST', '/stop', {})));
  if (name === 'tap') return text(format(await call('POST', '/act', { button: args.button, id: args.id || '' })));
  if (name === 'stick') {
    const seconds = Math.min(8, Math.max(0.05, Number(args.seconds) || 0.2));
    await call('POST', '/input', { ...args, seconds });
    await sleep(seconds * 1000 + 150);
    return text(format(await call('GET', '/state')));
  }
  if (name === 'play' || name === 'longevity') {
    const seconds = Math.min(600, Math.max(1, Number(args.seconds) || (name === 'longevity' ? 180 : 20)));
    const path = name === 'longevity' ? '/longevity' : '/play';
    const body = {
      seconds,
      until: args.until || 'time',
      origin: args.origin || 'plate',
      style: args.style || 'echo',
    };
    if (name === 'play' && args.fresh !== undefined) body.fresh = Boolean(args.fresh);
    await call('POST', path, body);
    return text(format(await waitPlay(seconds)));
  }
  return text(`Unknown tool ${name}`, true);
}

async function handle(msg) {
  if (!msg.method || msg.id === undefined) return;
  if (msg.method === 'initialize') {
    const requested = typeof msg.params?.protocolVersion === 'string' ? msg.params.protocolVersion : '2025-06-18';
    write({
      jsonrpc: '2.0',
      id: msg.id,
      result: {
        protocolVersion: requested,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'echoshafts', version: '0.1.0' },
        instructions: 'Echo Shafts must be running from the Debug scheme. look, then stick or tap to play by hand. play and longevity drive the stick and buttons. A fresh longevity session uses its own save.',
      },
    });
    return;
  }
  if (msg.method === 'ping') {
    write({ jsonrpc: '2.0', id: msg.id, result: {} });
    return;
  }
  if (msg.method === 'tools/list') {
    write({ jsonrpc: '2.0', id: msg.id, result: { tools: TOOLS } });
    return;
  }
  if (msg.method === 'prompts/list') {
    write({ jsonrpc: '2.0', id: msg.id, result: { prompts: [] } });
    return;
  }
  if (msg.method === 'resources/list') {
    write({ jsonrpc: '2.0', id: msg.id, result: { resources: [] } });
    return;
  }
  if (msg.method === 'tools/call') {
    try {
      write({ jsonrpc: '2.0', id: msg.id, result: await tool(String(msg.params?.name ?? ''), msg.params?.arguments ?? {}) });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      write({ jsonrpc: '2.0', id: msg.id, result: text(message, true) });
    }
    return;
  }
  write({ jsonrpc: '2.0', id: msg.id, error: { code: -32601, message: `Method not found: ${msg.method}` } });
}

let buf = Buffer.alloc(0);
let chain = Promise.resolve();
process.stdin.on('data', (chunk) => {
  buf = Buffer.concat([buf, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)]);
  while (true) {
    let taken = null;
    try { taken = takeMessage(buf); } catch { break; }
    if (!taken) break;
    buf = taken.rest;
    chain = chain.then(() => handle(taken.msg));
  }
});
process.stdin.resume();
