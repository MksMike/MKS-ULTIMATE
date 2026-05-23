---
@document: docs/CHECKPOINT-2026-05-23-saturday.md
@project: MKS-ULTIMATE
@purpose: Adendo da sessão de sábado 2026-05-23 — ADR-024 aceita + slices 24a/b/c, Fase 6 fechada (6.2 + 6.3), Fase 5 fechada (5b). Toda a ADR-019 materializada.
@audience: Próxima sessão (humano + IA)
---

# CHECKPOINT — 2026-05-23 (sessão de sábado)

Adendo a [`CHECKPOINT-2026-05-23.md`](CHECKPOINT-2026-05-23.md), que cobriu o trabalho da manhã/início do dia (auditoria V5, ADR-023, painel UX, refactor do Producer). Este documenta a sessão da tarde/noite: ADR-024 + 3 slices de implementação parcial, e o fechamento da rede de segurança da ADR-019 (Fase 5 + Fase 6).

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 9 arquivos, nesta ordem

1. `README.md`
2. `docs/CHECKPOINT-2026-05-20.md` — base, convenções, estado pós-Slice 1
3. `docs/CHECKPOINT-2026-05-20-slice2.md` — adendo pós-Slice 2
4. `docs/CHECKPOINT-2026-05-20-slice3a.md` — formato `.mksbk`
5. `docs/CHECKPOINT-2026-05-21-slice3b.md` — Producer + Custom Symbol + ADRs 015/007/018/016/017
6. `docs/CHECKPOINT-2026-05-22.md` — pós-validação ADR-005 (framework de teste)
7. `docs/CHECKPOINT-2026-05-22-cs.md` — Custom Symbol completo + Fases 5a/6.1
8. `docs/CHECKPOINT-2026-05-23.md` — manhã: ADR-023 proposta, painel SaaS Navy, Producer refactor
9. `docs/CHECKPOINT-2026-05-23-saturday.md` — este, sessão de sábado (ADR-024 + 24a/b/c + 6.2 + 6.3 + 5b)

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação.

---

## 2. Estado do código (HEAD = `c007daf`)

Branch principal: `main`. Local está **9 commits à frente do `origin/main`** no momento deste checkpoint — push será executado junto com o commit deste documento, conforme decisão do dono.

### Histórico desta sessão (linear na main, com merges no-ff)

```
* c007daf  Merge Slice 5b (TradeManager)
| * 6a32845  feat(trade): Slice 5b — CMksTradeManager
|/
* 80064ad  Merge Slice 6.3 (Por Conta)
| * 62f5753  feat(account+risk): Slice 6.3 — camada Por Conta
|/
* 8546dd1  Merge Slice 6.2 (Por Estratégia)
| * 48181dc  feat(risk): Slice 6.2 — camada Por Estratégia
|/
* bb8b5e0  Merge ADR-024 + slices 24a/b/c
| * 8de19b9  feat(error+data): Slice 24c — SYMBOL_MISMATCH=807
| * 608ec58  feat(clock+data): Slice 24b — Mt5Clock + ReplayClock + FileTickSource
| * 976f82a  feat(data): Slice 24a — TickFileFormat + Writer + Reader + golden test
| * 908cc1d  docs(adr): ADR-024 Tick Recorder + Replayer
|/
* 92c4569  docs(reference): promote V5 to reference/V5/ + README   ← último commit pré-sessão
```

Branches preservadas localmente (não-apagadas):
- `docs/adr-024-tick-recorder-replayer`
- `feat/slice-6.2-risk-per-strategy`
- `feat/slice-6.3-risk-per-account`
- `feat/slice-5b-trade-manager`

### ADRs aceitas até aqui

ADR-001 a 022 (manhã + sessões anteriores), **ADR-023 (Proposta — Timeline híbrida no CS, implementação adiada)**, **ADR-024 (Aceita — Tick Recorder + Replayer para paridade bit-a-bit)**.

ADR-008 segue como única pendência formal na fila (gap de fim-de-semana no RenkoBuilder, evidência parcial em `CHECKPOINT-2026-05-20-slice2.md` §6).

---

## 3. Sessão deste ciclo — em ordem cronológica

### 3.1 ADR-024 aceita

Materializa duas dívidas explícitas previamente registradas:
- ADR-012 §5 (layout binário do arquivo de captura) + §Consequências (captura/consumo como artefatos separados)
- ADR-015 §Consequências (engine de backtest fora do Strategy Tester nativo)

