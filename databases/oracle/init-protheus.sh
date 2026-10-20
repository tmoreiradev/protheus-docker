#!/bin/bash
echo "⚙️ Configurando ambiente TOTVS Protheus no Oracle 21c..."

# Injeta as variáveis de ambiente necessárias para o sqlplus local localizar a instância
export ORACLE_SID=ORCLCDB
export ORACLE_HOME=/opt/oracle/product/21c/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

# Conecta localmente como sysdba e executa as parametrizações
sqlplus -s / as sysdba <<EOF
-- 1. Trava inegociável do Protheus no Container Raiz (CDB)
ALTER SYSTEM SET CURSOR_SHARING=EXACT SCOPE=BOTH;

-- 2. Chaveia explicitamente a sessão para o Pluggable Database (PDB) do Protheus
ALTER SESSION SET CONTAINER = ORCLPDB1;

-- 3. Criação da Tablespace dedicada exclusiva dentro do PDB com arquivo físico isolado
-- Alterado o nome do arquivo para evitar conflito com o lixo órfão do CDB$ROOT
CREATE TABLESPACE PROTHEUS_DATA DATAFILE '/opt/oracle/oradata/protheus_data_pdb.dbf' SIZE 1G AUTOEXTEND ON NEXT 500M MAXSIZE UNLIMITED;

-- 4. Garante a criação do Usuário Local dentro do PDB associado à Tablespace correta
-- Se o usuário já existir parcialmente, o Oracle apenas reportará o erro e seguirá reto
CREATE USER ${DB_USER} IDENTIFIED BY "${DB_PASS}" DEFAULT TABLESPACE PROTHEUS_DATA QUOTA UNLIMITED ON PROTHEUS_DATA;

-- 5. Concessão de Privilégios locais exigidos pelo DBAccess
GRANT CONNECT, RESOURCE, DBA TO ${DB_USER};

EXIT;
EOF

echo "✅ Banco de Dados Oracle configurado e pronto para o Protheus!"