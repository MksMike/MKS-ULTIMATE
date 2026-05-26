---
@document: docs/ROADMAP.md
@project: MKS-ULTIMATE
@purpose: Roteiro de construção do framework, em ordem de execução
@audience: Dono do projeto, assistentes de IA, contribuidores futuros
---

# MKS-ULTIMATE — Roadmap

Este documento define **o que construir e em que ordem**. Cada fase tem entregáveis, critérios de saída e riscos mapeados. Datas não são fixadas deliberadamente — datas em projetos de framework envelhecem mal. O que vale é a sequência.

**Regra de ouro:** nenhuma fase começa antes da anterior ter todos os critérios de saída cumpridos. Pular fases foi um erro do V5 e não se repete aqui.

---

## Fase 0 — Fundação documental

**Status:** Concluída

**Entregáveis:**
- `README.md`
- `.gitignore`
- `CLAUDE.md`
- `CHANGELOG.md`
- `docs/Projeto.md`
- `docs/REGRAS.md`
- `docs/ROADMAP.md` (este arquivo)
- `docs/ARCHITECTURE.md` (inicialmente stub)
- `docs/PROTOCOLOS.md`
- `docs/CHEATSHEET.md`

**Critério de saída:** Todos os documentos acima existem e foram commitados.

**Por que importa:** Sem base documental, decisões arquiteturais se perdem. Cada volta ao projeto começaria do zero.

---

## Fase 1 — Abstrações do core (interfaces)

**Status:** Concluída

**Entregáveis:**
- `Core/Version.mqh` — definições de versão única do framework
- `Core/Interfaces/IBroker.mqh` — interface para execução de ordens
- `Core/Interfaces/ITickSource.mqh` — interface para fonte de ticks
- `Core/Interfaces/IClock.mqh` — interface para tempo (desacoplada de `TimeCurrent()`)
- `Core/Interfaces/ILogger.mqh` — interface para logging estruturado
- `Core/Interfaces/IRenkoSink.mqh` — interface que consome eventos de brick (`OnBrickClose`)
- `Core/Types/Tick.mqh` — struct de tick padronizado
- `Core/Types/Brick.mqh` — struct de brick Renko
- `Core/Types/OrderRequest.mqh` — struct de requisição de ordem (agnóstica de broker)
- `Core/Types/ExecutionResult.mqh` — struct de resultado de execução

**Critério de saída:**
- Todas as interfaces compiláveis no MetaEditor
- Cada interface com doc-comment explicando contrato
- Nenhuma implementação concreta ainda

**Por que importa:** Definir contratos antes de código concreto obriga o pensamento arquitetural. Facilita testes (mocks) e troca de implementações (live vs backtest) sem tocar na estratégia.

**Riscos:**
- **R1.1:** Sobreabstrair. Interfaces devem capturar o que é realmente variável entre live/backtest, não criar camadas gratuitas.
- **R1.2:** MQL5 tem limitações em relação a polimorfismo puro (não há `interface` keyword). Usamos classes abstratas com métodos virtuais puros. Validar que isso funciona em `iCustom` e outras APIs.

---

## Fase 2 — RenkoBuilder (coração do framework)

**Status:** Concluída

**Entregáveis:**
- `Core/RenkoBuilder/CMksRenkoBuilder.mqh` — classe que consome ticks e emite bricks
- Suporte inicial a:
  - Renko clássico (brick de tamanho fixo em pontos)
  - Renko ATR-based (tamanho dinâmico por ATR de período configurável)
- Emissão de evento `OnBrickClose(const Brick&)` para um `IRenkoSink` injetado
- Tratamento explícito de:
  - Gaps (preço salta mais de um brick)
  - Reversões (direção muda)
  - Ticks fora de ordem (se o `ITickSource` entregar)
  - Volume zero (phantom candidate — decisão documentada sobre se ignora, marca ou interrompe)

**Critério de saída:**
- Classe compilável
- Comportamento documentado brick-a-brick em `ARCHITECTURE.md`
- Determinismo validado: mesmo tick stream produz mesmos bricks, sempre
- Fase 3 (testes) cobre todos os casos listados

