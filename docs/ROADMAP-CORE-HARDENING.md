---
@document: docs/ROADMAP-CORE-HARDENING.md
@project: MKS-ULTIMATE
@purpose: Plano de fechamento e endurecimento do core derivado da auditoria de 2026-06-02 (docs/CHECKPOINT-2026-06-02-auditoria.md). Define O QUE falta para o core ser "100% robusto" e em que ordem, antes de desenvolver estratégias (Fase 10) e novos indicadores. Cada item rastreia um ou mais achados da auditoria.
@audience: Dono do projeto, assistentes de IA, contribuidores.
---

# MKS-ULTIMATE — Roadmap de fechamento do core (hardening)

Este documento é o **gate entre a Fase 9 e a Fase 10** do `docs/ROADMAP.md`. Ele existe porque a auditoria de 2026-06-02 mostrou que "Fase concluída" significava, em vários pontos, "código escrito e validado pontualmente" — não "verificado de ponta a ponta". Fechar essas lacunas é o que transforma o core de *aparentemente robusto* em *demonstravelmente robusto*.

**Princípio que rege este roadmap:** a lição do V5 aplicada ao próprio V6 — *o perigo não é código quebrado, é código que parece validado e não está*. Cada fase abaixo converte uma garantia hoje **afirmada** numa garantia **demonstrada por teste/dado**.

**Regra de ouro (herdada do `ROADMAP.md`):** nenhuma fase começa antes da anterior cumprir todos os critérios de saída. **E1–E5 são gate bloqueante para a Fase 10 (estratégias reais). E8 é pré-requisito de novos indicadores.** E6 (UX) e E7 (CS) podem correr em paralelo, mas E6 é pré-requisito de operação real e E7 de qualquer expansão do catálogo de indicadores via CS.

**Mapa de dependências:**

```
E1 (higiene/destravamento)
 └─> E2 (paridade de decisão)  ─┐
 └─> E3 (robustez do motor)    ─┼─> [GATE CORE] ─> Fase 10 (estratégias)
 └─> E4 (eixo 3 completo)      ─┤
 └─> E5 (gestão integrada)     ─┘
E6 (UX/produto)   — paralelo, pré-requisito de operação real
E7 (CS gate empírico) ──> E8 (fundação de indicadores) ─> novos indicadores
```

Referência cruzada: os IDs entre colchetes (ex.: `[H1]`, `[M9]`, `[cs-recovery-advances-timeline]`) são os achados de `docs/CHECKPOINT-2026-06-02-auditoria.md`.

---

## Fase E1 — Higiene imediata e destravamento

**Status:** Concluída (E1.1–E1.4) — E1.1 corrigido e estendido pela Fase E0 (ver nota).
**Bloqueia:** operação real (E1.1) e a confiança nas demais fases.

**Nota (sync 2026-07-19):** E1.1–E1.4 commitados (`e853833`, `88507bd`, `d60b3c1`, merge de branches). **Desvios registrados:** o gate de SL do E1.1 foi posto no **RiskManager** (código 410, faixa 4xx — gate simétrico bt/live), não no broker (faixa 2xx) como a letra pedia — melhor para paridade. A auditoria de 2026-07-19 (`docs/CHECKPOINT-2026-07-19-auditoria.md`, achado M12) mostrou que esse gate era **no-op na Exness (StopsLevel=0)** e que o SimulatedBroker aceitava qualquer SL. A **Fase E0** (correções imediatas do mesmo checkpoint) reancorou o piso de SL em **bricks** (fail-closed, fonte única no RiskManager), tirou StopsLevel do número de runtime (só fail-fast de anexação) e adicionou backstop no sim. FreezeLevel segue fora do piso de placement (é do Modify/trailing, E5). Ver `CHANGELOG.md [Não lançado]` (E0.1–E0.5).

**Por que primeiro:** são itens de baixo risco e alto retorno — destravam a operação, corrigem ferramentas que dão falsa confiança, e limpam divergências doc↔código que confundiriam quem executar as fases seguintes.

**Entregáveis:**

