"""Gera docs/architecture.svg: diagrama animado (SMIL) do fluxo de uma requisição no lab.

Uso: python docs/gen_architecture_svg.py docs/architecture.svg
"""
import sys

W, H = 900, 400
T = 18.0          # ciclo total: 3 subciclos de 6 s, um por banco
SUB = 6.0
BLUE, GREEN = "#58a6ff", "#3fb950"

# caixas: nome -> (x, y, w, h, titulo, subtitulo, cor)
NODES = {
    "client": (20, 170, 150, 60, "Navegador", "SmartClient WebApp", "#8b949e"),
    "app":    (230, 170, 170, 60, "AppServer", ":1234 · REST :8400", "#58a6ff"),
    "dba":    (470, 170, 150, 60, "DBAccess", "dbaccesscfg", "#d29922"),
    "lic":    (350, 30, 170, 60, "License Server", "SYS_RAWIO · /dev/mem", "#a371f7"),
    "pg":     (720, 60, 160, 56, "PostgreSQL 16", "WIN1252 · C", "#4169e1"),
    "ms":     (720, 172, 160, 56, "SQL Server 2022", "Latin1_General_BIN", "#cc2927"),
    "or":     (720, 284, 160, 56, "Oracle 21c", "PDB · CURSOR_SHARING", "#f80000"),
}

PATHS = {
    "client-app": "M170,200 L230,200",
    "app-lic":    "M335,170 L405,90",
    "app-dba":    "M400,200 L470,200",
    "dba-lic":    "M520,170 L465,90",
    "dba-pg":     "M620,188 C670,188 670,88 720,88",
    "dba-ms":     "M620,200 L720,200",
    "dba-or":     "M620,212 C670,212 670,312 720,312",
}

# (path, ida?, inicio, fim) em fração do subciclo; ida=True percorre o path no sentido em que foi desenhado
STEPS = [
    ("client-app", True, 0.00, 0.08),
    ("app-lic", True, 0.10, 0.18), ("app-lic", False, 0.18, 0.26),
    ("app-dba", True, 0.28, 0.36),
    ("dba-lic", True, 0.38, 0.46), ("dba-lic", False, 0.46, 0.54),
    ("DB", True, 0.56, 0.66), ("DB", False, 0.68, 0.78),
    ("app-dba", False, 0.80, 0.88),
    ("client-app", False, 0.90, 0.98),
]
DBS = ["pg", "ms", "or"]
CAPTIONS = [
    (0.00, 0.10, "Requisição chega ao AppServer"),
    (0.10, 0.28, "AppServer valida a licença"),
    (0.28, 0.38, "AppServer pede os dados ao DBAccess"),
    (0.38, 0.56, "DBAccess valida a licença"),
    (0.56, 0.80, "DBAccess consulta o banco"),
    (0.80, 1.00, "Resposta volta ao usuário"),
]
EPS = 0.0005


def kt(*vals):
    return ";".join(f"{v:.4f}" for v in vals)


def window(s, e):
    """keyTimes de opacidade: invisível, aparece em s, some em e."""
    s, e = max(s, EPS * 2), min(e, 1 - EPS * 2)
    return kt(0, s - EPS, s, e, e + EPS, 1), "0;0;1;1;0;0"


out = []
a = out.append
a(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
  'role="img" aria-label="Fluxo de uma requisição: navegador, AppServer, License Server, DBAccess e banco de dados">')
a('<style>text{font-family:-apple-system,"Segoe UI",Helvetica,Arial,sans-serif}'
  '.t{font-size:15px;font-weight:600;fill:#e6edf3}.s{font-size:11px;fill:#8b949e}'
  '.c{font-size:14px;fill:#e6edf3}.l{font-size:11px;fill:#8b949e}</style>')
a('<defs><filter id="glow" x="-100%" y="-100%" width="300%" height="300%">'
  '<feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>'
  '</filter></defs>')