Sete regras: formato `.mkstick` v1 (header 256B + record 64B, espelhando `.mksbk`), captura via Service em `MQL5/Services/`, granularidade 1-arquivo-por-dia-UTC, consumo via `CMksFileTickSource` implementando `ITickSource`, replay via EA `Replayer.mq5` montando composition root completo fora do Tester, proibições de runtime para estratégia ser replay-safe (REGRAS §1.9 futura), validação canônica via `fc /b` dos `.mksbk` + `diff` das linhas `decision=*` dos logs.

### 3.2 Slice 24a — TickFileFormat + Writer + Reader + golden test

- `Core/Data/TickFileFormat.mqh` — constantes do layout (magic `MKSTK01`, header 256B, record 64B).
- `Core/Data/CMksTickFileWriter.mqh` — espelho do `CMksBrickFileWriter`. Recusa sobrescrever (806), patch de header no Close, override de `createdAt`/`closedAt` para golden test reproduzível.
- `Core/Data/CMksTickFileReader.mqh` — valida magic+version+recordSize+headerSize+totalSize. `ReadNext` além de `tickCount` devolve `MKS_ERR_DATA_TRUNCATED`.
- `Tests/Test_CMksTickFile.mq5` — 5 testes: roundtrip campo-a-campo, golden rewrite byte-a-byte, magic inválido rejeitado, leitura além de `tickCount`, **golden de 10k ticks sintéticos**.

**Cobertura empírica:** 10106/10106 asserts em 5 tests, 0 failed.

### 3.3 Slice 24b — Clock + FileTickSource

- `Core/Clock/CMksMt5Clock.mqh` — `IClock` live, `TimeCurrent()*1000`. Centraliza o acesso permitido que a futura REGRAS §1.9 proibirá na estratégia.
- `Core/Clock/CMksReplayClock.mqh` — `IClock` replay derivado do tick corrente. Função pura do feed; null-safe.
- `Core/Data/CMksFileTickSource.mqh` — `ITickSource` sobre `.mkstick`. Política de proveniência:
  - `broker` mismatch → WARN-flag, Open sucede.
  - `account` mismatch → WARN-flag, Open sucede.
  - `symbol` mismatch → FATAL (`MKS_ERR_DATA_HEADER_INVALID` no slice 24b; renomeado para `MKS_ERR_DATA_SYMBOL_MISMATCH=807` no slice 24c).
  - Single-file no 24b. Multi-arquivo fica para slice 24d quando Recorder gerar mais de 1/janela.
- `Tests/Test_CMksFileTickSource.mq5` — 8 testes: open exato, broker/account WARN, symbol FATAL, ordem dos ticks + EOF, ReplayClock acompanha feed, Mt5Clock smoke, ReplayClock(NULL) safe.

**Cobertura empírica:** 74/74 asserts em 8 tests, 0 failed.

### 3.4 Slice 24c — código de erro dedicado

- `MKS_ERR_DATA_SYMBOL_MISMATCH = 807` adicionado a `Error.mqh`.
- 808–810 reservados-por-comentário (PROVENANCE/REOPEN/SEQ_DISCONTINUITY), seguindo o padrão da ADR-012 §Consequências ("número entra quando consumidor exige").
- Refactor do `CMksFileTickSource.Open` para usar 807 no symbol mismatch.
- Refactor do teste correspondente.

**Cobertura empírica (regressão):** 74/74 asserts em 8 tests, 0 failed.

### 3.5 Slice 6.2 — camada "Por Estratégia" no CMksRiskManager

Segundo anel da rede de segurança da ADR-019.

- `Core/Interfaces/IPositionBook.mqh` — consulta de estado: `OpenCount()`, `TotalLots()`. Separada de `IBroker` (que executa) por SRP.
- `Core/Position/CMksMt5PositionBook.mqh` — impl real symbol-bound, com filtro opcional de magic (permite coexistir múltiplas estratégias).
- `Core/Testing/Mocks/CMksFakePositionBook.mqh` — mock para testes.
- `CMksRiskManager.mqh` — `CMksRiskStrategyParams` (`maxOpenPositions`, `maxTotalLots`). 2º construtor sobrecarregado. Validate rejeita "ativo sem book" (erro de wiring). 2 checks novos no `CheckOrder`.
- `Error.mqh` — códigos `MKS_ERR_RISK_REJECTED_OPEN_POSITIONS=405`, `MKS_ERR_RISK_REJECTED_TOTAL_LOTS=406`.

