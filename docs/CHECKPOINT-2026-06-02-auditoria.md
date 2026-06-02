---
@document: docs/CHECKPOINT-2026-06-02-auditoria.md
@project: MKS-ULTIMATE
@purpose: Handoff da auditoria completa de 2026-06-02 — 10 dimensões, leitura integral do core, verificação adversária de cada achado alto/médio. Registra os 58 achados (4 altos, 9 médios, 45 baixos/cosméticos), o que está genuinamente bem-feito, e aponta o plano de fechamento do core (docs/ROADMAP-CORE-HARDENING.md).
@audience: Próxima sessão (humano + IA) que vá executar o fechamento do core antes de estratégias/indicadores.
---

# CHECKPOINT — 2026-06-02 (auditoria completa + decisão de fechar o core)

**Regra:** CHECKPOINT é guia, código é verdade.

**Contexto:** o dono pediu uma auditoria completa e crítica, com foco em (1) paridade backtest/live/demo/tester, (2) confiabilidade da geração de Renko, (3) indicadores fiéis, (4) divergências doc↔código, (5) UX/simplicidade rumo a SaaS, (6) a forma de trabalhar (arquitetura, processo, protocolos). Decisão tomada após a auditoria: **fechar o core e deixá-lo 100% robusto ANTES de desenvolver estratégias e indicadores.** O plano de execução vive em `docs/ROADMAP-CORE-HARDENING.md`.

---

## 1. Método

- **10 dimensões auditadas em paralelo** por agentes dedicados, cada um lendo os arquivos da sua dimensão integralmente e confrontando contra os ADRs/REGRAS/ROADMAP/V5-POSTMORTEM: paridade-ticks, renko-builder, custom-symbol, indicadores, broker-execução-custo, trade-risk, estratégia-ea, camada-de-testes, divergência-doc-código, ux-processo.
- **Verificação adversária:** cada achado de severidade **alta/média** passou por um segundo agente cético, instruído a *tentar refutá-lo* lendo o código real (default para "refutado" se não conseguisse confirmar). Dos candidatos brutos, **1 foi refutado** e os demais mantidos, vários com severidade **rebaixada** pelo verificador (ex.: 2 "alto" → "médio" por impacto menor que o alegado).
- **Cross-check independente do auditor humano-assistido (esta sessão):** leitura própria de `CMksRenkoBuilder`, `CMksColorReversalStrategy`, `Error.mqh`, `CMksCustomSymbolSink`, e dos composition roots. Os achados que verifiquei à mão (furo de paridade do `fillDays`, divergência de códigos de erro do ADR-024, limpeza da estratégia, presença dos 4 fixes do CS) **convergiram** com os agentes por caminhos independentes.
- **Disclaimer:** a auditoria é **estática** (leitura de código). Não houve execução de testes no MT5 nem do pipeline `verify-parity` (não há terminal nem `.mkstick`/`.mksbk` reais versionados). Achados de comportamento dinâmico (recovery em rampa, sobrevivência do CS à meia-noite) precisam de validação empírica.

**Resultado:** 58 achados confirmados/parciais — **4 altos, 9 médios, 42 baixos, 3 cosméticos** — e 1 refutado.

---

## 2. Veredito geral

O framework é **estruturalmente sólido e profissional**. Os quatro eixos que mataram o V5 estão **fechados no código**, não só na retórica:

- **Produtor único de bricks** (eixo 2): Producer, Replayer e ColorReversal instanciam o *mesmo* `CMksRenkoBuilder` com geometria classic idêntica e os mesmos `L=10/K=20/kRecoverAfter=5`. Zero `MQL5_TESTING` na lógica (grep confirmou: as únicas consultas de ambiente vivem nas bordas/composition roots).
- **Preço observado, não matemático** (eixo 1): `Brick.close` está marcado "NÃO usar para decisão"; o builder grava `triggerPrice`/`triggerTickId`; a estratégia decide por `direction` e registra `r.fillPrice`.
- **Custo no fill** (eixo 3): `FillPriceFor` embute half-spread + slippage no preço de fill — não num contador paralelo. (Ressalva: **comissão e swap** ainda escapam — ver M1.)
- **Sem bifurcação de ambiente** (eixo 4): a diferença backtest/live vive só no composition root.

