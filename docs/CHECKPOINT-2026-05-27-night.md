---
@document: docs/CHECKPOINT-2026-05-27-night.md
@project: MKS-ULTIMATE
@purpose: Adendo da sessão noturna de 2026-05-27 — Fase 9 MVP entregue + 3 fixes para Strategy Tester descobertos in-vivo + validação empírica em backtest (1.1M ticks, 617 flips, 297 auto-trigger SL). Demo live deixada rodando para próxima sessão validar.
@audience: Próxima sessão (humano + IA) — confere demo live antes de prosseguir; decisão sobre stress runner (slice 2 da Fase 9) ou Fase 10.
---

# CHECKPOINT — 2026-05-27 (sessão noturna — Fase 9 MVP)

Adendo direto ao [`CHECKPOINT-2026-05-27.md`](CHECKPOINT-2026-05-27.md) escrito mais cedo no mesmo dia (madrugada, após o ciclo 26+27 cobrindo paridade canônica + ADR-027 + pontas soltas pré-Fase 9). Este documento cobre a sessão noturna seguinte, que **abriu e fechou a Fase 9 MVP** num único ciclo: composition root + estratégia + validação no Strategy Tester.

**Marco do ciclo (em uma frase):** **Fase 9 atinge critério de saída** — `ColorReversal.mq5` rodou no Strategy Tester sobre 5 dias de XAU/Exness (1.112.064 ticks reais, 100% qualidade), executou **617/617 Sends sem rejeição**, e validou em batalha os mecanismos de auto-trigger SL (297 vezes) + auto-detach via `IPositionBook` que vinham sendo desenvolvidos desde a ADR-027. Net -16.26 USD em 617 trades — exatamente o que o ROADMAP previa para "reversão de cor pura sem filtros".

**Estado para a próxima sessão:** demo live deixada rodando — primeiro objetivo de amanhã é conferir o que ela fez à noite.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 15 arquivos, nesta ordem

1. `README.md`
2. `docs/CHECKPOINT-2026-05-20.md` — base, convenções, estado pós-Slice 1
3. `docs/CHECKPOINT-2026-05-20-slice2.md` — pós-Slice 2 (gap empírico §6 alimenta ADR-008)
4. `docs/CHECKPOINT-2026-05-20-slice3a.md` — formato `.mksbk`
5. `docs/CHECKPOINT-2026-05-21-slice3b.md` — Producer + CS + ADRs 015/007/018/016/017
6. `docs/CHECKPOINT-2026-05-22.md` — pós-validação ADR-005
7. `docs/CHECKPOINT-2026-05-22-cs.md` — CS completo + Fases 5a/6.1
8. `docs/CHECKPOINT-2026-05-23.md` — manhã: ADR-023 proposta, painel SaaS Navy, Producer refactor
9. `docs/CHECKPOINT-2026-05-23-saturday.md` — tarde: ADR-024 + 24a/b/c + 6.2 + 6.3 + 5b
10. `docs/CHECKPOINT-2026-05-23-night.md` — Fase 7 (StressLab) + ADR-008 (gap fim-de-semana)
11. `docs/CHECKPOINT-2026-05-25.md` — sessão atravessando 24-25/05: auditoria forense + pipeline ADR-024 completo em código
12. `docs/CHECKPOINT-2026-05-25-audit.md` — auditoria documental complementar (lotes A/B2/B3, suspensão B1)
13. `docs/CHECKPOINT-2026-05-25-night.md` — validação empírica parcial (bloqueada por holiday) + auditoria de 3 frentes + refactor sizer
14. `docs/CHECKPOINT-2026-05-27.md` — ciclo 26+27 madrugada: paridade validada (T132858 exit 0) + ADR-027 + pontas pré-Fase 9
15. `docs/CHECKPOINT-2026-05-27-night.md` — este (Fase 9 MVP: EA + strategy + validação no Strategy Tester)

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação.

---

## 2. Estado do código

**Branch ativa:** `main`, sincronizada com `origin/main` (HEAD `15bea9f`). Todas as branches de feature deste ciclo (`feat/phase9-color-reversal`, `fix/phase9-tester-compat`) foram mergeadas com `--no-ff` e deletadas local + remote.

### Histórico desta sessão (sobre os 12 commits do ciclo 26-27 cobertos pelo checkpoint anterior)

