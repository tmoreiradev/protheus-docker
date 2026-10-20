# Alinhado com o repositório Enterprise homologado pelo seu login no portal
FROM container-registry.oracle.com/database/enterprise:21.3.0.0

# Altera temporariamente para ROOT para ter privilégios de escrita nos diretórios de sistema
USER root

# Copia o script de inicialização para o diretório de autoboot da Oracle
COPY ./init-protheus.sh /opt/oracle/scripts/startup/01_setup-protheus.sh

# Garante a permissão de execução E altera o dono do arquivo para o usuário oracle
RUN chmod +x /opt/oracle/scripts/startup/01_setup-protheus.sh && \
    chown oracle:oinstall /opt/oracle/scripts/startup/01_setup-protheus.sh

# Devolve o controle para o usuário padrão da imagem para manter a segurança em runtime
USER oracle