- **E1.1 — SL respeita o stops level do broker** `[H3, pts-naming-misleading, k-l-defaults-coupled]`
  - `CMksMt5Broker.Send/Close` lê `SYMBOL_TRADE_STOPS_LEVEL` e `SYMBOL_TRADE_FREEZE_LEVEL` (via `ISymbol::StopsLevel()`, que já existe) e **recusa com erro semântico** (`MKS_ERR_BROKER_SL_BELOW_STOPS_LEVEL`, faixa 2xx) qualquer `slPrice` que viole — com log acionável dizendo o mínimo aceitável em pontos.
  - Default de `InpSlPoints` corrigido para valor são em XAU **ou** SL expresso em múltiplos de `InpBrickSize` (resolve também o naming enganoso "Pts").
  - `OnInit` valida `slPoints` contra o stops level e faz fail-fast com `Alert` (mesmo padrão da guarda hedging-only).
- **E1.2 — Watcher cobre os artefatos de produção** `[M9]`
  - `tools/watch-compile.ps1`: adicionar `Experts/MKS-ULTIMATE` e `Services/MKS-ULTIMATE` aos `entryRoots` e `watchRoots`; estender o regex para casar `#include "([^"]+)"` (quote-style) resolvendo relativo ao diretório do arquivo.
- **E1.3 — Reconciliação doc↔código** `[M5, changelog-adr024, roadmap-fase8-logger, adr007-context-fields]`
  - Nota de esclarecimento ao final da ADR-024 mapeando os nomes provisórios `MKS_ERR_TICKFILE_*` para os reais `MKS_ERR_DATA_*` (800-811), sem reescrever a ADR.
  - Alinhar o bullet "output plugável" da Fase 8 do `ROADMAP.md` ao real (dual Print+arquivo, ADR-007); ajustar "ticket" para exemplo de `ctxJson`.
  - Linha em `CHANGELOG.md [Não lançado]` registrando a reconciliação.
- **E1.4 — Alinhamento de branches** `[branch-divergence-stale-main]`
  - Mergear `feat/phase9-trade-visualization` (produção, validada) → `main`; deletar `feat/hedging-only-guard` (já mergeada); decidir e registrar a ordem de `sensors-foundation`/`indicators-bundle-1` (auditar antes de mergear).

**Critério de saída:**
- EA de fábrica abre ordem com SL válido (ou recusa com mensagem clara do mínimo) em demo.
- Salvar um `.mqh` do core recompila ColorReversal/Producer/Replayer; editar `TestRunner.mqh` recompila os testes.
- Nenhuma referência a código de erro inexistente nas ADRs canônicas de paridade.
- `main` reflete o último estado validado em MT5; branch zumbi deletada.

---

## Fase E2 — Fechamento da paridade (o gate central)

**Status:** Em andamento — **E2.0** (fundação DDR) completa e MT5-verificada; **E2.1 empiricamente VALIDADA (2026-07-21):** `verify-parity` **exit 0** sobre feed REAL (33.546 ticks XAUUSDm/Exness → 33 decisões / 17 flips, dois replays byte-a-byte idênticos). **E2.2 — golden bundle versionado (2026-07-21):** `tests/golden/e2-decision/` (fixture `.mkstick` + 2 journals golden + README); o **gate-crossing** foi provado no mesmo fixture (`InpMinEquityAbs=9990` → breaker 409 dispara; dois replays → exit 0, 18 decisões). O **determinismo da decisão — do brick ao breaker de conta — está provado sobre feed real.** **E2.4** (clock do feed) commitado. Pendente: teste headless automatizado do golden (hoje é procedimento manual + `verify-parity`), **E2.3** (âncora de proveniência no `.mksbk`), verificação do E2.4 na virada de dia, e a decisão da lacuna de cadência do snapshot (checkpoint §5.1).
**Depende de:** E1.
**Bloqueia:** Fase 10. **É o item que o dono mais teme** (paridade backtest/live/demo/tester).

**Por que importa:** hoje "paridade bit-a-bit — fato, não teorema" vale só no envelope `fillDays=0` comparando o **stream de bricks**. A camada onde o V5 quebrou a conta — decisão→execução→equity — nunca foi comparada live↔replay. Esta fase estende a prova de paridade dos bricks para a **decisão** e cria a rede de regressão real-tick.

**Entregáveis:**

- **E2.1 — Runner de paridade de decisão (Fase 9 slice 2)** `[H4]`
  - EA/Script fora do tester que monta `source(.mkstick) → builder → CMksColorReversalStrategy → CMksSimulatedBroker (+ StressLabBroker opcional)`, emite um **journal de ordens determinístico** (Send/Close/SL com lots/preço/seq do tick de gatilho).
  - Estender `verify-parity.ps1` para comparar o stream de **decisão** (`decision:buy/sell/close`), não só `msg:brick` — fechando o passo (d) da ADR-024 §7 hoje stubbed.