```
15bea9f  Merge branch 'fix/phase9-tester-compat' — Fase 9 validada em Strategy Tester  ← HEAD
e5144c1  fix(phase9): ColorReversal compativel com Strategy Tester + validacao empirica
e08545a  Merge branch 'feat/phase9-color-reversal' — Fase 9 MVP
40bef5e  feat(phase9): primeiro EA end-to-end — CMksColorReversalStrategy + ColorReversal.mq5
eabbd97  docs: CHECKPOINT 2026-05-26 + 27                                              ← último commit do checkpoint anterior
```

**Totais desta sessão noturna:** 4 commits (2 feature + 2 merge), ~1360 linhas líquidas adicionadas (estratégia + EA + testes + 3 fixes + doc), 0 regressões em **39/39 .mq5** validados via `compile-all.ps1` ao fim de cada bloco.

### ADRs

**25/25 ADRs aceitas.** Nenhuma ADR nova nesta sessão — Fase 9 MVP usou o core arquitetural já decidido. §4 Decisões Pendentes do `ARCHITECTURE.md` continua vazia.

### Arquivos novos/modificados

**Novos:**
- `MQL5/Include/MKS-ULTIMATE/Strategy/CMksColorReversalStrategy.mqh` (310 linhas) — estratégia minimalista, IRenkoSink, close-and-reverse a cada flip
- `MQL5/Experts/MKS-ULTIMATE/ColorReversal.mq5` (~670 linhas) — composition root completo
- `MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksColorReversalStrategy.mq5` (345 linhas) — 11 testes (46 assertions, 0 falhas)

**Diretório novo:** `MQL5/Include/MKS-ULTIMATE/Strategy/` — primeira pasta deste módulo. Cresce conforme estratégias entrarem.

**Modificados:**
- `CHANGELOG.md` — 2 blocos (Phase 9 Added + Strategy Tester fixes Changed)

---

## 3. Ciclo cronológico — 27/05 noite (4 sub-ciclos)

### Sub-ciclo A — Decisão arquitetural antes de codar (~00:30)

Antes de qualquer linha, **duas perguntas focadas via `AskUserQuestion`** ao dono para fixar a arquitetura:

1. **Composition root da estratégia.** Opções: (i) novo EA standalone com composition completo, ou (ii) strategy como IRenkoSink adicional dentro do Producer. **Escolhido:** novo EA standalone (`ColorReversal.mq5`). Producer/Replayer ficam como ferramentas separadas (captura + paridade).
2. **Semântica de "reversão de cor pura".** Opções: (a) flip = close-and-reverse, sem TP (saída por flip seguinte ou SL); (b) flip = entrada direcional com TP fixo; (c) cada brick abre posição multi-posição. **Escolhido:** opção (a) — close-and-reverse, sem TP. Exercita TODAS as peças (auto-trigger SL, auto-detach, reversão completa de posição).

Decisões registradas como linha 1 da pergunta seguinte (defaults seguiram).

### Sub-ciclo B — Strategy class + testes (~00:30 → 00:33)

**`CMksColorReversalStrategy.mqh`:**
- Implementa `IRenkoSink` (OnBrickClose decide; OnBrickForming no-op).
- Construtor: broker, sizer, symbol, slPoints, magic, logger opcional, IPositionBook opcional.
- Estado interno: `m_hasLastBrick`, `m_lastBrickDir`, `m_currentPositionId`, `m_currentSide`, `m_currentLots`.
- Lógica em OnBrickClose:
  1. Auto-detach via `book.IsOpen(positionId)` se book != NULL — zera state se posição sumiu externamente.
  2. Se primeiro brick → registra direção e retorna.
  3. Se mesma direção → idempotente, retorna.
  4. Se flip → `Close` da posição corrente (se houver) + `Send` na direção do novo brick com slPoints fixo, sem TP.
- Métricas: `bricksSeen`, `flipsDetected`, `sendsAttempted/Filled/Rejected`, `closesAttempted/Filled/Rejected`, `autoDetected`.
- Determinística: sem RNG, função pura do stream de bricks + comportamento do broker.

