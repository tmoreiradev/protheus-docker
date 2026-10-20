#!/bin/bash
# ==============================================================================
# TOTVS Protheus Modern DevOps - Environment Controller
# ==============================================================================
set -e

e_servico() {
    case "$1" in
        worker|upddistr|compile|test) return 0 ;;
        *) return 1 ;;
    esac
}

e_sgbd() {
    case "$1" in
        postgres|mssql|oracle) return 0 ;;
        *) return 1 ;;
    esac
}

# O DB_TYPE do .env declara qual banco este ambiente usa. Ele NÃO configura a
# conexão — quem faz isso é o .env.<sgbd>, que sobrescreve DB_TYPE/DB_SERVER/
# DB_PORT e ainda traz as credenciais root do SGBD. O papel do DB_TYPE aqui é
# ser o *seletor*: sem ele, o .env descreveria um banco e a stack subiria outro.
sgbd_do_env() {
    [ -f .env ] || return 0
    sed -n 's/^[[:space:]]*DB_TYPE[[:space:]]*=[[:space:]]*//p' .env 2>/dev/null \
        | tail -1 | tr -d '"'"'"'\r' | awk '{print $1}' | tr '[:upper:]' '[:lower:]'
}

ARG1=$(echo "$1" | tr '[:upper:]' '[:lower:]')
SGBD_ENV=$(sgbd_do_env)

# ------------------------------------------------------------------------------
# INCLUDES DO TDS/VSCODE: extraídas no HOST, não no container
# ------------------------------------------------------------------------------
# A extensão tds-vscode lê os .ch/.th da máquina onde o VSCode roda e envia o
# conteúdo ao AppServer junto com o fonte — ela nunca enxerga o sistema de
# arquivos do container. Apontar /totvs/protheus/includes no servers.json não
# funciona; os includes têm de existir descompactados aqui.
#
# Não confundir com o job `compile`, que extrai os mesmos zips DENTRO do
# container. São dois consumidores distintos do mesmo artefato.
#
# `-j` (achata os caminhos) porque a busca de includes não é recursiva e o
# pacote da TOTVS guarda tudo sob include/ — sem achatar, nem o PRTOPDEF.CH é
# encontrado, e todo .prw morre com C2090.
if [ "$ARG1" = "includes" ]; then
    command -v unzip >/dev/null 2>&1 || { echo "❌ unzip não encontrado no PATH."; exit 1; }

    DEST="protheus/includes/_extracted"
    ACHOU=0

    for PKG in advpl tlpp custom; do
        ZIP="protheus/includes/$PKG/includes.zip"
        [ -f "$ZIP" ] || continue
        rm -rf "${DEST:?}/$PKG"
        mkdir -p "$DEST/$PKG"
        unzip -joq "$ZIP" -d "$DEST/$PKG"
        QTD=$(find "$DEST/$PKG" -type f | wc -l | tr -d ' ')
        echo "📂 [$PKG] $QTD arquivo(s) → $DEST/$PKG"
        ACHOU=1
    done

    if [ "$ACHOU" = "0" ]; then
        echo "❌ Nenhum includes.zip em protheus/includes/{advpl,tlpp,custom}/."
        echo "   Os pacotes ADVPL vêm do portal TOTVS; o de TLPP é gerado (ver README)."
        exit 1
    fi

    echo ""
    echo "✅ Aponte o TDS para esses diretórios (servers.json → includes)."
    exit 0
fi

