FROM mcr.microsoft.com/mssql/server:2022-latest

USER root

# Instala ferramentas essenciais de checagem de rede
RUN apt-get update && apt-get install -y netcat-openbsd && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# Copia os artefatos de provisionamento
COPY init-protheus.sql entrypoint.sh /usr/src/app/

# Garante permissão global enquanto ainda estamos como root
RUN chmod +x /usr/src/app/entrypoint.sh

# Retorna para o usuário seguro padrão da Microsoft
USER mssql

EXPOSE 1433

ENTRYPOINT ["/usr/src/app/entrypoint.sh"]