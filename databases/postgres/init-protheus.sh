#!/bin/bash
set -e

echo "🚀 [Postgres Init] Iniciando criação da estrutura TOTVS Protheus..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER "$DB_USER" WITH
        LOGIN
        NOSUPERUSER
        INHERIT
        CREATEDB
        NOCREATEROLE
        NOREPLICATION
        CONNECTION LIMIT -1
        ENCRYPTED PASSWORD '$DB_PASS';
        
    CREATE DATABASE "$DB_NAME" WITH
        OWNER="$DB_USER"
        TEMPLATE=template0
        ENCODING='WIN1252'
        LC_COLLATE='C'
        LC_CTYPE='pt_BR.CP1252'
        CONNECTION LIMIT = -1;
        
    GRANT ALL PRIVILEGES ON DATABASE "$DB_NAME" TO "$DB_USER";
EOSQL

echo "✅ [Postgres Init] Base de dados e usuário criados com sucesso!"