**O risco central, porém, é a lição do V5 aplicada ao próprio V6:**

> O V5 não foi destruído por código quebrado — foi destruído por código que *parecia* validado. O mesmo risco existe aqui numa forma mais sutil: **a garantia de paridade é mais estreita do que os documentos afirmam, e a diferença é invisível porque tudo parece comprovado.**

"Paridade bit-a-bit — fato, não teorema" vale **apenas** no envelope estreito: Producer↔Replayer, `fillDays=0`, comparando o **stream de bricks** (`.mksbk`). Fora dele — que é o **default de produção** (`InpHistoricalFillDays=3`) — a garantia não foi provada, e a **camada onde o V5 quebrou a conta (decisão→execução→equity) nunca foi comparada live-vs-replay** (o Replayer nem instancia estratégia/broker). Fechar essa lacuna é o objetivo do `ROADMAP-CORE-HARDENING.md`.

---

## 3. Achados ALTOS (4) — verificados adversarialmente

| ID | Achado | Arquivo | Verificador |
|----|--------|---------|-------------|
| **H1** `no-real-tick-replay-test` | **Nenhum teste automatizado consome `.mkstick` real → builder → bricks.** Toda a suíte usa ticks sintéticos (spread fixo 0.10). A "paridade real com ticks reais" é procedimento de operador (`verify-parity.ps1` manual), não rede de regressão. `ValidateBuilderOnRealTicks` só imprime agregados (0 asserts); `Test_Producer` é ESBOCO interativo. | `Test_CMksRenkoBuilder.mq5` (suíte inteira) | confirmado (conf 0.85) |
| **H2** `soft-recovery-105-untested` | **Soft-recovery (código 105) tem cobertura zero.** `HandleKExceeded` com `gapDetected==true` reancora `m_lastClose`, reseta direção (`m_hasFirstBrick=false`) e reescreve a sequência de bricks — habilitado por default (`kRecoverAfter=5`), referenciado pelos 3 EAs, sem um único teste. Regressão (`<=`→`<`, ou `m_kFirstMid`→`mid`) passaria batida até um gap de reabertura em produção. | `CMksRenkoBuilder.mqh:89-127` | confirmado (conf 0.9-1.0) |
| **H3** `slpoints-default-invalid-stops` | **`InpSlPoints=30` (default) causa INVALID_STOPS (10016).** A estratégia passa `slPoints` cru; `CMksMt5Broker` calcula `slPrice = ref ± slPoints·point` **sem nunca consultar `SYMBOL_TRADE_STOPS_LEVEL`** — apesar de `ISymbol::StopsLevel()` já existir e não ser usado. 10016 não é retryable → ordem rejeitada. Falha **fechada** (sem perda, sem posição órfã), mas o EA de fábrica não consegue operar. Ocorreu em produção 06-02. | `ColorReversal.mq5:75`, `CMksMt5Broker.mqh:289-297` | confirmado, rebaixado de critical→high (fail-closed) |
| **H4** `replayer-never-exercises-decision` | **Paridade de DECISÃO nunca é verificada.** O Replayer monta só `source→clock→sizer→builder→writer` — **não instancia** broker, estratégia nem risk manager (grep: zero matches). O `fc/b` compara só o **stream de bricks**, não as ordens. `verify-parity.ps1` admite (l.231-236) que o filtro casa só eventos do builder, não `decision:buy/sell/close`. É o slice 2 pendente da Fase 9. A camada onde o V5 quebrou (eixos 1/3) não tem comparação live↔replay. | `Replayer.mq5` | confirmado, rebaixado high→medium pelo verificador (dívida rastreada, não falsa-afirmação em código), mantido como **alto** nesta síntese pela centralidade ao princípio norteador |

---

## 4. Achados MÉDIOS (9) — verificados adversarialmente

