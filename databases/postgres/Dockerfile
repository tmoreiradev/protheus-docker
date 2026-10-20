FROM postgres:16

# Instala o gerador de locales e garante a presença do pt_BR.CP1252 exigido no script
RUN apt-get update && apt-get install -y locales && \
    echo "pt_BR ISO-8859-1" >> /etc/locale.gen && \
    echo "pt_BR.CP1252 CP1252" >> /etc/locale.gen && \
    locale-gen

# Copia o script unificado para a pasta de inicialização nativa
COPY init-protheus.sh /docker-entrypoint-initdb.d/

# Força a permissão de execução do script
RUN chmod +x /docker-entrypoint-initdb.d/init-protheus.sh