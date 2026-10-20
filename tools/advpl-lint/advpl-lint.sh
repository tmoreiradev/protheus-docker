#!/usr/bin/env bash
# advpl-lint.sh — roda o analisador estático oficial da TOTVS (totvsengpro/advpl-tlpp-code-analyzer)
# sobre fontes ADVPL/TLPP e devolve output.json + summary.md. Só relata: o exit code nunca
# depende das ocorrências (0 = analisou; 2 = o analisador não rodou).
#
# Uso:
#   advpl-lint.sh [-o <dir_saida>] [-c <config.json>] [-q] <arquivo|pasta>...
#
#   -o  pasta onde ficam output.json, execution.log, console.log e summary.md
#       (default: ./advpl-lint-<data-hora>)
#   -c  config.json do analisador (default: tools/advpl-lint/config.json do lab)
#   -q  não imprime o summary no stdout
#
# Detalhes do container (lidos do entrypoint.sh da imagem, 2026-09-11):
#   - copia TODO *.pr?/*.ppo/*.tlpp achado em /tmp (recursivo) para /bin/src, FLAT: dois
#     fontes com o mesmo nome em pastas diferentes se sobrescrevem;
#   - copia todo *.ch/*.th achado em /tmp (inclusive dentro dos fontes) para /bin/includes,
#     e por cima os includes padrão da imagem (/bin/includes_padrao, linha lobo_guara);
#   - as includes TLPP (tlpp-*.th) NÃO vêm na imagem: sem elas todo fonte com
#     #include "tlpp-core.th" cai em CA0000 (erro de compilação). Por isso montamos as
#     do lab (protheus/includes/_extracted/tlpp e custom).
set -u
IMG="${ADVPL_LINT_IMAGE:-totvsengpro/advpl-tlpp-code-analyzer}"
LAB="${PROTHEUS_LAB:-$(cd "$(dirname "$0")/../.." && pwd)}"
OUT=""; CONF="$LAB/tools/advpl-lint/config.json"; QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2;;
    -c) CONF="$2"; shift 2;;
    -q) QUIET=1; shift;;
    -h|--help) sed -n 2,22p "$0"; exit 0;;
    *) break;;
  esac
done
[ $# -gt 0 ] || { echo "informe ao menos um arquivo ou pasta" >&2; exit 2; }
[ -f "$CONF" ] || { echo "config não existe: $CONF" >&2; exit 2; }
[ -n "$OUT" ] || OUT="./advpl-lint-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)

WORK=$(mktemp -d /tmp/advpl-lint.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src" "$WORK/includes" "$WORK/out" "$WORK/conf"
chmod 777 "$WORK/out"

# --- fontes: pastas entram inteiras (o container acha recursivamente); arquivos vão flat.
#     Nome repetido ganha prefixo para não ser sobrescrito dentro do container.
copy_src() {  # $1 caminho do arquivo
  local B; B=$(basename "$1")
  [ -e "$WORK/src/$B" ] && B="dup$RANDOM-$B"
  cp "$1" "$WORK/src/$B"
}
for A in "$@"; do
  if [ -d "$A" ]; then
    while IFS= read -r -d '' F; do copy_src "$F"; done \
      < <(find "$A" -type f \( -iname "*.tlpp" -o -iname "*.prw" -o -iname "*.prx" \) -print0)
  elif [ -f "$A" ]; then
    copy_src "$A"
  else
    echo "ignorado (não existe): $A" >&2
  fi
done
N=$(find "$WORK/src" -type f | wc -l)
[ "$N" -gt 0 ] || { echo "nenhum fonte .tlpp/.prw/.prx encontrado" >&2; exit 2; }

# --- includes do lab (TLPP + custom); as ADVPL padrão já estão na imagem
for D in "$LAB/protheus/includes/_extracted/tlpp" "$LAB/protheus/includes/_extracted/custom"; do
  [ -d "$D" ] && find "$D" -maxdepth 1 -type f \( -iname "*.th" -o -iname "*.ch" \) -exec cp {} "$WORK/includes/" \;
done
cp "$CONF" "$WORK/conf/config.json"

docker run --rm \
  -v "$WORK/src:/tmp" -v "$WORK/includes:/tmp/includes" \
  -v "$WORK/out:/bin/output" -v "$WORK/conf:/bin/conf" \
  "$IMG" > "$WORK/console.log" 2>&1
RC=$?
cp "$WORK/console.log" "$OUT/console.log"
cp "$WORK/out/output.json" "$OUT/output.json" 2>/dev/null
cp "$WORK/out/execution.log" "$OUT/execution.log" 2>/dev/null
if [ ! -s "$OUT/output.json" ]; then
  echo "analisador não gerou output.json (rc=$RC); veja $OUT/console.log" >&2
  exit 2
fi

# --- summary.md: totais, por regra, por arquivo (com linhas)
python3 "$(dirname "$(readlink -f "$0")")/summary.py" "$OUT/output.json" "$OUT/summary.md" "$N"
[ "$QUIET" = 1 ] || cat "$OUT/summary.md"
echo "[advpl-lint] saída em $OUT (output.json, execution.log, console.log, summary.md)" >&2
exit 0
