#!/bin/bash
set -e

# Definições de caminhos internos do container
STAGING_DIR="/totvs/protheus/patches_queue"
APO_DIR="/totvs/protheus/apo"
ROLLBACK_DIR="/totvs/protheus/apo/aporollback"
ENVIRONMENT="${ENV_NAME}"
CUSTOM_RPO="${RPO_CUSTOM_NAME:-custom}.rpo"

# Definições baseadas na especificação oficial de lote
LIST_FILE="/tmp/fontes_compilacao.lst"
OUTREPORT_DIR="/tmp/outreport/"
FILE_ERROR="${OUTREPORT_DIR}compile_errors.log"
FILE_SUCCESS="${OUTREPORT_DIR}compile_success.log"

# 📂 CAMINHOS DOS VOLUMES (Onde o host entrega os arquivos .zip)
VOL_ADVPL="/totvs/protheus/includes/advpl"
VOL_TLPP="/totvs/protheus/includes/tlpp"
VOL_CUSTOM="/totvs/protheus/includes/custom"

# 🚀 NOVOS CAMINHOS ISOLADOS (Dentro do /tmp interno do container, longe do Host)
INCLUDES_ADVPL="/tmp/includes_extracted/advpl"
INCLUDES_TLPP="/tmp/includes_extracted/tlpp"
INCLUDES_CUSTOM="/tmp/includes_extracted/custom"

echo "=== [Protheus-Compiler] Inicializando Esteira de Compilação GitOps (.LST) ==="

# 📦 [DYNAMIC UNZIP] Extrai os arquivos estritamente no escopo isolado do container
echo "📦 Isolando ambiente e checando pacotes compactados..."
mkdir -p "$INCLUDES_ADVPL" "$INCLUDES_TLPP" "$INCLUDES_CUSTOM"

if [ -f "${VOL_ADVPL}/includes.zip" ]; then
    echo "📂 Extraindo includes ADVPL para área temporária isolada do container..."
    unzip -joq "${VOL_ADVPL}/includes.zip" -d "$INCLUDES_ADVPL"
fi

if [ -f "${VOL_TLPP}/includes.zip" ]; then
    echo "📂 Extraindo includes TLPP para área temporária isolada do container..."
    unzip -joq "${VOL_TLPP}/includes.zip" -d "$INCLUDES_TLPP"
fi

if [ -f "${VOL_CUSTOM}/includes.zip" ]; then
    echo "📂 Extraindo includes Customizadas para área temporária isolada do container..."
    unzip -joq "${VOL_CUSTOM}/includes.zip" -d "$INCLUDES_CUSTOM"
fi

# Concatena as três variáveis isoladas usando o separador oficial ';'
INCLUDE_PATHS="${INCLUDES_ADVPL};${INCLUDES_TLPP};${INCLUDES_CUSTOM}"

# 1. Valida e monta o arquivo .lst em formato de linha única sem quebras ocultas
if [ -d "$STAGING_DIR" ]; then
    echo "🔍 Varrendo diretório de staging para gerar lote .lst..."
    
    FONTES=$(find "$STAGING_DIR" -type f \( -name "*.prw" -o -name "*.tlpp" -o -name "*.app" \) | tr '\n' ';')
    FONTES=$(echo "$FONTES" | tr -d '\r' | xargs)
    
    if [ -z "$FONTES" ]; then
        echo "❌ ERRO CRÍTICO: Nenhum arquivo .prw ou .tlpp localizado no staging!"
        exit 1
    fi
    
    printf "%s" "$FONTES" > "$LIST_FILE"
    
    echo "📝 Conteúdo do arquivo .lst estruturado para a TOTVS:"
    cat "$LIST_FILE"
    echo ""
else
    echo "❌ ERRO CRÍTICO: Diretório de staging não localizado!"
    exit 1
fi

# 2. Prepara os diretórios de saída do relatório e backup preventivo
mkdir -p "$OUTREPORT_DIR"
if [ -f "${APO_DIR}/${CUSTOM_RPO}" ]; then
    echo "💾 [Segurança] Gerando backup preventivo do RPO [${CUSTOM_RPO}]..."
    mkdir -p "$ROLLBACK_DIR"
    cp -p "${APO_DIR}/${CUSTOM_RPO}" "${ROLLBACK_DIR}/${CUSTOM_RPO}"
    BACKUP_EXISTS="true"
else
    BACKUP_EXISTS="false"
fi

# 3. Executa a compilação utilizando a nova sintaxe estrita da CLI
cd /totvs/protheus/bin/appserver
echo "⚙️  Invocando appsrvlinux com os parâmetros -files, -includes e -outreport..."
echo "📂 Mapeamento de Includes: ${INCLUDE_PATHS}"

ERROR=0
set +e
./appsrvlinux -compile -env="$ENVIRONMENT" -files="$LIST_FILE" -includes="$INCLUDE_PATHS" -outreport="$OUTREPORT_DIR"
ERROR=$?
set -e

# 4. Auditoria e validação pós-compilação com base no Outreport
echo "📊 Analisando relatórios de saída do compilador..."

if [ $ERROR -ne 0 ] || { [ -f "${FILE_ERROR}" ] && [ -s "${FILE_ERROR}" ]; }; then
    echo "❌ FALHA CRÍTICA: Detectados erros de compilação ou sintaxe nos fontes!"
    
    if [ -f "${FILE_ERROR}" ]; then
        echo "📝 --- LOG DE ERROS DA TOTVS ---"
        cat "${FILE_ERROR}"
        echo "--------------------------------"
    fi
    
    if [ "$BACKUP_EXISTS" = "true" ]; then
        echo "🔄 [ROLLBACK] Restaurando versão estável anterior do RPO..."
        cp -p "${ROLLBACK_DIR}/${CUSTOM_RPO}" "${APO_DIR}/${CUSTOM_RPO}"
        rm -f "${ROLLBACK_DIR}/${CUSTOM_RPO}"
    fi
    
    rm -f "$LIST_FILE"
    rm -rf "$OUTREPORT_DIR"
    rm -rf /tmp/includes_extracted
    exit 1
else
    echo "***************************************************"
    echo "* ✅ SUCESSO TOTAL: RPO compilado com sucesso!   *"
    echo "***************************************************"
    
    if [ -f "${FILE_SUCCESS}" ]; then
        echo "📝 Fontes integrados:"
        cat "${FILE_SUCCESS}"
    fi
    
    if [ "$BACKUP_EXISTS" = "true" ]; then
        rm -f "${ROLLBACK_DIR}/${CUSTOM_RPO}"
    fi
fi

rm -f "$LIST_FILE"
rm -rf "$OUTREPORT_DIR"
rm -rf /tmp/includes_extracted
echo "=== [Protheus-Compiler] Processo GitOps Encerrado ==="
exit 0