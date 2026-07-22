# Golden bundle — E2.2: paridade feed→brick sobre ticks REAIS (rede de regressão headless)

Este bundle versiona o **golden de BRICKS** do E2.2: o `CMksRenkoBuilder` (o produtor único)
rodando sobre um fixture `.mkstick` real, com o resultado comparado **campo a campo** contra
um `.mksbk` golden. Diferente do golden da decisão (`../e2-decision/`, que prova a camada de
decisão via `verify-parity.ps1` **manual**), este é **automatizado** no `TestRunner`:
`Test_RealTickGolden.mq5` falha a suíte em qualquer divergência.

**Reframe honesto (inegociável):** prova **paridade feed→brick determinística** (o builder,
wired canonicamente, reproduz o golden bit-a-bit) — a rede de regressão que pega qualquer
mudança futura no builder/geometria/L/K que altere os bricks. **NÃO** prova paridade
live-broker↔replay (estruturalmente impossível). Não afirmar "H1/H4 fechado" além disso.

## Conteúdo

| Arquivo | O quê |
|---|---|
| `XAUUSDm_CR_20260720T233245.golden.mksbk` | Golden: os bricks que o `CMksRenkoBuilder` produz sobre o fixture (gerado 1× via `InpRegenGolden=true`, ver abaixo). ~32 bricks. |
| _(fixture)_ | **Compartilhado** com `../e2-decision/XAUUSDm_CR_20260720T233245.mkstick` (~33.546 ticks reais XAUUSDm/Exness, digits=3, ~2,1 MB) — não duplicado aqui. |

## Bênção do golden (por que é CORRETO, não só consistente)

O golden usa o **mesmo fixture** do golden da decisão (`../e2-decision/`). Aquele bundle já
está validado: `verify-parity` **exit 0** sobre este feed → **33 decisões / 17 flips**
(`baseline.golden.tsv`). Os 17 flips vêm exatamente das reversões de cor dos **32 bricks**
deste golden — então os bricks que dirigem uma decisão já-aceita estão corretos. Cross-check:
`Test_Producer.mq5` (reconstrução textbook independente do Renko classic) continua disponível
como verificação manual de correção (fora da suíte automatizada).

## Config (espelha o Producer/Replayer e o golden da decisão)

`InpBrickSize=3.0`, `L=10` (`InpInvalidTickLimit`), `K=20` (`InpThresholdLimit`), geometria
**classic** (po=pro=0, rev=1). Comparação **exata** de todos os campos do brick: `direction`,
`thresholdsCrossed`, `open`, `close`, `high`, `low`, `triggerPrice`, `triggerTickId`,
`closeTimeMsc`, `volume`. O `createdAtMsc` (wall-clock) do header **não** é comparado.

## Setup + execução (o `Files/` do MT5 é gitignorado)

O MT5 lê de `<terminal>\MQL5\Files\` apenas. O setup copia fixture + golden para lá.

1. **Setup** — copie o fixture e o golden para `<terminal>\MQL5\Files\MKS-ULTIMATE\golden\`:
   - fixture: `tests\golden\e2-decision\XAUUSDm_CR_20260720T233245.mkstick`
   - golden:  `tests\golden\e2-brick\XAUUSDm_CR_20260720T233245.golden.mksbk`
   (Garanta o **XAUUSDm no Market Watch** — o source lê metadados do símbolo.)
2. **Rodar o teste** — anexe/execute o Script `Test_RealTickGolden` (defaults). Espera-se
   `N/N assertions ... (0 failed)` na aba Experts.

## (Re)gerar o golden

Só quando o builder mudar **intencionalmente** (novo comportamento aceito). Com o fixture já
em `Files\MKS-ULTIMATE\golden\`, rode `Test_RealTickGolden` com **`InpRegenGolden=true`** →
escreve `...golden.mksbk` em `Files\`. Commite o arquivo aqui (`tests\golden\e2-brick\`) e
rode de novo com `InpRegenGolden=false` (deve dar verde). **Regenerar é um ato deliberado** —
um golden que muda sem intenção é uma regressão mascarada.