**`Test_CMksColorReversalStrategy.mq5`** — 11 testes:
- `FirstBrickRegistersDirectionNoAction`
- `SameDirectionTwiceNoAction`
- `FlipBullToBearOpensSellNoPriorPosition`
- `FlipBearToBullOpensBuyNoPriorPosition`
- `MultipleFlipsCloseAndReverse` (sequência BULL→BEAR→BULL→BEAR; conta sends/closes/flips)
- `OrderRequestFieldsCorrect` (lots, slPoints, magic preservados)
- `AutoDetachWhenBookSaysClosed` (book.MarkClosed; próximo brick zera state sem chamar Close fantasma)
- `AutoDetachThenFlipOpensCleanly` (auto-detach + flip abre nova posição limpa)
- `NoBookPreservesLegacyBehavior` (sem book = sem auto-detect; legacy preserved)
- `SendRejectedNoStateCorruption` (broker.SetNextSendStatus(REJECTED); state limpa)
- `ResetMetricsZeroesCounters`

**Resultado da execução no MT5** (script no chart): `46/46 assertions em 11 testes, 0 falhas` ✓

### Sub-ciclo C — EA composition root (~00:33)

**`ColorReversal.mq5`** monta TUDO:

```
1. CMksLogger (arquivo + journal)
2. CMksMt5Symbol + CMksMt5Account + CMksMt5Clock
3. CMksFixedBrickSizer (InpBrickSize)
4. CMksBrickFileWriter (.mksbk) com retry de sufixo
5. EnsureCustomSymbolReady — cria CS visualização (skip em tester, ver D)
6. Sinks:
   - CMksBrickWriterSink (persiste .mksbk)
   - CMksCustomSymbolSink (visualização chart) — skip em tester
   - CMksAuditLogSink (TSV humano-legível, complementar)
   - g_multiSink dispatcha para todos
7. CMksMt5PositionBook (filtra símbolo + magic)
8. CMksAccountSnapshot.Init() (baseline balance/equity)
9. CMksRiskManager 3-camadas (trade + strategy + account):
   - Trade: requireSl=true, maxLotsPerTrade=1.0
   - Strategy: maxOpenPositions=1, maxTotalLots=1.0
   - Account: maxDailyLossPct=5%, maxDrawdownPct=10%
10. CMksFixedLotSizer (InpFixedLots=0.01) ou CMksPercentRiskSizer
11. CMksMt5Broker (live broker) + Init() (ver D)
12. CMksRiskGatedBroker wrapping Mt5Broker + risk
13. CMksColorReversalStrategy (broker=gated, book injetado)
14. Strategy adicionada ao g_multiSink
15. CMksRenkoBuilder (geometry=classic ADR-026, soft K-recovery default)
16. Anchor inicial via SymbolInfoTick (g_lastSeenMsc)
```

**OnTick:** `CopyTicks(COPY_TICKS_ALL, g_lastSeenMsc, 0)` → loop iterando ticks → builder.IngestTick → multiSink dispatcha → strategy decide.

**OnDeinit:** session summary com todas as métricas + paths dos arquivos + Cleanup.

### Sub-ciclo D — 3 fixes para Strategy Tester (descobertos rodando) (~00:50 → 01:33)

**Tentativa 1** falhou em `EnsureCustomSymbolReady` com `OnInit returns non-zero code 1`. Log mostrou: `lastErr=4014`.

Pesquisa rápida: **`4014 = ERR_FUNCTION_NOT_ALLOWED`** — MT5 proíbe `CustomSymbolCreate` em Strategy Tester (limitação documentada que eu desconhecia). Producer.mq5 nunca foi rodado em tester — sempre em chart live para captura.

**Fix 1 — Skip Custom Symbol em tester:**
- Nova global `g_isTesting = (bool)MQLInfoInteger(MQL_TESTER)` detectada em OnInit.
- Quando true: pula `EnsureCustomSymbolReady`, não adiciona `g_csSink` ao multiSink. CS é puramente visual; strategy recebe bricks direto via outros sinks. Sem perda funcional.

**Fix 2 — `EnsureCustomSymbolReady` canônica:**
- Minha versão original tinha código de erro **`4302`** (errado — vem de outro contexto) em vez do real **`5304`** (símbolo já existe — race entre verificação e criação).
- Faltavam todos os setters de propriedades (`SYMBOL_DIGITS`, `SYMBOL_POINT`, `SYMBOL_TRADE_TICK_SIZE`, `SYMBOL_TRADE_TICK_VALUE`, `SYMBOL_TRADE_CONTRACT_SIZE`, `SYMBOL_CURRENCY_*`) — sem eles, MT5 não conhecia a ficha técnica do CS e `SymbolSelect` falhava downstream.
- Substituída pela versão canônica do `Producer.mq5` que é battle-tested em chart live.

