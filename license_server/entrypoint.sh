#!/bin/bash
set -e

echo "✅ [License Server] Inicializando barramento de serviços..."
echo "🚀 [License Server] Iniciando o TOTVS License Server Virtual..."

cd bin/appserver

# Cria um arquivo vazio apenas para silenciar os warnings de loop do inifile se necessário
touch licenseserver.ini

if [ -f "./appsrvlinux" ]; then
    exec ./appsrvlinux -console
elif [ -f "./appsrv01" ]; then
    exec ./appsrv01 -console
else
    echo "❌ Erro Crítico: Binário não localizado!"
    exit 1
fi