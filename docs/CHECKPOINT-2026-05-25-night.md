---
@document: docs/CHECKPOINT-2026-05-25-night.md
@project: MKS-ULTIMATE
@purpose: Adendo da sessão noturna de 2026-05-25 — validação empírica parcial da ADR-024 (bloqueada por holiday US/UK), bugs descobertos in-vivo e corrigidos, auditoria forense de 3 frentes (resíduos median + semântica "Pts" + modos de brick), refactor de sizer factory expondo CMksAtrBrickSizer ao Producer. Estado final preparado para próxima sessão de auditoria.
@audience: Próxima sessão (humano + IA) — em especial auditor de divergências
---

# CHECKPOINT — 2026-05-25 (sessão noturna)

Adendo aos checkpoints anteriores do dia: [`CHECKPOINT-2026-05-25.md`](CHECKPOINT-2026-05-25.md) (cobriu a sessão atravessando 24→25, com auditoria forense + Bloco 1 + slices 24c-f + Bloco 3) e [`CHECKPOINT-2026-05-25-audit.md`](CHECKPOINT-2026-05-25-audit.md) (cobriu auditoria documental complementar com lotes A/B2/B3). Este documento cobre a etapa noturna que veio depois desses dois.

**Marco do ciclo:** **Tentativa de validação empírica end-to-end do pipeline ADR-024**. Bloqueada por dia de feriado (Memorial Day US + Spring Bank Holiday UK), mas a tentativa revelou 2 bugs reais que foram corrigidos in-vivo, motivou uma auditoria forense em 3 frentes específicas pedida pelo dono, e resultou em refactor que expõe o `CMksAtrBrickSizer` (pronto desde 2026-05-21 mas até hoje inacessível ao operador).

**Próxima sessão será auditoria completa em busca de divergências** — este checkpoint foi escrito como guia explícito do que mudou, deixando trilhas para o auditor encontrar pontos suspeitos.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 13 arquivos, nesta ordem

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
13. `docs/CHECKPOINT-2026-05-25-night.md` — este (validação empírica parcial + auditoria de 3 frentes + refactor sizer)

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação.

---

## 2. Estado do código

Branch ativa: `feat/producer-classic-only`, sincronizada com `origin/feat/producer-classic-only` no momento da escrita.

### Histórico desta etapa noturna (sobre os 7 commits já existentes do início do dia)

```
e95d52a  refactor(producer): InpBrickSize + sizer factory (Fixed/ATR) + naming honesto     ← HEAD
3e2b87e  fix(experts): Producer com InpHistoricalFillDays=0 nao transitava p/ live
72e50fd  fix(experts): Replayer PathStem corta no ultimo separator
70956fc  feat(tools): DumpMksTick script — inspecao visual de .mkstick
079e452  docs: sync per audit 2026-05-25 + lote A + lote B2/B3                              ← commit do dono / auditoria documental
8881977  feat(tools): PreloadHistory script — prepara cache de ticks pre-ADR-024 empirico
e712c13  docs: CHECKPOINT 2026-05-25 (sessao atravessando 24-25/05)                         ← último commit anterior a esta etapa
```

**Totais da etapa noturna:** 5 commits (8881977 → e95d52a), `~770 linhas líquidas adicionadas` (PreloadHistory + DumpMksTick + 2 fixes + refactor + CHANGELOG), 0 regressões em **37/37 .mq5** validados via `compile-all.ps1`.

### ADRs aceitas

**24/24 ADRs aceitas + notas de esclarecimento acumuladas.** §4 Decisões Pendentes da `ARCHITECTURE.md` continua vazia. Esta sessão não acrescentou ADR formal — apenas trabalho de implementação e refactor sobre ADRs já existentes (especialmente ADR-018 que materializou o `CMksAtrBrickSizer` em 2026-05-21 e agora ganhou exposição via input do Producer).

---

## 3. Ciclo cronológico desta etapa

### 3.1 PreloadHistory.mq5 — preparação do cache de ticks (commit `8881977`)