- **E2.2 — Fixture real-tick + golden test automatizado** `[H1, M7]`
  - Comitar um `.mkstick` real pequeno (alguns milhares de ticks XAU com spread variável e ≥1 gap de fim de semana).
  - `Test_RealTickGolden.mq5` no conjunto automatizado: abre o fixture via `CMksFileTickSource`, roda `CMksRenkoBuilder`, compara os bricks (incl. `triggerPrice`, `triggerTickId`, `high`, `low`) contra um `.mksbk` golden versionado byte-a-byte. Falha o `TestRunner` em divergência.
  - Promover `Test_Producer` de "ESBOCO textbook" a Layer A (reconstrução via o produtor único `CMksRenkoBuilder`, cobrindo `triggerTickId`/high/low) ou aposentá-lo em favor do golden.
- **E2.3 — Paridade à prova de operador** `[parity-historical-fill, seed-lastclose, atr-sizer-state]`
  - Em `InpParityRunMode`, forçar `InpHistoricalFillDays=0` (ou fail-fast no `OnInit` se >0).
  - Gravar a **âncora da escada** (`seedMid` + `seedTickSeq`) e, no modo ATR, o snapshot do sizer no header do `.mksbk`, para o reader validar que duas séries são comparáveis.
- **E2.4 — Tempo de decisão derivado do feed** `[parity-mt5clock-wallclock-leak, parity-mt5clock-isready-asymmetry]`
  - `IClock` de decisão (a fronteira de dia UTC do `CMksAccountSnapshot`) derivado do `timeMsc` do feed em ambos os ambientes — não de `TimeCurrent()` em live — para sobreviver ao replay perto da meia-noite UTC. Padronizar a inicialização do snapshot no 1º tick em ambos os ambientes.

**Critério de saída:**
- `verify-parity.ps1` cobre o stream de **decisão** (ordens), não só bricks; um run live↔replay sobre o mesmo `.mkstick` dá 0 diferenças no journal de ordens, **incluindo uma janela que cruza a meia-noite UTC**.
- Existe um teste headless que prova `builder` sobre **ticks reais** → bricks golden (a "paridade real com ticks reais" vira rede de regressão, não procedimento de operador).
- Rodar paridade com config errada (`fillDays>0`) é impossível ou falha cedo com mensagem clara.

---

## Fase E3 — Robustez do motor Renko

**Status:** Em andamento — **E3.2** (deadlock de rampa monotônica) e **E3.3** (reset de estado pós-reanchor) corrigidos, e **E3.1** (rede de teste do código 105) escrita, via **ADR-033** (2026-07-21). **MT5-verificado (2026-07-21): `Test_CMksRenkoBuilder` 497/497 assertions, 29 tests, 0 failed.** Pendente só o item de processo do critério de saída (Protocolo 1 exigir duplo-run).
**Depende de:** E1. **Bloqueia:** Fase 10.

**Nota (2026-07-21):** o soft-recovery (105) sai de cobertura ZERO `[H2]` para 6 testes determinísticos (incl. paridade duplo-run pós-recovery). O deadlock `[M2]` foi corrigido trocando a âncora fixa (`m_kFirstMid`) por deslizante (`m_kPrevMid`) — ver ADR-033 e `CHANGELOG.md [Não lançado]`. O achado `[recovery-doc-says-variance]` foi fechado (comentários sincronizados). Falta rodar a suíte no MT5 e alinhar o Protocolo 1.

**Por que importa:** o motor é a fundação de tudo. O caminho de soft-recovery (que reescreve a sequência de bricks) estava habilitado por default e rodava **sem rede de teste**; e o detector de gap travava no cenário mais plausível de reabertura.

**Entregáveis:**

- **E3.1 — Cobertura do soft-recovery (código 105)** `[H2]`
  - Testes determinísticos: (1) gap legítimo (N mids consecutivos agrupados dentro de S) → exatamente 1 código 105 no N-ésimo, reanchor correto, próximo movimento define direção; (2) spike isolado (mids dispersos, variância > S) → permanece 102, NÃO reanchora; (3) tick aceito no meio do run zera o contador; (4) **paridade pós-recovery**: dois builders com o mesmo stream contendo um recovery produzem bricks idênticos (incl. `triggerPrice`/`triggerTickId`).