# ------------------------------------------------------------------------------
# UM CORE POR BASE (desde 2026-10-05): `base` escolhe o lab alvo, nao recria nada
# ------------------------------------------------------------------------------
#
#   ./run.sh base                  # lista os labs: base, core, estado, porta; marca o atual
#   ./run.sh base lab2       # escolhe a lab2 para jobs/testes e garante o core dela no ar
#   ./run.sh base lab2 stop  # para o core E o License Server da lab2 (lab ocioso libera ~1,1-1,6 GB)
#   ./run.sh base --name           # so o nome do lab atual        (para scripts)
#   ./run.sh base --container      # so o container do lab atual   (para scripts)
#   ./run.sh base --port           # so a porta WebApp do lab atual
#
# Cada base do protheus_postgres tem o SEU core, sempre com a mesma base: no compose,
# appserver_core = lab (1234), appserver_core_lab2 = lab2 (1236) e
# appserver_core_dev = dev (1237, profile `dev`, desligado por padrao). Todos compartilham o
# RPO (./protheus/apo) e o dbaccess (que registra todos os aliases, ver DB_NAMES); cada um tem
# o PROPRIO License Server (pool de licencas isolado: o ProBat de um lab nao derruba quem esta
# logado no outro) e os proprios volumes system/data/log. A escolha fica em
# .lab-current (gitignored) e vale para `./run.sh compile|test|worker|upddistr` (DB_NAME e
# volumes do job) e para o test-local.sh (container). Cada .env.base.<nome> declara, alem do
# DB_NAME, LAB_SERVICE, LAB_CONTAINER, LAB_SYSTEM_VOL, LAB_DATA_VOL, LAB_LOG_VOL, LAB_GENERATED,
# LAB_PORT e LAB_PROFILE.
#
# Antes este comando RECRIAVA dbaccess + core apontando para a outra base (32 s por sentido,
# derrubando quem estivesse logado); com um core por base, trocar de base nao derruba ninguem.
LAB_CURRENT_FILE=".lab-current"

lab_nome_atual() {
    if [ -s "$LAB_CURRENT_FILE" ]; then cat "$LAB_CURRENT_FILE"; else echo "lab"; fi
}

# lab_load <nome>: carrega .env.base.<nome> no shell (DB_NAME e LAB_*), com defaults.
lab_load() {
    local spec=".env.base.$1"
    [ -f "$spec" ] || { echo "❌ Base desconhecida: [$1] — nao existe $spec."; return 1; }
    set -a
    . "./$spec"
    set +a
    [ -n "${DB_NAME:-}" ] || { echo "❌ $spec nao define DB_NAME."; return 1; }
    [ -n "${LAB_SERVICE:-}" ] && [ -n "${LAB_CONTAINER:-}" ] || { echo "❌ $spec precisa de LAB_SERVICE e LAB_CONTAINER (um core por base)."; return 1; }
    LAB_SYSTEM_VOL="${LAB_SYSTEM_VOL:-protheus_system}"
    LAB_DATA_VOL="${LAB_DATA_VOL:-protheus_data}"
    LAB_LOG_VOL="${LAB_LOG_VOL:-protheus_log}"
    LAB_GENERATED="${LAB_GENERATED:-appserver/generated}"
    LAB_PORT="${LAB_PORT:-1234}"
    LAB_PROFILE="${LAB_PROFILE:-}"
    LAB_LICENSE_SERVICE="${LAB_LICENSE_SERVICE:-}"
    export LAB_SYSTEM_VOL LAB_DATA_VOL LAB_LOG_VOL
}

# Semeia system/data de um lab que nunca subiu a partir dos volumes do lab principal (usuarios,
# senhas, perfis, menus). Os volumes ja precisam existir COM os labels do compose (criados
# por `compose create`): um volume criado a mao faz o compose recusar o servico.
lab_seed_volumes() {
    local proj par src dst
    proj=$(basename "$PWD")
    for par in "protheus_system:$LAB_SYSTEM_VOL" "protheus_data:$LAB_DATA_VOL"; do
        src="${proj}_${par%%:*}"; dst="${proj}_${par##*:}"
        [ "$src" = "$dst" ] && continue
        docker volume inspect "$dst" >/dev/null 2>&1 || { echo "❌ Volume $dst nao existe (o compose create deveria te-lo criado)."; return 1; }
        if [ -z "$(docker run --rm -v "$dst:/d:ro" alpine ls -A /d)" ]; then
            echo "🌱 Semeando $dst a partir de $src (usuarios, senhas, perfis, menus)..."
            docker run --rm -v "$src:/s:ro" -v "$dst:/d" alpine sh -c 'cp -a /s/. /d/'
        fi
    done
}

