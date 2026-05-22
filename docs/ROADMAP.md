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

## Fase 5 — Trade Management

**Status:** Não iniciada

**Nota (ADR-019):** A fase está sub-dividida em **5a (`CMksPositionSizer`)** e **5b (`CMksTradeManager`)**. Sequência real: **5a → Fase 6 → 5b**. Razão: o Risk Manager (Fase 6) consome o Sizer; construir o Risk antes do TradeManager faz a rede de segurança nascer antes do gatilho. Cláusula anti-precedente: outras sub-divisões de fase só são permitidas via ADR própria.

**Entregáveis:**
- `Core/Trade/CMksTradeManager.mqh` — gestão de trade aberto
  - Break-even
  - Trailing stop (start point + step)
  - Partial close (em percentual, não em lot hardcoded)
  - State machine explícita (evita re-executar ações)
- `Core/Trade/CMksPositionSizer.mqh` — sizing plugável
  - Fixed lot
  - Percent risk
  - ATR-adjusted
  - Kelly fracionado (para referência, não recomendado como default)

**Critério de saída:**
- Unit tests para todas as combinações de BE + trail + partial
- Sem `Sleep` bloqueante
- Sem bifurcação live/backtest

**Por que importa:** Gestão errada de trade transforma estratégia boa em perdedora e vice-versa. Precisa ser testável em isolamento.

---

## Fase 6 — Risk Management em camadas

**Status:** Não iniciada

**Nota (ADR-019):** Sub-dividida em três sub-slices **executados na mesma ordem**, apenas em commits/rodadas separadas: **6.1 Por trade** (SL/TP obrigatórios, max lots, limite via Sizer), **6.2 Por estratégia** (max posições simultâneas, exposure total), **6.3 Por conta** (daily loss limit, max drawdown, circuit breaker). A sub-divisão **não viola** a cláusula anti-precedente da ADR-019 porque não inverte ordem (todas vêm antes da Fase 7). Cumpre o critério de saída só quando 6.1, 6.2 e 6.3 estão fechados e o teste end-to-end passa.

**Entregáveis:**
- `Core/Risk/CMksRiskManager.mqh` — middleware que toda `OrderRequest` atravessa antes de virar ordem real
- Camadas:
  - **Por trade:** SL/TP obrigatórios, tamanho máximo por trade
  - **Por estratégia:** máximo de posições simultâneas, exposure total
  - **Por conta:** daily loss limit, max drawdown, circuit breaker
- Logging estruturado de toda rejeição de ordem pelo risk manager

**Critério de saída:**
- Cada camada testada isoladamente
- Teste end-to-end: configurar limite, violar limite, verificar que trade é bloqueado com log claro

**Por que importa:** Foi a ausência disso que permitiu o V5 quebrar conta em 4 horas.

---

## Fase 7 — StressLab

**Status:** Não iniciada

**Entregáveis:**
- `StressLab/CStressLabEngine.mqh` — envolve o `CMksSimulatedBroker` e injeta condições adversas
- Parâmetros ajustáveis por "nível de estresse":
  - Spread multiplier (1x, 2x, 5x, 10x do spread real do broker)
  - Slippage distribution (fixo, normal, cauda-pesada)
  - Latência (média, variância, spikes)
  - Taxa de rejeição (% de ordens que retornam erro)
  - Taxa de requote
  - Delay de preenchimento
- Capacidade de rodar uma estratégia em múltiplos níveis de estresse e comparar resultados (tabela de sensibilidade)

**Critério de saída:**
- Pipeline: estratégia → backtest normal → stress leve → stress médio → stress alto → relatório comparativo
- Documentação de cada parâmetro: o que significa, como medir no broker real, como setar

**Por que importa:** Essa fase é o que separa este framework de qualquer outro. Backtests "bonitos" passam; backtests que sobrevivem ao StressLab são confiáveis.

---

## Fase 8 — Logging e observabilidade

**Status:** Parcialmente concluída

**Nota:** `CMksLogger` (`Core/Log/CMksLogger.mqh`) materializado via ADR-007 e em uso no `Producer.mq5` desde slice3b. Cobre: formato JSON-line, níveis TRACE/DEBUG/INFO/WARN/ERROR + META, output dual (Print + arquivo), header de sessão com proveniência (broker/account/symbol/digits/EA/sessionStartMsc), timestamp ISO 8601 UTC, contexto livre via `ctxJson` parametrizável. Pendente para Concluir: **ferramenta de log-diff** que compara um log de backtest com um de live e aponta a primeira divergência (último item do critério de saída abaixo).

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