**Motivação:** o pipeline ADR-024 exige que o terminal MT5 tenha cache local de ticks dos N dias requeridos pelo `InpHistoricalFillDays` do Producer. `CopyTicksRange` lê do cache; se vazio, retorna 0 e o fill histórico falha.

**Arquivo:** `MQL5/Scripts/MKS-ULTIMATE/PreloadHistory.mq5` (180 linhas).

**Comportamento:**
- Loop dia-a-dia (de hoje-N+1 até hoje) chamando `CopyTicksRange` para `[day_start_utc, day_end_utc]`.
- Retry com `Sleep(InpAttemptDelayMs=500)` até `InpMaxAttemptsPerDay=20` por dia, caso primeira chamada retorne 0 (terminal pode estar baixando do servidor async).
- Reporta cobertura por dia + agregados (total, média, min/max).
- Marca dias úteis vazios como WARNING (gap suspeito); weekends vazios são esperados.
- `SymbolSelect(InpSymbol, true)` antes do loop — exige símbolo no Market Watch.

**Validação empírica em 2026-05-25:** XAUUSDm/Exness, 30 dias → 26 dias com dados, 4 vazios (2 weekends + 2 dias iniciais antes do mercado abrir no domingo), **5.834.172 ticks totais**, média 224k/dia, min/max 11k/405k, 41.1s de execução.

### 3.2 Tentativa de captura empírica do pipeline ADR-024

**Pipeline canônico (ADR-024 §regra 7):**
1. Producer em chart real + TickRecorder Service em paralelo por ≥1h → gera `live.mksbk` + `live.mkstick` + `live.log`
2. Replayer EA sobre `live.mkstick` → gera `replay.mksbk`
3. `tools/verify-parity.ps1` faz `fc /b` (ignorando 8 bytes wall-clock no header) → exit 0 = paridade bit-a-bit

**Execução real:**

| Sessão | Producer | TickRecorder | Resultado |
|---|---|---|---|
| 1 | `T082814` (17:28-17:45, fillDays=30, removido por template change) | `XAUUSDm_20260525.mkstick` (17:28-17:45, 1.739 ticks) | Sessão curta, ~16min |
| 2 | `T090255` (18:02-21:27, fillDays=30, removido manualmente, **3h25min**) | `_2.mkstick` (18:03-21:28, **22.645 ticks**) | **Captura limpa**, validada pelo DumpMksTick |
| 3 | (não iniciada — só TickRecorder por engano, 17s) | `_3.mkstick` (21:54, 27 ticks) | Mal-entendido sobre "esperar 5-10s" |
| 4 | `T125930` (21:59, fillDays=**0**, mas painel preso por bug) | `_4.mkstick` (capturado mas Producer com bug) | Detectou bug do FinishInitAndGoLive |

**Replayer rodou sobre `_2.mkstick` (sessão 2):**
- Processou 22.645 ticks em **47ms** (482k ticks/seg de throughput)
- Gerou 22 bricks (vs 21 live no Producer da mesma sessão)
- EOF natural, halted=false, ticksInvalid=0, ticksK102=0
- **Diferença 22 vs 21 NÃO é bug** — é consequência arquitetural de Producer e Replayer partirem de estados iniciais diferentes (Producer com fill histórico tinha lastClose ≈ 4555.xxx; Replayer sem fill começou com lastClose = primeiro tick ≈ 4558.22). Explicado em detalhe abaixo (§3.4).

**Bloqueio para validação canônica final:**
- Dia era **Memorial Day (US)** + **Spring Bank Holiday (UK)** → mercado de NY e Londres fechados, XAU/Exness com volume drasticamente reduzido
- Em mercado calmo, sessão limpa (`fillDays=0`) de 30min-1h geraria apenas 0-3 bricks live → amostra estatisticamente insuficiente
- **Decisão correta do dono: adiar validação canônica para terça 26/05** com mercado ativo

### 3.3 Dois bugs descobertos in-vivo e corrigidos

#### Bug A — `Replayer.PathStem` cortava no PRIMEIRO separator em vez do ÚLTIMO (commit `72e50fd`)

