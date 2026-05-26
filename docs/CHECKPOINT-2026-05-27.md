---
@document: docs/CHECKPOINT-2026-05-27.md
@project: MKS-ULTIMATE
@purpose: Checkpoint cobrindo dois dias contínuos (2026-05-26 + madrugada de 2026-05-27) — paridade canônica validada empiricamente, ADR-027 (StressLab credível), soft K-recovery, Checkpoint no BrickFileWriter, auto-detach no TradeManager, snapshot fresh no RiskManager. Estado final: Fase 9 plenamente desbloqueada.
@audience: Próxima sessão (humano + IA) — antes de abrir a Fase 9 (primeiro EA end-to-end), use este documento como guia do que mudou em 26+27/05.
---

# CHECKPOINT — 2026-05-26 + 2026-05-27 (dois dias contínuos)

Continuação direta da sessão de [`CHECKPOINT-2026-05-25-night.md`](CHECKPOINT-2026-05-25-night.md), que fechou com o pipeline ADR-024 100% em código mas a validação empírica canônica pendente por feriado US/UK.

**Marco do ciclo (em uma frase):** **Paridade canônica do projeto deixou de ser teorema e virou fato verificável** — `verify-parity.ps1` retornou exit 0 sobre uma sessão real em XAUUSDm/Exness, e todos os bloqueadores pré-requisito da Fase 9 documentados na auditoria 2026-05-25 foram resolvidos em código + cobertos por teste + documentados.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 14 arquivos, nesta ordem

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
14. `docs/CHECKPOINT-2026-05-27.md` — este (paridade validada + ADR-027 + auto-detach + snapshot fresh)

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação.

---

## 2. Estado do código

**Branch ativa:** `main`, sincronizada com `origin/main` no momento da escrita (HEAD `52779da`). Todas as branches de feature deste ciclo (`feat/producer-classic-only`, `feat/followups-post-parity`, `feat/stresslab-credibility`, `feat/phase9-prep`) foram mergeadas com `--no-ff` e deletadas local + remote.

### Histórico completo dos 12 commits do ciclo 26-27/05

```
52779da  Merge branch 'feat/phase9-prep' — pontas soltas pre-Fase 9              ← 27/05 00:02 — HEAD
671628f  feat(core): pontas soltas pre-Fase 9 — TradeManager auto-detach,
         RiskManager snapshot fresh, ROADMAP sync                                  ← 27/05 00:02
91c78c4  Merge branch 'feat/stresslab-credibility' — ADR-027 (StressLab credivel) ← 26/05 23:41
573b94b  feat(stresslab): ADR-027 — latencia aplicada, spread composto,
         SL/TP auto-disparados                                                     ← 26/05 23:40
2bfa092  Merge branch 'feat/followups-post-parity' — Checkpoint + soft K-recovery ← 26/05 23:15
3c7a643  feat(core): soft recovery de gap + Checkpoint no BrickFileWriter         ← 26/05 23:00
dc2165c  Merge branch 'feat/producer-classic-only' — pipeline 1-EA + paridade
         canonica validada                                                         ← 26/05 22:48
8277865  feat(parity): InpParityRunMode + CMksAuditLogSink — pipeline 1-EA p/
         paridade canonica                                                         ← 26/05 22:23
83f8844  refactor(producer): OnTick usa CopyTicks(COPY_TICKS_ALL) — alinha feed
         com TickRecorder                                                          ← 26/05 21:13
538c263  docs(adr): ADR-011 nota — premissa do K e cenario lastClose stale       ← 26/05 17:53
5fc37f4  docs: CHECKPOINT 2026-05-25 night (validacao empirica + auditoria
         forense + refactor sizer)                                                 ← 26/05 00:01
```

**Totais do ciclo 26-27/05:** 12 commits (11 funcionais + 1 doc do checkpoint anterior), ~1640 linhas adicionadas, 0 regressões em **37/37 .mq5** validados via `compile-all.ps1` no fim de cada ciclo.

### ADRs aceitas

**25/25 ADRs aceitas** (era 24 no início; este ciclo adicionou ADR-027). §4 Decisões Pendentes do `ARCHITECTURE.md` continua vazia. Notas de esclarecimento acumuladas em ADR-011 (premissa do K incompleta — gap estrutural vs spike isolado).

### Arquivos modificados/criados neste ciclo (resumo)

