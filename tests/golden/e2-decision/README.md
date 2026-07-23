# Golden bundle — E2.2: determinismo da decisão sobre feed REAL

Este bundle versiona a prova empírica do **gate central do E2** (paridade/determinismo da
camada de decisão), obtida em 2026-07-21 sobre feed real da Exness. É a rede de regressão:
qualquer mudança futura no caminho `feed → builder → estratégia → risco → conta → broker`
que altere as decisões vai divergir destes journals golden.

**Reframe honesto (inegociável):** prova **determinismo sim↔sim** (runner↔runner) + paridade
feed→brick. **NÃO** prova paridade live-broker↔replay (estruturalmente impossível — o SL real
dispara em tick/preço que o sim não reproduz). Proibido afirmar "H4 fechado".

## Conteúdo

| Arquivo | O quê |
|---|---|
| `XAUUSDm_CR_20260720T233245.mkstick` | Fixture: ~33.546 ticks reais do XAUUSDm (Exness, digits=3, ~2,1 MB), capturados pelo `ColorReversal` (`InpRecordMkstick=true`, `InpHistoricalFillDays=0`). 32 bricks, 17 flips. |
| `baseline.golden.tsv` | Journal golden da **config A** (gates de conta inativos) — **33 decisões / 17 flips**. |
| `gate-minequity.golden.tsv` | Journal golden da **config B** (breaker absoluto ativo) — **18 decisões**: 1 trade + REJECTs `409 min_equity_breached`. |

## Config comum (DecisionReplayer)

`InpBrickSize=3.0`, `L=10`, `K=20`, `InpSlBricks=10` (ADR-032 → 30000 pts = 10 bricks em digits=3),
`InpMagic=527001`, `InpLotMode=FIXED`, `InpFixedLots=0.01`, `InpStartBalance=10000`,
custos `InpSpreadPts=InpSlipPts=InpCommPerLot=0`, `InpMinSlBricks=1`, `InpMaxOpenPositions=1`.

- **Config A (baseline):** `InpMaxDailyLossPct=0`, `InpMaxDrawdownPct=0`, `InpMinEquityAbs=0` (gates inativos).
- **Config B (gate-crossing):** igual à A, mas **`InpMinEquityAbs=9990`** — o breaker de conta
  (código 409, a proteção que faltou no V5) dispara após o 1º trade e rejeita todo Send seguinte.

## Reproduzir

1. Copie `XAUUSDm_CR_20260720T233245.mkstick` para `<terminal>\MQL5\Files\MKS-ULTIMATE\Ticks\`
   (o MT5 lê ticks só de dentro de `MQL5\Files\`). Garanta o **XAUUSDm no Market Watch**
   (o replay lê Point/tickSize do símbolo vivo).
2. Rode o `DecisionReplayer` **2×** com a config A (só mudando `InpJournalPath` → `run1.tsv`/`run2.tsv`)
   e **2×** com a config B (`gate1.tsv`/`gate2.tsv`).
3. Verifique o determinismo (dois runs da MESMA config → idênticos) e a regressão (run vs golden):
   ```powershell
   # determinismo (run↔run)
   tools\verify-parity.ps1 -JournalA <...>\run1.tsv  -JournalB <...>\run2.tsv   # → exit 0, 33 decisões
   tools\verify-parity.ps1 -JournalA <...>\gate1.tsv -JournalB <...>\gate2.tsv  # → exit 0, 18 decisões
   # regressão (run↔golden) — compara contra este bundle
   tools\verify-parity.ps1 -JournalA <...>\run1.tsv  -JournalB tests\golden\e2-decision\baseline.golden.tsv
   tools\verify-parity.ps1 -JournalA <...>\gate1.tsv -JournalB tests\golden\e2-decision\gate-minequity.golden.tsv
   ```
   `verify-parity` ignora as linhas `#` do header (proveniência/timestamps que variam entre sessões);
   compara o cabeçalho de colunas + as linhas de decisão. **exit 0 em todos = golden intacto.**

## Resultado registrado (2026-07-21)

Ambas as configs deram `verify-parity` **exit 0** entre dois replays independentes:
- baseline: `decision journals IDÊNTICOS (33 decisões)`
- gate:     `decision journals IDÊNTICOS (18 decisões)`

O determinismo da camada de decisão — incluindo o **breaker de conta** — está demonstrado sobre
feed real. Ver `CHANGELOG.md [Não lançado]` e a Fase E2 de `docs/ROADMAP-CORE-HARDENING.md`.

## Automatizado (2026-07-24)

- **`Test_RealTickGolden.mq5`** — golden de BRICKS headless (fixture → `CMksRenkoBuilder` →
  compara records vs `../e2-brick/`).
- **`Test_DecisionGolden.mq5`** — golden de DECISÃO headless: roda o `CMksDecisionRunner` sobre este
  fixture (config A) e compara o journal produzido contra `baseline.golden.tsv`, **ignorando as
  linhas `#`** (mesma normalização do `verify-parity`), falhando o `TestRunner` em divergência.
  Substitui o procedimento manual acima pela config A. **Setup:** copiar o fixture **e**
  `baseline.golden.tsv` para `<terminal>\MQL5\Files\MKS-ULTIMATE\golden\` (o `Files/` é gitignorado).
- A âncora do E2.3 (`seedMid`/`seedTickSeq`) já aparece no header do journal (linha `# ANCHOR`) —
  ignorada no diff, mas reforça a proveniência.

## Pendente

- Automatizar também a **config B** (gate-crossing, `InpMinEquityAbs=9990` → `gate-minequity.golden.tsv`)
  no mesmo molde do `Test_DecisionGolden` (hoje só a config A está automatizada).