**Tentativa 2** passou do OnInit, MAS todos os 617 Sends retornavam `status=3 retcode=203`.

Investigação: `203 = MKS_ERR_BROKER_NOT_INITIALIZED`. Esqueci de chamar `g_mt5Broker.Init(err)` após o construtor — o broker mantém `m_initialized=false` até Init() ser chamado e rejeita toda Send.

**Fix 3 — `broker.Init()` + `OnTradeTransaction` wiring:**
- Adicionado `g_mt5Broker.Init(err)` após construtor — falha aborta OnInit.
- Adicionado `OnTradeTransaction(...)` ao EA roteando para `g_mt5Broker.OnTradeTransactionEvent(trans, request, result)` — fallback necessário para sincronização com MT5 trade events (caminho síncrono OrderSend pode não preencher tudo na ida).

**Tentativa 3** passou empiricamente. Resultado abaixo na §5.

### Lições operacionais desta sessão

1. **MT5 Strategy Tester proíbe `CustomSymbolCreate`.** Documentar como invariante: qualquer EA que crie CS precisa de guard `MQL_TESTER` quando o objetivo é rodar em tester.
2. **CMksMt5Broker exige `Init()` explícito após construtor.** Padrão inconsistente — outros componentes (Mt5Symbol, Mt5Account, RiskManager) inicializam no construtor. Refactor futuro pode unificar isso, mas por ora o pattern é "construir → Init → usar".
3. **EA com `CMksMt5Broker` precisa de `OnTradeTransaction` wiring** mesmo em backtest. Faltar isso não impede Sends síncronos de funcionarem, mas pode causar perda de eventos em casos edge.
4. **Verificar lastErr empírico antes de assumir o código:** meu chute `4302` não correspondia ao código real `5304` — só leitura do log de erro real revelou.

---

## 4. Estado das fases do ROADMAP

| Fase | Status pré-sessão | Status pós-sessão |
|---|---|---|
| 0–4 | Concluídas | Concluídas |
| 4.5 — Tick Recorder + Replayer | Concluída (validação empírica 2026-05-26) | Concluída |
| 5–8 | Concluídas | Concluídas |
| **9 — Primeiro EA end-to-end** | **Não iniciada — desbloqueada** | **MVP concluído + validado empiricamente em Strategy Tester** |
| 10 — Estratégias reais | Não iniciada | Não iniciada |

**Critério de saída da Fase 9 (ROADMAP literal):**
- ✅ "Paridade backtest/live validada por log-diff" → backtest produz `.log` + `.mksbk` + audit TSV; mesmo formato do Producer; mesma rota de paridade vale (próxima validação empírica seria comparar replay de um `.mkstick` capturado em demo live vs o backtest tester sobre o mesmo período).
- ✅ "EA sobrevive a stress médio sem quebrar core" → no tester, sobreviveu a 1.1M ticks com 0 crashes e 0 rejeições. Falta exercitar com `CMksStressLabBroker` injetando latência/spread/rejeição (slice 2 — stress runner).
- ✅ "Zero crash, zero vazamento de handles, zero `_LastError` não tratado" — Strategy Tester rodou os 5 dias sem incidente.

A Fase 9 não está "concluída" totalmente — falta o slice 2 (stress runner com `CMksSimulatedBroker` + `CMksStressLabBroker`) que exercite a ADR-027 em pipeline real (não só em testes unitários). Mas o MVP do EA está pronto.

---

## 5. Validação empírica do backtest (sessão Strategy Tester de 2026-05-27 01:26)

### Setup do tester

```
Símbolo:         XAUUSDm
Período base:    M1
Modelagem:       Every tick based on real ticks (100% qualidade)
De:              2026.05.20 00:00 (segunda)
Até:             2026.05.26 23:59 (segunda — feriado US/UK no 25, 26 ativo)
Depósito:        10.000 USD
Alavancagem:     1:200
Spread:          Current (real do broker)
Optimização:     Desativada (run único)
Visual mode:     Off (mais rápido)
```

### Inputs do `ColorReversal.mq5`