**Core/Types:**
- `Error.mqh` — novo código `MKS_ERR_RENKO_RECOVERED_FROM_GAP = 105`

**Core/RenkoBuilder:**
- `CMksRenkoBuilder.mqh` — soft recovery de gap estrutural (kRecoverAfter=5 default; helper HandleKExceeded consolida duas paths)

**Core/Data:**
- `CMksBrickFileWriter.mqh` — métodos novos `Checkpoint(err)` + `Flush()` (simétricos ao TickFileWriter)

**Core/Output:**
- `CMksAuditLogSink.mqh` — NOVO arquivo (sink TSV humano-legível complementar ao .mksbk binário)

**Core/Interfaces:**
- `IPositionBook.mqh` — método novo `IsOpen(positionId) → bool`

**Core/Position:**
- `CMksMt5PositionBook.mqh` — implementação de `IsOpen` via `PositionGetTicket` + escopo

**Core/Testing/Mocks:**
- `CMksFakePositionBook.mqh` — `MarkClosed(id)` + array de fechados

**Core/Trade:**
- `CMksTradeManager.mqh` — 5º arg opcional `IPositionBook*` no construtor; `Update` consulta book.IsOpen e auto-detacha; struct `MksTradeManagerStep` ganha flag `autoDetached`

**Core/Risk:**
- `CMksRiskManager.mqh` — `CheckOrder` chama `m_snapshot.Update()` no início

**Core/Broker:**
- `CMksSimulatedBroker.mqh` — auto-trigger SL/TP em OnTick via `CheckSlTpTriggers`; struct nova `MksSimAutoCloseEvent`; fila + métodos `PollAutoCloses`, `PendingAutoCloses`, `AutoCloseTotal`

**StressLab:**
- `CMksStressParams.mqh` — novos campos `baselineSpreadPoints` e `latencyDriftPointsPerMs`
- `CMksStressLabBroker.mqh` — slip total = sampled + extraHalfSpread + slipFromLatency; helper `SampleLatencyMs()`; métricas `latencyTotalMs`/`latencyMaxMs`

**Experts:**
- `Producer.mq5` — OnTick refactor SymbolInfoTick→CopyTicks(COPY_TICKS_ALL); `InpParityRunMode` + `g_tickWriter` paralelo + audit sink; Checkpoint periódico do .mksbk a cada 60s; tratamento do código 105 (recovery); session summary ganha err105Recovered + parityMode + parityMksTickPath + parityTickCount + parityAuditPath
- `Replayer.mq5` — `InpAlsoWriteAudit` + multiSink quando ligado; tratamento do código 105; rename `InpBrickSizePts` → `InpBrickSize` (consistência com Producer)

**Testes:**
- `Test_CMksTradeManager.mq5` — 3 testes novos (auto-detach scenarios)
- `Test_CMksRiskManager.mq5` — 2 testes novos (snapshot fresh)
- `Test_CMksSimulatedBroker.mq5` — 5 testes novos (auto-trigger SL/TP)
- `Test_CMksStressLabBroker.mq5` — 4 testes novos (latency + spread compose), 1 teste removido (materializava fórmula bug)

**Docs:**
- `ARCHITECTURE.md` — nota ADR-011 + ADR-027 nova
- `ROADMAP.md` — Fase 4.5 status "validação concluída"; limitações resolvidas das Fases 5/6/7 marcadas com strikethrough + nota
- `CHANGELOG.md` — 3 blocos novos (paridade canônica + ADR-027 + pontas soltas)

**Tools:**
- (nenhum novo neste ciclo — todos os necessários já existiam: `verify-parity.ps1`, `compile-all.ps1`)

---

## 3. Ciclo cronológico — 26/05 manhã → 27/05 madrugada

A ordem cronológica é importante porque cada bloco resolveu o que o anterior abriu. **6 sub-ciclos** identificáveis:

### Sub-ciclo A — 26/05 manhã (commit `538c263`, 17:53)

**Tema:** ADR-011 nota — premissa do K limit reconhecida como incompleta.

A descoberta foi feita no fim da sessão anterior (25/05 noite): rodando Producer com `InpBrickSize=1.0` em mercado calmo, o builder travou permanentemente após o primeiro M>K. Investigação confirmou:

- §regra 4 da ADR-011 estabelece K como "guarda contra corrupção de tick" — quando `M > K`, builder rejeita e mantém `m_lastClose` intacto, esperando o "próximo tick legítimo" voltar para perto.
- **Cenário não previsto:** gap estrutural (fill histórico com S pequeno + tempo offline). O primeiro tick live está LEGITIMAMENTE distante do `m_lastClose` antigo. Builder rejeita por M>K, m_lastClose fica stale, próximo tick legítimo também rejeitado pelo mesmo motivo → travamento permanente.
- A premissa de "M>K ≡ corrupção isolada" estava incompleta — gap estrutural produz N rejeições consecutivas com mids agrupados (não 1 outlier isolado).

**Conteúdo do commit:** nota de esclarecimento em [`ARCHITECTURE.md §3`](ARCHITECTURE.md) (após ADR-011 mas sem alterá-la) documentando os dois casos distintos, mitigação operacional verificada (`InpHistoricalFillDays=0` ou `K ≥ 100/S` heurística), e abrindo a porta para "soft recovery inteligente" como follow-up arquitetural (deixou parâmetros concretos para próxima ADR).

### Sub-ciclo B — 26/05 noite, refactor de OnTick (commit `83f8844`, 21:13)

**Tema:** Producer.OnTick refactor — `SymbolInfoTick` → `CopyTicks(COPY_TICKS_ALL)`, alinhamento de feed com TickRecorder.

**Descoberta empírica:** sessão de 12h em demo com Producer + TickRecorder em paralelo registrou:
- Producer (via OnTick → SymbolInfoTick) viu **16.615 ticks → 248 bricks**.
- TickRecorder (via OnTimer → CopyTicks) viu **34.083 ticks**.
- Replayer sobre o .mkstick do TickRecorder produziu **364 bricks**.
- Trigger prices dos primeiros bricks eram **idênticos byte-a-byte** (builder é determinístico ✓), mas open/close/low divergiam por offset constante ~0.037 USD por causa do anchor inicial diferente.

**Causa:** `SymbolInfoTick` retorna o tick "mais recente" no momento do callback — em bursts, ticks intermediários são perdidos. `CopyTicks(COPY_TICKS_ALL)` retorna a janela completa entre dois instantes.

**Conteúdo do commit:** Producer.OnTick reescrito para usar `CopyTicks(COPY_TICKS_ALL, lastSeenMsc, 0)` com loop de iteração, dedup por timeMsc, filtro `bid<=0 && ask<=0`. Nova global `g_lastSeenMsc`. Anchor inicial via SymbolInfoTick em `FinishInitAndGoLive`. Log "ready" passa a incluir `anchorMsc`. 113 linhas modificadas.

### Sub-ciclo C — 26/05 noite, pipeline 1-EA + validação empírica (commits `8277865` + `dc2165c`, 22:23 + 22:48)

**Tema:** Resolução estrutural do problema de anchor mismatch — fundir TickRecorder dentro do Producer, no MESMO loop.

**Diagnóstico:** mesmo com OnTick→CopyTicks (sub-ciclo B), Producer e TickRecorder rodando em programas separados começam em instantes ligeiramente diferentes. Se TickRecorder iniciou 5s antes do Producer, o anchor de `m_lastClose` do builder do Producer é diferente do anchor implícito no `.mkstick`. Resultado pós-refactor B: 115 vs 116 bricks + 3958 bytes divergentes em fc/b.

**Solução:** novo input `InpParityRunMode` no Producer. Quando `true`:
- Producer escreve `.mkstick` paralelo (`g_tickWriter`) **no mesmo loop do OnTick que alimenta o builder** — anchor sincronizado por construção.
- Producer também escreve audit TSV via `CMksAuditLogSink` (novo arquivo) — diff humano-legível complementar ao `fc /b` binário.
- Replayer ganha `InpAlsoWriteAudit` simétrico — mesmas linhas, mesma precisão (%.6f).

**Conteúdo dos commits:**
- `8277865` — implementação completa do `InpParityRunMode` + `CMksAuditLogSink`. 333 linhas adicionadas.
- `dc2165c` — merge `feat/producer-classic-only` em main com 10 commits acumulados (incluindo todo o trabalho do dia anterior sobre sizer factory, classic-only, etc.).

**Validação empírica T132858 (executada às 22:38 e validada às 22:48):**

Sessão de paridade em XAUUSDm/Exness, `InpBrickSize=3.0`, classic geometry, ~6 minutos de mercado ativo:

| Métrica | Valor |
|---|---|
| Ticks gravados no `.mkstick` | 3377 (216.384 bytes) |
| Bricks gravados no `.mksbk` | 38 (2.992 bytes) |
| Audit TSV do Producer | 3.799 bytes |
| `verify-parity.ps1` exit code | **0** (`.mksbk` byte-a-byte idênticos, wall-clock 184-191 ignorado) |
| `diff` dos audit TSV (Producer vs Replayer) | **0 diferenças** |

**Significado:** a paridade canônica ADR-024 §regra 7c (`live.mksbk == replay.mksbk` byte-a-byte) deixa de ser teorema e vira fato verificável a cada commit que toca o caminho de paridade.

### Sub-ciclo D — 26/05 noite tardia, followups técnicos (commits `3c7a643` + `2bfa092`, 23:00 + 23:15)

**Tema:** Três pontas técnicas que apareceram durante a validação empírica.

**D.1 — `Checkpoint()` no `CMksBrickFileWriter`:** durante a sessão T132858, observei que o `.mksbk` ficou com `brickCount=0` no header até o Producer fechar — crash do terminal antes do close deixaria o arquivo aparentemente vazio. `CMksTickFileWriter` já tinha `Checkpoint()`/`Flush()` simétricos; faltava no Brick. Adicionado, com chamada no `Producer.OnTimer` a cada 60s no live mode. Brick writer agora patcheia header (brickCount + timeMscFirst + timeMscLast) periodicamente sem fechar handle.

**D.2 — `InpBrickSizePts` → `InpBrickSize` no Replayer:** Producer foi renomeado em 25/05; Replayer ficou com naming velho. Consistência.

**D.3 — Soft recovery de gap estrutural no builder:** materialização da nota ADR-011 do sub-ciclo A. Novo parâmetro do construtor `kRecoverAfter=5` (default; 0 desabilita). Algoritmo:
- Após N rejeições K consecutivas (M>K), se `|mid - kFirstMid| ≤ size` (mids agrupados), o builder reconhece gap legítimo.
- Reanchora: `m_lastClose = mid`, reset forming extremes, `m_hasFirstBrick = false`.
- Retorna `false` com novo código `MKS_ERR_RENKO_RECOVERED_FROM_GAP = 105` (faixa RenkoBuilder).
- Reset do contador em qualquer tick aceito — exige sequência consecutiva.
- Helper `HandleKExceeded` consolida as duas paths (primeiro brick + subsequentes) que duplicavam o erro 102.

Producer e Replayer logam 105 distinto de 102 (contadores `g_k105Recovered` / `g_ticksK105`, session/replay summary ganham campos `err105Recovered` / `ticksK105Recovered`).

Doc ADR-011 nota atualizada de "follow-up pendente" para "soft recovery implementado" com parâmetros concretos.

### Sub-ciclo E — 26/05 noite muito tardia, ADR-027 (commits `573b94b` + `91c78c4`, 23:40 + 23:41)

**Tema:** StressLab credível — resolução dos 3 bloqueadores explícitos da Fase 7 ("pré-requisito da Fase 9" segundo o ROADMAP).

Recriações sutis do **eixo 3 do V5-POSTMORTEM** (custo modelado mas sem efeito no equity do backtest):

**E.1 — Latência aplicada (§7.1):** `latencyMeanMs`/`latencyStdevMs` no `CMksStressParams` eram declarados mas **o RNG sequer era tocado** — nem o "informativo" funcionava. Solução:
- Novo parâmetro `latencyDriftPointsPerMs` em `CMksStressParams` (default 0).
- `CMksStressLabBroker.SampleLatencyMs()` sorteia via Gaussiana, clampa em zero.
- Slip adicional: `slipFromLatency = sampledLatencyMs × driftPerMs` adverso ao lado da ordem.
- Métricas novas: `latencyTotalMs`, `latencyMaxMs`.
- `drift=0` preserva semântica "informativa" antiga para backward-compat.
- Heurística sugerida XAU/Exness: 0.01 pts/ms (100ms → 1 ponto adverso).