**Cobertura empírica:** 55/55 asserts em 36 tests, 0 failed (15 novos + 21 da camada anterior).

### 3.6 Slice 6.3 — camada "Por Conta" no CMksRiskManager

Terceiro e último anel da rede de segurança — exatamente o que o V5 não tinha quando quebrou conta em 4h.

- `Core/Account/CMksAccountSnapshot.mqh` — classe stateful. Rastreia balance de início-do-dia-UTC e peak equity desde Init. Rollover automático (mesma fronteira UTC do `.mksbk`/`.mkstick`). Init idempotente, Update auto-inicializa.
- `Core/Testing/Mocks/CMksFakeClock.mqh` — `IClock` configurável (SetNowMsc, Advance) para exercitar rollover controladamente.
- `CMksRiskManager.mqh` — `CMksRiskAccountParams` (`maxDailyLossPct`, `maxDrawdownPct`, `minEquityAbs`). 3º construtor sobrecarregado. 3 checks novos. Snapshot expõe `Equity()`/`Balance()` (facade) para evitar IAccount duplicada como dep.
- `Error.mqh` — códigos `MKS_ERR_RISK_REJECTED_DAILY_LOSS=407`, `MKS_ERR_RISK_REJECTED_DRAWDOWN=408`, `MKS_ERR_RISK_REJECTED_MIN_EQUITY=409`.

**Cobertura empírica:** 27/27 asserts em 13 tests no `Test_CMksAccountSnapshot` + 85/85 asserts em 57 tests no `Test_CMksRiskManager` (36 antigos + 21 novos). 0 failed em ambos.

### 3.7 Slice 5b — CMksTradeManager

Fecha a Fase 5. Gestão de posição aberta — break-even, trailing stop, partial close, state machine idempotente. Lição V5 #2 ("gestão tem state machine, não 'vou lembrar de fechar'") materializada.

- `Core/Trade/CMksTradeManager.mqh` — 1 instância por posição, stateful (`m_beApplied`, `m_partialDone`, `m_trailActive`, `m_currentSl`). API: `Validate` → `Attach` → loop de `Update(MksTick)` → `Detach`. Ordem fixa em Update: BE → Partial → Trail. Idempotente (re-Update no mesmo tick não re-aplica BE/partial; trail só avança SL).
- `Core/Testing/Mocks/CMksRecordingBroker.mqh` — mock de `IBroker` que registra cada chamada `Modify`/`Close` em arrays inspecionáveis (`ModifyAt`, `LastClose`, etc.). Configurável para simular falhas.
- `Error.mqh` — código `MKS_ERR_TRADE_MANAGER_INVALID_PARAM=303`.

**Cobertura empírica:** 61/61 asserts em 25 tests, 0 failed.

**Fix capturado pelo compile headless:** include de `Error.mqh` estava faltando no TradeManager; `Validate` referenciava `MksError` sem o tipo na TU. Apanhado antes do test run — exatamente o caso de uso do watcher (REGRAS §1.3 não-compila).

---

## 4. Estado das fases do ROADMAP

| Fase | Antes da sessão | Depois da sessão |
|---|---|---|
| 0 — Fundação documental | concluída | concluída |
| 1 — Abstrações do core | concluída | concluída |
| 2 — RenkoBuilder | concluída | concluída |
| 3 — Testes unitários | concluída | concluída |
| 4 — Broker abstractions | concluída | concluída |
| **5 — Trade Management** | **parcial (só 5a)** | **concluída** |
| **6 — Risk Management em camadas** | **parcial (só 6.1)** | **concluída** |
| 7 — StressLab | não iniciada | não iniciada |
| 8 — Logging/observability | parcial | parcial (falta log-diff tool, depende 24d/e) |
| 9 — EA validação end-to-end | não iniciada | não iniciada |
| 10 — Estratégias reais | não iniciada | não iniciada |

**ADR-019 inteira (`5a → 6.1 → 6.2 → 6.3 → 5b`) materializada e validada.** A rede de segurança que faltava ao V5 está completa.

---

## 5. Cobertura de teste — agregado pós-sessão

