# ==============================================================================
# ESTÁGIO 1: Builder (Download de Drivers com SSL Validado)
# ==============================================================================
# Base Oracle Linux 8, não Ubuntu: o Protheus valida o sistema operacional e
# Ubuntu não consta na lista da TOTVS (confira com ./check-so.sh).
FROM oraclelinux:8 AS builder

# Injetado ca-certificates para permitir handshakes SSL seguros no download
RUN dnf -y install --setopt=install_weak_deps=False \
    wget \
    unzip \
    tar \
    gzip \
    ca-certificates \
    && dnf clean all && rm -rf /var/cache/dnf

WORKDIR /tmp/build

# Agora o handshake SSL com a Oracle passará liso com segurança
RUN wget https://download.oracle.com/otn_software/linux/instantclient/213000/instantclient-basiclite-linux.x64-21.3.0.0.0.zip && \
    unzip instantclient-basiclite-linux.x64-21.3.0.0.0.zip

COPY ./dbaccess.tar.gz .
RUN mkdir -p dbaccess_extracao /tmp/out_dbaccess && \
    tar -xzf dbaccess.tar.gz -C dbaccess_extracao/ && \
    (cp -R dbaccess_extracao/*/* /tmp/out_dbaccess/ 2>/dev/null || cp -R dbaccess_extracao/* /tmp/out_dbaccess/)

# ==============================================================================
# ESTÁGIO 2: Runner
# ==============================================================================
FROM oraclelinux:8 AS runner
LABEL version="24.1.1.3"

# ncurses-compat-libs traz a libtinfo.so.5; nmap-ncat é o `nc` do healthcheck.
RUN dnf -y install --setopt=install_weak_deps=False \
    curl ca-certificates gnupg2 gettext nmap-ncat \
    unixODBC unixODBC-devel postgresql-odbc glibc ncurses-compat-libs libstdc++ libaio \
    && dnf clean all && rm -rf /var/cache/dnf

# O `odbc-postgresql` do Ubuntu registrava DUAS seções — [PostgreSQL ANSI]
# (psqlodbca.so) e [PostgreSQL Unicode] (psqlodbcw.so). O `postgresql-odbc` do
# OL8 registra só [PostgreSQL], apontando para o driver Unicode. A connection
# string montada pelo entrypoint pede {PostgreSQL ANSI}: sem esta seção o
# dbAccess recusa toda conexão com -35 e mesmo assim segue `healthy`, porque o
# healthcheck só bate na porta.
RUN printf '%s\n' \
    '[PostgreSQL ANSI]' \
    'Description=PostgreSQL ODBC driver (ANSI version)' \
    'Driver=/usr/lib64/psqlodbca.so' \
    'Setup=/usr/lib64/libodbcpsqlS.so' \
    'Debug=0' \
    'CommLog=1' \
    'UsageCount=1' \
    '' \
    '[PostgreSQL Unicode]' \
    'Description=PostgreSQL ODBC driver (Unicode version)' \
    'Driver=/usr/lib64/psqlodbcw.so' \
    'Setup=/usr/lib64/libodbcpsqlS.so' \
    'Debug=0' \
    'CommLog=1' \
    'UsageCount=1' > /tmp/psqlodbc.ini && \
    odbcinst -i -d -f /tmp/psqlodbc.ini && rm -f /tmp/psqlodbc.ini

# Driver MSSQL da Microsoft: repositório de RHEL 8 (o de Ubuntu não serve aqui).
RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc && \
    curl -sSL https://packages.microsoft.com/config/rhel/8/prod.repo > /etc/yum.repos.d/mssql-release.repo && \
    ACCEPT_EULA=Y dnf -y install msodbcsql18 && \
    dnf clean all && rm -rf /var/cache/dnf

COPY --from=builder /tmp/build/instantclient_21_3 /opt/oracle/instantclient_21_3
COPY --from=builder /tmp/out_dbaccess /opt/totvs/dbaccess/multi/

RUN echo /opt/oracle/instantclient_21_3 > /etc/ld.so.conf.d/oracle-instantclient.conf && ldconfig

WORKDIR /opt/totvs/dbaccess/multi

# Correção do Caminho relativo ao contexto específico do tier
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    (chmod +x dbaccess64 2>/dev/null || true) && \
    chmod -R 755 /opt/totvs/dbaccess/multi/

ENV ORACLE_HOME=/opt/oracle/instantclient_21_3
ENV LD_LIBRARY_PATH=/opt/oracle/instantclient_21_3:$LD_LIBRARY_PATH

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
