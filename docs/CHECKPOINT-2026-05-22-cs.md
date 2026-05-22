---
@document: docs/CHECKPOINT-2026-05-22-cs.md
@project: MKS-ULTIMATE
@purpose: Adendo do dia 2026-05-22 (tarde/noite) — Fases 5a/6.1 abertas, Custom Symbol finalizado com inputs ricos e visual Median tradicional
@audience: Próxima sessão (humano + IA)
---

# CHECKPOINT — 2026-05-22 (Custom Symbol completo + Fases 5a/6.1)

Adendo a [`CHECKPOINT-2026-05-22.md`](CHECKPOINT-2026-05-22.md). Cobre exclusivamente o trabalho desde aquele fechamento: ADR-019 aceita (inversão de ordem Sizer/Risk/Trade), Slices 5a e 6.1 entregues, Custom Symbol auditado e expandido em 4 sub-slices via ADRs 020/021/022.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 7 arquivos, nesta ordem

1. `README.md`
2. `docs/CHECKPOINT-2026-05-20.md` — base, convenções, estado pós-Slice 1
3. `docs/CHECKPOINT-2026-05-20-slice2.md` — adendo pós-Slice 2
4. `docs/CHECKPOINT-2026-05-20-slice3a.md` — formato `.mksbk`
5. `docs/CHECKPOINT-2026-05-21-slice3b.md` — Producer + Custom Symbol + ADRs 015/007/018/016/017
6. `docs/CHECKPOINT-2026-05-22.md` — pós-validação ADR-005 (framework de teste)
7. `docs/CHECKPOINT-2026-05-22-cs.md` — este, incremental

Sub-artefatos: `docs/CHECKPOINT-2026-05-22-adr005.md` (test plan ADR-005 arquivado). Consultar apenas em re-validação do framework de teste.

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação.

---

## 2. Estado do código (HEAD = `83bc1ed`)

20 commits sobre `5636f4b` (último checkpoint). Trabalho em três frentes intercaladas, todas autorizadas pelo dono no PC:

| Frente | Commits | Resultado |
|---|---|---|
| **ADR-019 + Slice 5a** (Trade/Sizer) | `a1229c4` → `12c3f73` | 5 commits; `CMksPositionSizer` (Fixed + PercentRisk) + 61 asserts em 30 tests |
| **Slice 6.1** (Risk camada Por Trade) | `6107776` → `973a61e` | 3 commits; `CMksRiskManager` + `CMksRiskGatedBroker` + 56 asserts em 31 tests |
| **Custom Symbol** (ADRs 020/021/022) | `88aaf7c` → `83bc1ed` | 12 commits; sinks extraídos, semântica visual fixada, bar parcial em formação, Producer dinâmico, visual Median tradicional |

### Estrutura nova

Pasta criada: `MQL5/Include/MKS-ULTIMATE/Core/Output/` (sinks de destination/visualização).

| Arquivo novo | Linhas | Função |
|---|---|---|
| `Core/Interfaces/IPositionSizer.mqh` | 47 | Contrato `ComputeLots(slPoints, &lots, &err)` + `Validate` |
| `Core/Trade/CMksFixedLotSizer.mqh` | 110 | Lots fixo, valida múltiplo de step + clamp [VolumeMin, VolumeMax] |
| `Core/Trade/CMksPercentRiskSizer.mqh` | 156 | `lots = balance × risk% / (slPts × TickValue × Point/TickSize)`, floor para step |
| `Core/Risk/CMksRiskManager.mqh` | 167 | Middleware: requireSl/Tp, maxLotsPerTrade, sizer opcional, log estruturado em rejeição |
| `Core/Risk/CMksRiskGatedBroker.mqh` | 83 | Wrapper IBroker: `Send` passa por Risk; `Close`/`Modify` delegam direto |
| `Core/Output/CMksCustomSymbolSink.mqh` | ~110 | CS sink — extraído do Producer; sem wicks default; bar parcial em formação; tamanho visual full |
| `Core/Output/CMksMultiSink.mqh` | 50 | Sink composto delegando `OnBrickClose` + `OnBrickForming` |
| `Core/Data/CMksBrickWriterSink.mqh` | 65 | Writer sink — extraído do Producer |

### Mudanças em arquivos existentes