- **E3.2 — Corrigir o deadlock em rampa monotônica** `[M2, recovery-doc-says-variance]`
  - Ancorar a banda de detecção no mid **anterior** (deslizante) ou medir dispersão real da janela — em vez de distância fixa ao primeiro mid rejeitado — para que reabertura direcional sustentada (caso ADR-008) acione o recovery.
  - Sincronizar comentário/ADR-011-nota com o critério real implementado.
  - Teste do cenário rampa monotônica (builder não trava).
- **E3.3 — Limpeza de estado pós-reanchor** `[recovery-stale-lastDirection]`
  - Resetar `m_lastDirection` para inerte no reanchor (simetria com o construtor), ou documentar que `forming.direction` é stale até o primeiro brick pós-recovery.

**Critério de saída:**
- Todo caminho determinismo-crítico do builder (102/103/104/105, gap de fim de semana, multi-threshold, primeiro brick) tem teste que **roda 2× e compara** (não "determinismo assumido").
- Reabertura em rampa monotônica não trava o builder (teste prova recovery).
- Protocolo 1 atualizado: "determinismo verificado" exige teste duplo-run, não inspeção.

---

## Fase E4 — Eixo 3 completo (custo sentido no resultado)

**Status:** Em andamento — **E4.1** (comissão→moeda no journal/report) e **E4.3** (warning de spread inerte) feitos via **ADR-034** (2026-07-21); **E4.2** com os testes de comissão escritos (incl. o `[M1]/[M8]`: dois runs diferindo só na comissão → net diferente). **MT5-verificado (2026-07-21): `Test_CMksTradeJournal` 49/49 (21 tests) + `Test_CMksStressLabReport` 42/42 (8 tests), 0 failed.** Pendente só o sub-teste "`slip>0` reduz o `NetPnLCurrency`". Swap segue OFF (v1, ADR-030) mas a estrutura é swap-aware.
**Depende de:** E1. **Bloqueia:** Fase 10 (e a credibilidade do StressLab como oráculo de decisão).

**Por que importa:** spread e slippage já entram no fill (bom). Mas **comissão e swap são computados e descartados** — o exato padrão "contabilizado num relatório, nunca aplicado ao equity" do eixo 3 do V5, hoje latente na métrica de decisão do StressLab determinístico.

**Entregáveis:**

- **E4.1 — Comissão e swap chegam ao resultado** `[M1, M8, fixedlot-sizer-ignores-sl]`
  - `CMksTradeJournal` recebe comissão (abertura + fechamento, incl. `commissionClose` do auto-close de SL/TP) e expõe um `netPnLCurrency` que a subtrai; `CMksStressLabReport` reporta o resultado líquido em moeda, não só `netPnLPoints`.
- **E4.2 — Asserções de equity/custo** `[M4, slippage-counter-not-validated]`
  - Teste de round-trip: abrir+fechar com spread+slippage+comissão conhecidos e assertar que o resultado realizado caiu pelo custo esperado.
  - Teste que prova: dois runs idênticos exceto `commissionPerLot` produzem `netPnL` diferente (hoje produziriam idêntico — esse é o sintoma).
  - Teste que prova: `slip>0` reduz estritamente o `netPnL` vs `slip=0` (ancorar o efeito no resultado, não no contador).
- **E4.3 — Knobs de stress não-inertes** `[spread-multiplier-silent-noop]`
  - Warning/assert em runtime quando `spreadMultiplier>1` e `baselineSpreadPoints==0` (stress de spread configurado mas inerte) — simétrico ao argumento da ADR-030 contra requote inerte.

**Critério de saída:**
- Nenhum custo é computado-e-descartado no caminho `SimulatedBroker→Journal→StressLabReport`.
- A métrica de sobrevivência do StressLab (a que diz "ir pra live") sente comissão, swap, spread e slippage.
- Documentado onde o eixo 3 é provado por teste.

---

## Fase E5 — Gestão de trade integrada

**Status:** ✅ **Concluída** — **E5.1/E5.2** via **ADR-035** + **E5.3/E5.4** via **ADR-036** (2026-07-21), todos MT5-verificados. Compila **0/0** (`compile-all`, 48 arquivos). **Fecha o gate E1–E5 → destrava a Fase 10.**
- **E5.1/E5.2 (ADR-035):** MT5-verificado — `Test_TradeManagerIntegration` 52/52 (7 tests), `Test_CMksTradeManager` 74/74 (28 tests), `Test_CMksSimulatedBroker` 83/83 (20 tests), 0 failed ✅.
- **E5.3/E5.4 (ADR-036):** MT5-verificado — `Test_CMksColorReversalStrategy` 22 tests, 0 failed ✅ (2 novos + 20 existentes, sem regressão).
**Depende de:** E1, E4. **Bloqueia:** Fase 10.