**Por que importa:** Renko é o dado base de todo o framework. Se o builder não é determinístico e auditável, tudo que vier depois é areia movediça. No V5, o builder em si era correto — o problema foi haver múltiplos caminhos de produção de bricks (ticks reais no backtest, OHLC de M1 no live) que geravam sequências diferentes para o mesmo intervalo. Ver `docs/V5-POSTMORTEM.md`, eixo 2.

**Riscos:**
- **R2.1:** Performance. MQL5 é single-threaded e o `OnTick` é chamado por cada tick. O builder precisa ser barato.
- **R2.2:** Precisão em ativos de diferentes escalas (FX vs índices vs ações). Unidade de medida precisa ser consistente (pontos do símbolo).
- **R2.3:** Decisão pendente: como lidar com fins de semana / reabertura? Descartar gap? Fechar brick parcial? Documentar decisão.

---

## Fase 3 — Testes unitários do core

**Status:** Concluída

**Nota:** Framework formal `Core/Testing/` materializado e validado empiricamente em 2026-05-22 (ADR-005 aceita). Inventário: `Asserts.mqh` (macros `MKS_ASSERT_*` com `__FILE__:__LINE__`), `TestRunner.mqh` (registro automático via `MKS_RUN(#funcname)`, summary com Alert em falha), mocks (`CMksCapturingSink`, `CMksFakeSymbol`, `CMksFakeAccount`). As 4 suítes pré-existentes foram migradas (redução de -55% a -67% em linhas) + smoke test do próprio framework. Total atual: **648/648 assertions** em **41 tests** + smoke. Detalhes em `docs/CHECKPOINT-2026-05-22.md`.

**Entregáveis:**
- Estrutura de testes em `tests/` (formato a decidir — pode ser scripts `.mq5` que rodam asserções, ou infra externa)
- `tests/test_RenkoBuilder.mq5` — cobertura dos casos da Fase 2
- `tests/test_TradeManager.mq5` — quando existir
- Framework mínimo de asserções (`ASSERT_EQ`, `ASSERT_TRUE`, etc.) em `Core/Testing/`
- Execução: conseguir rodar todos os testes com um comando ou script

**Critério de saída:**
- 100% dos casos listados na Fase 2 cobertos
- Todos os testes passando
- Falha clara e rastreável quando um teste quebra

**Por que importa:** Sem isso, "o builder funciona" vira crença. Teste é o que transforma crença em fato.

**Riscos:**
- **R3.1:** MQL5 não tem framework de teste nativo. Ou importamos/adaptamos algo existente, ou construímos um mínimo viável.
- **R3.2:** Isolamento. Cada teste precisa ter ambiente próprio — mocks de `IBroker`, `ITickSource`, `IClock`.

---

## Fase 4 — Broker abstractions

**Status:** Concluída

**Nota:** ADR-017 inteira materializada em código testado. `CMksMt5Broker` validado em demo XAUUSDm/Exness (Send+Close em 524ms, sem timeout). `CMksSimulatedBroker` cobre 12 cenários com 51 assertions. `CMksCostModel` plugável (spread, slippage, commission, swap). Retry interno (REQUOTE/PRICE_CHANGED/PRICE_OFF, 3 tentativas, backoff 100ms), fallback de filling (FOK→IOC→RETURN), retcodes MT5 tratados via códigos 200–203.

**Entregáveis:**
- `Core/Broker/CMksMt5Broker.mqh` — implementação de `IBroker` usando API MT5 real (para live e backtest nativo)
- `Core/Broker/CMksSimulatedBroker.mqh` — broker simulado que aceita `OrderRequest` e retorna `ExecutionResult` modelado (para StressLab)
- `Core/Broker/CostModel.mqh` — modelo de custos plugável (spread, comissão, swap, slippage)
- Retry logic com backoff
- Fallback de filling mode (FOK → IOC → Return)
- Tratamento explícito de retcodes do MT5 (REQUOTE, TIMEOUT, INVALID_FILL, etc.)