| ID | Achado | Arquivo |
|----|--------|---------|
| **M1** `commission-swap-parallel-counter` | **Comissão e swap são computados mas NUNCA aplicados ao PnL** no caminho `SimulatedBroker→TradeJournal`. O journal mede só `(close−open)/point`; `RecordClose` nem recebe comissão. É o **eixo 3 ressurgindo na métrica de decisão do StressLab** — vira alto quando o StressLab determinístico for o oráculo de "ir pra live". (Hoje o caminho de produção usa o tester nativo, cujo equity aplica comissão — por isso médio, não alto.) | `CMksTradeJournal.mqh:73-79` |
| **M2** `recovery-monotonic-ramp-deadlock` | **Recovery trava em rampa monotônica.** `m_kFirstMid` é fixado no *primeiro* mid rejeitado e nunca atualiza; reabertura direcional sustentada (caso ADR-008) afasta-se da banda `±S` e `gapDetected` fica `false` para sempre. Cobre "salto+patamar", não "salto+tendência". Mitigado por `fillDays=0` + dimensionar K. | `CMksRenkoBuilder.mqh:95-103` |
| **M3** `cs-multithreshold-atr-fictional-prices` | **"Zero divergência preço/desenho" só vale para fixed + M=1.** Em brick multi-threshold (M>1, ocorre no default classic) `brick.close=open±M·S` mas `visualClose=open±S`; em ATR o `brickSizePts` é congelado no `defaultSize` do warm-up. Indicadores arrastados no CS calculam sobre números fictícios — o mesmo defeito que a ADR-026 fechou só para o median. | `CMksCustomSymbolSink.mqh:122-141` |
| **M4** `eixo3-equity-never-asserted` | **Eixo 3 nunca é assertado na curva de equity.** Prova-se que o fill embute custo, mas nenhum teste fecha round-trip e verifica que o equity caiu pelo custo. `CMksSimulatedBroker` não mantém equity/PnL; o journal é em pontos. Meia-verdade: embutir no fill ≠ o resultado sentir. (`Test_RPT_CaptureFromRealPipeline` fecha o round-trip mas só assere `slippageTotalPoints`, não o efeito no netPnL.) | `CMksSimulatedBroker.mqh:250-358` |
| **M5** `adr024-phantom-error-codes` | **ADR-024 nomeia 6 códigos `MKS_ERR_TICKFILE_*` que não existem**, com números que colidem com os `MKS_ERR_DATA_*` reais (symbol mismatch é 807, não 803; seq é 810, não 804). O código está correto; a ADR canônica da paridade nunca foi reconciliada. Propaga para o `CHANGELOG.md:248`. | `ARCHITECTURE.md:1750-1758` vs `Error.mqh:62-78` |
| **M6** `validate-renkobuilder-no-asserts` | **`ValidateRenkoBuilder.mq5` tem 0 asserções** — os "Esperado:" vivem em comentários que nenhum código checa (`overshoot=18` etc.). Falso senso de cobertura. Mitigado: os mesmos casos têm asserts reais em `Test_CMksRenkoBuilder` (`Test_Overshoot`, `Test_FormingBrickAfterEmission`). | `ValidateRenkoBuilder.mq5:153-163` |
| **M7** `producer-test-draft-no-trigger` | **`Test_Producer` (melhor prova real-tick) é rascunho interativo**, rotulado "ESBOCO", depende de dados externos, só cobre classic, **não compara `triggerTickId` nem high/low** (nem `triggerPrice`, descobriu o verificador) — justamente os campos que distinguem close matemático de mid observado (eixo 1). | `Test_Producer.mq5:5-15,354-359` |
| **M8** `commission-not-on-autoclose-consumed` | **`commissionClose` do auto-close de SL/TP também é descartado** pelo journal (reinstância de M1 na saída mais comum em live). O broker cumpre o contrato (carrega o campo); o defeito está no consumidor (report/journal em pontos). | `CMksSimulatedBroker.mqh:197-208` |
| **M9** `watcher-blind-experts-quote-includes` | **Watcher cego aos `Experts/`/`Services/` e a `#include "quote-style"`.** Salvar um `.mqh` do core **não recompila** ColorReversal/Producer/Replayer — exatamente os artefatos que vão a mercado e onde o trabalho ativo está. Editar `TestRunner.mqh` (quote-include) não recompila os 20 testes que o usam. Falsa confiança pior que ausência. | `tools/watch-compile.ps1:20,31,56,122` |

