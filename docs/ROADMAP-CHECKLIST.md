---
@document: docs/ROADMAP-CHECKLIST.md
@project: MKS-ULTIMATE
@purpose: Checklist sincero e mensurável do projeto — inventário do que JÁ foi construído (assinalado) e do que FALTA construir (em aberto), com critério de "pronto" verificável em cada item. Snapshot vivo; atualizar a cada fatia entregue.
@audience: Dono do projeto, assistentes de IA, contribuidores.
---

# MKS-ULTIMATE — Checklist de Roadmap (sincero e mensurável)

**Como ler.** Cada item tem um critério **mensurável** de "pronto" (teste que passa, ADR aceita, prova empírica, ou entregável verificável). Nada de "feito" por sensação.

- `[x]` **pronto** — critério cumprido e verificado.
- `[~]` **parcial** — existe e funciona, mas o critério de "pronto" ainda tem ponta aberta.
- `[ ]` **em aberto** — não construído.

**Régua honesta (vale para o documento inteiro):** paridade provada é **determinismo** (teste↔replay), NÃO fidelidade ao tick do broker ao vivo (estruturalmente impossível — nomeado, não escondido). E **robustez ≠ lucratividade**: a fundação está pronta; edge comprovado é o maior espaço em branco.

---

## Placar (2026-07-21)

| Bloco | Estado |
|---|---|
| **Núcleo / gate de estratégias (E1–E5)** | ✅ **fechado** (todos MT5-verificados) |
| Produto operável (E6) | 🟢 quase (E6.1/E6.3 MT5-verificado; falta só validar preset EURUSD com dado) |
| Fundação de indicadores / CS (E7–E8) | ⬜ aberto (E7 pende de dado) |
| Estratégia lucrativa (Fase 10) | ⬜ aberto (sem hipótese de edge) |
| Painel de monitoramento (E9) | ⬜ aberto (adiado por decisão do dono) |
| StressLab calibrado ao broker real | ⬜ aberto |

---

## PARTE 1 — O que JÁ foi construído

### 1. Fundação documental (Fase 0)
- [x] `Projeto.md`, `REGRAS.md`, `ROADMAP.md`, `ARCHITECTURE.md`, `PROTOCOLOS.md`, `CHEATSHEET.md`, `V5-POSTMORTEM.md`, `TOM-E-CHATS.md`, `CHANGELOG.md`, `CLAUDE.md` — *medida: todos existem e estão commitados; ordem de leitura definida no CLAUDE.md.*

### 2. Abstrações do core — interfaces e tipos (Fase 1)
- [x] Interfaces: `IBroker`, `ITickSource`, `IClock`, `ILogger`, `IRenkoSink`, `ISymbol`, `IAccount`, `IPositionSizer`, `IPositionBook`, `IBrickSizer`, `ITradeVisualizer`, `ISensor` — *medida: compilam; polimorfismo via classe abstrata (ADR-004).*
- [x] Tipos POD: `MksTick`, `MksBrick`, `MksOrderRequest`, `MksExecutionResult`, `MksError`, `MksFormingBrick`, `MksRenkoGeometry`, `MksSensorState` — *medida: autocontidos, usados em todo o core.*

### 3. Motor Renko (Fase 2)
- [x] `CMksRenkoBuilder` — produtor ÚNICO de bricks a partir de ticks, determinístico — *medida: `Test_CMksRenkoBuilder` verde no MT5.*
- [x] Brick sizers: `CMksFixedBrickSizer` + `CMksAtrBrickSizer` (ADR-018) — *medida: `Test_CMksAtrBrickSizer` verde.*
- [x] Cruzamento multi-threshold (ADR-011) + tick inválido/L (ADR-006) + gap de reabertura (ADR-008) — *medida: cobertos em teste.*
- [x] Soft-recovery de gap estrutural (código 105) com âncora deslizante (ADR-033, corrige deadlock em rampa) — *medida: `Test_CMksRenkoBuilder` 497/497 assertions, 29 tests, 0 failed (MT5, E3).*