| Suite | Tests | Asserts | Status |
|---|---|---|---|
| Test_CMksRenkoBuilder | — | (acumulado prévio) | ✓ |
| Test_CMksAtrBrickSizer | 11 | 72 | ✓ |
| Test_CMksBrickFile | 4 | (acumulado prévio) | ✓ |
| Test_CMksPositionSizer | — | (acumulado prévio) | ✓ |
| Test_CMksSimulatedBroker | 12 | 51 | ✓ |
| Test_CMksTickFile **(novo)** | 5 | 10106 | ✓ |
| Test_CMksFileTickSource **(novo)** | 8 | 74 | ✓ |
| Test_CMksRiskManager (estendido) | 57 | 85 | ✓ |
| Test_CMksRiskGatedBroker | — | (acumulado prévio) | ✓ |
| Test_CMksAccountSnapshot **(novo)** | 13 | 27 | ✓ |
| Test_CMksTradeManager **(novo)** | 25 | 61 | ✓ |
| **Total novo nesta sessão** | **— ** | **10353 asserts** | ✓ |

Todos os tests compilam **0 errors, 0 warnings** via `MetaEditor64 //compile` headless. Sem regressões nos testes pré-existentes.

---

## 6. Pendências em aberto

### 6.1 ADR-024 — 3 de 6 slices completos

Pendentes (todos requerem mercado aberto):

- **Slice 24d** — `TickRecorder.mq5` Service em `MQL5/Services/MKS-ULTIMATE/`. Captura empírica de 1h+ no broker EXNESS XAUUSDm gera o primeiro `.mkstick` real.
- **Slice 24e** — `Replayer.mq5` EA em `MQL5/Experts/MKS-ULTIMATE/`. Consome o `.mkstick` do 24d, monta composition root completo fora do Tester, gera `replay.mksbk`.
- **Slice 24f** — `tools/verify-parity.ps1` (fecha a dívida da Fase 8 — log-diff tool), `REGRAS.md §1.9` (proibições replay-safe na estratégia), `PROTOCOLOS.md` Protocolo 1 (item de paridade), `ROADMAP.md` Fase 4.5 declarada concluída se §7 da ADR-024 passar com janela ≥1h sem divergências.

Códigos de erro reservados-por-comentário a materializar em 24d/24e:
- 808 — `MKS_ERR_DATA_PROVENANCE_MISMATCH`
- 809 — `MKS_ERR_DATA_REOPEN_INCOMPATIBLE`
- 810 — `MKS_ERR_DATA_SEQ_DISCONTINUITY`

### 6.2 Outras pendências de fases

- **ADR-008** (gap de fim-de-semana no RenkoBuilder) — única ADR formal pendente. Sem urgência; será decidida quando aparecer dor.
- **Fase 7 — StressLab** — totalmente atacável sem mercado (envolve modelagem aplicada sobre `CMksSimulatedBroker` + `CMksCostModel`).
- **Fase 9 — EA validação end-to-end** — depende de ADR-024 completa.

### 6.3 Branches preservadas localmente

Quatro branches `feat/*` e `docs/*` ainda existem localmente após os merges no-ff. Podem ser apagadas com `git branch -d <name>` quando você quiser limpar — não fiz por padrão.

---

## 7. Próximos passos sugeridos

Em ordem de prioridade arquitetural:

1. **Quando mercado abrir (segunda)**: Slice 24d → 24e → 24f para fechar ADR-024. Daí a Fase 4.5 fica concluída e a paridade bit-a-bit fica validada empiricamente.
2. **Independente de mercado**: Fase 7 (StressLab) é a próxima frente substancial atacável sem mercado. Envolve criar `CStressLabEngine` que envolve o `CMksSimulatedBroker` injetando spread multiplier, slippage distribution, latência, rejeição etc. Permite criar pipeline normal → stress leve → stress médio → stress alto antes de existir EA real.
3. **Eventualmente**: ADR-008 (gap fim-de-semana) — só docs, baixo custo, pode entrar em qualquer hora morta.

---

## 8. Comandos úteis para próximo chat

```powershell
# Estado do branch
git log --oneline --graph -15

# Compile headless do produto inteiro (manual; o watcher faz isso automaticamente)
& "C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe" /compile:"<path/to/file.mq5>" /log:"<temp.log>"

# Limpar branches já mergeadas
git branch -d docs/adr-024-tick-recorder-replayer
git branch -d feat/slice-6.2-risk-per-strategy
git branch -d feat/slice-6.3-risk-per-account
git branch -d feat/slice-5b-trade-manager

# Watcher (auto-start via .vscode/tasks.json; manual:)
powershell -ExecutionPolicy Bypass -File c:\dev\MKS-ULTIMATE\tools\watch-compile.ps1
```

---

**Sessão de sábado 2026-05-23 fechada. Push realizado junto deste commit.**