---

## 5. Achados BAIXOS (42) e COSMÉTICOS (3) — por dimensão

Lista compacta (ID — síntese — `arquivo:linha`). Detalhe completo (realidade/impacto/recomendação) está disponível sob demanda.

### Paridade
- `parity-mt5clock-wallclock-leak` (low) — `CMksMt5Clock.NowMsc()` retorna `TimeCurrent()*1000` (wall-clock, truncado em segundos); `ReplayClock` retorna `tick.timeMsc`. A camada Por-Conta usa `NowMsc()` para a fronteira de dia UTC → reset diário cai em momento diferente sob replay perto da meia-noite. `CMksMt5Clock.mqh:25-29`.
- `parity-historical-fill-copyticksrange` (low) — fill via `CopyTicksRange` ≠ feed live; em `InpParityRunMode` o default de `fillDays` é 30, gerando `.mksbk` com bricks que o replay não reproduz → **falso-negativo** de paridade. `Producer.mq5:440-467`.
- `parity-brickfileformat-direction-doc` (low) — doc diz "0=BULL,1=BEAR"; enum real é BULL=1, BEAR=-1 (round-trip fechado, só doc errada). `BrickFileFormat.mqh:40`.
- `parity-mt5clock-isready-asymmetry` (low) — `CMksMt5Clock.IsReady()` sempre true vs `ReplayClock` condicional ao 1º tick → `snapshot.Init()` em `OnInit` captura baseline diferente entre ambientes. `CMksMt5Clock.mqh:33`.

### Renko
- `recovery-doc-says-variance` (low, confirmado) — comentário diz "variância ≤ S"; código mede distância ao primeiro mid (`MathAbs(mid-m_kFirstMid)<=size`), não variância. `CMksRenkoBuilder.mqh:99-103`.
- `seed-lastclose-depends-on-fillDays` (low) — `m_lastClose` = mid do 1º tick; `fillDays` muda o 1º tick → muda toda a escada. Default ≠ config de paridade. `CMksRenkoBuilder.mqh:235-243`.
- `atr-sizer-state-breaks-parity` (low) — ATR acumula estado sobre bricks; warm-up com `fillDays>0` vs zero produz tamanhos divergentes (estado não serializado no `.mkstick`). `CMksAtrBrickSizer.mqh:137-170`.
- `recovery-stale-lastDirection` (low) — reanchor não reseta `m_lastDirection`; `GetFormingBrick()` retorna direção stale (só observabilidade). `CMksRenkoBuilder.mqh:105-119,388-390`.
- `equality-double-compare` (low) — `==`/`>=` em double; determinístico intra-binário, risco só se Producer/Replayer rodarem FPU/arquitetura diferentes. `CMksRenkoBuilder.mqh:275,287-289`.

### Custom Symbol
- `cs-midnight-survival-unverified` (low) — os 4 fixes estão no código, mas a sobrevivência à virada de dia (06-02→06-03) é **pendente de dado** pelo próprio doc. `ARCHITECTURE.md:1664`.
- `cs-spec-wipe-vs-explicit-wipe` (low) — `InpResetCustomSymbolBars=true` (default) apaga toda a série a cada `OnInit` via `CustomRatesDelete`; mascara o teste de persistência do fix (b). `Producer.mq5:697-705`.
- `cs-forming-bar-orphan-vs-doc` (low) — em mercado calmo a bar parcial fica órfã num slot anterior (comportamento aceito por ADR-023 r.3), mas o header do sink diz "sobrescreve este mesmo slot". `CMksCustomSymbolSink.mqh:11-12,170-174`.
- `cs-recovery-advances-timeline-on-fail` (low) — em falha permanente do `CustomRatesUpdate`, `lastBarTime`/`nextBarTime` avançam mesmo assim → painter ancora em slot vazio + timeline deriva. **Corrigir: só avançar no ramo de sucesso.** `CMksCustomSymbolSink.mqh:145-167`.
- `cs-forming-no-recovery-asymmetry` (cosmetic) — `OnBrickForming` (mais frequente) não loga a 1ª falha; o sinal mais precoce da morte do CS é mudo. `CMksCustomSymbolSink.mqh:188-194`.
- `cs-painter-discards-real-timemsc` (cosmetic) — painter usa `lastBarTime` em live (correto por ADR-028), mas o header da interface ainda diz "tempo real". `CMksChartPainter.mqh:133-138`.

