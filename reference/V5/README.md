# V5 — `MKS-Framework-Renko` (projeto anterior)

Código-fonte completo do **V5**, projeto Renko anterior do dono. Mantido neste repo como **referência arquitetural e histórica**, NÃO como base de evolução.

## Aviso importante

O V5 quebrou conta em 4 horas de operação live em 2026 após backtests aparentemente excelentes. A análise de causa-raiz está em [`docs/V5-POSTMORTEM.md`](../../docs/V5-POSTMORTEM.md). Os 4 eixos principais do colapso:

1. Estratégia operando sobre `close` matemático do brick, não sobre preço observado.
2. Backtest e live produzindo bricks por caminhos diferentes (5 produtores distintos identificados na auditoria).
3. Custos de execução simulados sem afetar o equity do backtest.
4. Bifurcação de lógica entre backtest e live via input booleano.

**Nada do V5 deve ser usado como base do MKS-ULTIMATE.** O framework atual é uma reconstrução do zero com decisões arquiteturais documentadas em ADRs (`docs/ARCHITECTURE.md`).

## Conteúdo da pasta

| Arquivo | Tamanho | Função |
|---|---|---|
| `V5--Core.mqh` | 25KB | Motor Renko (auditado — ver V5-POSTMORTEM Eixos 1-2) |
| `V5-Renko-Types.mqh` | 22KB | Tipos / enums / parsing de Custom Symbol |
| `V5-Logger.mqh` | 20KB | Logger inline (com bug de `RemoveComponentFilter` documentado no code-review) |
| `V5-Generator.mq5` | 25KB | Gerador de histórico — chunks de 1 dia para evitar OOM |
| `V5-LiveEngine.mq5` | 33KB | Motor live — confirmou divergência de paths com Generator |
| `V5-CE-PRO.mq5` | 91KB | Strategy Engine com simulação StressLab embutida (auditado Eixo 3) |
| `V5-Dashboard.mq5` | 150KB | Painel V5 (3.069 linhas, paleta SaaS Navy/Slate) — referência visual para `CMksProgressPanel` |
| `V5-Dashboard2.mq5` | 150KB | **Idêntico ao Dashboard.mq5** (bit-a-bit, 149.893 bytes) — duplicação |
| `V5-PanelBridge.mqh` | 6KB | Bridge via GlobalVariables (interface assíncrona) |
| `V5-ProgressPanel.mqh` | 13KB | Classe `CProgressPanel` — referência direta de API para `CMksProgressPanel` |
| `MKS-Dashboard.mq5` | 0 bytes | Arquivo vazio (provavelmente placeholder remanescente) |
| `MKS-Dashboard2.mq5` | 0 bytes | Arquivo vazio (provavelmente placeholder remanescente) |

## Material extraído do V5 para o MKS-ULTIMATE

| Origem (V5) | Destino (MKS-ULTIMATE) | ADR/Slice |
|---|---|---|
| Paleta SaaS Navy (Dashboard linhas 44-92) | `CMksProgressPanel` cores | Slice 23b |
| API `CProgressPanel` (Init/UpdateStatus/Finish/ShowError/Clear) | `CMksProgressPanel` API | Slice 23b |
| Estrutura de chunks por dia (Generator) | Sem aplicação direta (Producer faz CopyTicksRange único + chunks por timer) | ADR-022 |
| Naming `<symbol>_MKS_<size>_<mode>_<preset>` | Naming estendido `<symbol>.MKS_<typeCode>_<size>[_<pro>_<po>]` | ADR-022 regra 5 |
| Algoritmo de threshold caminhado | `CMksRenkoBuilder` (re-desenhado com guarda K=20) | ADR-010, ADR-011 |
| **Bifurcação live/backtest** | **Rejeitada** — Producer único combate Eixo 2 | ADR-013, ADR-015 |
| **Estratégia em close matemático** | **Rejeitada** — `triggerPrice` exposto em `MksBrick` | Eixo 1, ADR-010 §5 |

## Auditoria documentada

A auditoria completa do V5 está em três lugares:

1. [`docs/V5-POSTMORTEM.md`](../../docs/V5-POSTMORTEM.md) — análise de causa-raiz dos 4 eixos.
2. [`Renko-Ultimate/Code-Review-V5-Robustez.md`](../../Renko-Ultimate/Code-Review-V5-Robustez.md) (gitignored) — 30+ bugs e armadilhas identificados linha por linha. Material privado, não vai pro repo público.
3. [`docs/CHECKPOINT-2026-05-23.md`](../../docs/CHECKPOINT-2026-05-23.md) §3 — auditoria do Dashboard + ProgressPanel para extração visual.

## Política de uso

- ✅ **Consultar** quando precisar entender por que uma decisão do MKS-ULTIMATE foi tomada (motivação histórica).
- ✅ **Comparar** API/visual quando trabalhando em features de UX (painel, dashboards futuros).
- ❌ **NUNCA copiar código** para o MKS-ULTIMATE sem revisão crítica explícita (ADR documentando a importação).
- ❌ **NUNCA basear nova estratégia** no V5 — todas as 5 lições do POSTMORTEM se aplicam.

Última atualização: 2026-05-23.
