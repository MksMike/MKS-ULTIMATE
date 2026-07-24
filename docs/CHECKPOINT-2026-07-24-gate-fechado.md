---
@document: docs/CHECKPOINT-2026-07-24-gate-fechado.md
@project: MKS-ULTIMATE
@session: 2026-07-23 → 2026-07-24 (maratona, atravessou 2 dias)
@purpose: Handoff da sessão que aplicou o Lote C-fix da auditoria, os follow-ups #2/#3, a ADR-041, e FECHOU o gate E1–E5 (E2 inteiro verificado) → Fase 10 destravada.
@audience: Próxima sessão (humano + IA). CHECKPOINT é guia, código é verdade.
---

# CHECKPOINT 2026-07-24 — Gate E1–E5 FECHADO → Fase 10 destravada

## TL;DR (o marco)

Sessão-maratona que fechou o **último eixo do endurecimento do core**: o **E2 (paridade)** — onde o V5 quebrou a conta. Com E1/E3/E4/E5 já fechados nas sessões anteriores, **o gate E1–E5 está formalmente aberto** e a **Fase 10 (estratégias reais)**, bloqueada desde a auditoria de 2026-06-02, está **destravada**.

A paridade de **bricks E de decisão** deixou de ser procedimento manual (`verify-parity.ps1`) e virou **rede de regressão automática no TestRunner**. 16 commits, todos no padrão, cada mudança de risco **verificada adversarialmente** (workflows de 3–5 lentes). Reframe honesto MANTIDO (E2 prova determinismo sim↔sim + paridade feed→brick; live↔broker-real é estruturalmente não-bit-exato — proibido dizer "H4 fechado").

## Gate E1–E5 → Fase 10

| E1 | E2 | E3 | E4 | E5 |
|---|---|---|---|---|
| ✅ | ✅ | ✅ | ✅ | ✅ |

E7/E8 (CS/indicadores) e a decisão de cadência do snapshot NÃO bloqueiam a Fase 10 — bloqueiam só *novos indicadores*.

---

## O que foi feito (por frente)