### 4. Framework de testes do core (Fase 3)
- [x] `Core/Testing/`: `Asserts.mqh` (macros `MKS_ASSERT_*` com `__FILE__:__LINE__`), `TestRunner.mqh` (registro automático + Alert em falha), mocks (`CMksFakeSymbol`, `CMksFakeAccount`, `CMksFakeClock`, `CMksFakePositionBook`, `CMksRecordingBroker`, `CMksRecordingVisualizer`, `CMksCapturingSink`) — *medida: ADR-005 validada; suítes rodam com um comando/arrasto de script.*

### 5. Abstrações de broker + custo (Fase 4)
- [x] `CMksMt5Broker` (live/tester real, retry+fallback de filling, retcodes 200–204) — *medida: validado em demo XAUUSDm/Exness.*
- [x] `CMksSimulatedBroker` (backtest determinístico, auto-close SL/TP ADR-027, injeção one-shot de fill parcial E5.2) — *medida: `Test_CMksSimulatedBroker` 83/83 (20 tests, MT5).*
- [x] `CMksCostModel` (spread, slippage, comissão, swap) — *medida: `Validate` + uso no sim.*
- [x] Hedging-only invariante v1 — recusa netting/exchange na borda (ADR-029) — *medida: fail-fast com popup, testado.*

### 6. Captura + replay — pipeline de paridade (Fase 4.5)
- [x] Formato `.mkstick` + `CMksTickFileWriter`/`Reader` + `CMksFileTickSource` + `CMksMultiFileTickSource` — *medida: `Test_CMksTickFile`/`FileTickSource`/`MultiFileTickSource` verdes.*
- [x] Clocks: `CMksMt5Clock`, `CMksReplayClock`, `CMksFeedClock` (E2.4) — *medida: usados em live/replay/runner.*
- [x] `TickRecorder.mq5` (Service) + `Replayer.mq5` (EA) + `tools/verify-parity.ps1` — *medida: paridade `.mksbk` byte-a-byte exit 0 (empírico).*

### 7. Gestão de trade (Fase 5)
- [x] Sizers: `CMksFixedLotSizer`, `CMksPercentRiskSizer` — *medida: `Test_CMksPositionSizer` verde.*
- [x] `CMksTradeManager` — break-even, trailing (ratchet), partial close idempotente, auto-detach via `IPositionBook`, **acúmulo de fill parcial** (E5.2/ADR-035) — *medida: `Test_CMksTradeManager` 74/74 (28 tests, MT5).*
- [x] `CMksTradeJournal` money-aware — comissão/swap chegam ao resultado em moeda (E4/ADR-034) — *medida: `Test_CMksTradeJournal` 49/49 (21 tests, MT5).*
- [x] **TradeManager provado num composition root REAL** (E5.1/ADR-035) — *medida: `Test_TradeManagerIntegration` 52/52 (7 tests, MT5): BE/trail/partial contra fills reais + auto-detach no SL + rejeições do gate + determinismo duplo-run.*

### 8. Risk management em camadas (Fase 6)
- [x] `CMksRiskManager` — 3 camadas (por trade / estratégia / conta), códigos 400–410 — *medida: `Test_CMksRiskManager` verde.*
- [x] `CMksRiskGatedBroker` — todo Send passa pelo risco (elimina "esqueci de chamar o risk") — *medida: `Test_CMksRiskGatedBroker` verde + gate-crossing provado no golden (breaker 409 dispara).*
- [x] `CMksAccountSnapshot` — baseline diário UTC + peak equity; `DayPnL` = equity flutuante (deliberado, ADR-036) — *medida: `Test_CMksAccountSnapshot` verde.*
- [x] Position books: `CMksMt5PositionBook`, `CMksSimPositionBook` — *medida: semântica `IsOpen` idêntica live↔sim.*
- [x] Breaker documentado como **preventivo** (bloqueia entrada; não fecha posição aberta) — E5.4/ADR-036.

