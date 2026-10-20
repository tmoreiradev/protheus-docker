#!/bin/bash
set -e

# Traduz o argumento do container em minúsculas (core, worker, upddistr, compile)
ROLE=$(echo "$1" | tr '[:upper:]' '[:lower:]')
echo "=== [AppServer] Inicializando Modo Especialista: [${ROLE^^}] ==="

# Mapeamento dinâmico das variáveis globais injetadas pelo Docker Compose
PORT=${APP_PORT_MULTI}
LICENSE_HOST=${LICENSE_SERVER:-protheus_license}
LICENSE_PORT=${LICENSE_SERVER_PORT:-5555}
DB_PORT_INI=${DBACCESS_PORT:-7890}
DB_SERVER_INI=${DBACCESS_SERVER:-protheus_dbaccess}

# Garante o fallback do nome do RPO Customizado caso não esteja mapeado
RPO_CUSTOM_TARGET="${RPO_CUSTOM_NAME:-custom}"

# Tratamento exclusivo para o nome do log do ConsoleFile baseado no serviço
case "$ROLE" in
    core)     LOG_NAME="appserver_core.log"     ;;
    worker)   LOG_NAME="appserver_worker.log"   ;;
    upddistr) LOG_NAME="appserver_upddistr.log" ;;
    compile)  LOG_NAME="appserver_compiler.log" ;;
    test)     LOG_NAME="appserver_test.log"     ;;
    *)        LOG_NAME="appserver.log"          ;;
esac

# 1. Aguarda a retaguarda de infraestrutura estar online de forma flexível
echo "⏳ Validando conectividade com o barramento de infraestrutura..."
while ! nc -z "$DB_SERVER_INI" "$DB_PORT_INI"; do sleep 1; done
while ! nc -z "$LICENSE_HOST" "$LICENSE_PORT"; do sleep 1; done
echo "✅ Conectividade com DbAccess e License Server established!"


# 2. Carga Inicial Isolada com Injeção Segura de Travas
echo "📦 Verificando integridade dos volumes isolados..."

# Garante a árvore mínima necessária dentro dos volumes do Docker
mkdir -p /totvs/protheus/system /totvs/protheus/systemload /totvs/protheus/log /totvs/protheus/data /totvs/protheus/apo/aporollback /totvs/protheus/patches_queue

# --- EXTRAÇÃO ISOLADA DO FISCAL.ZIP ---
if [ ! -f "/totvs/protheus/system/.fiscal_boot_done" ]; then
    if [ -f "/tmp/source_system/fiscal.zip" ]; then
        echo "📂 [First Boot] Extraindo dicionários de sistema (fiscal.zip)..."
        touch /totvs/protheus/system/.fiscal_boot_done
        unzip -nq /tmp/source_system/fiscal.zip -d /totvs/protheus/system/
        echo "✅ Arquivos do fiscal.zip populados com sucesso!"
    fi
else
    echo "⏭️  Arquivos do fiscal.zip já inicializados anteriormente. Pulando."
fi