if [ "$ARG1" = "base" ]; then
    BASE_NOME=$(echo "${2:-}" | tr '[:upper:]' '[:lower:]')
    BASE_ACAO=$(echo "${3:-}" | tr '[:upper:]' '[:lower:]')
    SGBD_BASE="${SGBD_ENV:-postgres}"
    ENV_SPEC_BASE=".env.$SGBD_BASE"
    [ -f "$ENV_SPEC_BASE" ] || { echo "❌ O arquivo $ENV_SPEC_BASE nao existe."; exit 1; }
    export SGBD="$SGBD_BASE"

    compose_lab() {
        if [ -n "${LAB_PROFILE:-}" ]; then
            docker compose --env-file .env --env-file "$ENV_SPEC_BASE" --profile "$LAB_PROFILE" "$@"
        else
            docker compose --env-file .env --env-file "$ENV_SPEC_BASE" "$@"
        fi
    }

    case "$BASE_NOME" in
        --name)      lab_nome_atual; exit 0 ;;
        --container) lab_load "$(lab_nome_atual)" >/dev/null || exit 1; echo "$LAB_CONTAINER"; exit 0 ;;
        --port)      lab_load "$(lab_nome_atual)" >/dev/null || exit 1; echo "$LAB_PORT"; exit 0 ;;
        "")
            ATUAL=$(lab_nome_atual)
            echo "🗂️  Labs declarados (* = alvo atual dos jobs e do test-local.sh):"
            printf '  %s %-12s %-22s %-22s %-10s %s\n' " " "LAB" "BASE" "CONTAINER" "ESTADO" "WEBAPP"
            for F in .env.base.*; do
                [ -f "$F" ] || continue
                NOME="${F#.env.base.}"
                (
                    lab_load "$NOME" >/dev/null 2>&1 || exit 0
                    ST=$(docker inspect -f '{{.State.Status}}' "$LAB_CONTAINER" 2>/dev/null | head -1)
                    [ -n "$ST" ] || ST="nunca subiu"
                    MARK=" "; [ "$NOME" = "$ATUAL" ] && MARK="*"
                    printf '  %s %-12s %-22s %-22s %-10s http://127.0.0.1:%s/webapp/\n' "$MARK" "$NOME" "$DB_NAME" "$LAB_CONTAINER" "$ST" "$LAB_PORT"
                )
            done
            echo ""
            echo "👉 ./run.sh base <lab>        escolhe (e sobe) o lab    ./run.sh base <lab> stop    para o core dele"
            exit 0
            ;;
    esac

    lab_load "$BASE_NOME" || { echo "👉 Use ./run.sh base para listar os labs declarados."; exit 1; }

    if [ "$BASE_ACAO" = "stop" ]; then
        # Para o core e o License Server proprio do lab (o compartilhado do lab principal fica,
        # porque o dbaccess tambem fala com ele).
        compose_lab stop "$LAB_SERVICE" $LAB_LICENSE_SERVICE
        echo "⏹️  Lab [$BASE_NOME] parado (${LAB_CONTAINER}${LAB_LICENSE_SERVICE:+ + $LAB_LICENSE_SERVICE}). A escolha do lab atual nao mudou: $(lab_nome_atual)."
        exit 0
    fi
    if [ -n "$BASE_ACAO" ]; then
        echo "❌ Acao desconhecida: [$BASE_ACAO]. So existe 'stop'."
        exit 1
    fi

    # Confere que o banco EXISTE antes de subir o core. Apontar o dbAccess para um banco
    # inexistente nao da erro de conexao: o core sobe pedindo para criar empresa, sintoma
    # identico ao de uma base virgem legitima — e ai a medicao mede o typo, nao a base.
    if [ "$SGBD_BASE" = "postgres" ] && docker ps --format '{{.Names}}' | grep -qx protheus_postgres; then
        if ! docker exec protheus_postgres psql -U postgres -Atc \
                "select 1 from pg_database where datname = '$DB_NAME'" 2>/dev/null | grep -qx 1; then
            echo "❌ O banco [$DB_NAME] nao existe no protheus_postgres."
            echo "👉 Crie-o com os mesmos parametros do databases/postgres/init-protheus.sh"
            echo "   (ENCODING=WIN1252, LC_COLLATE=C, LC_CTYPE=pt_BR.CP1252) — ver databases/postgres/init-protheus.sh."
            exit 1
        fi
    fi

    mkdir -p "$LAB_GENERATED"
    if ! docker ps -a --format '{{.Names}}' | grep -qx "$LAB_CONTAINER"; then
        echo "🧱 Primeira subida do core [$LAB_CONTAINER]: criando container e volumes..."
        compose_lab create --no-recreate "$LAB_SERVICE" >/dev/null
        lab_seed_volumes || exit 1
    fi
    if [ -n "$LAB_LICENSE_SERVICE" ]; then
        # License Server proprio do lab primeiro: o entrypoint do core espera a porta dele.
        compose_lab up -d --no-deps "$LAB_LICENSE_SERVICE"
    fi
    # `up -d` sempre: e idempotente (so recria se a definicao do servico mudou, por exemplo
    # o License Server dele) e sobe o core se estiver parado. Nao toca em dbaccess/postgres.
    echo "🚀 Garantindo o core [$LAB_CONTAINER] no ar (base $DB_NAME)..."
    compose_lab up -d --no-deps "$LAB_SERVICE"
    echo "$BASE_NOME" > "$LAB_CURRENT_FILE"

    echo ""
    echo "✅ Lab atual: [$BASE_NOME] → $LAB_CONTAINER, base $DB_NAME"
    echo "   WebApp: http://127.0.0.1:${LAB_PORT}/webapp/"
    echo "   Log:    docker logs --tail 40 $LAB_CONTAINER"
    exit 0