**Sintoma:** ao rodar Replayer sobre `MKS-ULTIMATE\Ticks\XAUUSDm_20260525_2.mkstick`, o output saiu em `MKS-ULTIMATE\Bricks\replay_Ticks\XAUUSDm_..._.mksbk` — **subpasta `replay_Ticks\` indesejada criada**.

**Causa:** `PathStem` usava `MathMax(StringFind(path,"\\",0), StringFind(path,"/",0))`. `StringFind` em MQL5 retorna a **primeira** ocorrência, não a última. Para path com múltiplos separadores, cortava no primeiro `\\` e deixava subdiretório no stem.

**Fix:** loop reverso com `StringGetCharacter` achando o último separador. MQL5 não tem `StringFindLast` nativo.

**Antes:** `replay_Ticks\\XAUUSDm_20260525_2_20260525T124822.mksbk`
**Depois:** `replay_XAUUSDm_20260525_2_<TS>.mksbk`

Sem afetar a corretude funcional — apenas o path do output estava errado.

#### Bug B — Producer com `InpHistoricalFillDays=0` não transitava para modo live (commit `3e2b87e`)

**Sintoma:** painel SaaS Navy preso em "Carregando 0 dias de histórico... 0%". `ChartOpen` do CS nunca disparava automaticamente.

**Causa:** `OnInit` chama `StartHistoricalFill(0)` que retorna false sem setar `g_fillRunning`. `OnTimer` entrava no caminho de fill se `g_fillRunning=true`; caso contrário entrava no caminho de live se `Mode()==LIVE`. Mas o painel iniciava em INIT e **só transitava para LIVE dentro de `FinishInitAndGoLive`**, que **só era chamado por `ProcessHistoricalChunk` quando o fill terminava**. Sem fill, `FinishInitAndGoLive` nunca disparava → painel preso permanentemente.

OnTick continuava processando ticks live (guarda `if(g_fillRunning) return` deixa passar quando false), mas painel/ChartOpen quebrados.

**Fix:** no fim do `OnInit`, depois do `EventSetMillisecondTimer`, se `!g_fillRequested` chama `FinishInitAndGoLive()` diretamente. Caminho legítimo, usado para teste de paridade canônica ADR-024.

#### Achado P1 que NÃO foi consertado nesta sessão (registrado como follow-up)

Durante inspeção do filesystem durante captura ativa, observou-se que o tamanho do `.mksbk` no disco **não acompanhava** o `bricksTotal` reportado pelo painel (524288 bytes = chunk preallocado pelo Windows, não múltiplo válido de 256+N*72). O **`CMksBrickFileWriter` não tem `Checkpoint()` periódico** — só faz patch do header no `Close()`. **`CMksTickFileWriter` tem** (adicionado no Slice 24d).

**Consequência operacional:** crash do terminal durante sessão do Producer perde os bricks bufferizados desde o último flush automático do MT5. Encerramento ordenado (Producer removed → OnDeinit → Close → patch header) preserva tudo.

**Mitigação atual:** documentar a necessidade de encerrar Producer **antes** de fechar terminal/MT5.
**Mitigação arquitetural (follow-up):** adicionar `Checkpoint(err)` simétrico ao do TickFileWriter em `CMksBrickFileWriter`. Estimativa ~30min, fica para próxima sessão.

### 3.4 Auditoria forense de 3 frentes — pedido do dono

Após as captures e bugs, o dono pediu **leitura completa em busca de divergências e lacunas** em 3 frentes específicas:

#### Frente 1 — Resíduos de "median" após ADR-026

**Veredito:** ✅ **ZERO vazamento.** As 20+ ocorrências de "median" estão em locais legítimos:
- Testes do core (`Test_CMksRenkoBuilder.mq5`): 20 chamadas a `MksGeometryMedian()` — cobertura legítima da geometria preservada por ADR-026 cláusula 4
- Fábrica `MksGeometryMedian()` em `RenkoGeometry.mqh:70-75` — preservada para testes e leitura de `.mksbk` antigos
- Comentários documentativos em `CMksRenkoBuilder.mqh:34, 63` (com referência a ADR-026 §4)
- Documentação no sink `CMksCustomSymbolSink.mqh:58-67` sobre fallback legacy
- `PRICE_MEDIAN` nos indicadores `CMksRSI.mq5:120` e `CMksMACD.mq5:147` — **falso positivo do grep**, é price type de candle (`(high+low)/2`), não relacionado a geometria Renko

**Confirmações:**
- `Producer.mq5:426` (`MksGeometryClassic()` hardcoded) ✓
- `Replayer.mq5` input group "=== Brick (classic, ADR-026) ===" ✓
- `TickRecorder.mq5` zero referências (Service não interpreta brick) ✓
- `RenkoGeometry.mqh:28-31` default do construtor = classic (era median pré-ADR-026) ✓

#### Frente 2 — Semântica de "Pts" no `InpBrickSize` (achado real e crítico)

**Hipótese do dono confirmada:** o input nome `InpBrickSizePts` (antes do refactor desta sessão) era **enganoso**.

Evidência de código:
- `CMksFixedBrickSizer.mqh:27`: `m_sizePoints = sizePoints;` (armazena verbatim, **sem conversão**)
- `CMksRenkoBuilder.mqh:67`: `return base + sign * (1.0 - m_geometry.po) * size;` (`size` é somado **direto no preço em USD**)
- `Producer.mq5` (antes): `new CMksFixedBrickSizer(InpBrickSizePts)` — passa sem multiplicar por `Symbol::Point()`

Validação cruzada empírica: com `InpBrickSizePts = 3.0` em XAUUSDm (Digits=3, Point=0.001), se fosse "3 pontos literal" = 0.003 USD por brick → produziria milhares de bricks/dia. Realidade observada: ~280 bricks/dia → bate com brick de **3 USD literais**.

**Conclusão:** o input recebe **price units** (USD para XAU, EUR para EURUSD), **não pontos do símbolo**. Naming era mentira.

**Fix (commit `e95d52a`):**
- Input renomeado para `InpBrickSize`
- Comentário atualizado: `"Tamanho do brick (price units: USD para XAU, EUR para EUR/USD, etc. NÃO é ponto do símbolo apesar de "Pts" interno)"`
- `IBrickSizer::SizePoints()` ganhou comentário extenso explicando a semântica
- `CMksFixedBrickSizer.mqh` ganhou `@responsibility` clarificado + nota acima da classe

**Não alterado por escopo:**
- Método interno `SizePoints()` da `IBrickSizer` permanece com nome histórico (renomeação afetaria toda a interface, todas as implementações, todos os testes — fica como follow-up de baixa prioridade)
- Campo interno `m_sizePoints` mantido por simetria com método

#### Frente 3 — Modos de brick existentes + lacunas

**Existentes (e o estado de exposição ao Producer):**
- `CMksFixedBrickSizer` — tamanho constante, em uso, default Fixed
- `CMksAtrBrickSizer` — ATR Wilder sobre bricks fechados (ADR-018), 72 assertions cobrindo Wilder smoothing, warm-up, transição, clamps, determinismo, **PRONTO E TESTADO desde 2026-05-21** mas **inacessível pelo Producer** (hardcoded em `new CMksFixedBrickSizer(...)`)

**Fix (commit `e95d52a`):**
- Adicionado `enum ENUM_BRICK_SIZER_MODE { SIZER_MODE_FIXED, SIZER_MODE_ATR }`
- Inputs novos no Producer: `InpSizerMode`, `InpAtrPeriod=14`, `InpAtrMultiplier=1.0`, `InpAtrDefaultSize=1.5`, `InpAtrMinSize`, `InpAtrMaxSize`
- Factory `CreateSizer(mode)` instancia o sizer correto
- `g_sizer` agora é `IBrickSizer*` (polimórfico) em vez de `CMksFixedBrickSizer*`
- Naming do CS: Fixed = `<symbol>.MKS_3`; ATR = `<symbol>.MKS_ATR14x100` (period × round(mult*100))
- Helpers `FormatFixedSizeLabel`, `FormatAtrSizeLabel`, `CurrentSizerLabel`, `SizerModeName` isolam formatação
- Header do `.mksbk` e sink do CS gravam `sizer.SizePoints()` inicial como referência
- Log de starting passa a incluir `sizerMode`, `atrPeriod`, `atrMult`, `atrDefault`

**Lacunas que permanecem (não tratadas):**
- Pips literais (FX EUR/GBP/JPY) — não há helper de conversão para nomenclatura pip
- Points reais via `ISymbol::Point()` como unidade base — não implementado
- R-multiplier explícito (size = N × ATR como filosofia de risco) — parcialmente coberto pelo ATR sizer com `multiplier`, mas sem abstração de "1R"
- Volume / Tempo — fora de escopo (não é Renko)

#### Frente 4 — Tamanho ideal de brick em XAU (insight do dono)

**Insight do dono:** "3 USD em XAU é grande demais — maior parte do tempo bricks ficam laterais sem tendência."

**Confirmação empírica:** sessão `T090255` (3h25min) emitiu **21 bricks live** = **~6 bricks/hora em mercado calmo**. Para scalping (hold < 30min) é grosso demais.

**Sugestões registradas (não aplicadas no código — operacional):**
- 1.0-1.5 USD: scalping moderado (~12-18 bricks/h ativa) — recomendado para experimentar
- 2.0 USD: scalping confortável (~9 bricks/h ativa)
- 3.0 USD (atual): swing intra-day (~6 bricks/h ativa) — bom para tendência
- 5.0 USD: swing calmo (~3 bricks/h ativa)
- **Solução melhor:** usar ATR sizer (agora exposto via input) com `multiplier=1.0`, `period=14` bricks, `defaultSize=1.5` — brick adaptativo a volatilidade

### 3.5 Refactor sizer factory (commit `e95d52a`)

Detalhado no commit message. Resumo:
- Endereça **3 problemas relacionados** identificados na auditoria num único refactor coordenado: naming enganoso + ATR ocioso + cadência inadequada
- 145 linhas modificadas no Producer + 13 no IBrickSizer + 16 no CMksFixedBrickSizer
- **37/37 .mq5 compilam 0 erros 0 warnings** via `compile-all.ps1` em ~50s
- ADR-018 já contemplava o comportamento — nenhuma mudança arquitetural, apenas exposição ao operador
- Median permanece isolada (ADR-026 cláusula 4)

---

## 4. Estado das fases do ROADMAP

| Fase | Antes desta etapa | Após esta etapa |
|---|---|---|
| 0-4 | concluídas | concluídas |
| **4.5 — Tick Recorder + Replayer (ADR-024)** | 100% em código (validação empírica pendente) | **100% em código + ferramentas auxiliares (PreloadHistory, DumpMksTick) + 2 bugs descobertos e corrigidos** — validação canônica E2E ainda pendente (bloqueada por holiday US/UK no dia da tentativa) |
| 5-6 | concluídas | concluídas |
| 7 — StressLab | concluída no escopo factível | concluída (mesmas 3 limitações materiais conhecidas — pré-requisito Fase 9) |
| 8 — Logging/observability | parcial (log-diff via verify-parity.ps1) | parcial (mesmo estado) |
| 9 — EA validação end-to-end | não iniciada | não iniciada |
| 10 — Estratégias reais | não iniciada | não iniciada |

**Métrica-chave da Fase 4.5:** atingiu o **máximo possível em ambiente fora do mercado ativo**. O que falta é literalmente uma sessão de captura limpa em horário de NY/Londres + `verify-parity.ps1` retornando exit 0. Toda a infraestrutura (Producer, TickRecorder, FileTickSource single+multi, ReplayClock, Replayer, verify-parity, PreloadHistory, DumpMksTick) está pronta e validada compile-clean.

---

## 5. Cobertura de teste e validação empírica

### Testes unitários

| Tipo | Estado |
|---|---|
| Suíte completa de testes (`Test_*.mq5`) | **22 arquivos**, todos compilam 0/0 via `compile-all.ps1` |
| Suite total (Experts + Services + Scripts + Indicators) | **37 .mq5**, 0 erros, 0 warnings, ~50s para compilar tudo headless |

### Validação empírica desta sessão

| Item | Status | Evidência |
|---|---|---|
| PreloadHistory rodando em XAUUSDm/Exness | ✓ | 5.834.172 ticks em 30 dias, 26 dias com dados, sem gaps em dias úteis |
| TickRecorder gravando ticks limpos | ✓ | `_2.mkstick`: 22.645 ticks em 3h25min, **0 timestamps regredindo, 0 preços inválidos** |
| DumpMksTick lendo .mkstick e exibindo proveniência + estatísticas | ✓ | header íntegro, spread coerente (0.30 USD em horário calmo), 13 gaps >5s (maior 9.6s) |
| Replayer consumindo .mkstick → .mksbk | ✓ | 22.645 ticks → 22 bricks em 47ms (482k ticks/s) |
| `verify-parity.ps1` em sessão canônica (Producer fillDays=0 + TickRecorder em paralelo) | ✗ | **Bloqueada — adiada para 26/05 com mercado ativo** |

---

## 6. Pendências em aberto

### 6.1 Validação empírica end-to-end da ADR-024 (R4.5.1)

**Procedimento documentado em `docs/CHEATSHEET.md` §9.3 e [`CHECKPOINT-2026-05-25.md`](CHECKPOINT-2026-05-25.md) §7.1. Adendo nesta sessão:**

- Para sessão canônica, **Producer deve usar `InpHistoricalFillDays=0`** (sem fill histórico — caso contrário Producer e Replayer partem de estados iniciais diferentes e o verify-parity falha por número de bricks diferente, NÃO por bug do builder)
- Sequência: **TickRecorder primeiro** (5-10s para pegar anchor) → **Producer depois** (com `fillDays=0` e mesmo símbolo)
- Encerrar **ordenadamente** (Producer Remove + TickRecorder Stop) — caso contrário bricks bufferizados no `.mksbk` podem se perder (achado §3.3 follow-up)

### 6.2 Follow-ups arquiteturais descobertos nesta sessão

| Item | Origem | Prioridade |
|---|---|---|
| **`Checkpoint()` no `CMksBrickFileWriter`** simétrico ao já existente em `CMksTickFileWriter` (§3.3 achado P1 novo) | Inspeção empírica do filesystem buffer | P1 — endereçar antes de operação contínua de longa duração |
| **Renomear método `SizePoints()` da interface `IBrickSizer`** + `m_sizePoints` interno → algo como `Size()` / `BrickSize()` | Auditoria Frente 2 | P3 — escopo grande (afeta toda interface + impl + testes), baixo retorno |
| **Documentar geometria assumida em `Replayer.mq5:56`** | Auditoria Frente 5 | P3 — cosmético |
| **Comentário linha 34 do `CMksRenkoBuilder.mqh`** ganhar `"(ADR-026 §4)"` para deixar explícito | Auditoria Frente 5 | P3 — cosmético |

### 6.3 Achados anteriores ainda em aberto

Todos transcritos do [`CHECKPOINT-2026-05-25.md`](CHECKPOINT-2026-05-25.md) §7 — nada foi atacado nesta etapa:

- **R4.5.2 / ADR-027** — marcar bricks históricos vs live no `.mksbk` quando estratégia entrar (decisão do dono "marcar o brick"). Não atacado.
- **P1-7** — rate de ticks inválidos consecutivos: adiar até evidência live mostrar necessidade
- **P2-4** — Logger precisão de ms: Bloco 4 (Observabilidade)
- **P2-5** — `CMksCostModel` slippage estocástico: adiar
- **P2-6** — `CMksStressLabBroker` slippage bidirecional: adiar
- **P2-7** — teste paridade `CMksMt5Broker` vs `CMksSimulatedBroker`: Bloco 3
- **3 limitações materiais da Fase 7** (pré-requisito Fase 9):
  1. Latência sorteada mas não aplicada ao fill
  2. `spreadMultiplier` mal composto com `CMksCostModel`
  3. SL/TP não disparados pelo `CMksSimulatedBroker`

### 6.4 Pontos sensíveis que merecem atenção do auditor na próxima sessão

Esta sessão modificou Producer.mq5 significativamente (145 linhas). O auditor pode querer verificar:

- **`g_sizer` agora é `IBrickSizer*` polimórfico** — todas as chamadas continuam funcionais? `Validate(err)` está na interface ✓. Não há cast para `CMksFixedBrickSizer*` em lugar nenhum ✓ (verificado via grep).
- **Cleanup de `g_sizer`** — `delete g_sizer` em `Cleanup()` chama destrutor virtual ✓ (`IBrickSizer` tem `virtual ~IBrickSizer() {}` por ADR-004).
- **Naming do CS para ATR** — `<symbol>.MKS_ATR14x100`: cabe no limite de 32 chars do MT5? Verificação: `XAUUSDm.MKS_ATR14x100` = 21 chars ✓. Para symbol mais longo + mult >1000% poderia estourar — não validado limite empírico.
- **WriteHeader recebe `sizer.SizePoints()` inicial** — em ATR, isso é `defaultSize`, não o ATR real. Header carrega valor de referência da sessão, não tamanho efetivo de cada brick. **O tamanho efetivo de cada brick está implícito no `(close - open)` do record** — auditor verificar se isso é claro para consumidor.
- **`g_csSink.brickSizePts = sizerInitialSize`** — em ATR esse valor não muda durante a sessão. Visualmente, em ATR com mudança de regime, o CS pode parecer inconsistente. **Não é bug funcional** (CS é visualização), mas pode confundir.
- **`g_panel.LiveMode(... currentSize ...)`** — em ATR exibe tamanho corrente apenas uma vez no momento da transição init→live. Não é atualizado dinamicamente.
- **Comentários de "median" em `CMksCustomSymbolSink.mqh:58-67`** — código defensivo para median legacy. Auditor pode verificar se ainda faz sentido após ADR-026 — provavelmente sim (é fallback documentado).

---

## 7. Próximos passos sugeridos

### Imediato — próxima sessão de auditoria (que o dono planeja abrir)

**Objetivo declarado pelo dono:** auditoria completa em busca de divergências que ficaram passar.

**Pontos sugeridos de atenção** (sem listar prematuramente para não enviesar):
- Producer.mq5 mudou muito hoje — relê-lo por inteiro
- Naming `InpBrickSize` propagou para todos os usos? `grep -ri InpBrickSizePts` deve dar 0
- `IBrickSizer*` polimorfismo funciona em todas as chamadas?
- `CMksAtrBrickSizer` agora exposto — Replayer também deveria expor? (Replayer hardcoded em `CMksFixedBrickSizer` ainda)
- Documentação atualizada com o que mudou hoje? (CHANGELOG sim; outros docs talvez não)
- Notas de esclarecimento das ADRs estão coerentes entre si?
- Erros que estão na faixa `808` reservados sem materializar
- Frame de paridade ADR-024 entre Producer e Replayer com sizer diferente (Replayer ainda usa Fixed) — divergência potencial

### Quando mercado abrir (terça 26/05) — Fase 4.5 final

**Sessão canônica:**
1. Iniciar TickRecorder Service (`InpSymbol=XAUUSDm`)
2. Esperar 5-10s
3. Anexar Producer no chart `XAUUSDm,M1` com **`InpHistoricalFillDays=0`**
4. Considerar testar `InpBrickSize=1.5` ou `InpSizerMode=SIZER_MODE_ATR` para sentir cadência mais fina
5. Deixar 30-60min em horário ativo (Londres ou NY)
6. Encerrar **ordenadamente** (Producer Remove + TickRecorder Stop)
7. Rodar Replayer sobre o `.mkstick` capturado (path correto, lembrar do bug B fixado)
8. Rodar `tools/verify-parity.ps1` com `LiveMksbk` + `ReplayMksbk` corretos
9. **Exit code 0 = Fase 4.5 declarada 100% concluída** + merge da branch para `main`

### Depois — atacar 3 limitações materiais da Fase 7 + Fase 9

Pré-requisito da Fase 9 (EA validação end-to-end):
- Latência aplicada ao fill no StressLab
- spreadMultiplier composto corretamente com CMksCostModel
- SL/TP disparados pelo CMksSimulatedBroker

Estimativa: 4-6h em sessão dedicada. Depois Fase 9 (EA end-to-end usando o framework inteiro).

### Independente de mercado

- ADR-027 marcar bricks históricos vs live (quando estratégia entrar)
- Camada de produto / UX (indicadores, painel completo, presets por instrumento)
- `Checkpoint()` no CMksBrickFileWriter (follow-up §6.2)

---

## 8. Comandos úteis para o próximo chat

```powershell
# Estado da branch
git log --oneline -10