### 1. Lote C-fix da auditoria (`2a9c490`) — verificado por workflow (5 lentes)
Após verificar os 5 achados de dinheiro/dados do Lote C (`ba6f0dd`: 1 refutado — o "pior risco de dinheiro", partial fill do Mt5Broker, era falso alarme; 4 confirmados), apliquei os fixes confirmados:
- **`CMksMt5Broker.Send()`** — removido o gate `!m_fillingFallbackDone`: a cadeia de filling FOK→IOC→RETURN passa a percorrer inteira num Send (termina porque `TryFillingFallback` devolve false em RETURN). Membro/getter renomeados `m_fillingFallbackUsed`/`FillingFallbackUsed` (viraram observáveis; "Done" era armadilha).
- **`CMksMt5Broker.Close()` — BLOCKER descoberto na verificação adversarial:** Close **não tinha** o fallback de INVALID_FILL → o `FlattenAll` do circuit breaker (ADR-040) receberia INVALID_FILL a cada tick e **nunca fecharia** — a defesa central contra a lição do V5 falhava em silêncio. Espelhei o branch (lição #2 da retrospectiva: Send↔Close).
- **`CMksTradeManager.Validate()`** — `beOffset >= beActivation → reject` (SL ficaria ≥ preço no gatilho) + 2 testes.
- **MT5-verde:** `Test_CMksTradeManager` 80/80 (34 tests), `Test_CMksCircuitBreaker` 18/18, `Test_TradeManagerIntegration` 52/52.

### 2. Follow-ups #2/#3 (`f21b8f1`)
- **#2 (classe do bug B — validador de dinheiro sem teto):** `CMksRiskManager.Validate` rejeita `maxDailyLossPct >= 100` e `maxDrawdownPct >= 100` (limite inerte: o broker liquida antes de 100%). +2 testes. **MT5:** `Test_CMksRiskManager` 121/121.
- **#3 (latch `m_streamCorrupt`):** CONFIRMADO INTENCIONAL (ADR-006 §5/§6 — interrupção reportada; recuperação é do EA). Comentário reforçado. Zero mudança de comportamento.

### 3. ADR-041 (proposta `a2f7871` → aceita + núcleo `96fb53d`)
**Distância mínima de SL de gestão (BE/trail) ancorada em bricks.** Fecha o follow-up #1 (StopsLevel no Modify de BE/trail = divergência live↔sim = eixo-2 do V5). Decisão (Opção A): floor ancorado em bricks, config-time no `Validate`, StopsLevel fora do runtime (espelha ADR-032). **Núcleo implementado** (`manageMinSlPoints` no params + checks no Validate + 4 testes); o input `InpManageMinSlBricks` fica **diferido ao wiring do TM num EA** (o TM só existe em testes — input morto seria proibido).

### 4. Bug do CS reportado pelo dono → NÃO era bug de dado (`ee852c6`)
O dono viu um **buraco horizontal no CS**. Apliquei "dado antes do conserto": **parseei os 8048 bricks do `.mksbk`** — contiguidade perfeita, tempo monotônico, direções válidas. **O dado está impecável; o buraco é o artefato da timeline híbrida (viz), não bug** — mercado lento → bricks minutos apart → slots M1 vazios → known-open (raiz = eixo-por-índice, E7/E8). De brinde, corrigi um comentário mentiroso do `BrickFileFormat.mqh` (enum é `BEAR=-1, BULL=1`, não `0/1`). **Memória salva:** `cs-gap-horizontal-timeline` (não re-parsear no próximo gap — é viz).

### 5. E3 + E4 fechados (`64bc151`)
- **E4.2 (eixo 3 em MOEDA):** `Test_SR_SlippageDegradesNetCurrency` prova que `slip>0` reduz **estritamente** o `netPnLCurrency` (não só pontos). **MT5:** `Test_CMksStressRunner` 30/30.
- **E3 (processo):** Protocolo 1 §determinismo reforçado — exige **teste duplo-run automatizado** (não inspeção). Motivação: achado `[H2]`.

### 6. E2 inteiro — a paridade verificada (o coração da sessão)
- **E2.2 — golden de BRICKS headless** (`b9d876f`, `f3a142d`, `63e8ca9`): `Test_RealTickGolden` (Layer A — `CMksRenkoBuilder` real sobre o fixture via `CMksFileTickSource`, hermético) compara records vs golden `.mksbk` versionado (`tests/golden/e2-brick/`). Golden **abençoado**: 32 bricks, **17 flips == os 17 flips do golden da decisão** já validado. `Test_Producer` rebaixado a cross-check manual. **MT5: 10/10.**
- **E2.3 — âncora de proveniência no `.mksbk`** (`7e7a526`): `seedMid`@192 + `seedTickSeq`@200 (mid+seq do 1º tick que semeia o builder), forward-compat sobre espaço reservado (formatVersion segue 1; pré-E2.3 lê 0/0); patchada no Close/Checkpoint; getters no builder+reader; `HasSeed`. + **fail-fast** `InpParityRunMode ⇒ fillDays=0`. **Verificado adversarialmente (3 lentes, 0 regressões).** **MT5:** `Test_CMksBrickFile` 110/110, `Test_CMksRenkoBuilder` 503/503.
- **E2.4 — rollover feed-driven na meia-noite** (`99ade1f`): `Test_Runner_MidnightRolloverDeterministic` prova que a fronteira de dia UTC é dirigida pelo `timeMsc` do feed (`CMksFeedClock`), não wall-clock — feed-time ~2026-05-23 ≠ wall-clock 2026-07-24: se fosse `TimeCurrent()` o rollover não dispararia e o teste falharia. **MT5:** `Test_CMksDecisionRunner` 45/45.
- **Golden de DECISÃO headless** (`cdd388c` config A, `9afb94e` config B): `Test_DecisionGolden` roda o `CMksDecisionRunner` sobre o fixture e compara o journal vs `baseline.golden.tsv` (config A, gates off) e `gate-minequity.golden.tsv` (config B, `minEquityAbs=9990`, 1 trade + 16 REJECTED 409), **ignorando linhas `#`** (como o `verify-parity`). Descoberta: só `slPoints=30000` difere dos defaults do struct. **Config A MT5-verde 5/5 (casou de 1ª).**
- **E2 FECHADO — decisão de cadência do snapshot** (`33f3b70`): o núcleo (`parity-mt5clock-*`, rooted no `CMksMt5Clock`) já estava resolvido pelo E2.4 (live e replay usam ambos `CMksFeedClock`; grep confirma `CMksMt5Clock` fora de todo composition root de decisão). Residual (live seedeia do tick pré-attach + Init no OnInit; replay Init lazy no 1º tick) **aceito e documentado** — mesmo dia UTC no attach, auto-corrige na virada, sim↔sim é bit-exato. Endurecimento (lazy no ColorReversal) diferido.

## Commits da sessão (16, todos em `origin/main` até `ac9d0e9`; 2 locais à frente)

```
ba6f0dd  Lote C — veredictos (1 refutado, 4 confirmados)
2a9c490  Lote C-fix — filling fallback (Send+Close) + teto BE
f21b8f1  follow-ups #2 (teto RiskManager) + #3 (latch confirmado)
a2f7871  ADR-041 proposta
96fb53d  ADR-041 aceita + núcleo
ee852c6  fix comentário enum do .mksbk (CS gap = viz, não dado)
64bc151  fecha E3 e E4
b9d876f  Test_RealTickGolden (golden de bricks)
f3a142d  golden .mksbk abençoado (32 bricks, 17 flips)
63e8ca9  fecha E2.2 + Test_Producer → manual
7e7a526  E2.3 âncora de proveniência + fail-fast
99ade1f  E2.4 rollover feed-driven na meia-noite
cdd388c  Test_DecisionGolden (config A)
ac9d0e9  MT5-verde E2.3/E2.4/golden-decisão   ← último PUSHADO
9afb94e  Test_DecisionGolden config B          ← LOCAL (não pushado)
33f3b70  E2 FECHADO (cadência do snapshot)     ← LOCAL (não pushado)
```

## Pendências para a próxima sessão

- **Push:** feito ao fim desta sessão (incl. este checkpoint) — `origin/main` está current.
- **MT5-verde do `Test_DecisionGolden` config B** (config A já 5/5). Se divergir, o teste imprime a 1ª linha (produzido vs golden) → ajuste de 1 tiro. Risco residual: modelo de dinheiro (mas robusto — a partir do trip do gate todo SEND é REJECTED, então o journal independe do `tickValue` exato desde que o 1º trade dispare).
- **Setup dos goldens no `Files/`:** o fixture `.mkstick` + `baseline.golden.tsv` + `gate-minequity.golden.tsv` + `XAUUSDm_CR_20260720T233245.golden.mksbk` foram copiados para `<terminal>\MQL5\Files\MKS-ULTIMATE\golden\` nesta sessão (a máquina de casa). Numa máquina nova, re-copiar de `tests/golden/e2-{brick,decision}/`.

## Estado / próximas frentes

- **Fase 10 (estratégias reais) — DESTRAVADA.** Cada estratégia é projeto próprio; merece sessão de planejamento (precisa da **tese de edge** do dono).
- **E6** (UX) quase pronto (pende smoke do preset EURUSD, sub-item `InpHistoricalFillDays`).
- **E7/E8** (CS/indicadores) — paralelos; E7 pende de dado (sobrevivência do CS à meia-noite) + fixes do E7.2; E8 depende de E7. Bloqueiam **novos indicadores**, não a Fase 10.
- **Diferido nomeado:** input `InpManageMinSlBricks` (nasce com o wiring do TM num EA); config B MT5-verde; lazy-init do snapshot no ColorReversal (simetria total, sem ganho hoje); slippage puro do StressLab (dado de ordem real); ADRs 039/040 seguem **Proposta**.

## Método (o que se confirmou)

A **verificação adversarial via workflow** pagou de novo: pegou o **BLOCKER do Close()** (o filling fallback ausente que quebraria o flatten-on-breach) e **refutou** o "pior risco de dinheiro" do Lote C (partial fill — era falso alarme). Padrão a manter: dado antes do conserto; caminhos gêmeos (Send↔Close, live↔replay); verificar adversarialmente antes de commitar o que toca dinheiro/paridade/formato.