**E.2 — `spreadMultiplier` compõe sobre baseline (§7.2):** fórmula original somava `(mult-1)` pontos planos, ignorando completamente o `spreadPoints` do CostModel subjacente. `mult=10` adicionava **9 pontos** em vez de "spread 10× maior". Solução:
- Novo parâmetro `baselineSpreadPoints` em `CMksStressParams` (default 0).
- Fórmula nova: `extraHalfSpread = (mult-1) × (baseline/2)` por lado.
- Caller informa `baselineSpreadPoints` ao construir o preset com o spread do CostModel — presets ficam zerados (acoplar valor ao preset acoplaria preset a símbolo, anti-padrão).
- `baseline=0` faz `spreadMultiplier` virar no-op (backward-compat).

**E.3 — Auto-trigger SL/TP no `CMksSimulatedBroker` (§7.3):** posições com SL/TP só fechavam por Close() explícito do EA — broker simulado nunca capturava o evento mais frequente em live (stop hit). Solução:
- Nova struct `MksSimAutoCloseEvent` (positionId, side, lots, openPrice, closePrice, commissionClose, openTimeMsc, closeTimeMsc, dealCloseId, hitSl).
- Fila interna `m_autoCloseEvents[]` + contador monotônico `m_autoCloseTotal`.
- `OnTick` chama `CheckSlTpTriggers()` após atualizar mid.
- `CheckSlTpTriggers`:
  - Para cada posição aberta, computa `bidProxy = mid - halfSpread`, `askProxy = mid + halfSpread` (half-spread do CostModel).
  - BUY: hitSl se `bidProxy <= sl`, hitTp se `bidProxy >= tp`.
  - SELL: hitSl se `askProxy >= sl`, hitTp se `askProxy <= tp`.
  - Fecha via `CostModel.FillPriceFor(opposite, mid, point)` — close price inclui slippage (modela SL hit realista: close pode ser pior que o nível).
  - SL tem precedência sobre TP no mesmo tick (worst-case).
- Métodos novos: `PollAutoCloses(out[])`, `PendingAutoCloses()`, `AutoCloseTotal()`.

**ADR-027** registra as 3 mudanças em uma ADR única (5 alternativas rejeitadas + 6 fronteiras explícitas). ROADMAP Fase 7 status: "Concluída com limitações" → "Concluída".

**Testes (E):** 4 novos no `Test_CMksStressLabBroker` (composição baseline, no-op sem baseline, latency drift fixed, latency zero-drift legacy preserved), 5 novos no `Test_CMksSimulatedBroker` (SL BUY, TP SELL, stays open, half-spread proxy, determinismo).

### Sub-ciclo F — 27/05 madrugada, pontas soltas finais (commits `671628f` + `52779da`, 00:02)

**Tema:** Três pontas identificadas como bloqueantes para Fase 9 após uma auditoria final do ROADMAP §"Limitações conhecidas".

**F.1 — TradeManager auto-detach via IPositionBook:** a correção §7.3 da ADR-027 (auto-trigger SL/TP) **criou** um gap novo — `CMksTradeManager` continuava com `m_attached=true` apontando para posição que o broker já fechou. Próximo `Update()` chamaria `Modify`/`Close` sobre positionId fantasma. Solução:
- `IPositionBook` ganha método `IsOpen(positionId)`.
- `CMksMt5PositionBook` implementa via `PositionGetTicket` iterando `PositionsTotal` com filtro escopo (símbolo+magic).
- `CMksFakePositionBook` ganha `MarkClosed(id)` para testes.
- `CMksTradeManager` ganha 5º arg opcional `IPositionBook*` no construtor (default NULL = legacy).
- `Update()` consulta `book.IsOpen(positionId)` no início; se false, zera `m_attached`, marca `step.autoDetached=true` e retorna sem broker.
- Struct `MksTradeManagerStep` ganha flag `autoDetached`.

**F.2 — RiskManager.CheckOrder atualiza snapshot proativamente:** documentado como "fix barato (1 linha)" desde a auditoria 2026-05-25. Sem essa chamada, `DayPnLPct`/`DrawdownPct`/`Equity` ficavam congelados desde o último `Init()` se o EA esquecesse de chamar `snapshot.Update()` por tick — proteção da conta cega. Solução:
- `CheckOrder` chama `if(m_snapshot != NULL) m_snapshot.Update()` no início.
- Idempotente (rollover de dia + peak monotônico já tratados internamente).
- Backward-compat preservado: snapshot=NULL → no-op.

**F.3 — ROADMAP §4.5 sync com a validação empírica de 2026-05-26:** doc estava "validação empírica end-to-end pendente". Atualizado para "concluída (2026-05-26): verify-parity.ps1 exit 0 + diff dos audit TSV 0 diferenças". Limitações resolvidas das Fases 5 e 6 marcadas com strikethrough + nota da resolução.

