#!/usr/bin/env bash
# ==============================================================================
# check-so.sh — o SO das imagens está na lista homologada pela TOTVS?
# ==============================================================================
# O Protheus 12.1.2410+ valida o sistema operacional no primeiro acesso de cada
# base (tela "Finalizar", MSFINAL): em Produção e Homologação um SO fora da lista
# bloqueia o acesso. Para o instalador Linux 12.1.2410 valem SUSE 15, Red Hat 8 e
# Oracle Linux 8 — Ubuntu não consta em nenhuma versão da lista.
#
# Duas medições, porque são fontes diferentes:
#   1. `/etc/os-release` de cada container (o que o SO diz de si).
#   2. `operating_system.linux_distribution` do `diagnostics.json` que o próprio
#      AppServer escreve no boot (o que o Protheus leu, e é o texto que a tela
#      "Finalizar" exibe). Sem esta segunda o teste provaria a imagem, não o ERP.
#
# Uso: ./check-so.sh   → exit 0 se todos passam, 1 se algum reprova.
# ==============================================================================
set -uo pipefail

CONTAINERS=(protheus_core protheus_dbaccess protheus_license)
DIAG=/totvs/protheus/bin/appserver/diagnostics.json

# ID + major do VERSION_ID, como aparece em /etc/os-release.
HOMOLOGADOS=("ol:8" "rhel:8" "sles:15")

falhas=0

esta_na_lista() {
    local alvo="$1"
    for h in "${HOMOLOGADOS[@]}"; do [ "$alvo" = "$h" ] && return 0; done
    return 1
}

echo "🔎 SO homologado pelo Protheus 12.1.2410 — esperado: ${HOMOLOGADOS[*]}"
echo

for c in "${CONTAINERS[@]}"; do
    if ! docker inspect "$c" >/dev/null 2>&1; then
        echo "⏭️  $c não existe, pulando"
        continue
    fi

    os=$(docker exec "$c" cat /etc/os-release 2>/dev/null)
    if [ -z "$os" ]; then
        echo "❌ $c: não consegui ler /etc/os-release"
        falhas=$((falhas + 1))
        continue
    fi

    id=$(echo "$os"     | sed -n 's/^ID=//p'         | tr -d '"' | head -1)
    ver=$(echo "$os"    | sed -n 's/^VERSION_ID=//p' | tr -d '"' | head -1)
    pretty=$(echo "$os" | sed -n 's/^PRETTY_NAME=//p'| tr -d '"' | head -1)
    major="${ver%%.*}"

    if esta_na_lista "${id}:${major}"; then
        echo "✅ $c: $pretty (${id}:${major})"
    else
        echo "❌ $c: $pretty (${id}:${major}) — fora da lista"
        falhas=$((falhas + 1))
    fi
done

echo

# O que o AppServer leu, não o que a imagem diz. Só o core escreve diagnostics.json.
if docker inspect protheus_core >/dev/null 2>&1; then
    distro=$(docker exec protheus_core cat "$DIAG" 2>/dev/null \
             | sed -n 's/.*"linux_distribution":[^"]*"\([^"]*\)".*/\1/p' | head -1)
    lid=$(docker exec protheus_core cat "$DIAG" 2>/dev/null \
          | sed -n 's/.*"linux_id":[^"]*"\([^"]*\)".*/\1/p' | head -1)

    if [ -z "$distro" ]; then
        echo "❌ diagnostics.json do AppServer: sem linux_distribution (core já subiu?)"
        falhas=$((falhas + 1))
    elif esta_na_lista "${lid}:8" || esta_na_lista "${lid}:15"; then
        echo "✅ AppServer reporta: $distro (linux_id=$lid)"
    else
        echo "❌ AppServer reporta: $distro (linux_id=$lid) — fora da lista"
        falhas=$((falhas + 1))
    fi
fi

echo
if [ "$falhas" -eq 0 ]; then
    echo "✅ SO homologado em todos os pontos medidos."
    exit 0
fi
echo "❌ $falhas reprovação(ões). O Protheus recusa o acesso em ambiente de Produção/Homologação."
exit 1