fi

if [ -z "$ARG1" ] || e_servico "$ARG1"; then
    # Sem SGBD no comando: herda do .env e desloca os argumentos.
    SGBD="$SGBD_ENV"
    SERVICE="$ARG1"
    COMMAND=$2
    [ -n "$SGBD" ] && echo "🔎 SGBD [$SGBD] herdado do DB_TYPE do .env"
else
    SGBD="$ARG1"
    SERVICE=$(echo "$2" | tr '[:upper:]' '[:lower:]')
    COMMAND=$3

    # O argumento vence, mas nunca em silêncio: um .env que descreve outro banco
    # é justamente o que faz alguém depurar a stack errada. Só avisa quando o
    # argumento é um SGBD de verdade — senão um typo dispara um alerta sem sentido.
    if e_sgbd "$SGBD" && [ -n "$SGBD_ENV" ] && [ "$SGBD" != "$SGBD_ENV" ]; then
        echo "⚠️  O .env declara DB_TYPE=$(echo "$SGBD_ENV" | tr '[:lower:]' '[:upper:]'), mas você pediu [$SGBD]."
        echo "   O argumento vence. Ajuste o DB_TYPE do .env para refletir o ambiente."
    fi
fi

export SGBD  # <-- CRUCIAL: Torna a variável visível para o processo do Docker Compose

# Caso o segundo argumento seja "down", inverte as variáveis para manter compatibilidade clássica
if [ "$SERVICE" = "down" ]; then
    COMMAND="down"
    SERVICE=""
fi

# Versões em caixa alta para exibição. Feito com tr em vez de ${VAR^^} porque
# a expansão de caixa só existe no bash 4+, e o /bin/bash do macOS é o 3.2.
SGBD_UP=$(echo "$SGBD" | tr '[:lower:]' '[:upper:]')
SERVICE_UP=$(echo "$SERVICE" | tr '[:lower:]' '[:upper:]')

# Valida se o comando base do banco foi passado de forma correta
if [ -z "$SGBD" ] || { [ "$SGBD" != "postgres" ] && [ "$SGBD" != "mssql" ] && [ "$SGBD" != "oracle" ] && [ "$SGBD" != "down" ]; }; then
    echo "❌ Uso correto: ./run.sh [postgres | mssql | oracle | down] [opcional: worker | upddistr | compile | test] [opcional: command]"
    echo "👉 Exemplo Base:     ./run.sh postgres"
    echo "👉 Exemplo Worker:   ./run.sh postgres worker"
    echo "👉 Exemplo Migrador: ./run.sh postgres upddistr"
    echo "👉 Exemplo Compiler: ./run.sh postgres compile"
    echo "👉 Exemplo Testes:   ./run.sh postgres test"
    echo "👉 Exemplo Derrubar: ./run.sh postgres down"
    echo ""
    echo "🧩 Sem Docker:       ./run.sh includes   (descompacta os .ch/.th para o TDS/VSCode)"
    echo "🗄️  Um core por base: ./run.sh base [lab | lab2 | dev] [stop]   (escolhe/sobe/para o core da base)"
    echo ""
    echo "💡 Omitindo o SGBD, ele é lido do DB_TYPE do .env: ./run.sh | ./run.sh compile"
    if [ -z "$SGBD_ENV" ]; then
        echo "   (hoje não há um DB_TYPE válido no .env, por isso o SGBD é obrigatório)"
    fi
    exit 1
fi

