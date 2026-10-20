# Padrões de código — protheus-docker

Este é o documento que o `/code-review` audita no eixo **Standards**. O repositório é
infra: 11 scripts Bash e um `docker-compose.yaml`. As regras abaixo saem do que os
scripts já fazem, não de um guia genérico de shell.

Arquitetura, uso e procedimentos operacionais estão no [README.md](README.md).

## Mudanças cirúrgicas

Esta regra pesa mais aqui do que num repositório de aplicação: um script de infra
quebrado derruba o ambiente de todo mundo.

- **Não delete código aparentemente morto.** Um `if` que parece redundante pode existir
  por causa de um SGBD específico, de um primeiro boot, ou de uma versão do AppServer.
  Aponte no PR, não remova.
- **Não melhore o que está ao lado.** Refatoração oportunista em script de infra mistura
  o que precisa de revisão cuidadosa com o que é óbvio.
- **Case o estilo do arquivo**, mesmo discordando.
- **Um PR, um assunto.**

## Bash

### Shebang e modo estrito

A convenção do repositório é `#!/bin/bash` com `set -e` — é o que 9 dos 11 scripts usam.

**Prefira `set -euo pipefail`** em script novo: `-u` pega variável não definida e
`pipefail` impede que uma falha no meio de um pipe passe despercebida. Ambos já
salvaram tempo aqui.

**Exceção documentada:** script que trata os próprios códigos de saída — para dar
mensagem útil em vez de morrer mudo — omite o `-e` e usa `set -uo pipefail`. É o caso do
`test_runner.sh` e do `test-local.sh`, que precisam ler o resultado do appserver e
decidir o que dizer. Quando omitir o `-e`, **diga no cabeçalho por quê**.

> Divergência conhecida: esses dois scripts usam `#!/usr/bin/env bash`, e não
> `#!/bin/bash` como os outros nove. Não há motivo técnico aqui — o Bash está sempre em
> `/bin/bash` na imagem. Vale uniformizar quando alguém encostar neles.

### Mensagens ao operador

Mensagem destinada a quem roda o comando leva **emoji como prefixo de estado** — é a
convenção do repositório, com 85 ocorrências:

```sh
echo "🚀 Invocando a Esteira de Compilação..."
echo "✅ Processo executado com sucesso total!"
echo "❌ ERRO CRÍTICO: script não encontrado!"
echo "⏳ Aguardando o barramento de infraestrutura..."
echo "👉 Use: worker, upddistr, compile ou test"
```

**Toda mensagem de erro diz o que fazer a seguir**, não só o que falhou. O `❌` vem
acompanhado de um `👉` sempre que houver ação possível.

### Comentários

Em **português**, explicando **por quê** — não o quê. O padrão da casa é um bloco no
topo do script dizendo qual problema ele resolve, e comentários inline onde a razão não
é óbvia. Bom exemplo: o cabeçalho do `test_runner.sh`, que lista as três armadilhas do
ProBat com a medição que as revelou.

Quando a razão for algo medido, **registre a data e o número**. `"medido em 18/08/2026:
13s contra 58s"` vale mais que `"mais rápido"`.

## Docker Compose

- **Serviço efêmero declara `profiles:`** — assim ele não sobe junto com a stack base.
  Hoje: `worker`, `upddistr`, `compile`, `test`.
- **Dependência de infra é `depends_on` com `condition: service_healthy`**, nunca `sleep`.
- **Variável de ambiente vem do `.env`**, com default no compose (`${VAR:-padrao}`) só
  quando a ausência for aceitável.
- **Bind de saída é explícito.** Se o container gera artefato que alguém vai ler no host
  — relatório, log, XML —, monte um diretório para isso em vez de depender de
  `docker cp`.

## O que nunca entra no repositório

Os artefatos licenciados da TOTVS: `appserver.tar.gz`, `webapp.tar.gz`,
`dbaccess.tar.gz`, `license.tar.gz`. O `.gitignore` barra `*.tar.gz` e isso é
deliberado — são ~300 MB e redistribuição de software licenciado.

Consequência prática: **este repositório não constrói em runner hospedado**. Qualquer
automação que dependa de subir o ambiente precisa de máquina provisionada.

## Antes de abrir o PR

O repositório não tem CI. Verifique à mão:

```sh
bash -n <script>                    # sintaxe
docker compose --env-file .env config --quiet   # compose válido
./run.sh compile                    # se mexeu na esteira de compilação
./test-local.sh                     # se mexeu na de testes
```

Mudou algo que roda dentro do container? **Rode de verdade.** O ciclo aqui é curto e
não há suíte que pegue regressão por você.