**Critério de saída:**
- Testes de integração do MT5 broker em conta demo
- Testes unitários do simulated broker
- Documentação completa de como custos são modelados

**Por que importa:** Execução é onde backtest mente mais facilmente. Modelo de custos explícito é o antídoto.

**Riscos:**
- **R4.1:** Comportamento do MT5 varia entre brokers. Modelo precisa ser parametrizável.
- **R4.2:** Netting vs hedging — tratar na abstração, não delegar pra estratégia decidir.

---

## Fase 4.5 — Tick Recorder + Replayer (pipeline de paridade)

**Status:** Concluída (código + script + validação empírica)

**Nota:** Fase inserida por ADR-024 (aceita 2026-05-23) entre a Fase 4 (Broker abstractions, concluída) e a Fase 5 (Trade Management). Materializa o pipeline canônico de paridade bit-a-bit do feed Renko e da decisão da estratégia — sem essa fase, a paridade do projeto é teorema; com ela, é fato verificável.

**Validação empírica (2026-05-26):** Sessão `T132858` em XAUUSDm/Exness com `InpParityRunMode=true` produziu 38 bricks (2992 bytes), 3377 ticks (216384 bytes) e audit TSV (3799 bytes). `tools/verify-parity.ps1` retornou **exit 0** (`.mksbk` byte-a-byte idênticos, ignorando bytes 184–191 de wall-clock conforme ADR-024); `diff` dos audit TSV (Producer vs Replayer) retornou **0 diferenças**. A canonicidade da paridade (ADR-024 §7c) está empiricamente verificada — fato, não teorema.

**Entregáveis** (todos concluídos em 2026-05-24, branch `feat/producer-classic-only`):

- `MQL5/Include/MKS-ULTIMATE/Core/Data/TickFileFormat.mqh` — layout binário `.mkstick` v1 (header 256B + record 64B, little-endian)
- `MQL5/Include/MKS-ULTIMATE/Core/Data/CMksTickFileWriter.mqh` — writer com `Checkpoint()` para tolerância a crash
- `MQL5/Include/MKS-ULTIMATE/Core/Data/CMksTickFileReader.mqh`
- `MQL5/Include/MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh` — `ITickSource` single-file
- `MQL5/Include/MKS-ULTIMATE/Core/Data/CMksMultiFileTickSource.mqh` — `ITickSource` multi-day com validação cross-file (810, 811)
- `MQL5/Include/MKS-ULTIMATE/Core/Clock/CMksMt5Clock.mqh` — `IClock` live
- `MQL5/Include/MKS-ULTIMATE/Core/Clock/CMksReplayClock.mqh` — `IClock` replay (função pura do feed)
- `MQL5/Services/MKS-ULTIMATE/TickRecorder.mq5` — Service captura `.mkstick` em background, roll-over diário UTC
- `MQL5/Experts/MKS-ULTIMATE/Replayer.mq5` — EA monta composition root fora do Strategy Tester e replaya
- `tools/verify-parity.ps1` — script PowerShell que executa a validação canônica (fc /b dos `.mksbk` + diff dos logs)
- `MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksTickFile.mq5`, `Test_CMksFileTickSource.mq5`, `Test_CMksMultiFileTickSource.mq5` — testes unitários cobrindo formato binário, single-file, multi-day, ReplayClock

**Critério de saída:**
- ✅ Todos os arquivos acima compilam 0 erros / 0 warnings via MetaEditor64 headless
- ✅ Testes unitários cobrem cenários de proveniência, descontinuidade, EOF, ReplayClock
- ✅ **Validação empírica concluída** (2026-05-26): pipeline `InpParityRunMode` num único EA → `verify-parity.ps1` exit 0 + diff dos audit TSV 0 diferenças