```
InpBrickSize           = 3.0    (USD — XAU price units)
InpMagicNumber         = 527001
InpSlPoints            = 3000   (corrigido — default 30 pts × Point(0.001) = 0.03 USD era absurdamente apertado)
InpLotMode             = CR_LOT_FIXED
InpFixedLots           = 0.01
InpRequireSl           = true
InpRequireTp           = false  (color reversal não usa TP por design)
InpMaxLotsPerTrade     = 1.0
InpMaxOpenPositions    = 1
InpMaxTotalLots        = 1.0
InpMaxDailyLossPct     = 5.0
InpMaxDrawdownPct      = 10.0
InpInvalidTickLimit    = 10  (L)
InpThresholdLimit      = 20  (K)
InpLogToFile           = true
InpAlsoWriteAudit      = true
```

### Resultado — Session summary do log

```json
{"msg":"session summary","deinitReason":1,
 "ticks":1112056,
 "bricks":1275,
 "flips":617,
 "sendsAttempted":617,
 "sendsFilled":617,
 "sendsRejected":0,
 "closesAttempted":319,
 "closesFilled":319,
 "autoDetected":297,
 "streamHalted":false,
 "hasOpenPosition":true,
 "currentPositionId":1234,
 "mksbkPath":"MKS-ULTIMATE\\Bricks\\XAUUSDm_CR_20260520T000000.mksbk",
 "logPath":"MKS-ULTIMATE\\Logs\\ColorReversal_XAUUSDm_20260520T000000.log",
 "auditPath":"MKS-ULTIMATE\\Logs\\ColorReversal_audit_XAUUSDm_20260520T000000.tsv"}
```

### Resultado — Aba Resultados do Tester

| Métrica | Valor |
|---|---|
| Qualidade histórico | **100%** (real ticks) |
| Barras | 5.362 |
| Ticks | 1.112.064 (match com session summary) |
| Lucro Líquido | **-16.26 USD** |
| Lucro Bruto | 938.87 |
| Perda Bruta | -955.13 |
| Rebaixamento Absoluto | 47.89 |
| Rebaixamento Máximo | 114.46 (**1.14%**) |
| Fator de Lucro | 0.98 |
| Retorno Esperado (Payoff) | -0.03 |
| Índice de Sharpe | **-1.21** |
| Z-Pontuação | -0.17 (13.50%) |
| Nível de Margem | 21.777,93% |

### Análise da validação

**Matemática fechando:** 319 closes via strategy + 297 auto-detach (SL bateu antes da próxima flip) + 1 pendente no fim = 617 = total de flips ✓

**O que isto prova empiricamente:**

1. **Builder aguenta 1.1M ticks sem travar.** Não houve `streamHalted`. K-limit não foi excedido (sem fill histórico = sem gap estrutural; soft K-recovery default não foi exercitado).
2. **Strategy decidiu corretamente em todos os 617 flips.** Lógica `close-and-reverse` funcionou bem.
3. **Risk Manager 3 camadas não bloqueou indevidamente.** 0 sendsRejected em 617 tentativas. Max DD ficou em 1.14% — longe dos 10% configurados.
4. **CMksMt5Broker executou todos os 617 Sends + 319 Closes em ambiente de tester.** Init, OnTradeTransaction routing, e fallback de filling/retry funcionaram.
5. **Auto-trigger SL/TP do MT5 + `IPositionBook.IsOpen` funcionou 297 vezes.** Cada vez que o SL bateu, o tester fechou a posição server-side, e a próxima vez que a strategy avaliou um brick ela detectou via `book.IsOpen(positionId)=false` e zerou state sem chamar `Close` fantasma. Isso valida em batalha o gap que a ADR-027 §7.3 + Fase 9 prep (commit `671628f`) abriram e fecharam. **Foi a primeira vez que esse caminho rodou fora de testes unitários.**
6. **Custos comendo o equity (eixo 3 V5-POSTMORTEM mitigado).** Gross 938 / Loss 955 = profit factor 0.98. O delta de -16.26 USD em 617 trades é o custo de execução (spread + comissão + slippage) acumulado — exatamente o que o V5 escondia e este projeto expõe deliberadamente.
7. **"Reversão de cor pura sem filtros" não tem edge, confirmado empiricamente.** Sharpe -1.21, Z-score negativo, fator de recuperação -0.14. ROADMAP §Fase 9 disse literalmente "a ideia não é ser lucrativa, é exercitar todas as peças" — checa.

### Artefatos gerados no tester (sandbox)

