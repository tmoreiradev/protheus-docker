#!/bin/bash
set -e

# Dispara o SQL Server em background
/opt/mssql/bin/sqlservr &

echo "⏳ [SQL Server Init] Aguardando a completa inicialização dos serviços internos do sistema..."

# Tenta se conectar com o sa de 2 em 2 segundos até o motor aceitar a query de teste
until /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" -C -No > /dev/null 2>&1; do
    sleep 2
done

echo "🚀 [SQL Server Init] Motor pronto! Executando script de provisionamento da base TOTVS..."

# Injeta dinamicamente as variáveis do .env para dentro do script SQL
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
    -i init-protheus.sql \
    -v SQL_DB="$DB_NAME" SQL_USER="$DB_USER" SQL_PASS="$DB_PASS" \
    -C -No

echo "✅ [SQL Server Init] Banco de dados e usuário criados com sucesso!"

# Mantém o processo do sqlservr em primeiro plano
wait