**Por que importa:** Sem esta fase, qualquer afirmação de "backtest e live produzem o mesmo resultado" é fé. Com ela, é prova mecânica e automatizável a cada commit que toca o caminho de paridade (`RenkoBuilder`, `ITickSource`, `IClock`, sinks que escrevem `.mksbk`). Protocolo 1 ganha item exigindo `verify-parity.ps1` antes de declarar pronto módulos que tocam paridade.

**Riscos:**
- **R4.5.1:** Validação empírica ainda não foi executada — o pipeline pode revelar bug que escapou aos testes unitários. Resposta: rodar antes de qualquer estratégia entrar (Fase 9).
- **R4.5.2:** O fill histórico do `Producer.mq5` ainda lê de `CopyTicksRange`, fonte diferente dos ticks live. Paridade canônica vale apenas para o trecho live capturado. Resposta documentada como dívida na auditoria; ADR-027 futura quando estratégia entrar.

---

## Fase 5 — Trade Management

**Status:** Concluída

**Nota (ADR-019):** A fase está sub-dividida em **5a (sizers)** e **5b (`CMksTradeManager`)**. Sequência real executada: **5a → Fase 6 → 5b**. Razão: o Risk Manager (Fase 6) consome o Sizer; construir o Risk antes do TradeManager faz a rede de segurança nascer antes do gatilho. Cláusula anti-precedente: outras sub-divisões de fase só são permitidas via ADR própria.

**Entregáveis (concluídos):**
- `Core/Interfaces/IPositionSizer.mqh` — contrato `ComputeLots(slDistancePoints, lots&, err&) → bool`.
- `Core/Trade/CMksFixedLotSizer.mqh` — lots fixos validados contra `VolumeMin/Max/Step` do símbolo (slice 5a).
- `Core/Trade/CMksPercentRiskSizer.mqh` — lots calculados a partir de % do balance e distância do SL; floor para `VolumeStep` (slice 5a).
- `Core/Trade/CMksTradeManager.mqh` — gestão de trade aberto (slice 5b):
  - Break-even (gatilho + offset).
  - Trailing stop (start point + step, ratchet — nunca afrouxa).
  - Partial close (em percentual dos lots iniciais).
  - State machine idempotente (re-executar `Update` não re-aplica ações).
- `Core/Trade/CMksTradeJournal.mqh` — diário de trades + agregados (win rate, profit factor, gross/avg/largest, sequências); consumido pelo `CMksStressLabReport` (Fase 7).
- Cobertura de testes: `Test_CMksPositionSizer.mq5`, `Test_CMksTradeManager.mq5`, `Test_CMksTradeJournal.mq5` no framework `Core/Testing/` (ADR-005).

**Critério de saída:** atendido — testes cobrem combinações BE+trail+partial, zero `Sleep` bloqueante, zero bifurcação live/backtest.

**Escopo reduzido (assumido):**
- **`ATR-adjusted` sizer e `Kelly fracionado` sizer não foram implementados.** O eixo de tamanho dinâmico já está coberto no `CMksAtrBrickSizer` (tamanho do brick, ADR-018), e sizing por Kelly é estatística agressiva sem dados de retorno realizados ainda. Ficam para ADR futura quando estratégia rodando produzir histórico suficiente.

**Limitações conhecidas (auditoria 2026-05-25):**
- **`CMksTradeManager` + conta netting:** `positionId` em netting não identifica posição individual; partial close pode dessincronizar estado interno. Aceitável enquanto o pipeline operar em hedging; ADR explícita necessária se conta netting virar caso de uso.
- ~~**Auto-detach em fechamento externo (SL hit, manual close)**~~ — **resolvido em 2026-05-26**: `CMksTradeManager` ganhou injeção opcional de `IPositionBook`. Quando provido, `Update()` consulta `book.IsOpen(positionId)` no início e auto-detacha se a posição sumiu. `IPositionBook` ganhou método `IsOpen(positionId)`; `CMksMt5PositionBook` itera posições MT5 com escopo símbolo+magic; `CMksFakePositionBook` ganhou `MarkClosed(id)` para testes. Step do `Update` ganhou flag `autoDetached`.