### 9. StressLab (Fase 7)
- [x] `CMksRandom` (RNG seedável), `CMksStressParams` (5 presets None→Nightmare), `CMksStressLabBroker` (rejeição/requote/slippage/spread composto/latência — ADR-027/030), `CMksStressLabReport` — *medida: `Test_CMksRandom`/`StressLabBroker`/`StressLabReport` verdes; warning de spread inerte (E4.3).*
- [~] **Calibração ao broker real** — os presets são sintéticos, não ancorados no comportamento medido da Exness. *Critério de pronto: medir spread/slippage/latência reais e ancorar os presets.* → **PARTE 2**.

### 10. Logging e observabilidade (Fase 8)
- [x] `CMksLogger` (JSON-line, níveis, output dual, proveniência), `CMksAuditLogSink`, log-diff no `verify-parity` — *medida: logs bt/live comparáveis; ADR-007.*

### 11. Primeiro EA end-to-end (Fase 9)
- [x] `CMksColorReversalStrategy` (reversão de cor pura, IRenkoSink, auto-detach, adoção de órfã, flatten-on-halt, **sem exposição dupla no flip** E5.3/ADR-036) — *medida: `Test_CMksColorReversalStrategy` 22 tests, 0 failed (MT5).*
- [x] `ColorReversal.mq5` composition root completo (builder + sinks + risco 3-camadas + broker gateado + visualização) — *medida: validado em tester + demo live (11 ordens reais Exness).*
- [x] Visualização de trades (ADR-028: `ITradeVisualizer` + `CMksChartPainter`), timeline híbrida (ADR-023) — *medida: paridade viz on/off provada em teste.*
- [x] **Slice-2: runner de stress liga/desliga** (estratégia sobre `SimulatedBroker` + `StressLabBroker` por níveis, comparando com/sem) — *critério: um relatório comparativo None→Nightmare de uma corrida.* → **FEITO + MT5-verificado (ADR-038, 2026-07-21): smoke sobre o golden gerou a tabela comparativa. Core sobreviveu aos 5 níveis sem quebrar.** Ver Parte 2 §B.

### 12. Paridade de DECISÃO — o gate central (E2)
- [x] Runner DDR: `CMksDecisionRunner` + `CMksJournalingBroker` + `CMksDecisionJournal` + `CMksSimAccount` — *medida: `Test_CMksDecisionRunner` 36/36 (MT5).*
- [x] `DecisionReplayer.mq5` + diff de decision journal no `verify-parity` (`-JournalA/-JournalB`) — *medida: exit 0.*
- [x] **Determinismo da decisão PROVADO sobre feed REAL** — 33.546 ticks XAUUSDm → journal idêntico byte-a-byte em 2 replays (baseline 33 decisões + gate-crossing 18 com breaker 409) — *medida: `verify-parity` exit 0.*
- [x] **Golden bundle versionado** em `tests/golden/e2-decision/` (fixture + 2 journals golden + README) — *medida: existe no repo.*
- [~] Pontas pequenas: teste headless automatizado do golden (hoje procedimento manual); E2.3 (âncora de proveniência no `.mksbk`); verificação do E2.4 cruzando meia-noite UTC (pende de captura). *Não bloqueiam o gate.*

### 13. Hardening — gate E1–E5 (Fase 9.5)
- [x] **E1** higiene/destravamento (SL vs stops level, watcher, doc↔código, branches) — *medida: E0/E1 no CHANGELOG, MT5.*
- [x] **E2** paridade de decisão — *medida: item 12.*
- [x] **E3** robustez do motor (soft-recovery testado, deadlock corrigido) — *medida: 497/497 MT5 (ADR-033).*
- [x] **E4** eixo 3 completo (custo sentido no resultado) — *medida: 49/49 + 42/42 MT5 (ADR-034).*
- [x] **E5** gestão integrada (TradeManager fim-a-fim + partial-fill + exposição órfã + breaker documentado) — *medida: ADRs 035/036, MT5 verde.*
- ✅ **GATE E1–E5 CUMPRIDO → Fase 10 destravada.**