**Nota (2026-07-21):** o `CMksTradeManager` sai de "coberto só por mock" (`CMksRecordingBroker`) para provado na cadeia REAL — `CMksCostModel → CMksSimulatedBroker → CMksRiskGatedBroker(+RiskManager+FixedLotSizer+SimPositionBook) → CMksTradeManager` — via `Test_TradeManagerIntegration.mq5` (7 testes: BE/partial/trail contra fills reais + idempotência; auto-detach no SL hit; rejeições do gate; fill parcial acumulado; determinismo duplo-run). O bug `[partial-close-partial-status-reapplies]` (partial re-fechava o alvo inteiro sobre o residual num `MKS_EXEC_PARTIAL`) foi corrigido com um acumulador de fill (re-emite só o residual) — ADR-035. O E5.3 fechou a **exposição dupla no flip** (Close falho mantém o vínculo, não abre nova posição) e o E5.4 **documentou** o breaker como preventivo (flatten-on-breach adiado) + a semântica flutuante do `DayPnL` — ADR-036. Ver `CHANGELOG.md [Não lançado]`.

**Por que importa:** a peça que responde à ausência que quebrou o V5 (gestão reativa) está coberta por unit tests mas **nunca rodou num composition root real**. Estratégias reais vão usá-la — precisa funcionar fim a fim antes.

**Entregáveis:**

- **E5.1 — TradeManager integrado fim a fim** `[trademanager-not-wired-in-ea]` — **feito (ADR-035, 2026-07-21; MT5 pendente)**
  - Runner (ou EA de validação) que compõe `CMksTradeManager` sobre `CMksSimulatedBroker` + auto-close, exercitando BE/trailing/partial contra fills reais e o interplay com auto-detach e o `CMksRiskGatedBroker`. → materializado como teste de integração headless `Test_TradeManagerIntegration.mq5` (o critério de saída pede "testes que provam"); EA de replay com gestão fica para a Fase 10 se necessário.
- **E5.2 — Partial close trata fill parcial** `[partial-close-partial-status-reapplies]` — **feito (ADR-035, 2026-07-21; MT5 pendente)**
  - Tratar `MKS_EXEC_PARTIAL` explicitamente (acumular `filledLots`, recalcular sobre o residual, ou marcar progresso) + teste com `SetNextCloseStatus(MKS_EXEC_PARTIAL)`. → acumulador `m_partialFilledLots` re-emite só o residual até o alvo; `SetNextCloseStatus` adicionado ao `CMksSimulatedBroker` (one-shot, determinístico); regressão provada em `Test_TradeManagerIntegration`.
- **E5.3 — Exposição órfã no flip** `[close-failure-clears-state-still-opens]` — **feito (ADR-036, 2026-07-21; MT5 pendente)**
  - Em flip, se `CloseCurrentIfAny` retornar `false`, NÃO abrir nova posição no mesmo brick (deixar auto-detach/risk reconciliar) ou ao menos logar WARN de exposição dupla potencial. → `CloseCurrentIfAny` mantém o vínculo na falha (só zera em `FILLED`); `OnBrickClose` só abre se `m_currentPositionId==0` após o fecho, senão loga WARN. +2 testes.
- **E5.4 — Semântica do circuit breaker** `[circuit-breaker-only-gates-opening, daypnl-uses-equity, rollover-baseline]` — **feito (ADR-036, 2026-07-21; doc)**
  - Documentar nos ADRs que o breaker é **preventivo (entrada)**, não corretivo (saída); avaliar um componente `flatten-on-breach` (fecha tudo + bloqueia) acionado por `OnTick` ao cruzar `minEquityAbs`/`maxDrawdownPct`. → documentado (ADR-036 + comentário do `CMksRiskAccountParams`); `flatten-on-breach` **avaliado e adiado** (decisão do dono: só documentar por ora), registrado na §4 Decisões pendentes do ARCHITECTURE.
  - Decidir e alinhar a semântica de `DayPnL` (equity flutuante vs balance realizado) entre doc e código. → decidido **equity flutuante** (mais protetor); alinhado no comentário do `CMksAccountSnapshot::DayPnL`.