# ------------------------------------------------------------------------------
# INTERCEPTOR CRÍTICO: Cenário de destruição total do ambiente (down global)
# ------------------------------------------------------------------------------
if [ "$SGBD" = "down" ]; then
    echo "🛑 Derrubando a infraestrutura global e limpando volumes persistentes..."

    ENV_ARG=""
    if [ -f ".env" ]; then
        ENV_ARG="--env-file .env"
    fi

    docker compose $ENV_ARG --profile "*" down -v 2>/dev/null
    echo "✅ Ambiente totalmente limpo com segurança!"
    exit 0
fi

# Chaveamento de variáveis baseado no banco escolhido
ENV_SPEC=".env.$SGBD"
if [ ! -f "$ENV_SPEC" ]; then
    echo "❌ Erro crítico: O arquivo de ambiente especialista $ENV_SPEC não foi localizado na raiz!"
    exit 1
fi

# Monta a cadeia de perfis ativos de forma dinâmica
PROFILES_ARGS="--profile $SGBD"
if [ -n "$SERVICE" ] && [ "$SERVICE" != "down" ]; then
    if [ "$SERVICE" != "worker" ] && [ "$SERVICE" != "upddistr" ] && [ "$SERVICE" != "compile" ] && [ "$SERVICE" != "test" ]; then
        echo "❌ Serviço especialista desconhecido: $SERVICE"
        echo "👉 Use: worker, upddistr, compile ou test"
        exit 1
    fi
    PROFILES_ARGS="$PROFILES_ARGS --profile $SERVICE"
    echo "⚙️  Chaveando ecossistema dinamicamente para [${SGBD_UP}] com serviço adicional [${SERVICE_UP}]..."
else
    echo "⚙️  Chaveando ecossistema dinamicamente para [${SGBD_UP}] (Apenas Infra Base + Core)..."
fi

# Determina e executa a ação final do Docker Compose de forma isolada
if [ "$COMMAND" = "down" ]; then
    if [ -n "$SERVICE" ]; then
        echo "🔻 Desligando especificamente o serviço especialista: [${SERVICE_UP}]..."
        docker compose --env-file .env --env-file "$ENV_SPEC" stop appserver_$SERVICE
        docker compose --env-file .env --env-file "$ENV_SPEC" rm -f appserver_$SERVICE
    else
        echo "🔻 Desligando a stack base sob os perfis selecionados..."
        docker compose --env-file .env --env-file "$ENV_SPEC" $PROFILES_ARGS down -v
    fi