**Por que importa:** Gestão errada de trade transforma estratégia boa em perdedora e vice-versa. Precisa ser testável em isolamento — e é, em testes do framework `Core/Testing`.

---

## Fase 6 — Risk Management em camadas

**Status:** Concluída

**Nota (ADR-019):** Sub-dividida em três sub-slices executados na ordem **6.1 → 6.2 → 6.3**: cada slice fechou camada própria no `CMksRiskManager` sem refator das anteriores. A sub-divisão **não violou** a cláusula anti-precedente da ADR-019 porque não inverteu ordem (todas vieram antes da Fase 7).

**Entregáveis (concluídos):**
- `Core/Interfaces/IPositionBook.mqh` — contrato de leitura de estado (`OpenCount`, `TotalLots`), consumido pelas checagens da camada estratégia.
- `Core/Position/CMksMt5PositionBook.mqh` — implementação real via API `PositionsTotal`/`PositionGet*`, filtrável por símbolo + magic.
- `Core/Account/CMksAccountSnapshot.mqh` — stateful: rastreia `dayStartBalance` (rollover UTC) e `peakEquity` (monotônico) para alimentar camada Por Conta.
- `Core/Risk/CMksRiskManager.mqh` — middleware com 3 construtores (trade only / trade+strategy / trade+strategy+account):
  - **6.1 Por trade:** SL/TP obrigatórios (config), `maxLotsPerTrade`, limite vs `IPositionSizer`. Códigos 400–404.
  - **6.2 Por estratégia:** `maxOpenPositions`, `maxTotalLots` via `IPositionBook`. Códigos 405–406.
  - **6.3 Por conta:** `maxDailyLossPct`, `maxDrawdownPct`, `minEquityAbs` (circuit breaker) via `CMksAccountSnapshot`. Códigos 407–409.
- `Core/Risk/CMksRiskGatedBroker.mqh` — decorator de `IBroker` que força toda `Send` a passar pelo `CMksRiskManager`. Eliminação estrutural de "esqueci de chamar o risk manager".
- Logging estruturado de toda rejeição via `ILogger` injetado (`MKS_LOG_WARN`).
- Cobertura de testes: `Test_CMksRiskManager.mq5`, `Test_CMksRiskGatedBroker.mq5`, `Test_CMksAccountSnapshot.mq5`.

**Critério de saída:** atendido — cada camada testada isoladamente; teste end-to-end (configurar limite → violar → trade bloqueado com log) coberto em `Test_CMksRiskGatedBroker`.

**Limitações conhecidas (auditoria 2026-05-25):**
- ~~**`CMksRiskManager.CheckOrder` não chama `snapshot.Update()`**~~ — **resolvido em 2026-05-26**: `CheckOrder` agora faz `if(m_snapshot != NULL) m_snapshot.Update()` no início, garantindo que as checagens Por Conta operem sobre balance/equity correntes mesmo se o EA esquecer de chamar `snapshot.Update()` por tick. Idempotente (Update já trata rollover e peak monotônico).

**Por que importa:** Foi a ausência disso que permitiu o V5 quebrar conta em 4 horas.

---

## Fase 7 — StressLab

**Status:** Concluída

**Nota arquitetural:** O `CStressLabEngine.mqh` previsto não foi materializado. A arquitetura final dispensou um "engine" separado em favor de composição direta — o EA monta `CMksSimulatedBroker` → `CMksStressLabBroker` (wrapper) e roda a estratégia. Métricas agregadas em `CMksStressLabReport` capturadas por execução. Trade-off: simplicidade arquitetural vs. ausência de orquestração automatizada multi-nível (operador roda N corridas manualmente e agrega).

