#!/usr/bin/env python3
"""Resume o output.json do advpl-tlpp-code-analyzer em Markdown.

Uso: summary.py <output.json> <summary.md> <n_fontes>
"""
import collections
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
n_src = int(sys.argv[3])
rules = collections.Counter()
sev = collections.Counter()
per_file = collections.defaultdict(lambda: collections.defaultdict(list))
titles = {}
for f, items in data.items():
    for it in items:
        r = it.get("rule") or ""
        if not r:
            continue
        s = it.get("severity") or "?"
        rules[(s, r)] += 1
        sev[s] += 1
        per_file[f][f"{s} {r}"].append(str(it.get("line") or "?"))
        if r not in titles:
            msg = it.get("message") or ""
            t = msg.split("|")[0].replace("Regra:", "").replace(f"{r}:", "").strip(" .:")
            titles[r] = t[:90]

lines = []
tot = sum(sev.values())
lines.append(
    f"## Analisador estático TOTVS (advpl-tlpp-code-analyzer): {n_src} fonte(s), "
    f"{len(per_file)} com ocorrência, {sev.get('ERROR', 0)} ERROR, {sev.get('WARN', 0)} WARN"
)
lines.append("")
if tot == 0:
    lines.append("Nenhuma ocorrência.")
else:
    lines.append("| Sev. | Regra | Ocorrências | O que é |")
    lines.append("|---|---|---|---|")
    for (s, r), c in sorted(rules.items(), key=lambda x: (x[0][0] != "ERROR", -x[1])):
        lines.append(f"| {s} | {r} | {c} | {titles.get(r, '')} |")
    lines.append("")
    lines.append("### Por arquivo")
    for f in sorted(per_file, key=lambda x: -sum(len(v) for v in per_file[x].values())):
        parts = []
        for k, ls in sorted(per_file[f].items(), key=lambda x: (not x[0].startswith("ERROR"), x[0])):
            shown = ", ".join(ls[:8]) + (f", +{len(ls) - 8}" if len(ls) > 8 else "")
            parts.append(f"{k} ({shown})")
        lines.append(f"- `{f}`: " + "; ".join(parts))
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(lines) + "\n")