**Critério de saída:**
- ✅ BE/trailing/partial rodam fim a fim contra fills reais (incl. parciais) com testes que provam o comportamento e a idempotência (E5.1/E5.2, MT5-verificado).
- ✅ Comportamento definido e testado para Close falho no flip (E5.3, MT5-verificado); para breach do breaker com posição aberta, decidido que o breaker é **preventivo** e o corretivo (`flatten-on-breach`) fica em aberto e nomeado (E5.4).
- ✅ Doc do breaker reflete o que ele faz (preventivo) e a lacuna corretiva está **decidida** (adiada conscientemente, registrada).

---

## Fase E6 — Produto operável (UX SaaS)

**Status:** Não iniciada
**Paralela a E2–E5; pré-requisito de operação real (não de construir o core).**

**Por que importa:** o foco declarado é experiência do usuário — "simples de operar, sem confundir com opções demais". Hoje a superfície de configuração e o fluxo de operação contradizem essa meta, e um default (`InpSlPoints=30`) já quebrou em produção.

**Entregáveis:**

- **E6.1 — Reduzir a superfície de configuração** `[input-surface-too-large, k-l-defaults-coupled]`
  - Agrupar inputs em **Básico** (instrumento, brick size, modo de lote/risco, limites de risco) vs **Avançado/Diagnóstico** (L/K, flags de log, cores).
  - Esconder K/L atrás de defaults no composition root (já têm justificativa em ADR — não precisam ser inputs); derivar K automaticamente de `fillDays`/`brickSize` (`K = max(20, ceil(gapEsperado/S))`).
  - Unificar o default de `InpHistoricalFillDays` entre Producer e ColorReversal (ou documentar por que diferem).
- **E6.2 — Unidades explícitas** `[pts-naming-misleading]`
  - Padronizar a unidade do SL para a mesma do brick (preço, ou múltiplos de `brickSize`); eliminar "Pts" do naming onde o valor não é ponto do símbolo.
- **E6.3 — Presets por instrumento**
  - Um preset por instrumento (XAU, EURUSD…) que pré-popula brick/SL/limites sãos — o operador escolhe o instrumento, não 30 números.
- **E6.4 — Runbook de primeira execução + consolidação de artefatos** `[run-ea-flow-manual-multistep, header-describes-nonexistent-stress-runner]`
  - Runbook de 1 página no `CHEATSHEET.md` (ordem dos passos, anexar no símbolo real, conta hedging, qual EA para quê).
  - Avaliar se o `Producer` ainda precisa existir como EA separado para o operador final (útil para dev, confunde como produto).
  - Corrigir o `@responsibility` de `ColorReversal.mq5` (narra stress runner inexistente).

**Critério de saída:**
- Operador roda com ≤ ~8 inputs básicos, defaults sãos por instrumento, sem aritmética manual de config.
- Runbook de 1 página existe; o fluxo de "primeira execução" tem caminho único documentado.

---

## Fase E7 — Custom Symbol: gate empírico

**Status:** Em andamento (4 fixes aplicados; sobrevivência à meia-noite pendente de dado)
**Paralela; pré-requisito de E8.**

**Por que importa:** o CS é **visual** (a estratégia não o lê — invariante ADR-020 §1, verificado). Mas a "cura" da morte à meia-noite é hipótese até o dado existir, e a fundação de indicadores depende de o CS ser confiável (ou de migrar para `IRenkoIndicator`).

**Entregáveis:**

- **E7.1 — Validar a sobrevivência à virada de dia** `[cs-midnight-survival-unverified, cs-spec-wipe-vs-explicit-wipe]`
  - Rodar o gate empírico cruzando ≥1 meia-noite de servidor (06-02→06-03) e idealmente um fim de semana, com **0 `CS UPDATE FAIL`**; rodar ao menos uma vez com `InpResetCustomSymbolBars=false` para isolar o fix (b) (persistência do histórico) do efeito de wipe+refill.
- **E7.2 — Robustez do sink na falha** `[cs-recovery-advances-timeline-on-fail, cs-forming-no-recovery-asymmetry, cs-forming-bar-orphan-vs-doc, cs-painter-discards-real-timemsc]`
  - Só avançar `lastBarTime`/`nextBarTime` no ramo de **sucesso** do `CustomRatesUpdate` (em falha, manter o slot anterior — painter ancora na última barra real).
  - Logar a 1ª falha de `OnBrickForming` (captura o instante exato da recusa do container).
  - Corrigir comentários do sink/painter para refletir o comportamento real (bar parcial órfã em mercado calmo; ancoragem em `lastBarTime` em live).
