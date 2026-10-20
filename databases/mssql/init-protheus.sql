-- Cria o banco de dados utilizando a collation estrita Latin1_General_BIN exigida pela TOTVS
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = '$(SQL_DB)')
BEGIN
    CREATE DATABASE [$(SQL_DB)] COLLATE Latin1_General_BIN;
END
GO

-- Habilita o isolamento de snapshot para evitar Deadlocks no ERP Protheus
ALTER DATABASE [$(SQL_DB)] SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE [$(SQL_DB)] SET READ_COMMITTED_SNAPSHOT ON;
GO

-- Cria o Login de acesso desativando a validação de política estrita do SO local
IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = '$(SQL_USER)')
BEGIN
    CREATE LOGIN [$(SQL_USER)] 
        WITH PASSWORD = '$(SQL_PASS)', 
        DEFAULT_DATABASE = [$(SQL_DB)],
        CHECK_EXPIRATION = OFF,    -- <-- Ignora expiração no ambiente de Dev
        CHECK_POLICY = OFF;        -- <-- Ignora a trava de complexidade do SO Linux
END
GO

-- Conecta no contexto do novo banco e vincula o usuário como Owner administrativo
USE [$(SQL_DB)];
GO
IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = '$(SQL_USER)')
BEGIN
    CREATE USER [$(SQL_USER)] FOR LOGIN [$(SQL_USER)];
    ALTER ROLE db_owner ADD MEMBER [$(SQL_USER)];
END
GO