### Indicadores
- `indicators-not-magnitude-aware` (low) — os 5 recebem `tick_volume[]` (= `thresholdsCrossed`) mas nunca leem; bricks M>1 entram como caixa nominal → operam sobre níveis que o mercado não imprimiu (eixo-1-like na visualização). `CMksChandelier.mq5` + 4 outros.
- `auto-infer-bricksize-fragile-fallback` (low, confirmado) — `|close[1]-open[1]|` é correto em produção (fixed+`brickSizePts>0`), mas quebra silenciosamente no fallback legado (`brickSizePts==0`) e em ATR. `CMksChandelier.mq5:134-147` / `CMksSuperTrend.mq5:131-143`.
- `flipping-tests-internal-consistency` (low) — testes de Chandelier/SuperTrend derivam `expectedStop` lendo o `trendBuf` do **próprio** indicador; não recomputam a máquina de estados de trend desde o seed. `Test_CMksChandelier.mq5:159-205` / `Test_CMksSuperTrend.mq5:156-205`.
- `catalog-status-unsubstantiated` (low) — status "✓ N bars, zero divergência" não tem artefato de execução versionado; "RSI bate 0.0" contradiz a tolerância do próprio teste (1e-10). `INDICATORS.md:95-101`.
- `indicators-foundation-vs-cs-deprecation` (low) — os 5 dependem 100% do CS via `iCustom`, cujo futuro está em disputa (ADR-031). Construir mais antes de resolver ADR-031 pode ser trabalho jogado fora. `INDICATORS.md:24,28-30`.

### Broker / execução / custo
- `slippage-counter-not-validated-against-pnl` (low) — teste valida o contador `slippageTotalPoints`, não que o slip moveu o `netPnL`. `Test_CMksStressLabReport.mq5:213-220`.
- `spread-multiplier-silent-noop` (low) — `baselineSpreadPoints=0` em todos os presets → `spreadMultiplier=10` do `Nightmare` adiciona ZERO de spread (knob inerte por default). `CMksStressParams.mqh:139-197`.
- `mt5broker-sleep-retry-backoff` (low) — `Sleep` no retry/backoff e `WaitForDealAdd` (borda, caminho de exceção, não-HFT — aceitável; registrar como dívida na ADR-017). `CMksMt5Broker.mqh:153,339,385,469`.

### Trade / risco
- `partial-close-partial-status-reapplies` (low) — partial não trata `MKS_EXEC_PARTIAL`; flag fica `false` e re-fecha `m_initialLots*pct` de novo → excede o volume pretendido. Sem teste de PARTIAL. `CMksTradeManager.mqh:341-361`.
- `circuit-breaker-only-gates-opening` (low, confirmado) — breaker (drawdown/minEquity/dailyLoss) só bloqueia abertura; posição em curso continua sangrando. É freio de mão, não botão de pânico. `CMksRiskGatedBroker.mqh:68-84`.
- `daypnl-uses-equity-not-balance` (low) — `DayPnL()=Equity()-dayStartBalance` mistura equity flutuante com baseline de balance; diverge do doc "balance início do dia". `CMksAccountSnapshot.mqh:120-133`.
- `rollover-baseline-equity-vs-balance` (low) — rollover correto; viés herdado é o mesmo de `daypnl-uses-equity` (resolver junto). `CMksAccountSnapshot.mqh:90-104`.
- `trademanager-not-wired-in-ea` (low) — `CMksTradeManager` (BE/trail/partial) não é usado por nenhum EA; a state machine de gestão nunca roda fim-a-fim. `ColorReversal.mq5:684-692`.
- `fixedlot-sizer-ignores-sl-distance` (low) — `FixedLot.ComputeLots` ignora `slDistancePoints`; a checagem "lots vs sizer" do Risk vira tautológica no modo fixo (e o EA passa `sizer=NULL` ao Risk). `CMksFixedLotSizer.mqh:97-117`.