# --- EXTRAÇÃO ISOLADA DO MENUS.ZIP ---
if [ ! -f "/totvs/protheus/system/.menus_boot_done" ]; then
    if [ -f "/tmp/source_system/menus.zip" ]; then
        echo "📂 [First Boot] Extraindo menus corporativos (menus.zip)..."
        touch /totvs/protheus/system/.menus_boot_done
        unzip -nq /tmp/source_system/menus.zip -d /totvs/protheus/system/
        if [ -d "/totvs/protheus/system/menus" ]; then
            echo "📂 Ajustando estrutura de diretórios do menus.zip para a raiz da system..."
            mv /totvs/protheus/system/menus/* /totvs/protheus/system/ 2>/dev/null || true
            rmdir /totvs/protheus/system/menus 2>/dev/null || true
        fi
        echo "✅ Arquivos do menus.zip populados com sucesso!"
    fi
else
    echo "⏭️  Arquivos do menus.zip já inicializados anteriormente. Pulando."
fi

# --- EXTRAÇÃO ISOLADA DO SYSTEMLOAD (DICIONÁRIO COMPLETO, DIFERENCIAL E HELP) ---
# O UPDDISTR exige os dois dicionários: o completo (SXSppp.TXT, em dicionarios.zip)
# e o diferencial (SDFppp.TXT, em diferencial.zip). Faltando o diferencial, ele morre
# com "File \systemload\SDFppp.TXT not found".
#
# Os dois pacotes trazem um sx2.unq cada. O `-n` não sobrescreve, então vence o do
# dicionário completo — que é o superset. A ordem do laço é, portanto, significativa.
if [ ! -f "/totvs/protheus/systemload/.systemload_boot_done" ]; then
    echo "📂 [First Boot] Extraindo dados de carga in /totvs/protheus/systemload/ (Aguarde)..."
    touch /totvs/protheus/systemload/.systemload_boot_done
    for PKG in dicionarios diferencial help; do
        if [ -f "/tmp/source_systemload/${PKG}.zip" ]; then
            echo "   → ${PKG}.zip"
            unzip -nq "/tmp/source_systemload/${PKG}.zip" -d /totvs/protheus/systemload/
        fi
    done
    echo "✅ Volume systemload populado com sucesso!"
else
    echo "⏭️  Volume systemload já inicializado anteriormente. Pulando extração."
fi

# 3. Renderização dinâmica do appserver.ini com as variáveis validadas
cd /totvs/protheus/bin/appserver
echo "📝 Gerando appserver.ini dinâmico para o modo [${ROLE^^}]..."

# Escrita limpa sem escape de variáveis locais, mapeando dinamicamente o nome do RPO Customizado
cat <<EOF > appserver.ini
[${ENV_NAME}]
SourcePath=/totvs/protheus/apo
RPOCustom=/totvs/protheus/apo/${RPO_CUSTOM_TARGET}.rpo
RPOTLPP=/totvs/protheus/apo/tlpp.rpo
RootPath=/totvs/protheus
StartPath=/system/
RpoDb=SQL
RpoLanguage=Multi
RpoVersion=120
LocalFiles=SQLITE
LocalDbExtension=.db
StartSysInDB=1
TopMemoMega=50
DBPort=${DB_PORT_INI}
DBAlias=${DB_NAME}
DBServer=${DB_SERVER_INI}
DBDatabase=${DB_TYPE}

[Drivers]
Active=TCP
MultiProtocolPort=$( [ "$ROLE" = "upddistr" ] || [ "$ROLE" = "compile" ] || [ "$ROLE" = "test" ] && echo "0" || echo "1" )
MultiProtocolPortSecure=0

[TCP]
TYPE=TCPIP
Port=${PORT}

[LicenseClient]
Server=${LICENSE_HOST}
Port=${LICENSE_PORT}

[General]
$( [ "$ROLE" = "upddistr" ] || [ "$ROLE" = "compile" ] || [ "$ROLE" = "test" ] && echo ";app_environment=${ENV_NAME}" || echo "app_environment=${ENV_NAME}" )
ShowFullLog=0
MaxStringSize=500
MaxQuerySize=31960
PowerSchemeShowUpgradeSuggestion=0
ConsoleFile=/totvs/protheus/log/${LOG_NAME}
ConsoleLog=1
AsyncConsoleLog=1
BuildKillUsers=1

[WebApp]
Port=${PORT}
LastMainProg=SIGAADV,SIGACFG,MPSDU,SIGAMDI
EnvServer=${ENV_NAME}
NonStopOnError=1
EOF

# 🛡️ Injeção de Segurança e Governança Cirúrgica Baseada no Papel
if [ "$ROLE" = "worker" ] || [ "$ROLE" = "upddistr" ] || [ "$ROLE" = "compile" ] || [ "$ROLE" = "test" ]; then
    cat <<EOF >> appserver.ini

[WebMonitor]
Enable=0

[APP_MONITOR]
Enable=0
Gui=0

[TDS]
AllowMonitor=*
AllowApplyPatch=*
AllowEdit=*
EnableDisconnectUser=*
EnableSendMessage=*
EnableBlockNewConnection=*
EnableStopServer=*
EOF
else
    # Bloqueio rigoroso de governança nos ambientes de Runtime
    cat <<EOF >> appserver.ini

[WebMonitor]
Enable=0

[APP_MONITOR]
Enable=0
Gui=0

[TDS]
AllowMonitor=*
AllowApplyPatch=0
AllowEdit=0
EnableDisconnectUser=0
EnableSendMessage=0
EnableBlockNewConnection=0
EnableStopServer=0
EOF
fi

# Bloco estrutural WebApp comum a todos
cat <<EOF >> appserver.ini

[WebApp/webapp]
MPP=
EOF

# Append dos blocos especialistas dedicados (REST no CORE / UPDDISTR)
#
# O REST roda dentro do próprio core, num servidor HTTP dedicado numa porta
# separada (REST_HTTP_PORT). Não conflita com o WebApp, que é servido pela porta
# multiprotocolo (APP_PORT_MULTI).
if [ "$ROLE" = "core" ]; then
    cat <<EOF >> appserver.ini

[HTTPJOB]
Main=HTTP_START
Environment=${ENV_NAME}

[ONSTART]
Jobs=HTTPJOB
RefreshRate=120

[HTTPV11]
Enable=1
Sockets=HTTPREST

[HTTPREST]
Port=${REST_HTTP_PORT}
URIs=HTTPURI
SECURITY=1

[HTTPURI]
URL=${REST_URI}
PrepareIn=${REST_PREP_ENV}
Instances=${REST_INSTANCES}
Stateless=1
CORSEnable=1
AllowOrigin=*
EOF
elif [ "$ROLE" = "upddistr" ]; then
    cat <<EOF >> appserver.ini

[UPDJOB]
MAIN=UPDDISTR
ENVIRONMENT=${ENV_NAME}

[ONSTART]
Jobs=UPDJOB
RefreshRate=900
EOF
fi

# 3.1 Overrides do appserver.custom.ini
#
# Ponto de extensão: o .ini é gerado do zero a cada boot, então editá-lo dentro
# do container não adianta. Aqui mesclamos o arquivo de override do host —
# chave existente é substituída na seção certa, chave nova é acrescentada.
# É a última etapa antes de subir o binário, de propósito: o override vence.
CUSTOM_INI="/tmp/appserver.custom.ini"
if [ -f "$CUSTOM_INI" ] && grep -qE '^[[:space:]]*[^#;[:space:]][^=]*=' "$CUSTOM_INI"; then
    echo "🧩 Aplicando overrides de appserver.custom.ini..."
    awk -f /usr/local/bin/ini_merge.awk "$CUSTOM_INI" appserver.ini > appserver.ini.merged
    mv appserver.ini.merged appserver.ini
    echo "✅ appserver.ini mesclado com os overrides."
fi

# 3.2 Espelho de leitura no host
#
# Exporta o .ini FINAL — já com os overrides — para que dê para conferir todas as
# chaves em vigor sem entrar no container. Um arquivo por papel, porque o .ini é
# diferente em cada um (MultiProtocolPort, app_environment, [TDS], ONSTART...).
#
# É saída, nunca entrada: nada aqui é lido de volta. Um espelho que servisse de
# entrada congelaria os valores que vêm do .env e criaria duas fontes de verdade.
MIRROR_DIR="/totvs/protheus/generated"
if [ -d "$MIRROR_DIR" ]; then
    MIRROR="${MIRROR_DIR}/appserver.${ROLE}.ini"
    {
        echo "; ==========================================================================="
        echo "; GERADO AUTOMATICAMENTE — NÃO EDITE. Reescrito a cada boot do [${ROLE^^}]."
        echo ";"
        echo "; Espelho do appserver.ini em vigor, já com os overrides aplicados."
        echo "; Para mudar algo, edite appserver/appserver.custom.ini e reinicie."
        echo "; ==========================================================================="
        echo ""
        cat appserver.ini
    } > "$MIRROR"
    echo "🪞 Espelho exportado: appserver/generated/appserver.${ROLE}.ini"
fi

# 4. Inicialização do Binário Oficial com Verificação de Sanidade
echo "🔍 Validando integridade física do executável TOTVS..."
if [ ! -f "appsrvlinux" ]; then
    echo "❌ ERRO CRÍTICO: O binário appsrvlinux NÃO foi encontrado no diretório atual ($(pwd))!"
    exit 1
fi

echo "🔑 Forçando permissões de execução no binário..."
chmod +x appsrvlinux

# ⚡ ORCHESTRATION ENGINE
if [ "$ROLE" = "worker" ]; then
    echo "🚀 Preparando ambiente local do Worker..."
    cd /totvs/protheus/bin/appserver
    if [ -f "/usr/local/bin/patch_deployer.sh" ]; then
        echo "🤖 [Worker] Assumindo controle do contêiner em Foreground para execução síncrona..."
        exec /usr/local/bin/patch_deployer.sh
    else
        echo "❌ ERRO CRÍTICO: O script /usr/local/bin/patch_deployer.sh não foi encontrado!"
        exit 1
    fi
elif [ "$ROLE" = "compile" ]; then
    echo "🚀 Preparando ambiente local do Compilador GitOps..."
    cd /totvs/protheus/bin/appserver
    if [ -f "/usr/local/bin/code_compiler.sh" ]; then
        echo "🤖 [Compiler] Assumindo controle do contêiner em Foreground para compilação..."
        exec /usr/local/bin/code_compiler.sh
    else
        echo "❌ ERRO CRÍTICO: O script /usr/local/bin/code_compiler.sh não foi encontrado!"
        exit 1
    fi
elif [ "$ROLE" = "test" ]; then
    echo "🚀 Preparando esteira de testes ProBat..."
    cd /totvs/protheus/bin/appserver
    if [ -f "/usr/local/bin/test_runner.sh" ]; then
        echo "🤖 [Test] Assumindo controle do contêiner em Foreground para os testes..."
        exec /usr/local/bin/test_runner.sh
    else
        echo "❌ ERRO CRÍTICO: O script /usr/local/bin/test_runner.sh não foi encontrado!"
        exit 1
    fi
elif [ "$ROLE" = "upddistr" ]; then
    echo "📝 Preparando arquivo de parâmetros upddistr_param.json..."
    
    # Máscaras de aspas tratadas de forma estática e segura no escopo do JSON
    cat <<EOF > /totvs/protheus/systemload/upddistr_param.json
{
 "user": "${UPD_USER:-admin}",
 "password": "${UPD_PASSWORD-senha}",
 "simulacao": ${UPD_SIMULACAO:-false},
 "localizacao": "${UPD_LOCALIZACAO:-BRA}",
 "sixexclusive": ${UPD_SIXEXCLUSIVE:-true},
 "empresas": ["${UPD_EMPRESAS:-99}"],
 "logprocess": ${UPD_LOGPROCESS:-false},
 "logatualizacao": ${UPD_LOGATUALIZACAO:-true},
 "logwarning": ${UPD_LOGWARNING:-false},
 "loginclusao": ${UPD_LOGINCLUSAO:-false},
 "logcritical": ${UPD_LOGCRITICAL:-true},
 "updstop": ${UPD_UPDSTOP:-false},
 "oktoall": ${UPD_OKTOALL:-true},
 "deletebkp": ${UPD_DELETEBKP:-false},
 "keeplog": ${UPD_KEEPLOG:-false},
 "typeenviroment": "${UPD_TYPEENVIRONMENT:-3}"
}
EOF

    echo "🚀 Disparando engine de compatibilização UPDDISTR em Foreground..."
    cd /totvs/protheus/bin/appserver
    
    # Remove qualquer Result.json antigo para evitar falsos positivos
    rm -f /totvs/protheus/systemload/Result.json
    
    # Executa o AppServer travando o console. O ONSTART chamará o UPDDISTR imediatamente.
    exec ./appsrvlinux -console
else
    echo "🚀 Disparando TOTVS Application Server Linux no modo [${ROLE^^}]..."
    cd /totvs/protheus/bin/appserver
    exec ./appsrvlinux -console
fi