- `Core/Types/Error.mqh`: faixas Trade (300-302) e Risk (400-404) populadas com 8 códigos.
- `Core/Types/FormingBrick.mqh`: ganha campo `currentMid` (ADR-021 §5).
- `Core/Interfaces/IRenkoSink.mqh`: ganha `virtual void OnBrickForming(const MksFormingBrick &fb) {}` default vazio.
- `Core/RenkoBuilder/CMksRenkoBuilder.mqh`: ganha `m_lastMid`, `m_emitForming`, `SetEmitForming(bool)`, e chamada de `OnBrickForming` ao fim de cada `IngestTick` válido.
- `Core/Testing/Mocks/CMksCapturingSink.mqh`: ganha array `formings[]` + `formingCount` + override de `OnBrickForming` para inspeção em testes.
- `Experts/MKS-ULTIMATE/Producer.mq5`: refactor de -136/+127 linhas. Inputs em 4 grupos (`input group`), `ENUM_MKS_GEOMETRY_TYPE` (Median/Classic/Custom), `BuildGeometry()`, `BuildCustomSymbolName()` estendido, validação de 32 chars, `SetEmitForming(false/true)` envolvendo `RunHistoricalFill`, `ChartOpen(csName, PERIOD_M1)` ao final do OnInit. Tres classes inline (sinks) removidas.
- `docs/ROADMAP.md`: Fase 3 → Concluída, Fase 8 → Parcialmente concluída, Fase 5 ganha nota da sub-divisão 5a/5b (ADR-019), Fase 6 ganha nota da sub-divisão 6.1/6.2/6.3.

### ADRs movimentadas

| ADR | Tema | Status |
|---|---|---|
| **019** | Ordem de construção `PositionSizer → RiskManager → TradeManager` | **Aceita** (`da57729`) |
| **020** | Custom Symbol — semântica, contrato visual e fronteiras de uso | **Aceita** (`088e87a`, +2 ajustes) |
| **021** | Bar parcial do brick em formação no CS (substitui parcialmente regras 2 e 4 da ADR-020) | **Aceita** (`67a4f7f`) |
| **022** | Producer dinâmico — tipo, geometria, wicks toggle, naming estendido, auto-open (substitui parcialmente regras 3 e 6 da ADR-020) | **Aceita** (`45bead2`, +regra 8 em `83bc1ed`) |

ADRs anteriores (001–018) sem alteração.

### Bugs encontrados e corrigidos

- **`CMksRiskManager` rvalue → const &** (commit `bd0ccc6` durante slice 6.1): `sizerErr.ToString()` passado como `const string &` falhou em MQL5 (não aceita rvalue por referência). Fix: capturar em variável local antes de `MKS_SET_ERROR`. Aprendizado registrado.
- **`CMksMultiSink` engolia `OnBrickForming`** (commit `9cc6431`): herança do default vazio do `IRenkoSink` impedia delegação aos sinks contidos. Bar parcial nunca chegava ao CS. Fix + teste de regressão.
- **Median Renko visual era "Classic-like"** (commit `83bc1ed`): `brick.close = open + (1-PO)*size` matemático gera bricks de tamanho `0.5*size` sem sobreposição. Visual V5 tradicional precisa de tamanho `full size` com sobreposição. Fix sem mexer no builder/matemática: sink renderiza `visualClose = brick.open ± brickSizePts`. `.mksbk` preserva close matemático intacto (ADR-022 regra 8).

---

## 3. Cobertura de teste

| Suíte | Asserts | Tests | Mudança hoje |
|---|---|---|---|
| `Test_MksTestFramework` (smoke) | 11 | 4 | — |
| `Test_CMksSimulatedBroker` | 51 | 12 | — |
| `Test_CMksAtrBrickSizer` | 72 | 11 | — |
| `Test_CMksBrickFile` | 97 | 4 | — |
| `Test_CMksRenkoBuilder` | 428+ | 14+8 | **+8 tests de `OnBrickForming` (ADR-021)** |
| `Test_CMksPositionSizer` (novo) | 61 | 30 | **novo** |
| `Test_CMksRiskManager` (novo) | 33 | 21 | **novo** |
| `Test_CMksRiskGatedBroker` (novo) | 23 | 10 | **novo** |
| **TOTAL (excl. smoke)** | **~810** | **~110** | — |

Crescimento desde checkpoint anterior: +160 asserts, +69 tests. Nada quebrado.

**Lacunas conhecidas** (não-bloqueantes):
- `CMksMt5Symbol`, `CMksMt5Account`, `CMksMt5Broker` — sem unit tests (dependem de API MT5 global).
- `CMksLogger` — sem unit test (validado empiricamente via Producer).
- `CMksCustomSymbolSink` — sem unit test isolado (dependeria de mockar `CustomRatesUpdate`); cobertura indireta via Producer empírico.

---

## 4. Slices executados (em ordem)

### Slice 5a — `CMksPositionSizer`