### Estratégia / EA
- `warmup-seed-asymmetry-tester-vs-live` (low) — seed de `m_lastBrickDir` diverge: live semeia via `RunHistoricalFill` (CopyTicksRange); tester pula o fill. 1ª decisão live ≠ replay. `ColorReversal.mq5:714-766`.
- `close-failure-clears-state-still-opens` (low) — em flip, `CloseCurrentIfAny` zera state mesmo em falha e abre nova posição → exposição órfã possível se o gate de risco não recusar. **Não abrir se Close falhou.** `CMksColorReversalStrategy.mqh:158-184`.
- `header-describes-nonexistent-stress-runner` (low) — `@responsibility` de `ColorReversal.mq5` narra um stress runner como existente; ele não existe. `ColorReversal.mq5:14-16`.

### Camada de testes
- `fakeclock-isready-cannot-be-false` (low) — `CMksFakeClock.IsReady()` hardcoded true, sem setter; impossível testar o ramo "clock não pronto". `CMksFakeClock.mqh:27-29`.

### Doc↔código
- `adr024-phantom-error-codes` (low, confirmado) — ver M5 (o mesmo achado, registrado nas duas dimensões). `ARCHITECTURE.md:1750-1758`.
- `changelog-adr024-tickfile-perpetuation` (low) — CHANGELOG repete os nomes `MKS_ERR_TICKFILE_*` fantasmas. `CHANGELOG.md:248`.
- `compile-all-35-mq5-stale` (low) — CHANGELOG diz "todos os 35 .mq5"; disco tem 41 (script varre dinâmico, só o número narrado envelheceu). `CHANGELOG.md:153`.
- `roadmap-fase8-logger-pluggable` (low) — ROADMAP diz logger "output plugável"; o `CMksLogger` tem destino dual fixo (Print + arquivo), fiel à ADR-007. `ROADMAP.md:282-284`.
- `adr007-context-fields-vs-impl` (low) — ROADMAP lista "ticket" como contexto automático; logger emite `ctxJson` livre, sem campo ticket automático. `ROADMAP.md:284`.
- `roadmap-test-count-historical` (cosmetic) — "648/648" já etiquetado como histórico; piso "870" levemente desatualizado vs ~918 macros. `ROADMAP.md:102`.

### UX / processo
- `input-surface-too-large` (low) — ~30 inputs no ColorReversal; K/L e flags de diagnóstico expostos ao operador. `ColorReversal.mq5:68-120`.
- `run-ea-flow-manual-multistep` (low) — fluxo de operação tem 3 EAs + 1 service + scripts com responsabilidades sobrepostas; fácil errar a anexação. `ColorReversal.mq5:386-396`.
- `branch-divergence-stale-main` (low) — `main` em 27/05; `phase9-viz` +18 commits; `sensors-foundation` +39/−2 (divergência real). ADR-029/030 validados só em feature branch. `CHECKPOINT-2026-05-30.md:38`.
- `checkpoint-adr-proliferation-cost` (low) — 17 checkpoints + 31 ADRs em ~12 dias, com retrabalho (ADR-031 escrita→revertida; cap da 023-A admitido como band-aid). `CHECKPOINTS.md:22-38`.
- `k-l-defaults-coupled-to-fill-days` (low) — segurança do K=20 depende de `fillDays`/`brickSize` via **comentário**, não via código; defaults de `fillDays` divergem entre Producer (30) e ColorReversal (3). `Producer.mq5:83`.
- `pts-naming-misleading` (low) — `InpBrickSize` é unidade de preço apesar de "Pts" interno; `InpSlPoints` é ponto do símbolo. Dois inputs vizinhos, "points" com semânticas diferentes — ligado ao H3. `Producer.mq5:71`.

---

## 6. Achado REFUTADO pela verificação adversária (1)

- `test-determinism-same-process` (era médio) — alegava que `Test_Determinism` (dois builders no mesmo processo) "não é o rodar-2×-comparar do Protocolo 1". **Refutado:** o Protocolo 1 não se apoia nesse unit test para a garantia bit-a-bit cross-run — essa vem do `verify-parity.ps1` (live vs replay, processos distintos). O fato mecânico era verdadeiro, mas a tese (garantia "mais fraca do que parece") caiu.

