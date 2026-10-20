# ==============================================================================
# ESTÁGIO 1: Builder (Descarte de instaladores e lixo estrutural)
# ==============================================================================
# Base Oracle Linux 8, não Ubuntu: o Protheus 12.1.2410+ valida o sistema
# operacional no primeiro acesso de cada base (tela "Finalizar") e Ubuntu não
# consta na lista da TOTVS (confira com ./check-so.sh).
FROM oraclelinux:8 AS builder

RUN dnf -y install --setopt=install_weak_deps=False tar gzip && \
    dnf clean all && rm -rf /var/cache/dnf
WORKDIR /tmp/build

# Ajustados os caminhos para o contexto local da subpasta appserver
COPY ./protheus/bin/appserver/appserver.tar.gz .
COPY ./protheus/bin/smartclient/webapp.tar.gz .

RUN mkdir -p appserver && \
    tar -xzf appserver.tar.gz -C appserver/ && \
    tar -xzf webapp.tar.gz -C appserver/

# ==============================================================================
# ESTÁGIO 2: Runner (Imagem Enxuta de Produção)
# ==============================================================================
FROM oraclelinux:8 AS runner
LABEL version="24.3.1.9"

ENV LANG=pt_BR.UTF-8
ENV LANGUAGE=pt_BR:pt
ENV LC_ALL=pt_BR.UTF-8
ENV PATH="/totvs/protheus/bin/appserver:${PATH}"

# glibc-langpack-pt substitui locales+locale-gen: na imagem OL8 o glibc vem com
# langpack mínimo e sem ele LANG=pt_BR.UTF-8 cai para C em silêncio.
# ncurses-compat-libs traz a libtinfo.so.5 que o libtinfo5 do Ubuntu dava.
# nmap-ncat é o `nc` dos healthchecks.
RUN dnf -y install --setopt=install_weak_deps=False \
    glibc \
    glibc-langpack-pt \
    ncurses-compat-libs \
    libuuid \
    libstdc++ \
    nmap-ncat \
    unzip \
    dmidecode \
    && dnf clean all && rm -rf /var/cache/dnf

RUN mkdir -p /totvs/protheus/bin/appserver \
             /totvs/protheus/apo \
             /totvs/protheus/system \
             /totvs/protheus/systemload \
             /totvs/protheus/log \
             /totvs/protheus/data

# Copia os binários mesclados do builder sem manter os .tar.gz nas camadas
COPY --from=builder /tmp/build/appserver /totvs/protheus/bin/appserver/

# Correção do caminho do script para o contexto local
COPY ./appserver/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ./appserver/patch_deployer.sh /usr/local/bin/patch_deployer.sh
COPY ./appserver/code_compiler.sh /usr/local/bin/code_compiler.sh
COPY ./appserver/test_runner.sh /usr/local/bin/test_runner.sh
COPY ./appserver/ini_merge.awk /usr/local/bin/ini_merge.awk

RUN chmod +x /usr/local/bin/entrypoint.sh \
             /usr/local/bin/patch_deployer.sh \
             /usr/local/bin/code_compiler.sh \
             /usr/local/bin/test_runner.sh \
             /totvs/protheus/bin/appserver/appsrvlinux

WORKDIR /totvs/protheus/bin/appserver
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