---

## PARTE 2 — O que FALTA construir

### A. Produto operável (E6) — *quase fechado*
- [x] **E6.1/E6.3 — superfície de inputs enxuta + presets** (ADR-037) — *medida: MT5-verificado 2026-07-21 — dialog nos 3 níveis sem K/L, preset XAU sobrepõe (S:3.00000, CS `MKSCR_3`), Custom preserva (S:99.00000), OnInit limpo. Item (d) tester order-cycle não re-exercitado (fora do diff).*
- [x] E6.2 — unidades explícitas (SL em bricks, ADR-032) — herdado, pronto.
- [x] E6.4 (runbook + header) — `CHEATSHEET §9.8`; Producer mantido separado (decisão do dono).
- [x] **E6.4 — sub-item:** `InpHistoricalFillDays` — *documentado por que diferem (2026-07-21): Producer=30 (visualização), ColorReversal=3 (warm-up), DecisionReplayer=0 (paridade) — por PAPEL, não acidente; rationale cruzado nos 3 sites.*
- [ ] **Preset EURUSD validado** — os valores (brick 0.0010 / SL 10 bricks) são chute inicial. *Critério: validar com dado real de EURUSD.*

### B. StressLab calibrado + liga/desliga — *prioridade Agora (pedido do dono)*
- [x] **Runner de estresse liga/desliga** — rodar a estratégia SEM o StressLab, depois COM, e comparar lado a lado. *Critério: um EA/script que produz um relatório comparativo (None→Nightmare) de uma corrida sobre `.mkstick`, com o net por nível.* → **FEITO + MT5-verificado (ADR-038, 2026-07-21): `CMksTradeJournalingBroker` + `CMksStressRunner` + `StressReplayer.mq5`; testes 27/27 + 17/17; smoke sobre o golden (33.546 ticks) produziu a tabela None→Nightmare (slippage degrada o net; rejeições reduzem trades). Compila 51/0/0.**
- [~] **Calibração ao broker real** — medir spread/slippage/latência reais da Exness (XAU) e ancorar os presets do `CMksStressParams`. *Critério: presets derivados de dado medido, documentados; "sobreviveu ao Nightmare" passa a ter significado.* → **PARCIAL (ADR-039, 2026-07-21): spread MEDIDO+LIGADO (240 pts / 0.24 USD, 417k ticks) e latência→drift MEDIDO+LIGADO (~0.25 pts/ms adverso, input tunável) no StressReplayer. Só o slippage puro PENDENTE (precisa dado requested-vs-filled de ordem real).**
- [ ] **Fácil de operar** — o liga/desliga como um input/botão, sem montar pipeline à mão. *Critério: operador roda a comparação com ≤ 2 passos.*

### C. Estratégia lucrativa (Fase 10) — *o maior espaço em branco; precisa do dono*
- [ ] **Hipótese de edge com premissa** — por que um padrão teria vantagem (não "reversão porque sim"). *Critério: uma tese escrita, avaliável no modo `##Estrategia##`.*
- [ ] **Backtest honesto da hipótese** — sem overfitting, com custo real. *Critério: resultado positivo que sobrevive a walk-forward/out-of-sample.*
- [ ] **Portão de StressLab** — a estratégia sobrevive ao estresse médio+. *Critério: net ainda positivo sob Medium/High.*
- [ ] **Demo longa antes de real** — Protocolo 5/6. *Critério: N dias de demo sem divergência estrutural.*
- [ ] **Track record** — histórico que justifique operar/vender. *Critério: curva de equity real auditável.*