- **E7.3 — Redigir a ADR-031 com o dado**
  - Com o gate cumprido, redigir formalmente a ADR-031 ("manter+corrigir o CS") — hoje só referenciada, ainda não escrita.

**Critério de saída:**
- CS sobrevive à virada de dia com 0 falhas (dado, não hipótese); persistência do histórico no re-attach confirmada com wipe desligado.
- ADR-031 escrita e aceita com a evidência empírica.

---

## Fase E8 — Fundação de indicadores

**Status:** Não iniciada
**Depende de:** E7. **Bloqueia:** desenvolvimento de novos indicadores.

**Por que importa:** o dono quer construir indicadores próprios para o Renko. Os 5 atuais têm fundação decente, mas dependem 100% do CS (cujo futuro a ADR-031 decide) e nenhum é magnitude-aware — herdam a distorção de M>1/ATR. Construir mais 10 antes de fechar isso é trabalho potencialmente jogado fora.

**Entregáveis:**

- **E8.1 — Política multi-threshold dos indicadores** `[indicators-not-magnitude-aware, cs-multithreshold-atr-fictional-prices (M3)]`
  - Decidir e documentar em `INDICATORS.md`: ou (a) os indicadores **leem `tick_volume`** (= `thresholdsCrossed`) e tratam M>1 (magnitude-aware), ou (b) declarar formalmente que a camada visual é fiel só para M=1, aceitando a perda. Hoje há silêncio entre `INDICATORS.md` ("fiéis") e ADR-011 ("precisa ser magnitude-aware").
- **E8.2 — Auto-infer robusto** `[auto-infer-bricksize-fragile-fallback]`
  - Validar a hipótese de tamanho constante (amostrar `|close-open|` de várias bars confirmadas; exigir consistência antes de aceitar) e avisar/exigir `InpBrickSizePts` manual quando divergir (ATR/legacy/M>1 não-colapsado).
- **E8.3 — Testes de verdade independente** `[flipping-tests-internal-consistency, catalog-status-unsubstantiated]`
  - Chandelier/SuperTrend: recomputar a máquina de estados `(Trend, ActiveStop)` desde o seed de forma independente (sem ler o `trendBuf` do indicador) e comparar a série inteira.
  - Capturar a saída real de cada `Test_*` (linha `OK: N bars … diff_max=…`) num artefato versionado; corrigir "RSI bate 0.0" para o `diff_max` observado.
- **E8.4 — Decisão CS vs IRenkoIndicator** `[indicators-foundation-vs-cs-deprecation]`
  - Com a ADR-031 fechada (E7), decidir se o catálogo expande sobre o CS (`iCustom`) ou migra para a família `IRenkoIndicator` (lendo `MksBrick` direto). Se migrar, portar os 5 existentes como prova de conceito antes de adicionar novos.

**Critério de saída:**
- Política de fidelidade do CS para M>1/ATR documentada e implementada (ou limitação declarada).
- Indicadores têm defesa própria contra bar de tamanho não-nominal.
- Testes recomputam a verdade independentemente; catálogo com `diff_max` real versionado.
- Caminho (CS vs IRenkoIndicator) decidido — só então o catálogo expande.

---

## GATE CORE → Fase 10

A Fase 10 (estratégias reais do `ROADMAP.md`) só começa quando **E1, E2, E3, E4 e E5** tiverem todos os critérios de saída cumpridos. Novos **indicadores** só começam após **E7 + E8**. Esta é a aplicação literal da regra de ouro do projeto e da disciplina anti-V5: *core demonstravelmente robusto antes de estratégias*.

**Resumo em 3 linhas:** (1) E1–E5 fecham as lacunas de **verificação** que fazem a paridade ser mais estreita que o discurso (paridade de decisão, teste real-tick, recovery testado, eixo 3 completo, gestão integrada) — são gate bloqueante para estratégias. (2) E6 (UX) e E7 (CS) correm em paralelo; E8 (indicadores) depende de E7. (3) Cada item rastreia um achado da auditoria de 2026-06-02 — o plano é a auditoria convertida em sequência executável, sob a regra de ouro do projeto.
