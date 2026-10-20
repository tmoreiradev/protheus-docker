# ==============================================================================
# ESTÁGIO 1: Builder
# ==============================================================================
# Base Oracle Linux 8, não Ubuntu: o Protheus valida o sistema operacional e
# Ubuntu não consta na lista da TOTVS (confira com ./check-so.sh).
FROM oraclelinux:8 AS builder

RUN dnf -y install --setopt=install_weak_deps=False \
    tar gzip java-11-openjdk-headless expect \
    && dnf clean all && rm -rf /var/cache/dnf

# printf, não echo: em OL8 o /bin/sh é o bash, cujo echo não interpreta \n — o
# stub sairia numa linha só e o instalador chamaria um systemctl quebrado.
RUN printf '#!/bin/bash\nexit 0\n' > /usr/local/bin/systemctl && chmod +x /usr/local/bin/systemctl

# Portas gravadas no appserver.ini do License Server em tempo de build.
# LICENSE_PORT é a que o ERP (dbAccess/AppServer) usa para pedir licença: tem de
# bater com LICENSE_SERVER_PORT do .env, e o compose a injeta como build arg.
ARG LICENSE_PORT=5555
ARG SERVICE_PORT=2234
ARG LOG_PORT=4000
ARG SERVICE_NAME=licenseVirtual

WORKDIR /tmp/totvs_installer
COPY ./license.tar.gz .
COPY ./install.exp .

# O script `install` do tarball é `java -jar installer.jar` e ignora argumentos —
# não existe modo silencioso. O IzPack sobe em console interativo, e sem stdin ele
# lê EOF no prompt "(1) continuar / (2) sair" e aborta. Por isso dirigimos os
# prompts com expect.
RUN tar -xzf license.tar.gz && rm license.tar.gz && chmod +x install.exp && \
    ./install.exp /totvs/totvslicensevirtual "$SERVICE_PORT" "$LOG_PORT" "$LICENSE_PORT" "$SERVICE_NAME"

# ==============================================================================
# ESTÁGIO 2: Runner
# ==============================================================================
FROM oraclelinux:8 AS runner
LABEL version="3.7.1"

ENV LANG=pt_BR.UTF-8
ENV LANGUAGE=pt_BR:pt
ENV LC_ALL=pt_BR.UTF-8

# glibc-langpack-pt no lugar de locales+locale-gen; ncurses-compat-libs traz a
# libtinfo.so.5; nmap-ncat é o `nc` do healthcheck.
RUN dnf -y install --setopt=install_weak_deps=False \
    glibc glibc-langpack-pt ncurses-compat-libs libuuid libstdc++ \
    nmap-ncat java-11-openjdk-headless dmidecode \
    && dnf clean all && rm -rf /var/cache/dnf

COPY --from=builder /totvs/totvslicensevirtual /totvs/totvslicensevirtual

WORKDIR /totvs/totvslicensevirtual
COPY ./entrypoint.sh ./
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