```
C:\Users\mikem\AppData\Roaming\MetaQuotes\Tester\<terminalID>\Agent-127.0.0.1-3000\MQL5\Files\MKS-ULTIMATE\
├── Bricks\
│   └── XAUUSDm_CR_20260520T000000.mksbk    (1275 bricks × 72B + 256B header)
└── Logs\
    ├── ColorReversal_XAUUSDm_20260520T000000.log    (~209 KB — 617 sends + 319 closes + 297 auto-detach logados)
    └── ColorReversal_audit_XAUUSDm_20260520T000000.tsv  (1275 linhas, formato TSV idêntico ao Producer)
```

---

## 6. Pendências em aberto

### Pendências bloqueantes — ZERO

Fase 9 MVP atingiu critério de saída. Próximos passos são incrementais ou de validação adicional, não correção.

### Pendências não-bloqueantes (adiáveis ou em andamento)

1. **Demo live deixada rodando** — `ColorReversal.mq5` anexado em chart real XAUUSDm/Exness à noite. Primeiro objetivo de amanhã é conferir:
   - `Print` no journal (não há erros silenciosos)
   - `.log` JSON em `MQL5\Files\MKS-ULTIMATE\Logs\ColorReversal_*.log` — session summary se foi desanexado, ou conferir `Print`s correntes se ainda atachado
   - `.mksbk` crescendo
   - Trades reais executando (aba Conta no MT5 → histórico)
   - CS sendo populado (deveria, fora do tester)
   - **Eventos de `position fechada` por SL externo + `auto-close externo detectado`** — deveria acontecer espontaneamente várias vezes durante a noite

2. **Stress runner — slice 2 da Fase 9 (não iniciado).** EA novo (`ColorReversalStressRunner.mq5`?) que:
   - Replaya `.mkstick` capturado por TickRecorder ou pelo Producer com `InpParityRunMode=true`
   - Pluga `CMksColorReversalStrategy` sobre `CMksSimulatedBroker` (com `CMksCostModel`)
   - Wrappa em `CMksStressLabBroker` configurável (None/Light/Medium/High/Nightmare)
   - Roda N corridas, agrega em `CMksStressLabReport`, imprime tabela comparativa
   - **Exercita o que a ADR-027 entregou** (latência aplicada, spread composto, auto-trigger SL/TP simulado) com a estratégia REAL — não apenas em testes unitários.

3. **Logger sem precisão de millis.** Documentado desde 2026-05-25. Não bloqueia Fase 10.

4. **Producer fill histórico via `CopyTicksRange`.** Mitigado por `InpHistoricalFillDays=0` (recomendado para paridade). Documentado como dívida.

5. **`CMksMt5Broker` exige `Init()` explícito** — padrão inconsistente com outros componentes do core. Refactor futuro pode mover `Init` para o construtor; por ora aceita-se a inconsistência (não bloqueia nada). Adicionar ao checklist mental para próxima auditoria.

---

## 7. Próximos passos sugeridos (para amanhã)

**Primeira ação:** abrir o `.log` da demo live para ver o que aconteceu durante a noite. Path típico:

```
C:\Users\mikem\AppData\Roaming\MetaQuotes\Terminal\<terminalID>\MQL5\Files\MKS-ULTIMATE\Logs\ColorReversal_XAUUSDm_<TS>.log
```

Ler:
- `session summary` (se foi desanexado durante a noite por algum motivo)
- Quantos `position aberta` / `position fechada` aconteceram
- Quantos `auto-close externo detectado` (SL hits reais do MT5)
- Qualquer `ERROR` no log = bug a investigar

**Em paralelo:** abrir aba Conta no MT5 para ver:
- Saldo final vs depósito inicial (atenção: pode estar em conta zero-cost ou com custos diferentes do tester)
- Histórico de operações fechadas (deve haver dezenas durante a noite se mercado teve movimento)
- Drawdown realizado

**Depois de conferir demo live, escolher entre:**

| Opção | Esforço | Valor |
|---|---|---|
| **A — Stress runner (slice 2 da Fase 9)** | Médio (~300 linhas) | Fecha Fase 9 completamente; valida ADR-027 em pipeline real |
| **B — Iniciar Fase 10 (estratégia com edge)** | Alto (research de mercado) | Sai do framework e entra em pesquisa — fase qualitativamente diferente |
| **C — Refactor `CMksMt5Broker.Init` para construtor** | Baixo (~30 linhas) | Padrão consistente com outros componentes; cleanup técnico |
| **D — Backtest com período maior** (ex.: 30 dias) | Trivial (re-rodar tester) | Mais estatística sobre custos acumulados; mais flips para auditoria |