---

## 7. O que está genuinamente BEM-FEITO (não é só lista de culpas)

- **Anti-V5 real no código:** produtor único, `triggerPrice`/`triggerTickId`, custo no fill (spread+slippage), zero condicional de ambiente na lógica. Verificado por grep e leitura, nas duas pontas (agentes + cross-check).
- **Serialização determinística:** `FileWriteDouble`/`FileReadDouble` (IEEE-754, round-trip bit-a-bit, sem texto), layout fixo, validação `FileSize==header+N·record`.
- **`ReplayClock` é função pura do feed**; `verify-parity.ps1` ignora corretamente só os 8 bytes de wall-clock (`createdAtMsc`) e mapeia offset→campo.
- **Migração `SymbolInfoTick`→`CopyTicks`** corrigiu uma divergência de feed real (16.615 vs 34.083 ticks) na causa-raiz.
- **Motor Renko:** escada estável (reset no threshold exato, não no mid), multi-threshold honesto (1 brick, sem fabricar), guarda de tick inválido limpa, `Test_Determinism` cobre o caminho normal brick-a-brick.
- **CS — fronteira visual respeitada:** grep no Include tree não acha nenhum read do CS em lógica; os **4 fixes** da reversão 06-02 (sessões 24/7 nos 7 dias; specs só na criação via `if(created)`; recovery no sink sem engolir erro; painter ancorado em `lastBarTime`) **estão presentes e corretos**. `ComputeBrickTime` é pura e tem 9 testes (incl. regressão do runaway de 05-29).
- **Broker/StressLab:** clamp "stress só piora", `CMksRandom` LCG seedável, auto-trigger SL/TP determinístico, adversidade simétrica entrada/saída (ADR-030) implementada e testada, guarda hedging-only em duas camadas.
- **Risco:** 3 camadas com códigos 400-409 batendo com os ADRs, breaker HARD na abertura (não cosmético), trailing ratchet genuíno, idempotência de BE/partial no caminho feliz e na falha.
- **Indicadores:** brick-driven sem ATR é decisão honesta; RSI/MACD na forma canônica de smoothing validados contra o nativo; Donchian recomputa a verdade independentemente; `probe = rates_total-2` pula corretamente a bar parcial.
- **Processo:** registro honesto e auto-crítico — a sessão **reverteu o próprio diagnóstico errado do CS** ao comparar com o V5 (que sobrevivia com o mesmo `CustomRatesUpdate`). Disciplina de proveniência, cleanup de ponteiros, observabilidade SaaS-grade (JSON-line + `.mksbk` + audit TSV + checkpoint de 60s).

---

## 8. Decisão e plano

**Decisão do dono:** fechar o core e deixá-lo 100% robusto **antes** de desenvolver estratégias e indicadores (disciplina anti-V5 — "core antes de estratégias").

**Plano de execução:** `docs/ROADMAP-CORE-HARDENING.md` — 8 fases de endurecimento (E1–E8), cada uma mapeando os achados acima a itens com critério de saída. As fases **E1–E5 são gate bloqueante** para a Fase 10 (estratégias reais); **E8** é pré-requisito de novos indicadores. Regra de ouro mantida: nenhuma fase começa antes da anterior cumprir o critério de saída.

---

**Resumo em 3 linhas:** (1) Core estruturalmente sólido — os 4 eixos do V5 estão fechados no código; o risco é a paridade ser **mais estreita do que os docs dizem** (provada só em `fillDays=0`, stream de bricks; decisão→equity nunca replayada). (2) 58 achados: 4 altos (paridade real-tick sem teste, recovery 105 sem teste, SL default quebrado, paridade de decisão não verificada), 9 médios (comissão fora do PnL, recovery em rampa, CS fictício em M>1/ATR, watcher cego…), 45 baixos/cosméticos; 1 refutado. (3) Decisão: fechar o core via `ROADMAP-CORE-HARDENING.md` (E1–E5 bloqueiam estratégias; E8 bloqueia indicadores) antes de qualquer estratégia/indicador novo.