**Testes (F):** 3 novos no `Test_CMksTradeManager` (auto-detach scenarios, no-book legacy), 2 novos no `Test_CMksRiskManager` (snapshot fresh, no-snapshot no-op).

---

## 4. Estado das fases do ROADMAP

| Fase | Status pré-ciclo | Status pós-ciclo |
|---|---|---|
| 0 — Fundação documental | Concluída | Concluída |
| 1 — Abstrações do core | Concluída | Concluída |
| 2 — RenkoBuilder | Concluída | Concluída (+ soft recovery de gap) |
| 3 — Testes unitários | Concluída | Concluída (+ 14 testes novos no ciclo) |
| 4 — Broker abstractions | Concluída | Concluída (+ auto-trigger SL/TP no SimulatedBroker) |
| 4.5 — Tick Recorder + Replayer | Código pronto, validação empírica pendente | **Concluída — validação empírica 2026-05-26 exit 0** |
| 5 — Trade Management | Concluída c/ limitações | Concluída (limitação auto-detach resolvida) |
| 6 — Risk Management | Concluída c/ limitações | Concluída (limitação snapshot fresh resolvida) |
| 7 — StressLab | Concluída c/ 3 limitações pré-requisito Fase 9 | **Concluída — todas as 3 limitações resolvidas por ADR-027** |
| 8 — Logging e observabilidade | Concluída | Concluída |
| 9 — Primeiro EA end-to-end | Não iniciada (bloqueada) | **Não iniciada — DESBLOQUEADA** |
| 10 — Estratégias reais | Não iniciada | Não iniciada |

**Limitações conhecidas restantes (não bloqueiam Fase 9):**
- Fase 5 — `CMksTradeManager` + conta netting (aceitável enquanto hedging; ADR necessária se mudar)
- Fase 4.5 — fill histórico do Producer lê de `CopyTicksRange`, fonte diferente dos ticks live (mitigado por `InpHistoricalFillDays=0`, recomendado para sessões de paridade)
- Fase 8 — logger sem precisão de millis (nice-to-have, MQL5 não expõe `TimeCurrent` com ms)
- Fase 5 — ATR-adjusted/Kelly sizers não materializados (eixo dinâmico já coberto por `CMksAtrBrickSizer`; Kelly precisa de histórico de retornos da Fase 10+)

---

## 5. Cobertura de teste e validação empírica

### Compile-all (sanity de cada ciclo)

37/37 arquivos `.mq5` compilam **0 erros, 0 warnings** ao final de cada sub-ciclo. Verificado em:
- 26/05 ~21:10 (pós-refactor OnTick)
- 26/05 ~22:20 (pós-InpParityRunMode + audit sink)
- 26/05 ~22:55 (pós-followups técnicos: Checkpoint + soft recovery + Replayer rename)
- 26/05 ~23:35 (pós-ADR-027: latency + spread + auto-trigger)
- 27/05 ~00:01 (pós-pontas soltas: auto-detach + snapshot fresh)

### Testes adicionados no ciclo (14 novos)

| Suite | Testes novos | O que provam |
|---|---|---|
| `Test_CMksStressLabBroker.mq5` | 4 (+1 removido) | spread compose correto, no-op sem baseline, latency drift fixed, latency zero-drift legacy |
| `Test_CMksSimulatedBroker.mq5` | 5 | SL BUY, TP SELL, stays-open sem hit, half-spread proxy, determinismo |
| `Test_CMksTradeManager.mq5` | 3 | auto-detach com book, no-op subsequente, legacy sem book |
| `Test_CMksRiskManager.mq5` | 2 | snapshot fresh em CheckOrder, no-op sem snapshot |

### Validação empírica (sessão T132858, 26/05 22:38)

Detalhada no sub-ciclo C. Resumo numérico:

```
Arquivo                                      Tamanho        Conteúdo
XAUUSDm_20260526T132858_parity.mkstick      216.384 bytes  3377 ticks
XAUUSDm_20260526T132858.mksbk                 2.992 bytes    38 bricks
Producer_audit_XAUUSDm_20260526T132858.tsv    3.799 bytes    38 linhas + header
replay_XAUUSDm_20260526T132858_parity...mksbk 2.992 bytes    38 bricks
Replayer_audit_XAUUSDm_20260526T134115.tsv    3.799 bytes    38 linhas + header

verify-parity.ps1: EXIT 0 (byte-a-byte idênticos, ignorando wall-clock 184-191)
diff -u dos audit TSV: EXIT 0 (linha-a-linha idênticos)
```

