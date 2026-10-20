# advpl-lint — analisador estático oficial da TOTVS no lab

`advpl-lint.sh` embrulha a imagem `totvsengpro/advpl-tlpp-code-analyzer` (runAlone 2.0.9, regras em
https://sonar-rules.engpro.totvs.com.br/menu/rules). Só relata: o exit code é 0 quando o analisador rodou e
2 quando não rodou; as ocorrências nunca mudam o exit code (`breakOnError: false` no `config.json`).

```
tools/advpl-lint/advpl-lint.sh -o /tmp/lint src/meu_fonte.tlpp
tools/advpl-lint/advpl-lint.sh -o /tmp/lint-src src/          # pasta inteira
```

Saída em `-o`: `output.json` (o do analisador), `execution.log`, `console.log` e `summary.md` (totais, tabela por
regra e lista por arquivo com as linhas). O `summary.md` serve para anexar a um review ou a um comentário de PR.

## config.json

`ignoreList` começa vazia. Toda regra que entrar ali precisa de uma linha na tabela abaixo dizendo por quê
(JSON não aceita comentário).

| Código ignorado | Motivo |
|---|---|
| (nenhum) | |

## Como o container funciona (lido do entrypoint da imagem em 2026-09-11)

- Copia todo `*.pr?`, `*.ppo` e `*.tlpp` achado em `/tmp` (recursivo) para `/bin/src`, **flat**: dois fontes com o
  mesmo nome em pastas diferentes se sobrescrevem. O script prefixa duplicatas.
- Copia todo `*.ch`/`*.th` achado em `/tmp` para `/bin/includes` e por cima os includes ADVPL padrão da imagem
  (`/bin/includes_padrao`, linha lobo_guara).
- As includes **TLPP** (`tlpp-core.th`, `tlpp-rest.th`, `tlpp-object.th`, `tlpp-probat.th`) não vêm na imagem.
  Sem elas todo fonte que as inclui cai em `CA0000` (erro de compilação) e as demais regras não rodam nele. O
  script monta as do lab (`protheus/includes/_extracted/tlpp` e `custom`).
- `config.json` vai em `/bin/conf`; `output.json` sai em `/bin/output`. Java com `-Xmx6144M`: uma pasta com ~200
  fontes leva cerca de um minuto.

## Regras mais comuns

| Código | Sev. | Significado |
|---|---|---|
| CA2050 | WARN | Possível SQL inject (string de query montada com concatenação) |
| CA2051 | WARN | Possível SQL inject em `BeginSql` (embedded) |
| CS1000 | WARN | Query SQL escrita direto no ADVPL/TLPP |
| CA2004-2 | ERROR | Leitura direta do metadado SX3 (`SX3->`, `DbSelectArea("SX3")`) |
| CA2010 | ERROR | Leitura/atualização direta do SX6 |
| BG1200 | ERROR | Sobrescrita do bloco de erro (`ErrorBlock`) |
| CA2024 / CA2025 | ERROR | Atribuição a `cUserId` / `cEmpAnt` |
| CA1001-2 | WARN | Acesso a filesystem compartilhado (`MemoRead`, `FCreate`, `cGetFile`), ofensor para SmartERP |
| CA1004 | WARN | API de console (`ConOut`, `QOut`) |
| CA0000 | ERROR | Erro de compilação do próprio analisador (quase sempre include faltando) |
