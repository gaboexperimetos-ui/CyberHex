#!/usr/bin/env python3
"""codegraph — grafo del programa en un solo HTML autocontenido.

Lee las importaciones reales de Dart, Zig y C/Cython del repo y escribe una
pagina `docs/ui/graph.html` con un layout de fisica (force-directed) en canvas:
nodos = ficheros, aristas = imports. Sirve para leer la arquitectura de un
vistazo en lugar de abrir decenas de ficheros.

Uso:
    python3 tools/codegraph.py                 # escribe docs/ui/graph.html
    python3 tools/codegraph.py --out /tmp/g.html
    python3 tools/codegraph.py --root . --no-external

Sin dependencias: solo la libreria estandar.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Carpetas que se leen, en el orden en que se muestran en la leyenda.
DEFAULT_DIRS = ["lib", "core/src", "core/include", "core/examples", "core/tests"]

EXTS = {".dart": "dart", ".zig": "zig", ".c": "c", ".h": "h"}

RE_DART = re.compile(r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""", re.M)
RE_ZIG = re.compile(r"""@import\(\s*"([^"]+)"\s*\)""")
RE_C = re.compile(r"""^\s*#\s*include\s+["<]([^">]+)[">]""", re.M)

# Colores por grupo (paleta CyberHex: verde, cian, violeta, rosa, ambar).
GROUP_COLORS = {
    "lib": "#22C55E",
    "core/src": "#22D3EE",
    "core/include": "#A78BFA",
    "core/examples": "#F472B6",
    "core/tests": "#F59E0B",
}


def group_of(rel: Path) -> str:
    parts = rel.parts
    if parts[0] == "lib":
        return "lib"
    if parts[0] == "core" and len(parts) > 1:
        return "/".join(parts[:2])
    return parts[0]


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def collect(root: Path, dirs: list[str]) -> dict[str, Path]:
    files: dict[str, Path] = {}
    for d in dirs:
        base = root / d
        if not base.is_dir():
            continue
        for p in sorted(base.rglob("*")):
            if p.is_file() and p.suffix in EXTS:
                files[p.relative_to(root).as_posix()] = p
    return files


def resolve(target: str, src: Path, files: dict[str, Path], root: Path) -> str | None:
    """Traduce un objetivo de import a la ruta relativa del fichero, o None."""
    if target.startswith(("dart:", "package:", "std", "http", "https")):
        return None
    if target.startswith("package:cyberhex/"):
        target = target[len("package:cyberhex/"):]
    if target.startswith("<") or target.startswith(">"):
        return None

    cand = (src.parent / target).resolve()
    for guess in (cand, root / target, root / "lib" / target, root / "core/include" / target):
        try:
            rel = guess.relative_to(root.resolve()).as_posix()
        except ValueError:
            continue
        if rel in files:
            return rel
    return None


def build(root: Path, dirs: list[str]) -> dict:
    files = collect(root, dirs)
    nodes, edges, external = [], [], 0
    ffi_users: list[str] = []

    for rel, path in files.items():
        text = read(path)
        kind = EXTS[path.suffix]
        if kind == "dart":
            targets = RE_DART.findall(text)
        elif kind == "zig":
            targets = RE_ZIG.findall(text)
        else:
            targets = RE_C.findall(text)
        nodes.append(
            {
                "id": rel,
                "label": path.name,
                "group": group_of(Path(rel)),
                "kind": kind,
                "lines": text.count("\n") + 1,
                "bytes": path.stat().st_size if path.exists() else 0,
            }
        )
        for t in targets:
            hit = resolve(t, path, files, root)
            if hit is None:
                if not t.startswith(("dart:", "package:", "std")) and not t.startswith("<"):
                    external += 1
                continue
            if hit != rel:
                edges.append({"s": rel, "t": hit})

        # El puente Dart -> nucleo es FFI, no un import: se detecta aparte.
        if kind == "dart" and ("dart:ffi" in text or "DynamicLibrary" in text):
            ffi_users.append(rel)

    # Arista de enlace FFI hacia la cabecera del nucleo.
    header = next(
        (h for h in ("core/include/cyberhex_core.h",) if h in files),
        next((h for h in files if h.endswith(".h")), None),
    )
    if header:
        for rel in ffi_users:
            if rel != header:
                edges.append({"s": rel, "t": header})

    # Deduplica aristas y calcula grado.
    seen, uniq = set(), []
    for e in edges:
        key = (e["s"], e["t"])
        if key in seen:
            continue
        seen.add(key)
        uniq.append(e)
    deg: dict[str, int] = {n["id"]: 0 for n in nodes}
    for e in uniq:
        deg[e["s"]] += 1
        deg[e["t"]] += 1
    for n in nodes:
        n["deg"] = deg[n["id"]]

    return {
        "nodes": nodes,
        "edges": uniq,
        "external": external,
        "root": root.name,
        "groups": [g for g in DEFAULT_DIRS if any(n["group"] == g for n in nodes)],
        "colors": GROUP_COLORS,
    }