### D. Fundação de indicadores + Custom Symbol (E7 → E8) — *travado em dado*
- [ ] **E7.1 — sobrevivência do CS à meia-noite** — *critério: gate empírico cruzando ≥1 meia-noite de servidor com 0 `CS UPDATE FAIL` (pende de captura).*
- [ ] **E7.2 — robustez do sink na falha** (só avançar `lastBarTime` no sucesso; logar 1ª falha). *Critério: fixes aplicados + comentários alinhados.*
- [ ] **E7.3 — ADR-031 escrita** com o dado empírico. *Critério: ADR aceita.*
- [ ] **E8.1 — política multi-threshold dos 6 indicadores** (magnitude-aware ou limitação declarada). *Critério: documentado em INDICATORS.md + implementado.*
- [ ] **E8.2 — auto-infer robusto de brick size** nos indicadores. *Critério: valida consistência antes de aceitar.*
- [ ] **E8.3 — testes de verdade independente** (recomputar a máquina de estados sem ler o buffer do indicador). *Critério: série inteira comparada.*
- [ ] **E8.4 — decisão CS vs `IRenkoIndicator`** (iCustom vs ler `MksBrick` direto). *Critério: caminho decidido + 5 existentes portados se migrar.*
- [~] **Cardápio de indicadores próprios** — 6 existem (Chandelier, Donchian, MACD, RSI, SuperTrend, ReversalRegime) mas dependem 100% do CS e não são magnitude-aware. *Critério de pronto: E8 fechado + catálogo com `diff_max` real versionado.*

### E. Painel de monitoramento (E9) — *adiado por decisão do dono*
- [ ] **`CMksStatusPanel` / dashboard ao vivo** — acompanhar o robô operando (posição, risco, P&L, saúde do feed). *Critério: painel funcional; a ser desenvolvido DEPOIS de haver EA/indicador substancial.*

### F. Escala e multi-mercado — *não iniciado*
- [ ] **Multi-instrumento validado** (além do XAU). *Critério: paridade + operação provadas em ≥1 outro ativo.*
- [ ] **Multi-corretora validada** (além da Exness). *Critério: idem em outra corretora hedging.*

### G. Decisões arquiteturais em aberto
- [~] **`flatten-on-breach` (breaker corretivo)** — fechar tudo + travar ao cruzar minEquity/drawdown em `OnTick` (hoje o breaker é só preventivo). *Critério: decidir construir ou não; se sim, componente + teste (ADR-036 §Fronteiras).* → **construído + integrado (ADR-040, 2026-07-22): `CMksCircuitBreaker` + `Test_CMksCircuitBreaker` + integração no `ColorReversal` (input `InpEnableCorrectiveBreaker`, default ON), predicado único com o gate preventivo, sticky. 52/0/0. FALTA só o MT5-verde.**
- [ ] **Termo spread-aware dinâmico do piso de SL** (diferido ao E2, fecha a cauda do M12). *Critério: fórmula por-tick + teste.*
- [ ] **Cadência do snapshot live** (per-Send) vs runner (per-tick) — alinhar. *Critério: decisão de design do dono.*

### H. Backlog (sem posição definida — do `ROADMAP.md`)
- [ ] Outras barras além de Renko (Range, Tick, Volume, Seconds)
- [ ] Canal externo de alertas (Telegram/email)
- [ ] Sistema de sinais (EA recebe sinais, não gera)
- [ ] Otimização de parâmetros distribuída (fora do MT5)

---

## Ordem recomendada (prioridade real, não vontade)

1. **B — StressLab liga/desliga + calibrado** (pedido do dono; pré-requisito de qualquer "vai pra live" honesto).
2. **A — fechar E6** (pontas pequenas; produto operável de verdade).
3. **C — caçar edge** (precisa da hipótese do dono; sem ela, não há Fase 10).
4. **E — painel** (quando houver EA/indicador substancial).
5. **D — E7/E8 indicadores** (destrava quando houver captura cruzando meia-noite).
6. **F — escala multi-mercado** (depois de um edge provado num mercado).

**Uma linha:** a fundação (Partes 1) está pronta e provada; o trabalho que resta (Parte 2) é **comprovação** (edge, calibração, track record) e **operabilidade** (liga/desliga, painel) — não mais alicerce.
