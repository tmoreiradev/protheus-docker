#!/usr/bin/env bash
# ==============================================================================
# test-local.sh — ProBat no laço de desenvolvimento (rapido, sem subir container)
#
# Reaproveita o appserver_core que JA esta no ar em vez de criar um job efemero.
# Nao constroi imagem, nao para o core, nao reinicia nada.
#
#   ./test-local.sh              # todas as suites do RPO
#   ./test-local.sh minha_suite  # so uma suite
#
# ENTRADA DO PROBAT: por padrao -run=tlpp.probat.run, o runner do proprio ProBat.
# Uma thread de -run= nasce SEM ambiente (sem dDataBase, dicionario nem banco): todo
# teste que toca uma dessas coisas e ABORTADO inteiro, sem apontar assertiva. Para
# suites assim, compile um launcher seu que faca o RpcSetEnv e depois chame o runner:
#
#   PROBAT_ENTRY=U_MEUPROB ./test-local.sh
#
# Suites de integracao podem, alternativamente, preparar a PROPRIA thread no
# @OneTimeSetUp: o ProBat roda cada fixture numa thread diferente.
#
# QUANDO USAR O OUTRO CAMINHO: `./run.sh test` sobe um container dedicado e
# funciona mesmo com o core parado — é o que serve para automacao e para um
# ambiente limpo. Este aqui e para o ciclo curto de quem esta escrevendo teste.
#
# MEDIDO EM 18/08/2026, mesma suite de 19 assertivas:
#   ./run.sh test    58s   (3 builds + para o core + sobe container + restaura)
#   ./test-local.sh  13s   (só o boot do appserver dentro do core ativo)
#
# POR QUE NAO E MAIS RAPIDO QUE ISSO:
# O ini aceita [PROBAT] TESTS_DISCOVERY_MODE=0, que derruba para 4,3s. NAO USE.
# Medido: com DISCOVERY=0 o ProBat le um indice em CACHE e NAO enxerga teste
# recem-compilado — uma sonda compilada na hora apareceu com DISCOVERY=1 (20
# assertivas) e sumiu com DISCOVERY=0 (19). Os 3x de ganho custariam a unica
# coisa que a suite precisa garantir: que ela roda o que voce acabou de escrever.
# ==============================================================================
set -uo pipefail

# Um core por base (2026-10-05): sem PROBAT_CONTAINER, usa o core do lab ATUAL
# (.lab-current -> LAB_CONTAINER do .env.base.<nome>); sem nada disso, o protheus_core.
LAB_ATUAL=$(cat .lab-current 2>/dev/null || echo lab)
LAB_CONTAINER_DEFAULT=$(sed -n 's/^LAB_CONTAINER=//p' ".env.base.${LAB_ATUAL}" 2>/dev/null | head -1)
CONTAINER="${PROBAT_CONTAINER:-${LAB_CONTAINER_DEFAULT:-protheus_core}}"
ENVIRONMENT="${PROBAT_ENV:-protheus_dev}"
SUITE="${1:-}"
RUN_ID="dev$(date +%H%M%S)"
ENTRY="${PROBAT_ENTRY:-tlpp.probat.run}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "❌ O container [$CONTAINER] nao esta no ar."
    echo "👉 Suba o ambiente com ./run.sh — ou use ./run.sh test, que nao depende dele."
    exit 1
fi

# Qual base esta sendo medida. O appserver.ini da execucao sai do appserver.test.ini,
# que e um espelho escrito pelo ULTIMO `./run.sh test` e NAO acompanha o `./run.sh base`.
# Ate a  isso terminava em "TOPCONN -35 NO_DB_CONNECTION" com o lab parado em
# outra base (o gateway so conhece o alias da base em vigor). Agora o DBAlias da execucao
# e o do CORE em vigor (appserver.core.ini, reescrito a cada boot do core e portanto a cada
# `./run.sh base`): este script reaproveita o core no ar, entao mede a base que ele serve.
# Sem o core.ini (core nunca subiu com o entrypoint atual) vale o do test.ini, como antes.
BASE_ATUAL=$(docker exec "$CONTAINER" sh -c "sed -n 's/^DBAlias=//p' /totvs/protheus/generated/appserver.core.ini 2>/dev/null | head -1")
if [ -z "$BASE_ATUAL" ]; then
    BASE_ATUAL=$(docker exec "$CONTAINER" sh -c "sed -n 's/^DBAlias=//p' /totvs/protheus/generated/appserver.test.ini 2>/dev/null | head -1")
