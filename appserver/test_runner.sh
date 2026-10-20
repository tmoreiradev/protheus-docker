#!/usr/bin/env bash
# ==============================================================================
# test_runner.sh — Esteira de testes ProBat (papel ROLE=test)
#
# Roda a suite ProBat compilada no RPO e devolve o resultado em JUnit XML.
# Espelha o code_compiler.sh: efemero, sincrono, exit code util para CI.
#
# COMO O PROBAT E DISPARADO (fonte: totvs/tlpp-probat-samples, run/probat_run.sh):
#
#   appserver -console -consolelog -allowexit -runstartnormal \
#             -run=<PROBAT_ENTRY> -env=<env> custom:<id>
#
# SEM -ini=, e isto e a armadilha 4 abaixo.
#
# PROBAT_ENTRY escolhe a funcao do -run= (padrao tlpp.probat.run). Uma thread de -run=
# nasce sem ambiente Protheus; para suites que precisam de dicionario/banco, aponte para
# um launcher seu que faca o RpcSetEnv e so entao chame o runner.
#
# Nao ha API REST nem patch da TOTVS envolvido — ao contrario do ADVPR, que
# exige o patch de Setup distribuido em advpr.totvs.com.br.
#
# TRES ARMADILHAS, todas descobertas na marra em 18/08/2026:
#
#   1. O -ini= NAO aceita caminho. Falha com "file name contains directory
#      information". Hoje isso nem se aplica: a armadilha 4 tirou o -ini= daqui.
#
#   2. O [ONSTART] precisa ser zerado. O appserver.custom.ini injeta
#      "Jobs=HTTPJOB" em TODOS os papeis; num run de teste esses
#      jobs sobem, erram por conta propria e poluem o log. O proprio custom.ini
#      ja documenta que isso quebra o upddistr e pede para comentar o bloco a
#      mao. Aqui nao: o runner zera Jobs= na sua COPIA do ini, sem exigir nada
#      do operador e sem tocar no arquivo do host.
#
#   3. A execucao e SILENCIOSA. run e export saem com 0 e nao imprimem nada; o
#      resultado vai so para o XML. Nao confunda "sem saida" com "nao rodou" —
#      para distinguir, um -run= inexistente sai 252 e um valido sai 0.
#
# E UMA QUARTA, medida em 13/09/2026, que custou quatro dias:
#
#   4. O ini de execucao TEM de se chamar appserver.ini. Com -ini=<outro nome> o
#      RpcSetEnv morre em "Mudanca invalida em RPO File on CRIAPUBLICA(APLIB100.PRW)
#      line : 1193" - no -run=, em job de [ONSTART] e em thread filha -, e o mesmo
#      conteudo gravado como appserver.ini passa. Sem RpcSetEnv as suites "itest"
#      caiam na preparacao manual, que abre o dicionario so para leitura.
#      Por isso a execucao roda num diretorio de symlinks com um appserver.ini
#      proprio (Jobs= zerado), e nao com uma copia de outro nome ao lado do original.
# ==============================================================================
set -uo pipefail

APP_DIR="/totvs/protheus/bin/appserver"
INI_SRC="${APP_DIR}/appserver.ini"
RUN_DIR="/tmp/probat_run"
RESULT_SRC="/totvs/protheus/system/resultsprobat.xml"
OUT_DIR="/totvs/protheus/test-results"
ENVIRONMENT="${ENV_NAME}"
RUN_ID="ci$(date +%Y%m%d%H%M%S)"
SUITE="${PROBAT_SUITE:-}"
ENTRY="${PROBAT_ENTRY:-tlpp.probat.run}"

echo "=== [Protheus-Test] Esteira ProBat — ambiente [${ENVIRONMENT}] ==="

[ -d "$APP_DIR" ] || { echo "❌ ERRO: ${APP_DIR} inacessivel."; exit 1; }

# 1. Diretorio de execucao: symlinks para o appserver e um appserver.ini proprio com o
#    ONSTART neutralizado (armadilhas 2 e 4). Ficam fora dos symlinks os arquivos que o
#    appserver escreve no proprio diretorio (.lck, .log, diagnostics.json).
rm -rf "$RUN_DIR" && mkdir -p "$RUN_DIR" || { echo "❌ ERRO: nao consegui criar ${RUN_DIR}."; exit 1; }
for f in "$APP_DIR"/*; do
    case "${f##*/}" in
        *.ini|*.lck|*.log|diagnostics.json) ;;
        *) ln -s "$f" "$RUN_DIR/${f##*/}" ;;
    esac