### Validação empírica AINDA NÃO executada

- **Soft K-recovery (código 105)** — não foi exercitado num cenário real de gap (mercado calmo durante T132858 não disparou). Cenário natural: abertura de segunda após gap de fim-de-semana com `InpHistoricalFillDays>0` e `InpBrickSize=1.0`. Não bloqueia Fase 9.
- **Auto-trigger SL/TP do SimulatedBroker** — coberto por 5 testes unitários determinísticos com `MksFakeSymbol` + `CMksCostModel`, mas nunca rodado em pipeline real onde uma EA abre posição e o broker auto-fecha. Acontecerá naturalmente na Fase 9.

---

## 6. Pendências em aberto

### Pendências bloqueantes — ZERO

Todas as limitações documentadas como "pré-requisito Fase 9" estão resolvidas em código + cobertas por teste + documentadas (ADR-027 + commit `671628f`).

### Pendências não-bloqueantes (adiáveis)

1. **`CMksTradeManager` + conta netting.** Demo Exness é hedging. Vira problema se mudarmos para conta netting — então abre ADR explícita.
2. **Producer.mq5 fill histórico via `CopyTicksRange`.** Fonte diferente dos ticks live (paridade canônica vale só para o trecho live capturado). Mitigado por `InpHistoricalFillDays=0` (recomendado para paridade); documentado como dívida da auditoria. ADR-027-like quando estratégia entrar.
3. **Logger sem precisão de millis.** Solução barata: overload `Log()` aceitando `tickMsc`. Sem urgência — backtest determinístico não precisa de ms para reproduzir.
4. **ATR-adjusted / Kelly sizers.** Não materializados; ADR-018 (ATR sizer do brick) cobre eixo dinâmico. Kelly exige histórico de retornos realizados — espera Fase 10+.

### Validações empíricas adicionais oportunísticas (não bloqueiam Fase 9)

5. **Soft K-recovery em gap real.** Abertura de segunda com `InpHistoricalFillDays>0` e `InpBrickSize` pequeno deve disparar 105. Se não disparar, investigar — pode haver bug latente no algoritmo de variância.
6. **Checkpoint do .mksbk em crash real.** Forçar crash do terminal durante live (Task Manager kill MetaTrader) e verificar que `.mksbk` parcial é decodificável pelo `CMksBrickFileReader` até o último checkpoint.

---

## 7. Próximos passos sugeridos

**Próximo marco:** Fase 9 — primeiro EA end-to-end.

Conforme ROADMAP §Fase 9:
- EA minimalista usando todo o core construído
- Estratégia deliberadamente simples (reversão de cor pura, sem filtros) — não é para ser lucrativa, é para exercitar todas as peças
- Rodar em backtest, rodar em StressLab (3 níveis — agora estresseando de fato após ADR-027), rodar em demo live
- Comparar logs e validar paridade

**Decisões a tomar antes de codar a Fase 9:**

1. **Magic number do EA.** Estratégia precisa de magic próprio para `CMksMt5PositionBook` filtrar corretamente. Sugestão: número de 4 dígitos derivado da data do início (ex.: `527001`).
2. **Conta de teste.** Continuar em Exness demo (account 277678478) ou usar conta MetaQuotes-Demo para reduzir fricção? Eu sugiro manter Exness por consistência com sessões anteriores.
3. **Símbolo.** XAUUSDm é o default natural — todo o pipeline foi exercitado nele. EUR/USD entra na Fase 10.
4. **Composition root.** Onde montar o EA — pasta `MQL5/Experts/MKS-ULTIMATE/` (mesma do Producer/Replayer) com nome tipo `ColorReversal.mq5` ou `Phase9EA.mq5`? Sugestão: `ColorReversal.mq5` (nome descritivo da estratégia, não da fase — fase passa, estratégia fica).
5. **Composição da estratégia minimalista:**
   - Fonte de bricks: lê o `.mksbk` corrente do CS via `CopyRates(csName)` OU mais simples, sink direto do builder (estratégia recebe `OnBrickClose` via `IRenkoSink`)
   - Lógica: brick BULL → `Send(BUY)`, brick BEAR → `Send(SELL)`, SL/TP fixos via `CMksFixedLotSizer`
   - Trade Manager: trailing simples + auto-detach (resolvido neste ciclo)
   - Risk Manager: trade + strategy + account (3 camadas, todas testadas)
   - StressLab: rodar com `MksStressLight` / `MksStressMedium` / `MksStressHigh` em ciclos separados para comparação
   - Log-diff: usar `tools/verify-parity.ps1` para `.mksbk` paridade + filtro novo para "decisão" de estratégia (buy/sell/close)