a(f'<rect width="{W}" height="{H}" rx="14" fill="#0d1117" stroke="#30363d"/>')

for d in PATHS.values():
    a(f'<path d="{d}" fill="none" stroke="#30363d" stroke-width="2.5" stroke-linecap="round"/>')

for key, (x, y, w, h, title, sub, color) in NODES.items():
    a(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="#161b22" stroke="{color}" stroke-width="1.5"/>')
    a(f'<rect x="{x}" y="{y + 8}" width="4" height="{h - 16}" rx="2" fill="{color}"/>')
    a(f'<text class="t" x="{x + w / 2}" y="{y + h / 2 - 2}" text-anchor="middle">{title}</text>')
    a(f'<text class="s" x="{x + w / 2}" y="{y + h / 2 + 15}" text-anchor="middle">{sub}</text>')
    if key in DBS:
        i = DBS.index(key)
        s, e = (i * SUB) / T, ((i + 1) * SUB) / T
        # brilho no banco ativo durante o subciclo dele
        times = kt(0, max(s, EPS * 2) - EPS, max(s, EPS * 2), min(e, 1 - EPS * 2), min(e, 1 - EPS * 2) + EPS, 1)
        a(f'<rect x="{x - 3}" y="{y - 3}" width="{w + 6}" height="{h + 6}" rx="12" fill="none" '
          f'stroke="{color}" stroke-width="2" opacity="0">'
          f'<animate attributeName="opacity" dur="{T}s" repeatCount="indefinite" '
          f'keyTimes="{times}" values="0;0;0.9;0.9;0;0"/></rect>')

for cycle in range(3):
    db = DBS[cycle]
    for name, forward, fs, fe in STEPS:
        path = PATHS[f"dba-{db}"] if name == "DB" else PATHS[name]
        s = (cycle * SUB + fs * SUB) / T
        e = (cycle * SUB + fe * SUB) / T
        s, e = max(s, EPS * 2), min(e, 1 - EPS * 2)
        p0, p1 = (0, 1) if forward else (1, 0)
        color = BLUE if forward else GREEN
        otimes, ovals = window(s, e)
        a(f'<path d="{path}" fill="none" stroke="{color}" stroke-width="3" stroke-linecap="round" opacity="0">'
          f'<animate attributeName="opacity" dur="{T}s" repeatCount="indefinite" keyTimes="{otimes}" '
          f'values="{ovals.replace("1", "0.55")}"/></path>')
        a(f'<circle r="6" fill="{color}" filter="url(#glow)" opacity="0">'
          f'<animateMotion dur="{T}s" repeatCount="indefinite" path="{path}" calcMode="linear" '
          f'keyPoints="{p0};{p0};{p1};{p1}" keyTimes="{kt(0, s, e, 1)}"/>'
          f'<animate attributeName="opacity" dur="{T}s" repeatCount="indefinite" keyTimes="{otimes}" values="{ovals}"/>'
          '</circle>')

# legenda do passo atual
for cycle in range(3):
    for cs, ce, text in CAPTIONS:
        s = (cycle * SUB + cs * SUB) / T
        e = (cycle * SUB + ce * SUB) / T
        otimes, ovals = window(s, e)
        a(f'<text class="c" x="40" y="330" opacity="0">{text}'
          f'<animate attributeName="opacity" dur="{T}s" repeatCount="indefinite" keyTimes="{otimes}" values="{ovals}"/></text>')

a(f'<circle cx="46" cy="362" r="5" fill="{BLUE}"/><text class="l" x="58" y="366">requisição</text>')
a(f'<circle cx="146" cy="362" r="5" fill="{GREEN}"/><text class="l" x="158" y="366">resposta</text>')
a('<text class="l" x="40" y="300">Um banco por vez, escolhido pelo DB_TYPE do .env</text>')
a('</svg>')

open(sys.argv[1], "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