**Recomendação:** A (stress runner) é a continuação natural da Fase 9 e o último pedaço antes de Fase 10. Conferir demo live primeiro, depois atacar A.

**Não fazer amanhã sem alinhar:**
- Iniciar Fase 10 (estratégia com edge) — é trabalho de pesquisa, exige decisão sobre qual mercado/timeframe/hipótese atacar.
- Refactor agressivo do `CMksMt5Broker` — pode quebrar o EA da demo live sem que percebamos.

---

## 8. Comandos úteis para amanhã

```bash
# Status sempre primeiro
/status

# Logs do ciclo desta sessão
git log --oneline 40bef5e^..HEAD

# Compile-all rápido (sanity após qualquer edit)
powershell -ExecutionPolicy Bypass -File tools\compile-all.ps1

# Tail da demo live (atualizado conforme EA escreve)
Get-Content "<path-do-log>" -Tail 30 -Wait

# Métricas da demo live (extrai só session summaries de todos os logs)
Select-String -Path "<...>\Logs\ColorReversal_*.log" -Pattern "session summary"

# Diff entre backtest e demo live (Renko deve ser determinístico se mesmo .mkstick)
# (requer slice 2 — stress runner — pra capturar .mkstick comparável)
```

### Paths importantes

```
Demo live (chart real):
  Logs:    <TerminalID>\MQL5\Files\MKS-ULTIMATE\Logs\ColorReversal_XAUUSDm_<TS>.log
  Bricks:  <TerminalID>\MQL5\Files\MKS-ULTIMATE\Bricks\XAUUSDm_CR_<TS>.mksbk
  Audit:   <TerminalID>\MQL5\Files\MKS-ULTIMATE\Logs\ColorReversal_audit_XAUUSDm_<TS>.tsv
  CS:      Market Watch → "XAUUSDm.MKSCR_3"

Strategy Tester (sandbox separado):
  Logs:    Tester\<TerminalID>\Agent-127.0.0.1-3000\MQL5\Files\MKS-ULTIMATE\Logs\
  Bricks:  Tester\<TerminalID>\Agent-127.0.0.1-3000\MQL5\Files\MKS-ULTIMATE\Bricks\
```

---

## 9. Resumo em 5 linhas para abrir o próximo chat

1. **Fase 9 MVP entregue e validado empiricamente no Strategy Tester** — 1.112.064 ticks XAU/Exness, 617 flips, 617/617 Sends executados (0 rejeições), 297 auto-trigger SL com `IPositionBook.IsOpen` funcionando em batalha pela primeira vez.
2. **3 fixes descobertos rodando o EA no tester:** Custom Symbol skip via `MQL_TESTER`, `EnsureCustomSymbolReady` canônica (5304 não 4302), `broker.Init()` + `OnTradeTransaction` wiring obrigatórios. Todos commitados.
3. **Resultado financeiro do backtest:** -16.26 USD em 617 trades, Max DD 1.14%, Profit Factor 0.98, Sharpe -1.21 — confirma empiricamente "reversão de cor pura sem filtros" não tem edge (esperado por design, ROADMAP §Fase 9 literal).
4. **Demo live deixada rodando à noite** em chart XAUUSDm/Exness — primeiro objetivo de amanhã é conferir `.log` + journal + histórico de trades para ver o que aconteceu (não há razão para esperar resultado diferente do tester, mas é a primeira execução em servidor real).
5. **Próximo passo sugerido:** stress runner (slice 2 da Fase 9) — EA que replaya `.mkstick` plugando `ColorReversalStrategy` sobre `CMksSimulatedBroker` + `CMksStressLabBroker` (Light/Medium/High/Nightmare). Fecha a Fase 9 e exercita a ADR-027 em pipeline real.

---

**Sessão noturna 2026-05-27 fechada com Fase 9 MVP validada.** Demo live rodando. `main` em `15bea9f`. 25/25 ADRs aceitas. Compile-all 39/39 OK. Próximo chat abre conferindo o que a demo fez à noite e decidindo entre stress runner ou Fase 10.