**Entregáveis (concluídos):**
- `StressLab/CMksRandom.mqh` — RNG seedável (LCG Numerical Recipes), substituto canônico para `MathRand` (ADR-024 §6). Suporta uniform, gaussiana (Box-Muller), bernoulli.
- `StressLab/CMksStressParams.mqh` — 5 presets escalonados: `MksStressNone()`, `MksStressLight()`, `MksStressMedium()`, `MksStressHigh()`, `MksStressNightmare()`. Inclui `baselineSpreadPoints` e `latencyDriftPointsPerMs` (ADR-027).
- `StressLab/CMksStressLabBroker.mqh` — wrapper de `IBroker` que injeta:
  - **Rejeição pré-execução** (probabilística via `rejectionProb`).
  - **Loop de requote** (até `maxRequotes` tentativas com `requoteProb`).
  - **Slippage adverso** ao fill price (distribuição `FIXED` ou `NORMAL`, com clamp em zero — "stress só piora").
  - **Spread composto** sobre `baselineSpreadPoints` do CostModel — `spreadMultiplier=10` realmente equivale a "spread 10× maior" (ADR-027 §7.2).
  - **Latência adversa ao fill** via `latencyDriftPointsPerMs` — modela "preço se moveu durante a viagem da ordem" (ADR-027 §7.1).
- `Core/Broker/CMksSimulatedBroker.mqh` — broker simulado com **auto-trigger de SL/TP** em `OnTick` (ADR-027 §7.3). Fila `MksSimAutoCloseEvent` drenada via `PollAutoCloses` pelo caller. Slippage de SL hit modelado realisticamente (close pode ser pior que o nível).
- `StressLab/CMksStressLabReport.mqh` — snapshot agregado de uma corrida (métricas do StressLabBroker + do `CMksTradeJournal`); `MksStressLabPrintComparison` produz tabela ASCII comparativa entre níveis com marcador de degradação.
- Cobertura de testes: `Test_CMksRandom.mq5`, `Test_CMksStressLabBroker.mq5` (4 testes novos pós-ADR-027), `Test_CMksSimulatedBroker.mq5` (5 testes novos pós-ADR-027), `Test_CMksStressLabReport.mq5`.

**Critério de saída:** atendido — pipeline `estratégia → stress leve/médio/alto → relatório comparativo` é operacionalmente executável; cada parâmetro está documentado em `CMksStressParams.mqh`. Três bloqueadores da auditoria 2026-05-25 (latência não aplicada, spread mal composto, SL/TP sem auto-trigger) foram resolvidos pela ADR-027.

**Por que importa:** Essa fase é o que separa este framework de qualquer outro. Backtests "bonitos" passam; backtests que sobrevivem ao StressLab são confiáveis — **desde que o StressLab estresse o que precisa estressar**. Pós-ADR-027, os três eixos críticos (latência → drift no fill; spread → multiplicação composta; SL hit → auto-close com slippage) são exercitados de fato.

---

## Fase 8 — Logging e observabilidade

**Status:** Concluída

**Nota:** `CMksLogger` (`Core/Log/CMksLogger.mqh`) materializado via ADR-007 e em uso no `Producer.mq5`, `Replayer.mq5` e `TickRecorder.mq5`. Cobre: formato JSON-line, níveis TRACE/DEBUG/INFO/WARN/ERROR + META, output dual (Print + arquivo), header de sessão com proveniência (broker/account/symbol/digits/EA/sessionStartMsc), timestamp ISO 8601 UTC, contexto livre via `ctxJson` parametrizável. A ferramenta de log-diff foi materializada como `tools/verify-parity.ps1` (slice 24f) — compara linhas de decisão do builder após normalização (remove `ts` e `sessionStartMsc` que divergem inerentemente entre sessões). Quando estratégia entrar (Fase 9+), o filtro do diff expande para incluir `"decision":"buy/sell/close"` etc.

**Limitações conhecidas (auditoria 2026-05-25):**
- **Timestamp com precisão de segundo** (`.000Z` hardcoded) — MQL5 não expõe `TimeCurrent` com millis. Solução barata pendente: `Log()` aceitar `tickMsc` como overload para precisão quando o caller tem tick à mão.
- **`FileFlush` por linha** — durável em crash, mas custoso em volume. Aceitável enquanto a regra "hot path mudo" da ADR-007 valer.

