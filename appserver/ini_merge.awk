# Mescla um .ini de override no appserver.ini gerado pelo entrypoint.
#
#   awk -f ini_merge.awk override.ini appserver.ini > resultado.ini
#
# Regras:
#   - chave que já existe na seção  -> substituída no lugar (mantém a posição);
#   - chave nova numa seção existente -> acrescentada ao fim daquela seção;
#   - seção inteiramente nova        -> acrescentada ao fim do arquivo.
#
# Seções e chaves são comparadas sem distinção de caixa, que é como o AppServer
# as trata. O merge é explícito de propósito: não dependemos de o parser da TOTVS
# aceitar chaves duplicadas — o arquivo final nunca tem duplicatas.

function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }

# Segura linhas em branco para não emiti-las antes das chaves acrescentadas —
# senão a chave sairia depois do espaçamento, colada no cabeçalho seguinte.
function emitPending(   i) {
    for (i = 1; i <= np; i++) print pend[i]
    np = 0
}

# Ao sair de uma seção, despeja as chaves do override que ela ainda não tinha.
function flushSection(   j, K) {
    if (cur == "") return
    for (j = 1; j <= nkey[cur]; j++) {
        K = keyAt[cur, j]
        if (!((cur SUBSEP K) in done)) {
            print ovKey[cur, K] "=" ovVal[cur, K]
            done[cur, K] = 1
        }
    }
    cur = ""
}

# ---------------------------------------------------------------------------
# 1ª passada: carrega o arquivo de override
# ---------------------------------------------------------------------------
FNR == NR {
    t = trim($0)
    if (t == "" || t ~ /^[#;]/) next

    if (t ~ /^\[.*\]$/) {
        sec = trim(substr(t, 2, length(t) - 2))
        SEC = toupper(sec)
        if (!(SEC in secKnown)) {
            secKnown[SEC] = 1
            secOrder[++nsec] = SEC
            secLabel[SEC] = sec
        }
        next
    }

    eq = index(t, "=")
    if (eq == 0 || SEC == "") next

    key = trim(substr(t, 1, eq - 1))
    K = toupper(key)
    if (!((SEC SUBSEP K) in ovKnown)) {
        ovKnown[SEC SUBSEP K] = 1
        keyAt[SEC, ++nkey[SEC]] = K
    }
    ovKey[SEC, K] = key
    ovVal[SEC, K] = trim(substr(t, eq + 1))
    next
}

# ---------------------------------------------------------------------------
# 2ª passada: reescreve o .ini gerado
# ---------------------------------------------------------------------------
{
    line = $0
    sub(/\r$/, "", line)
    t = trim(line)

    if (t == "") { pend[++np] = line; next }

    if (t ~ /^\[.*\]$/) {
        flushSection()
        emitPending()
        cur = toupper(trim(substr(t, 2, length(t) - 2)))
        seen[cur] = 1
        print line
        next
    }

    emitPending()

    eq = index(t, "=")
    if (eq > 0 && cur != "") {
        key = trim(substr(t, 1, eq - 1))
        K = toupper(key)
        if ((cur SUBSEP K) in ovKnown) {
            print key "=" ovVal[cur, K]
            done[cur, K] = 1
            next
        }
    }

    print line
}

END {
    flushSection()
    emitPending()

    for (i = 1; i <= nsec; i++) {
        s = secOrder[i]
        if (s in seen) continue
        print ""
        print "[" secLabel[s] "]"
        for (j = 1; j <= nkey[s]; j++) {
            K = keyAt[s, j]
            print ovKey[s, K] "=" ovVal[s, K]
        }
    }
}