PAGE = r"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CyberHex · grafo del programa</title>
<style>
  :root{--bg:#0b0b12;--ink:#e9e9f5;--muted:#9a9ab4;--line:rgba(255,255,255,.10);--accent:#22d3ee}
  *{box-sizing:border-box}
  html,body{height:100%}
  body{margin:0;background:var(--bg);color:var(--ink);overflow:hidden;
    font-family:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,Inter,sans-serif}
  canvas{position:fixed;inset:0;display:block;touch-action:none;cursor:grab}
  canvas.grabbing{cursor:grabbing}
  header{position:fixed;left:18px;top:16px;z-index:5;max-width:min(46ch,52vw);pointer-events:none}
  header h1{margin:0 0 4px;font-size:19px;letter-spacing:-.3px;font-weight:800;
    background:linear-gradient(120deg,#fff,#22d3ee 70%);-webkit-background-clip:text;background-clip:text;color:transparent}
  header p{margin:0;font-size:12.5px;color:var(--muted);line-height:1.45}
  .panel{position:fixed;right:16px;top:16px;z-index:6;width:min(330px,84vw);display:flex;flex-direction:column;gap:10px;
    background:rgba(14,14,22,.82);backdrop-filter:blur(14px);border:1px solid var(--line);border-radius:16px;padding:12px}
  .panel[hidden]{display:none}
  .panel .path{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;color:var(--accent);word-break:break-all}
  .panel h2{margin:2px 0 0;font-size:15px}
  .panel .meta{display:flex;gap:8px;flex-wrap:wrap;font-size:11px;color:var(--muted)}
  .panel .meta span{border:1px solid var(--line);border-radius:999px;padding:2px 8px}
  .panel ul{margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:3px;max-height:34vh;overflow:auto}
  .panel li{font-size:11.5px;color:var(--muted);font-family:ui-monospace,monospace;cursor:pointer;padding:2px 4px;border-radius:6px}
  .panel li:hover{background:rgba(255,255,255,.07);color:var(--ink)}
  .panel .close{align-self:flex-end;appearance:none;border:1px solid var(--line);background:transparent;color:var(--muted);
    border-radius:999px;padding:3px 10px;font-size:11px;cursor:pointer}
  .hud{position:fixed;left:18px;bottom:16px;z-index:5;display:flex;flex-direction:column;gap:9px;align-items:flex-start}
  .legend{display:flex;flex-wrap:wrap;gap:10px;font-size:11.5px;color:var(--muted);max-width:min(560px,72vw)}
  .legend i{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:5px;vertical-align:middle}
  .tools{display:flex;gap:7px}
  .tools button{appearance:none;border:1px solid var(--line);background:rgba(20,20,30,.8);color:var(--ink);
    border-radius:999px;padding:6px 13px;font-size:12px;cursor:pointer}
  .tools button:hover{border-color:var(--accent);color:var(--accent)}
  .tools input{border:1px solid var(--line);background:rgba(20,20,30,.8);color:var(--ink);border-radius:999px;
    padding:6px 13px;font-size:12px;width:190px;outline:none}
  .tools input:focus{border-color:var(--accent)}
  .tip{position:fixed;z-index:7;pointer-events:none;background:rgba(10,10,16,.94);border:1px solid var(--line);
    border-radius:9px;padding:5px 9px;font-size:11.5px;font-family:ui-monospace,monospace;opacity:0;transition:opacity .12s;white-space:nowrap}
  .err{position:fixed;inset:0;display:grid;place-items:center;color:#ff6b81;font:14px ui-monospace,monospace}
</style>
</head>
<body>
<canvas id="c"></canvas>
<header>
  <h1>CyberHex · grafo del programa</h1>
  <p>Nodos = ficheros, aristas = imports reales. Arrastra, rueda para zoom, clic para leer un fichero.</p>
</header>

<aside class="panel" id="panel" hidden>
  <button class="close" id="close">cerrar</button>
  <div class="path" id="p-path"></div>
  <h2 id="p-name"></h2>
  <div class="meta" id="p-meta"></div>
  <ul id="p-in"></ul>
  <ul id="p-out"></ul>
</aside>

<div class="hud">
  <div class="legend" id="legend"></div>
  <div class="tools">
    <input id="q" placeholder="filtrar ficheros…" autocomplete="off">
    <button id="fit">recentrar</button>
    <button id="lab">etiquetas</button>
  </div>
</div>
<div class="tip" id="tip"></div>

<script>
const DATA = __DATA__;
const cv = document.getElementById('c');
const ctx = cv.getContext('2d');
const tip = document.getElementById('tip');
const panel = document.getElementById('panel');

let W = 0, H = 0, DPR = 1;
function resize(){
  DPR = Math.min(devicePixelRatio || 1, 2);
  W = cv.clientWidth; H = cv.clientHeight;
  cv.width = Math.round(W * DPR); cv.height = Math.round(H * DPR);
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
}
addEventListener('resize', resize);

const COLORS = DATA.colors;
const nodes = DATA.nodes.map((n, i) => {
  const a = (i / Math.max(DATA.nodes.length, 1)) * Math.PI * 2;
  const g = DATA.groups.indexOf(n.group);
  const rad = 120 + g * 90;
  return Object.assign({}, n, {
    x: Math.cos(a) * rad + (Math.random() - .5) * 40,
    y: Math.sin(a) * rad + (Math.random() - .5) * 40,
    vx: 0, vy: 0,
    r: Math.max(3.5, Math.min(15, 3 + Math.sqrt(n.lines) * 0.55)),
    color: COLORS[n.group] || '#94a3b8'
  });
});
const byId = new Map(nodes.map(n => [n.id, n]));
const links = DATA.edges.map(e => ({ s: byId.get(e.s), t: byId.get(e.t) })).filter(l => l.s && l.t);
const adj = new Map(nodes.map(n => [n.id, { in: [], out: [] }]));
for (const l of links) { adj.get(l.s.id).out.push(l.t); adj.get(l.t.id).in.push(l.s); }

let alpha = 1, view = { x: W / 2, y: H / 2, k: 1 }, showLabels = true, hover = null, sel = null, query = '';

function alphaTarget() { return alpha; }

function tick(){
  const n = nodes.length;
  // Repulsion O(n^2): con ~100 ficheros sobra.
  for (let i = 0; i < n; i++) {
    const a = nodes[i];
    for (let j = i + 1; j < n; j++) {
      const b = nodes[j];
      let dx = b.x - a.x, dy = b.y - a.y;
      let d2 = dx * dx + dy * dy;
      if (d2 < 1) { dx = Math.random() - .5; dy = Math.random() - .5; d2 = 1; }
      const d = Math.sqrt(d2);
      const f = (2600 * alpha) / d2;
      const ux = dx / d, uy = dy / d;
      a.vx -= ux * f; a.vy -= uy * f;
      b.vx += ux * f; b.vy += uy * f;
    }
  }
  // Muelles.
  for (const l of links) {
    const dx = l.t.x - l.s.x, dy = l.t.y - l.s.y;
    const d = Math.max(Math.hypot(dx, dy), .01);
    const f = (d - 108) * 0.045 * alpha;
    const ux = dx / d, uy = dy / d;
    l.s.vx += ux * f; l.s.vy += uy * f;
    l.t.vx -= ux * f; l.t.vy -= uy * f;
  }
  // Gravedad al centro + amortiguacion.
  for (const p of nodes) {
    p.vx += (W / 2 - p.x) * 0.0016 * alpha;
    p.vy += (H / 2 - p.y) * 0.0016 * alpha;
    if (p === sel || p === hover) { p.vx *= .55; p.vy *= .55; continue; }
    p.vx *= .84; p.vy *= .84;
    p.x += p.vx; p.y += p.vy;
  }
  alpha *= 0.985;
  if (alpha < 0.015) alpha = 0.015;
}

function toWorld(px, py){ return { x: (px - view.x) / view.k, y: (py - view.y) / view.k }; }

function draw(){
  ctx.clearRect(0, 0, W, H);
  // Fondo procedural: halos del tema.
  const g1 = ctx.createRadialGradient(W * .18, H * .12, 0, W * .18, H * .12, Math.max(W, H) * .8);
  g1.addColorStop(0, 'rgba(34,211,238,.10)'); g1.addColorStop(1, 'rgba(34,211,238,0)');
  ctx.fillStyle = g1; ctx.fillRect(0, 0, W, H);
  const g2 = ctx.createRadialGradient(W * .92, H * .05, 0, W * .92, H * .05, Math.max(W, H) * .7);
  g2.addColorStop(0, 'rgba(167,139,250,.10)'); g2.addColorStop(1, 'rgba(167,139,250,0)');
  ctx.fillStyle = g2; ctx.fillRect(0, 0, W, H);

  ctx.save();
  ctx.translate(view.x, view.y); ctx.scale(view.k, view.k);

  const focus = hover || sel;
  const near = focus ? new Set([focus.id, ...adj.get(focus.id).in.map(n => n.id), ...adj.get(focus.id).out.map(n => n.id)]) : null;

  ctx.lineWidth = 1 / view.k;
  for (const l of links) {
    const on = !near || near.has(l.s.id) && near.has(l.t.id);
    ctx.strokeStyle = on ? 'rgba(148,163,184,.34)' : 'rgba(148,163,184,.09)';
    ctx.beginPath(); ctx.moveTo(l.s.x, l.s.y); ctx.lineTo(l.t.x, l.t.y); ctx.stroke();
  }

  for (const p of nodes) {
    const dim = near && !near.has(p.id);
    const match = !query || p.id.toLowerCase().includes(query);
    ctx.globalAlpha = dim ? .22 : (match ? 1 : .16);
    ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
    ctx.fillStyle = p.color; ctx.fill();
    if (p === hover || p === sel) {
      ctx.lineWidth = 2 / view.k; ctx.strokeStyle = '#fff'; ctx.stroke();
    }
    if (showLabels && (view.k > .85 || p.r > 9 || p === hover || p === sel)) {
      ctx.fillStyle = 'rgba(233,233,245,.92)';
      ctx.font = `${Math.max(9, 10.5 / Math.max(view.k, .6))}px ui-monospace,monospace`;
      ctx.fillText(p.label, p.x + p.r + 4 / view.k, p.y + 3 / view.k);
    }
  }
  ctx.globalAlpha = 1;
  ctx.restore();
}

let raf = 0, running = true;
function loop(){
  if (running) { tick(); }
  draw();
  raf = requestAnimationFrame(loop);
}

// ---- interaccion ----
let drag = null, panning = false, moved = false;
cv.addEventListener('pointerdown', e => {
  cv.setPointerCapture(e.pointerId);
  const w = toWorld(e.clientX, e.clientY);
  const hit = pick(w.x, w.y);
  moved = false;
  if (hit) { sel = hit; showPanel(hit); alpha = Math.max(alpha, .5); drag = hit; }
  else { panning = true; drag = { x: e.clientX, y: e.clientY }; }
  cv.classList.add('grabbing');
});
cv.addEventListener('pointermove', e => {
  if (drag && drag.id) {
    const w = toWorld(e.clientX, e.clientY);
    drag.x = w.x; drag.y = w.y; drag.vx = 0; drag.vy = 0;
    moved = true; alpha = Math.max(alpha, .45);
    return;
  }
  if (panning && drag) {
    view.x += e.clientX - drag.x; view.y += e.clientY - drag.y;
    drag = { x: e.clientX, y: e.clientY }; moved = true; return;
  }
  const w = toWorld(e.clientX, e.clientY);
  const hit = pick(w.x, w.y);
  hover = hit;
  if (hit) {
    tip.textContent = hit.id + ' · ' + hit.lines + ' líneas';
    tip.style.opacity = '1';
    tip.style.left = (e.clientX + 14) + 'px';
    tip.style.top = (e.clientY + 14) + 'px';
    cv.style.cursor = 'pointer';
  } else { tip.style.opacity = '0'; cv.style.cursor = ''; }
});
addEventListener('pointerup', () => { drag = null; panning = false; cv.classList.remove('grabbing'); });
cv.addEventListener('wheel', e => {
  e.preventDefault();
  const k0 = view.k, k1 = Math.min(3.2, Math.max(.25, k0 * (e.deltaY < 0 ? 1.12 : .89)));
  const mx = e.clientX, my = e.clientY;
  view.x = mx - (mx - view.x) * (k1 / k0);
  view.y = my - (my - view.y) * (k1 / k0);
  view.k = k1;
}, { passive: false });

function pick(x, y){
  let best = null, bd = Infinity;
  for (const p of nodes) {
    const d = Math.hypot(p.x - x, p.y - y);
    if (d < p.r + 6 / view.k && d < bd) { bd = d; best = p; }
  }
  return best;
}

function showPanel(p){
  panel.hidden = false;
  document.getElementById('p-path').textContent = p.id;
  document.getElementById('p-name').textContent = p.label;
  document.getElementById('p-meta').innerHTML =
    `<span>${p.lines} líneas</span><span>${(p.bytes / 1024).toFixed(1)} KB</span>` +
    `<span>${p.kind}</span><span>grado ${p.deg}</span>`;
  const fill = (el, arr) => {
    el.innerHTML = '';
    for (const t of arr.slice(0, 40)) {
      const li = document.createElement('li');
      li.textContent = t.id;
      li.onclick = () => { sel = t; showPanel(t); alpha = Math.max(alpha, .5); };
      el.appendChild(li);
    }
  };
  fill(document.getElementById('p-in'), adj.get(p.id).in);
  fill(document.getElementById('p-out'), adj.get(p.id).out);
}
document.getElementById('close').onclick = () => { panel.hidden = true; sel = null; };

document.getElementById('fit').onclick = () => {
  if (!nodes.length) return;
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const p of nodes) { minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x); minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y); }
  const k = Math.min(2.2, Math.max(.3, Math.min(W / (maxX - minX + 120), H / (maxY - minY + 120))));
  view.k = k;
  view.x = W / 2 - ((minX + maxX) / 2) * k;
  view.y = H / 2 - ((minY + maxY) / 2) * k;
  alpha = .8;
};
document.getElementById('lab').onclick = () => { showLabels = !showLabels; };
const qEl = document.getElementById('q');
qEl.oninput = () => { query = qEl.value.trim().toLowerCase(); };

document.getElementById('legend').innerHTML = DATA.groups.map(g =>
  `<span><i style="background:${COLORS[g] || '#94a3b8'}"></i>${g}</span>`).join('') +
  `<span style="color:#64748b">${DATA.nodes.length} ficheros · ${DATA.edges.length} imports · ${DATA.external} externos</span>`;

resize();
for (let i = 0; i < 260; i++) tick();
loop();
</script>
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser(description="Grafo del programa en un HTML autocontenido.")
    ap.add_argument("--root", default=".", help="raiz del repo (por defecto .)")
    ap.add_argument("--out", default=None, help="ruta de salida (por defecto docs/ui/graph.html)")
    ap.add_argument("--dirs", nargs="*", default=None, help="carpetas a leer")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    if not (root / "lib").is_dir() and not (root / "core").is_dir():
        print(f"no parece el repo CyberHex: {root}", file=sys.stderr)
        return 2

    data = build(root, args.dirs or DEFAULT_DIRS)
    if not data["nodes"]:
        print("sin ficheros que graficar", file=sys.stderr)
        return 3

    out = Path(args.out) if args.out else root / "docs/ui/graph.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    out.write_text(PAGE.replace("__DATA__", payload), encoding="utf-8")

    print(f"{out}  ·  {len(data['nodes'])} nodos, {len(data['edges'])} aristas, {data['external']} imports externos")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())