done
sed 's/^Jobs=.*/Jobs=/' "$INI_SRC" > "$RUN_DIR/appserver.ini"
cd "$RUN_DIR" || { echo "❌ ERRO: ${RUN_DIR} inacessivel."; exit 1; }
echo "🧹 ONSTART neutralizado no appserver.ini de execucao (${RUN_DIR})."

# 2. Resultado antigo fora do caminho, para nao virar falso-positivo
rm -f "$RESULT_SRC"
mkdir -p "$OUT_DIR"

# 3. Execucao
ARGS=(-console -consolelog -allowexit -runstartnormal
      -run="$ENTRY" -env="$ENVIRONMENT" "custom:${RUN_ID}")
echo "🔌 Entrada do ProBat: -run=${ENTRY}"
if [ -n "$SUITE" ]; then
    ARGS+=(type:suite "$SUITE")
    echo "🚀 Executando a suite [${SUITE}]..."
else
    echo "🚀 Executando TODAS as suites com @TestFixture no RPO..."
fi

./appsrvlinux "${ARGS[@]}" > /tmp/probat_run.log 2>&1
RUN_EXIT=$?

if [ "$RUN_EXIT" -ne 0 ]; then
    echo "❌ O appserver saiu com codigo ${RUN_EXIT} — o -run= nao foi honrado."
    echo "   (252 costuma significar funcao inexistente no RPO: o tlppCore desta"
    echo "    versao pode nao trazer o ProBat.)"
    tail -30 /tmp/probat_run.log
    exit 1
fi

# 4. Apuracao — o XML e a UNICA fonte de verdade (armadilha 3)
if [ ! -f "$RESULT_SRC" ]; then
    echo "❌ ERRO: execucao terminou em 0 mas nao gerou ${RESULT_SRC}."
    echo "   Sem XML nao ha como afirmar que algum teste rodou. Tratando como falha."
    tail -30 /tmp/probat_run.log
    exit 1
fi

cp "$RESULT_SRC" "${OUT_DIR}/resultsprobat.xml"

SUMMARY=$(grep -o 'tests="[0-9]*" ok="[0-9]*" failures="[0-9]*" skipped="[0-9]*"' "$RESULT_SRC" | head -1)
TESTS=$(echo   "$SUMMARY" | sed -n 's/.*tests="\([0-9]*\)".*/\1/p')
OK=$(echo      "$SUMMARY" | sed -n 's/.*ok="\([0-9]*\)".*/\1/p')
FAILURES=$(echo "$SUMMARY" | sed -n 's/.*failures="\([0-9]*\)".*/\1/p')
SKIPPED=$(echo "$SUMMARY" | sed -n 's/.*skipped="\([0-9]*\)".*/\1/p')

echo ""
echo "📊 Resultado (JUnit XML em ${OUT_DIR}/resultsprobat.xml)"
echo "   assertivas: ${TESTS:-?}  ok: ${OK:-?}  falhas: ${FAILURES:-?}  puladas: ${SKIPPED:-?}"
echo ""
echo "   Metodos exercitados:"
grep -oE 'Method:[A-Z0-9_]+\(\)' "$RESULT_SRC" | sort -u | sed 's/^/     - /'
echo ""

# Zero assertiva e falha: quer dizer que nada foi descoberto no RPO.
if [ -z "${TESTS:-}" ] || [ "${TESTS:-0}" -eq 0 ]; then
    echo "❌ Nenhuma assertiva executada — nenhum @TestFixture encontrado no RPO."
    echo "   Compile os fontes de teste antes: ./run.sh compile"
    exit 1
fi

if [ "${FAILURES:-1}" -ne 0 ]; then
    echo "***************************************************"
    echo "* ❌ FALHA: ${FAILURES} assertiva(s) nao passaram      *"
    echo "***************************************************"
    grep -E '<failure|<error' "$RESULT_SRC" | head -20
    exit 1
fi

echo "***************************************************"
echo "* ✅ SUCESSO: ${OK}/${TESTS} assertivas passaram          *"
echo "***************************************************"
echo "=== [Protheus-Test] Processo encerrado ==="
exit 0