**Entregáveis:**
- `Core/Log/CMksLogger.mqh` — logger estruturado
- Formato: chave=valor ou JSON-line, não `Print("texto: " + (string)x)`
- Níveis: TRACE, DEBUG, INFO, WARN, ERROR
- Output plugável: arquivo, MT5 journal, stdout (backtest)
- Contexto automático: timestamp, módulo, símbolo, ticket, ID de sessão

**Critério de saída:**
- Logs de backtest e live comparáveis linha-a-linha
- Script ou ferramenta simples que pega log de backtest + log de live e aponta primeira divergência

**Por que importa:** Sem observabilidade estruturada, debug em live vira adivinhação. E paridade não se verifica por olhômetro — precisa de evidência.

---

## Fase 9 — Primeiro EA de validação end-to-end

**Status:** Não iniciada

**Entregáveis:**
- EA minimalista usando todo o core construído
- Estratégia deliberadamente simples (reversão de cor pura, sem filtros) — a ideia não é ser lucrativa, é exercitar todas as peças
- Rodar em backtest, rodar em stress lab (3 níveis), rodar em demo live
- Comparar logs e validar paridade

**Critério de saída:**
- Paridade backtest/live validada por log-diff
- EA sobrevive a stress médio sem quebrar core
- Zero crash, zero vazamento de handles, zero `_LastError` não tratado

**Por que importa:** Primeira hora da verdade. Se paridade falhar aqui, voltamos e consertamos o core antes de ir adiante.

---

## Fase 10 — Estratégias reais

**Status:** Não iniciada

Cada estratégia vira um projeto separado (EA próprio, documentação própria), usando o framework. Só começa depois da Fase 9 validada.

Não há lista prévia. Estratégias serão decididas conforme oportunidade e estudo.

---

## Backlog (ideias sem posição definida)

- Suporte a outras barras além de Renko (Range, Tick, Volume, Seconds)
- Dashboard de monitoramento de EA em live
- Integração com canal externo de alertas (Telegram, email)
- Sistema de sinais (EA recebe sinais, não gera)
- Multi-símbolo em um único EA
- Otimização de parâmetros distribuída (fora do MT5)

Tudo aqui entra no ROADMAP formal quando for priorizado. Por enquanto, ficam registrados pra não se perder.

---

## Lições aprendidas do V5 (para não esquecer)

Estas lições vêm da análise de causa-raiz documentada em `docs/V5-POSTMORTEM.md`, baseada na leitura do código-fonte do V5. Cada uma corresponde a um eixo da falha real:

- **A estratégia opera sobre preço observado, não sobre o close matemático do brick.** No V5, o `close` do brick era `open ± brickSize` — um valor calculado, sem relação com o tick que disparou o fechamento. A estratégia raciocinava num espaço de preços fictício.
- **Um único produtor de bricks.** O V5 tinha quatro caminhos diferentes de gerar bricks (ticks reais, OHLC de M1, amostragem por timer). Backtest e live nunca viram a mesma sequência.
- **Custo de execução é aplicado ao trade, não somado num relatório.** A simulação de custos do V5 alimentava contadores que só apareciam no relatório final — o equity do backtest nunca foi tocado por eles.
- **Caminho de código único.** Bifurcar live/backtest foi letal. E o gatilho da bifurcação é irrelevante: no V5 era um input, não um `if(MQL5_TESTING)` — e quebrou do mesmo jeito.
- **Reconstrução de estado é completa ou não acontece.** O `SyncWithExisting` do V5 restaurava o estado pela metade a cada restart.
- **Testes antes de estratégia.** Sem cobertura do core, toda estratégia é construída sobre incerteza.
- **Risk manager como middleware, não como lembrete.** "Vou lembrar de colocar stop" é ilusão.
- **Logging estruturado, não Print.** Em live sem log comparável, debug vira arqueologia.
- **Renko em casa.** O V5 já fazia isso corretamente — engine própria, sem indicador de caixa-preta. Mantemos.

Essas lições são permanentes. Cada violação futura deve ser comparada contra esta lista e contra o `docs/V5-POSTMORTEM.md`.