**Não fazer antes da Fase 9:**
- Não otimizar parâmetros — reversão de cor pura não é estratégia para otimizar
- Não acrescentar filtros — quanto mais simples a estratégia, mais clara a auditoria de paridade
- Não fazer multi-símbolo — fica para depois

---

## 8. Comandos úteis para o próximo chat

```bash
# Status sempre primeiro
/status

# Logs git deste ciclo
git log --oneline --graph 5fc37f4^..HEAD

# Sanity de compile (37 .mq5)
powershell -ExecutionPolicy Bypass -File tools\compile-all.ps1

# Validação canônica de paridade (rodar quando houver nova sessão)
powershell -ExecutionPolicy Bypass -File tools\verify-parity.ps1 `
  -LiveMksbk "<path-do-live.mksbk>" `
  -ReplayMksbk "<path-do-replay.mksbk>"

# Diff humano-legível dos audit TSV
diff "Producer_audit_<...>.tsv" "Replayer_audit_<...>.tsv"

# Watcher de compile (auto-rebuild on file change)
powershell -ExecutionPolicy Bypass -File tools\watch-compile.ps1
```

### Pasta de artefatos da sessão T132858 (validação canônica de 26/05)

```
C:\Users\mikem\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06\MQL5\Files\MKS-ULTIMATE\
├── Bricks\
│   ├── XAUUSDm_20260526T132858.mksbk                                     (live, 2992B)
│   └── replay_XAUUSDm_20260526T132858_parity_20260526T134115.mksbk       (replay, 2992B)
├── Ticks\
│   └── XAUUSDm_20260526T132858_parity.mkstick                            (216384B)
└── Logs\
    ├── XAUUSDm_20260526T132858.log                                       (Producer)
    ├── Replayer_XAUUSDm_20260526T134115.log                              (Replayer)
    ├── Producer_audit_XAUUSDm_20260526T132858.tsv                        (3799B)
    └── Replayer_audit_XAUUSDm_20260526T134115.tsv                        (3799B)
```

---

## 9. Resumo em 5 linhas para abrir o próximo chat

1. **Paridade canônica do projeto virou fato verificável (T132858 exit 0)** — `verify-parity.ps1` + diff de audit TSV provam `live.mksbk == replay.mksbk` byte-a-byte para sessão real em XAUUSDm/Exness.
2. **ADR-027 aceita:** StressLab credível — latência aplicada ao fill via `latencyDriftPointsPerMs`, `spreadMultiplier` compõe sobre `baselineSpreadPoints`, SL/TP auto-disparados no `CMksSimulatedBroker.OnTick`. Resolve eixo 3 do V5-POSTMORTEM no broker simulado.
3. **3 pontas finais resolvidas:** TradeManager auto-detach via `IPositionBook.IsOpen` (fecha gap aberto pela própria ADR-027 §7.3); `RiskManager.CheckOrder` atualiza snapshot proativamente; ROADMAP §4.5 sync.
4. **Estado atual:** branch `main` em `52779da`; 25/25 ADRs aceitas; **8/10 fases concluídas, Fase 9 plenamente desbloqueada** — todas as limitações pré-requisito foram resolvidas em código + teste + doc. 14 testes novos no ciclo, 37/37 .mq5 compilam 0/0.
5. **Próximo:** **Fase 9 — primeiro EA end-to-end** com estratégia minimalista (reversão de cor pura). Decisões pendentes antes de codar: magic number, símbolo (sugestão: continuar XAU/Exness), nome do arquivo (sugestão: `ColorReversal.mq5`), composition root.

---

**Ciclo 26-27/05 fechado.** Paridade canônica empírica + StressLab credível + auto-detach + snapshot fresh. Fase 9 é o próximo marco — não há mais limitação bloqueante. Este checkpoint é o guia.