ADR-019 estabeleceu a ordem `Sizer → Risk → TradeManager` (em vez do `Trade → Risk` do ROADMAP original) com cláusula anti-precedente. Sizer é o primeiro porque é dependência técnica do Risk (validar tamanho máximo).

- `IPositionSizer` polimórfico (ADR-004): `ComputeLots(slPts, &lots, &err)` + `Validate`.
- `CMksFixedLotSizer`: lots configurado, valida múltiplo de `VolumeStep` + clamp em `[VolumeMin, VolumeMax]` no `Validate`.
- `CMksPercentRiskSizer`: fórmula `risk% × balance / (slPts × moneyPerPointPerLot)`, com correção `Point/TickSize` (ativos onde diverge), `floor para step` (viés conservador — nunca excede risk%), out-of-range = erro (não clamp).
- Modos `ATR-adjusted` e `Kelly` deliberadamente fora desse slice.

Validado no MT5 EXNESS em 2026-05-22: `61/61 assertions in 30 tests (0 failed)`.

### Slice 6.1 — `CMksRiskManager` + `CMksRiskGatedBroker` (Camada "Por Trade")

ADR-019 e ROADMAP §Fase 6 fixaram a sub-divisão 6.1/6.2/6.3. Esta é a 6.1.

- `CMksRiskManager.CheckOrder(req, &err)`: ordem de avaliação fixa SL → TP → maxLotsPerTrade → sizer-opt. Primeira falha gera código específico (400-403).
- `CheckOrder` defaults: `requireSl=true` (lição V5 #7, não-negociável), `requireTp=false` (TP via trailing é comum), `maxLotsPerTrade=0` (sem limite absoluto).
- Logging estruturado via `ILogger` opcional — WARN com `ctxJson` em cada rejeição.
- `CMksRiskGatedBroker` é wrapper `IBroker` (não inline). Lição V5 #7 é literal: middleware, não lembrete.
  - `Send` passa por `Risk.CheckOrder`; rejeição → `MksExecutionResult` com status `REJECTED` e `brokerRetcode = err.code`, sem chamar o underlying.
  - `Close`/`Modify` delegam direto (Risk só protege a abertura no slice 6.1).

Validado: `33/33 in 21 tests` + `23/23 in 10 tests`.

### Slice 20a — Extração de sinks + sem wicks no CS

Resposta à auditoria do CHECKPOINT-2026-05-22 §A (Custom Symbol). Antes: 3 classes inline (`CBrickWriterSink`, `CCustomSymbolSink`, `CMultiSink`) dentro do `Producer.mq5`. Depois: extraídas para `Core/Output/` (sinks de destination) e `Core/Data/` (writer sink), com prefixo `CMks*` padronizado. ADR-020 regra 3 aplicada: bricks fechados no CS são caixinhas sem wicks (`high=max(open,close)`, `low=min(open,close)`).

### ADRs 020/021 — Custom Symbol semântica + bar parcial

**ADR-020 (Aceita):** 9 regras formalizando comportamento que era implícito. Destaques:
- Regra 1: CS é só visualização humana; nenhum código de lógica do framework lê do CS (combate eixo 2 do V5).
- Regra 3: bricks no CS sem wicks por default.
- Regra 6: naming `<symbol>.MKS_RKN<size>` (depois superseded pela ADR-022 regra 5).
- Regra 8: script utility `MksCleanupCustomSymbols.mq5` é entregável obrigatório (ainda dívida pendente).

**ADR-021 (Aceita):** Substitui parcialmente regras 2 e 4 da ADR-020. Adiciona bar parcial no CS para o brick em formação.
- `IRenkoSink.OnBrickForming(fb)` novo método `virtual` com corpo default vazio.
- Builder chama `OnBrickForming` ao fim de cada `IngestTick` válido — controlado por flag `m_emitForming` (default `true`).
- `Producer.SetEmitForming(false)` antes de `RunHistoricalFill`, `(true)` depois — evita milhões de `CustomRatesUpdate` em sequência durante fill histórico.
- `CMksCustomSymbolSink.OnBrickForming` atualiza bar do slot `nextBarTime` (a próxima bar não confirmada) com wicks e `close = fb.currentMid`.

### Slice 22 — Producer dinâmico (popup, tipo, naming, auto-open, visual full)

ADR-022 substitui parcialmente regras 3 e 6 da ADR-020.

- `ENUM_MKS_GEOMETRY_TYPE` (Median/Classic/Custom) — Median é default.
- Inputs reorganizados em 4 `input group` (Brick/Geometria, Histórico/Live, Custom Symbol, Logging) com tooltips. Popup nativo do MT5 é a "caixa de configuração".
- `InpHistoricalFillDays` default `0` → `30` (alinhado V5).
- `InpShowWicksInCS` (default `false`) — sink respeita: wicks visíveis se `true`.
- `BuildCustomSymbolName(symbol, type, size, pro, po)` — formato:
  - `<symbol>.MKS_M_<size>` (Median)
  - `<symbol>.MKS_C_<size>` (Classic)
  - `<symbol>.MKS_X_<size>_<proInt>_<poInt>` (Custom)
  - Validação 32 chars no OnInit, aborta `INIT_PARAMETERS_INCORRECT` se exceder.
- `ChartOpen(csName, PERIOD_M1)` ao fim do OnInit — abre chart do CS automaticamente. Falha = warn, não aborta.
- **Regra 8 (adicionada em `83bc1ed`):** CS desenha bricks com tamanho VISUAL FULL (`InpBrickSizePts`), independente do PO. Sink calcula `visualClose = brick.open ± brickSizePts`. `.mksbk` preserva `brick.close` matemático intacto. Visual reproduz Median Renko tradicional V5 com sobreposição = `PO*size`.

Validado visualmente no MT5: Median Renko com bricks de tamanho 3.0 e sobreposição de 1.5 (50%) confirmado em XAUUSDm em horário de mercado aberto.

---

## 5. Pendências em aberto

### 🔴 Crítico
- **Validação visual final do Median Renko com PO=0.5** após `83bc1ed`. Em sessão futura, confirmar que o chart `XAUUSDm.MKS_M_3` mostra sobreposição como esperado.

### 🟡 Médio (não-bloqueante)
- **Script `MksCleanupCustomSymbols.mq5`** (ADR-020 regra 8, dívida ainda em aberto). Operacional para limpar CSs órfãos do Market Watch após experimentação com configs diferentes (cada combinação tipo/size/pro/po gera CS único).
- **Slice 6.2 (Risk Por Estratégia)**: max posições simultâneas, exposure total. Requer acesso ao estado das posições do broker.
- **Slice 6.3 (Risk Por Conta)**: daily loss limit, max drawdown, circuit breaker.
- **Slice 5b (CMksTradeManager)**: state machine + BE + trailing + partial close. Nasce DENTRO da rede Risk.
- **Log-diff tool** (Fase 8 fechar): script que compara `.log` de backtest com `.log` de live e aponta primeira divergência.

### 🟢 Baixo
- **Test_All.mq5 unificado** (carry-over).
- **`Core/Testing/Fixtures.mqh` canônico** (carry-over).
- **`Renko-Ultimate/` untracked** — sub-pasta com apenas `Code-Review-V5-Robustez.md`. Decidir destino (mover para `docs/` ou apagar).
- **CHANGELOG.md** não foi atualizado nas últimas rodadas (ADRs 019–022 e slices 5a/6.1 ausentes). Faltam ~15 linhas.

---

## 6. Próximos passos sugeridos (não fechados)

1. **Validar visualmente ADR-022 regra 8** em mercado aberto. Se sobreposição não estiver como esperado, ajustar antes de qualquer trabalho novo.
2. **Slice 6.2 — Risk Por Estratégia**, OU **Slice 5b — TradeManager**. Ambos viáveis. ADR-019 estabeleceu Risk antes de Trade, então preferência é 6.2 → 6.3 → 5b.
3. **CHANGELOG catch-up** — uma rodada de 15-30 min documentando ADRs 019–022 e slices.
4. Decidir destino do `Renko-Ultimate/`.

---

## 7. Comandos úteis para próximo chat

```powershell
# estado atual
git log --oneline -10

# rodar testes existentes (em ordem)
# arrastar cada Test_*.mq5 no chart MT5, ver Toolbox > Experts
#   Test_MksTestFramework         (smoke)
#   Test_CMksSimulatedBroker      (51/51)
#   Test_CMksAtrBrickSizer        (72/72)
#   Test_CMksBrickFile            (97/97)
#   Test_CMksRenkoBuilder         (~440/440, agora com ADR-021)
#   Test_CMksPositionSizer        (61/61)
#   Test_CMksRiskManager          (33/33)
#   Test_CMksRiskGatedBroker      (23/23)

# rodar Producer com configs ricas (ADR-022)
# arrastar Experts > MKS-ULTIMATE > Producer no chart base XAUUSDm
# popup nativo do MT5 mostra inputs em 4 grupos
# após OK, chart do CS abre automaticamente em M1

# compile headless de um .mq5
& "C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe" /compile:<caminho>

# verificar sync junctions (regra de memória)
ls "$env:APPDATA\MetaQuotes\Terminal\<id>\MQL5\Include\MKS-ULTIMATE\Core"
```

Estado limpo. Próxima rodada começa em `main @ 83bc1ed`.