else
    # --------------------------------------------------------------------------
    # CENÁRIO ESPECIAL: WORKER, UPDDISTR E COMPILER (ESTEIRA ELÁSTICA SÍNCRONA)
    # --------------------------------------------------------------------------
    if [ "$SERVICE" = "worker" ] || [ "$SERVICE" = "upddistr" ] || [ "$SERVICE" = "compile" ] || [ "$SERVICE" = "test" ]; then
        # Um core por base (2026-10-05): o job roda contra o lab ATUAL (.lab-current). O
        # DB_NAME e os volumes system/log do job vem do .env.base dele (o compose le
        # LAB_SYSTEM_VOL/LAB_LOG_VOL). Os cores tem DB_NAME fixo no compose, entao o `up` de
        # restauracao nunca muda a base de ninguem (ate 19/09 isso devolvia o lab para a
        # protheus_dev em silencio).
        lab_load "$(lab_nome_atual)" || exit 1
        export DB_NAME
        echo "🗄️  Lab atual: [$(lab_nome_atual)] base [$DB_NAME] system [$LAB_SYSTEM_VOL]"

        echo "🕵️  Mapeando os cores no ar..."
        # TODOS os cores param: eles compartilham o ./protheus/apo e um processo so pode
        # segurar o RPO. Quem estava de pe volta no fim, exatamente os mesmos.
        CORES_ACTIVE=$(docker compose --env-file .env --env-file "$ENV_SPEC" --profile dev ps --status running --services 2>/dev/null | grep -E '^appserver_core' || true)

        echo "🛑 Isolando o RPO e Tabelas: parando os cores ativos [$(echo $CORES_ACTIVE | tr '\n' ' ')]..."
        for SVC in $CORES_ACTIVE; do
            docker compose --env-file .env --env-file "$ENV_SPEC" --profile dev stop "$SVC"
        done

        if [ "$SERVICE" = "worker" ]; then
            echo "🚀 Invocando o Protheus Automated Deploy Worker (Modo CLI Job com Force Build)..."
            set +e
            docker compose --env-file .env --env-file "$ENV_SPEC" run --build --rm appserver_worker
            EXEC_EXIT_CODE=$?
            set -e
        elif [ "$SERVICE" = "compile" ]; then
            echo "🚀 Invocando a Esteira de Compilação Síncrona GitOps (Modo CLI)..."
            set +e
            docker compose --env-file .env --env-file "$ENV_SPEC" run --build --rm appserver_compiler
            EXEC_EXIT_CODE=$?
            set -e
        elif [ "$SERVICE" = "test" ]; then
            echo "🚀 Invocando a Esteira de Testes ProBat (Modo CLI)..."
            set +e
            docker compose --env-file .env --env-file "$ENV_SPEC" run --build --rm appserver_test
            EXEC_EXIT_CODE=$?
            set -e
        else
            echo "🚀 Inicializando Executor UPDDISTR Síncrono (Dicionário de Dados)..."

            # Remove arquivos antigos em qualquer variação de caixa para evitar falsos positivos
            rm -f ./protheus/systemload/Result.json ./protheus/systemload/result.json

            # Inicializa o container do UPDDISTR
            docker compose --env-file .env --env-file "$ENV_SPEC" up --build -d appserver_upddistr

            echo "⏳ Processando compatibilização do dicionário. Monitorando output do resultado (Aguarde)..."
            set +e
            while true; do
                # 🔍 Check agnóstico de caixa (Procura por result.json ou Result.json)
                TARGET_FILE=""
                if [ -f "./protheus/systemload/Result.json" ]; then
                    TARGET_FILE="./protheus/systemload/Result.json"
                elif [ -f "./protheus/systemload/result.json" ]; then
                    TARGET_FILE="./protheus/systemload/result.json"
                fi

                if [ -n "$TARGET_FILE" ]; then
                    echo "📝 Arquivo de resultado detectado: [$TARGET_FILE]"
                    cat "$TARGET_FILE"
                    echo ""
                    if grep -q "success" "$TARGET_FILE"; then
                        EXEC_EXIT_CODE=0
                    else
                        EXEC_EXIT_CODE=1
                    fi
                    break
                fi

                # Verifica se o container caiu antes de gerar o json
                CONTAINER_RUNNING=$(docker compose --env-file .env --env-file "$ENV_SPEC" ps --status running --format json | grep -q "protheus_upddistr" && echo "true" || echo "false")
                if [ "$CONTAINER_RUNNING" = "false" ] && [ -z "$TARGET_FILE" ]; then
                    echo "❌ ERRO CRÍTICO: O container protheus_upddistr encerrou inesperadamente sem gerar o arquivo de resultado!"
                    EXEC_EXIT_CODE=1
                    break
                fi
                sleep 5
            done
            set -e

            echo "🧹 Removendo container temporário do UPDDISTR..."
            docker compose --env-file .env --env-file "$ENV_SPEC" stop appserver_upddistr 2>/dev/null || true
            docker compose --env-file .env --env-file "$ENV_SPEC" rm -f appserver_upddistr 2>/dev/null || true
        fi

        if [ $EXEC_EXIT_CODE -eq 0 ]; then
            echo "✅ Processo [${SERVICE_UP}] executado com sucesso total!"
        else
            echo "❌ Falha crítica detectada no processamento do [${SERVICE_UP}]."
        fi

        echo "🔄 Restaurando o ecossistema original para o estado anterior..."
        for SVC in $CORES_ACTIVE; do
            docker compose --env-file .env --env-file "$ENV_SPEC" --profile dev up -d --no-deps "$SVC"
        done

        # PULO DO GATO: Se o processo falhou, o run.sh precisa sair com erro AGORA para o GitHub capturar a falha!
        if [ $EXEC_EXIT_CODE -ne 0 ]; then
            exit 1
        fi

    else
        echo "🚀 Inicializando a infraestrutura base Protheus com banco [${SGBD_UP}]..."
        docker compose --env-file .env --env-file "$ENV_SPEC" $PROFILES_ARGS up --build -d
    fi

    echo "📊 Status atual dos containers ativos da Malha:"
    docker compose --env-file .env --env-file "$ENV_SPEC" --profile "*" ps
fi