fi
echo "🗄️  Base: ${BASE_ATUAL:-<sem appserver.core.ini nem appserver.test.ini; rode ./run.sh test uma vez>}"

SUITE_ARGS=""
if [ -n "$SUITE" ]; then
    SUITE_ARGS="type:suite $SUITE"
    echo "🚀 ProBat — suite [$SUITE] em [$CONTAINER]"
else
    echo "🚀 ProBat — todas as suites do RPO em [$CONTAINER]"
fi

# O ini de execucao TEM de se chamar appserver.ini, e por isso o appserver roda num
# diretorio proprio, e nao com -ini=. Medido em 13/09/2026: com
# -ini=<qualquer outro nome> o RpcSetEnv morre em "Mudanca invalida em RPO File on
# CRIAPUBLICA(APLIB100.PRW) line : 1193" - no -run=, num job de [ONSTART] e numa thread
# filha. O MESMO conteudo gravado como appserver.ini passa nos tres. Era isso que
# quebrava toda suite de integracao que escreve no dicionario.
#
# O appserver.ini do core nao pode ser tocado, entao o diretorio e de symlinks para o
# binario, as libs e o tlpp.rpo, com um appserver.ini de verdade (Jobs= zerado: o
# [ONSTART] herdado subiria o HTTPJOB e poluiria o log). Ficam FORA dos symlinks o
# que o appserver escreve no proprio diretorio (.lck, .log, diagnostics.json): por
# symlink ele sobrescreveria o do core, e o diagnostics.json e o que o check-so.sh le.
docker exec -i -e RUN_DIR="/tmp/probat_$RUN_ID" -e BASE_ATUAL="$BASE_ATUAL" "$CONTAINER" sh -s <<EOF || { echo "❌ Falha ao executar o appserver dentro do container."; exit 1; }
    set -u
    rm -rf "\$RUN_DIR" && mkdir -p "\$RUN_DIR" || exit 1
    for f in /totvs/protheus/bin/appserver/*; do
        case "\${f##*/}" in
            *.ini|*.lck|*.log|diagnostics.json) ;;
            *) ln -s "\$f" "\$RUN_DIR/\${f##*/}" ;;
        esac
    done
    sed -e 's/^Jobs=.*/Jobs=/' -e "s/^DBAlias=.*/DBAlias=\${BASE_ATUAL}/" /totvs/protheus/generated/appserver.test.ini > "\$RUN_DIR/appserver.ini"
    cd "\$RUN_DIR" || exit 1
    rm -f /totvs/protheus/system/resultsprobat.xml
    ./appsrvlinux -console -consolelog -allowexit -runstartnormal \
        -run=$ENTRY -env=$ENVIRONMENT \
        custom:$RUN_ID $SUITE_ARGS > /tmp/probat_local.log 2>&1
    cd / && rm -rf "\$RUN_DIR"
EOF

XML=$(docker exec "$CONTAINER" sh -c 'cat /totvs/protheus/system/resultsprobat.xml 2>/dev/null')
if [ -z "$XML" ]; then
    echo "❌ Nenhum relatorio gerado — nada foi executado."
    echo "👉 Compile os fontes de teste antes: ./run.sh compile"
    docker exec "$CONTAINER" sh -c 'tail -20 /tmp/probat_local.log'
    exit 1
fi

S=$(echo "$XML" | grep -o 'tests="[0-9]*" ok="[0-9]*" failures="[0-9]*" skipped="[0-9]*"' | head -1)
T=$(echo "$S" | sed -n 's/.*tests="\([0-9]*\)".*/\1/p')
O=$(echo "$S" | sed -n 's/.*ok="\([0-9]*\)".*/\1/p')
F=$(echo "$S" | sed -n 's/.*failures="\([0-9]*\)".*/\1/p')

mkdir -p protheus/test-results
docker exec "$CONTAINER" sh -c 'cat /totvs/protheus/system/resultsprobat.xml' > protheus/test-results/resultsprobat.xml

echo ""
echo "$XML" | grep -oE 'Method:[A-Z0-9_]+\(\)' | sort -u | sed 's/^/  - /'
echo ""

if [ -z "${T:-}" ] || [ "${T:-0}" -eq 0 ]; then
    echo "❌ Nenhuma assertiva executada — nenhum @TestFixture no RPO."
    exit 1
fi
if [ "${F:-1}" -ne 0 ]; then
    echo "❌ FALHA: $F de $T assertivas nao passaram"
    echo "$XML" | grep -E '<failure|<error' | head -10
    exit 1
fi
echo "✅ $O/$T assertivas passaram  ·  JUnit em protheus/test-results/resultsprobat.xml"