# Sanity check completo (37 .mq5)
powershell -ExecutionPolicy Bypass -File c:\dev\MKS-ULTIMATE\tools\compile-all.ps1 -Quiet

# Caça por resíduos de InpBrickSizePts (esperado: 0 hits)
grep -rn "InpBrickSizePts" c:\dev\MKS-ULTIMATE\MQL5\

# Caça por hardcode de CMksFixedBrickSizer (Replayer ainda tem!)
grep -rn "new CMksFixedBrickSizer\|new CMksAtrBrickSizer" c:\dev\MKS-ULTIMATE\MQL5\

# Watcher incremental (auto-start via .vscode/tasks.json; manual:)
powershell -ExecutionPolicy Bypass -File c:\dev\MKS-ULTIMATE\tools\watch-compile.ps1

# Push da branch (se necessário)
git push origin feat/producer-classic-only

# Pipeline canônico de paridade (depois de capturar live em demo)
powershell -ExecutionPolicy Bypass -File c:\dev\MKS-ULTIMATE\tools\verify-parity.ps1 `
  -LiveMksbk "<path-do-live.mksbk>" `
  -ReplayMksbk "<path-do-replay.mksbk>"
```

---

## 9. Resumo em 5 linhas para abrir o próximo chat

1. **Pipeline ADR-024 completo em código + ferramentas + 2 bugs descobertos e corrigidos** — falta só validação empírica canônica em mercado ativo (26/05).
2. **Producer refactored hoje (commit `e95d52a`):** input `InpBrickSizePts` → `InpBrickSize` (naming honesto, semântica price units), enum `ENUM_BRICK_SIZER_MODE`, factory `CreateSizer`, `CMksAtrBrickSizer` agora acessível via input — 145 linhas modificadas, 37/37 compilam 0/0.
3. **Auditoria forense de 3 frentes confirmou:** zero vazamento de median (ADR-026 respeitada), naming "Pts" era enganoso (refatorado), `CMksAtrBrickSizer` estava pronto desde 2026-05-21 mas inacessível (refatorado).
4. **Estado atual:** branch `feat/producer-classic-only` sincronizada com origin (HEAD `e95d52a`); 24/24 ADRs aceitas; 8/10 fases concluídas (Fase 4.5 100% em código, validação empírica pendente).
5. **Próxima sessão pelo dono:** auditoria completa em busca de divergências que passaram — Producer.mq5 é o arquivo que mais mudou hoje e merece relê-lo por inteiro; Replayer.mq5 ainda usa `CMksFixedBrickSizer` hardcoded (assimetria a investigar).

---

**Sessão noturna 2026-05-25 fechada.** Pipeline ADR-024 totalmente pronto em código e ferramentas. 2 bugs reais descobertos e corrigidos no caminho. Refactor de exposição do sizer ATR feito. Validação empírica canônica é o último passo, agendada para 26/05 com mercado ativo. Próximo chat o dono abrirá auditoria de divergências — este checkpoint é o guia.
