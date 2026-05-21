---
@document: docs/CHECKPOINT-2026-05-21-slice3b.md
@project: MKS-ULTIMATE
@purpose: Adendo pós-Slice 3b — EA produtor + Custom Symbol, ADR-014 aceita
@audience: Próxima sessão (humano + IA)
---

# CHECKPOINT — 2026-05-21 (pós-Slice 3b)

Adendo a [`CHECKPOINT-2026-05-20.md`](CHECKPOINT-2026-05-20.md), [`CHECKPOINT-2026-05-20-slice2.md`](CHECKPOINT-2026-05-20-slice2.md) e [`CHECKPOINT-2026-05-20-slice3a.md`](CHECKPOINT-2026-05-20-slice3a.md). Cobre exclusivamente o que mudou desde o fechamento do Slice 3a: ADR-014 aceita, EA produtor com arquivo `.mksbk` e Custom Symbol, validação empírica end-to-end.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 5 arquivos, nesta ordem

1. `README.md`
2. `docs/CHECKPOINT-2026-05-20.md` — base, convenções, estado pós-Slice 1
3. `docs/CHECKPOINT-2026-05-20-slice2.md` — adendo pós-Slice 2 (validação contra dado real)
4. `docs/CHECKPOINT-2026-05-20-slice3a.md` — formato binário `.mksbk` + serializador
5. `docs/CHECKPOINT-2026-05-21-slice3b.md` — este, incremental

Os demais documentos (`docs/REGRAS.md`, `docs/ARCHITECTURE.md`, `docs/V5-POSTMORTEM.md`, etc.) seguem como referência sob demanda.

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação.

---

## 2. Estado do código (HEAD = `466d15d`)

O dia 2026-05-21 cobriu três blocos de trabalho sobrepostos:
1. **Slice 3b proper** (commits até `a06cbe9`) — Producer + Custom Symbol.
2. **Integração da auditoria MQL5** (`4756e8e`) — distribuição de 4 sinais novos da auditoria nos docs existentes, sem criar arquivo de auditoria separado.
3. **Aceites de ADR + implementações de consequência** (commits de `e512524` em diante) — ADR-015/007/018 aceitas e materializadas em código testado: `CMksLogger` + Producer refactor + `CMksAtrBrickSizer`.

| Camada | Item | Estado |
|---|---|---|
| Slice 3a | `MQL5/Include/MKS-ULTIMATE/Core/Data/` — formato `.mksbk` + writer + reader | feito + testado (97 assertions) |
| Slice 3a | `MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksBrickFile.mq5` — golden file | feito + verde |
| Slice 3b parte 1 | `MQL5/Experts/MKS-ULTIMATE/Producer.mq5` — EA fundido (multi-sink, logger) | **feito + validado** |
| Slice 3b parte 1 | `MQL5/Scripts/MKS-ULTIMATE/ValidateProducerOutput.mq5` — leitor | **feito** |
| Slice 3b parte 2 | Custom Symbol no Producer (`CCustomSymbolSink` + `CMultiSink`) | **feito + validado** |
| Auditoria MQL5 | Integração nos docs (ARCHITECTURE §2/§4, Protocolo 9, §6 deste CHECKPOINT) | **feita** (commit `4756e8e`) |
| `CMksLogger` | `Core/Log/CMksLogger.mqh` — JSON-line + destino dual + arquivo por sessão | **feito + validado** (ADR-007) |
| `CMksAtrBrickSizer` | `Core/RenkoBuilder/CMksAtrBrickSizer.mqh` — ATR Wilder sobre bricks | **feito + testado (72 assertions)** (ADR-018) |
| `IBrickSizer.OnBrick` | Extensão da interface para feedback do builder | **feito** (commit `16c8e82`) |
| `ISymbol` + `CMksMt5Symbol` | `Core/Interfaces/ISymbol.mqh` + `Core/Symbol/CMksMt5Symbol.mqh` — ficha técnica do instrumento | **feito + validado** (ADR-016) |
| `IAccount` + `CMksMt5Account` | `Core/Interfaces/IAccount.mqh` + `Core/Account/CMksMt5Account.mqh` — estado da conta | **feito + validado** (ADR-016) |
| `Producer.mq5` via interfaces | Refactor: `g_iSymbol`/`g_iAccount` no composition root | **feito** (commit `398501c`) |
| `MksExecutionResult` expandido | Campos `swap`, `dealId`, `attempts` (ADR-017 §Consequências) | **feito** (commit `6ed70f8`) |
| Erros 200-203 | Faixa Broker: `TIMEOUT`/`INVALID_FILL`/`RETRY_EXHAUSTED`/`NOT_INITIALIZED` | **feito** (commit `6ed70f8`) |
| `CMksCostModel` | `Core/Broker/CMksCostModel.mqh` — spread, slippage, commission, swap configuráveis | **feito** (commit `25df429`, ADR-017 §8) |
| `CMksSimulatedBroker` | `Core/Broker/CMksSimulatedBroker.mqh` — broker em memória, hedging, sem auto-close de SL/TP | **feito + testado (51 assertions)** (commit `466d15d`, ADR-017) |
| `CMksMt5Broker` | Broker real para live trading | **pendente** (ADR-017 — implementação concreta) |

### ADRs — só o que mudou desde o checkpoint anterior

| ADR | Tema | Status |
|---|---|---|
| 014 | Política de rotação e naming do `.mksbk` | **Aceita** (`8e30554`) |
| 015 | Strategy Tester nativo como ferramenta vs. fonte de verdade | **Aceita** (`e512524`) |
| 007 | Formato e destino do log estruturado | **Aceita** (`6e40c40`) |
| 018 | Cálculo do ATR no `CMksAtrBrickSizer` | **Aceita** (`27b5226`) |
| 016 | Interfaces `ISymbol`/`IAccount` | **Aceita** (`27e28cc`) |
| 017 | Modelo de confirmação de execução do `CMksMt5Broker` | **Aceita** (`679e77e`) |

ADRs 001–013 sem alteração.

### Códigos de erro — só o que foi adicionado

- `MKS_ERR_DATA_FILE_EXISTS = 806` em `Core/Types/Error.mqh` (faixa Data). Consequência da ADR-014 §4 cláusula 4.
- `MKS_ERR_LOG_FILE_IO = 600` e `MKS_ERR_LOG_STATE_INVALID = 601` em `Core/Types/Error.mqh` (faixa Log). Consequência da ADR-007.

---

## 3. O que foi feito no Slice 3b + housekeeping pós-fechamento

Todos os commits do dia sobre HEAD `918c45f`:

```
466d15d feat(core): add CMksSimulatedBroker + tests (ADR-017)
25df429 feat(core): add CMksCostModel for simulated broker (ADR-017 §8)
6ed70f8 feat(core): expand MksExecutionResult + broker error codes (ADR-017)
33f775b docs: refresh CHECKPOINT with ADR-017 acceptance (HEAD 679e77e)
679e77e docs: accept ADR-017 (broker execution confirmation model)
af2ca24 docs: cleanup consequences of ADR-016 acceptance (Protocolo 9, tree, CHECKPOINT)
398501c feat(core): add ISymbol/IAccount + Mt5 impls, refactor Producer (ADR-016)
27e28cc docs: accept ADR-016 (ISymbol and IAccount interfaces)
8777d34 docs: refresh CHECKPOINT-slice3b with full day's work (HEAD 7e08c58)
7e08c58 feat(core): add CMksAtrBrickSizer (ADR-018)
3618e77 feat(core): add CMksLogger and refactor Producer (ADR-007)
16c8e82 feat(core): extend IBrickSizer with OnBrick (ADR-018 §2)
27b5226 docs: accept ADR-018 (ATR calculation on closed bricks)
6e40c40 docs: accept ADR-007 (structured log format)
2cdc008 docs(protocols): tighten Protocolo 2 with ADR-015 consequence
e512524 docs: accept ADR-015 (strategy tester as tool, not source of truth)
aa4b6d2 docs: refresh CHECKPOINT-slice3b with post-closure audit integration
4756e8e docs: integrate MQL5 alignment audit (ADR-015..018, Protocolo 9, Services/)
f734464 docs: add CHECKPOINT 2026-05-21 slice3b (handoff after Slice 3b)
a06cbe9 feat(experts): add Custom Symbol second sink to Producer (Slice 3b)
a3ac944 feat(experts): retry .mksbk filename on collision (ADR-014)
365931b feat(data): add MKS_ERR_DATA_FILE_EXISTS guard in Writer::Open (ADR-014)
8e30554 docs: accept ADR-014 (mksbk rotation policy and naming)
468206c feat(experts): add Producer EA fusing Builder/Sizer/Writer (Slice 3b)
```

### Parte 1 — EA produtor (`468206c`)

- **`Producer.mq5`** funde `CMksRenkoBuilder` + `CMksFixedBrickSizer` + `CMksBrickFileWriter` num único programa. Combate ao eixo 2 do V5: histórico (`CopyTicksRange` em OnInit) e live (`OnTick`) atravessam o mesmo motor e gravam no mesmo `.mksbk`.
- Inputs: `S=3`, `InpHistoricalFillDays` (default `0`), `InpInvalidTickLimit=10` (L), `InpThresholdLimit=20` (K), `InpPrintBricks`, `InpInvalidLogEvery=100`.
- Símbolo: chart-bound, `_Symbol` no OnInit (ADR-013 §2 borda); sem input divergente.
- Proveniência via `AccountInfoString(ACCOUNT_COMPANY)` + `AccountInfoInteger(ACCOUNT_LOGIN)`, gravada no header (ADR-012/013).
- `OnDeinit` chama `writer.Close()` que patcheia header com `brickCount`/`timeFirst`/`timeLast`/`createdAt`.
- Tratamento de erro: 102 sempre logado, 103 rate-limited, 104 para o stream e flagga `g_streamHalted`.
- Sink interno `CBrickWriterSink` — não promovido a include (princípio de não abstrair antes do segundo uso).

- **`ValidateProducerOutput.mq5`** lê o `.mksbk` mais recente em `MKS-ULTIMATE\Bricks\` (ou path explícito) via `CMksBrickFileReader`, imprime proveniência, geometria, distribuição de `thresholdsCrossed` (M=1, M=2..5, M=6..10, M>10), primeiros/últimos bricks. Round-trip Producer → arquivo → reader fechado.

### Parte 2 — ADR-014 + guard 806 + retry de sufixo (`8e30554`, `365931b`, `a3ac944`)

- **ADR-014 aceita** (`8e30554`). 5 cláusulas:
  1. Arquivo novo a cada `OnInit` (builder do zero, anti-`SyncWithExisting` do V5).
  2. Naming mínimo `<symbol>_<YYYYMMDDTHHMMSS>.mksbk` (proveniência mora no header, não no nome).
  3. Sub-pasta única `MKS-ULTIMATE\Bricks\`.
  4. Guarda contra colisão via `FileIsExist` → 806 → retry com sufixo `_2`, `_3`…
  5. Sem limpeza automática (retenção é operacional).

  6 alternativas rejeitadas (append, naming completo com broker/account, ms timestamp, sub-pasta por símbolo, sobrescrita silenciosa, limpeza automática). ADR formaliza retroativamente o desenho em vigor em `468206c`.

- **`MKS_ERR_DATA_FILE_EXISTS = 806`** + `FileIsExist` em `CMksBrickFileWriter::Open` (`365931b`). `Test_CMksBrickFile` permanece verde (97 assertions) — todos os 5 `writer.Open()` do teste já faziam `DeleteIfExists` antes.

- **Retry de sufixo no Producer** (`a3ac944`): `BuildBrickFilePath` ganha parâmetro `attempt`. Loop com `kMaxAttempts=100`. Sessão capturada uma vez para todos os retries usarem o mesmo timestamp; só o sufixo varia.

### Parte 3 — Custom Symbol (`a06cbe9`)

- **`CCustomSymbolSink : public IRenkoSink`** (local no `Producer.mq5`): cada `OnBrickClose` monta `MqlRates[1]` e chama `CustomRatesUpdate(csName, rates)`. **Slot M1 monotônico** (`nextBarTime += 60` por brick) evita colisão de timestamp — `CustomRatesUpdate` é upsert e sobrescreve bars com mesmo `time`, perdendo bricks de rajadas silenciosamente.
- **`CMultiSink : public IRenkoSink`** composite trivial agrega writerSink + csSink. Builder recebe `IRenkoSink* g_multiSink` que despacha para ambos. MultiSink **não possui** os sinks; `Cleanup` deleta cada um separadamente.
- **`EnsureCustomSymbolReady(cs, src, err)`** cria/recupera via `CustomSymbolCreate` (trata `lastErr=5304` "symbol already exists" como race), replica propriedades imutáveis do símbolo base (`SYMBOL_DIGITS`, `SYMBOL_CHART_MODE=BID`, `SYMBOL_POINT`, `TICK_SIZE`, `TICK_VALUE`, `CONTRACT_SIZE`, `CURRENCY_*`), e seleciona no Market Watch via `SymbolSelect`.
- **`BuildCustomSymbolName(symbol, sizePts)`** gera `<symbol>.MKS_RKN<size>` (ex.: `XAUUSDm.MKS_RKN3`). Naming sem ADR — decisão de implementação, ADR-014 §6 Fronteiras.
- Novo input `InpResetCustomSymbolBars` (default `true`): `CustomRatesDelete(0, LONG_MAX)` no OnInit, simétrico com a política de "sessão nova = limpo" da ADR-014.

### Parte 4 — Integração da auditoria MQL5 (`4756e8e`, pós-slice3b)

Após o fechamento do Slice 3b, o dono colou nesta sessão um relatório de auditoria de alinhamento (`AUDITORIA-MQL5-ALIGNMENT.md`) escrito em paralelo, sem acesso ao filesystem, datado de 2026-05-21 mas referenciando estado **pré-slice3b** (HEAD ≤ `42372f7`, ADR-012 como mais recente). 6 riscos identificados; após análise:

- **Sinais novos:** 4 (broker confirmation, Strategy Tester boundary, ISymbol/IAccount, ATR calculation).
- **Confirmação de pendências já registradas:** 1 (ADR-007).
- **Redundante / out-of-date:** o resto (broker já tem ADR-013 sobre outro tema; ADR números 013/014 sugeridos pela auditoria colidem com aceitas).
- **Discordância explícita:** sugestão de ADR só para "IBroker em vez de CTrade" rejeitada como over-documentation (já decorre de ADR-004 + V5-POSTMORTEM Eixo 1).

**Integração escolhida:** distribuir os 4 sinais novos em documentos existentes, **sem criar `docs/AUDITORIA-MQL5-ALIGNMENT.md`**. O conteúdo original (700 linhas, ~60% meta-conteúdo descartável) ficou só no chat. O sinal preservado:

- `ARCHITECTURE.md` §2: `Services/` na árvore.
- `ARCHITECTURE.md` §4: ADR-015 a 018 listadas como pendentes, com descrições e bloqueios.
- `PROTOCOLOS.md`: novo **Protocolo 9** com tabela completa de "chamadas API globais proibidas em código de lógica" (tempo, símbolo, conta, identidade, séries, execução, Custom Symbol) — cada função com substituto canônico. Protocolo 1 atualizado para apontar para Protocolo 9.
- §6 deste CHECKPOINT: ADRs 015–018 marcadas "adicionada pós-auditoria MQL5".

### Parte 5 — Aceites de ADR + implementações de consequência (pós-auditoria)

Após a integração da auditoria, três das quatro ADRs adicionadas foram aceitas e duas materializadas em código testado, no mesmo dia.

**ADRs aceitas (3):**

- **ADR-015** (`e512524`) — Strategy Tester nativo como ferramenta, não fonte de verdade. Decisão filosófica pura; sem código consequência. Bloqueava ADR-018 (vetou alternativa `iATR` nativo).
- **ADR-007** (`6e40c40`) — Formato e destino do log estruturado. JSON-line + destino dual (Print + FileWrite) + hot path mudo + arquivo por sessão + política de níveis na borda.
- **ADR-018** (`27b5226`) — Cálculo do ATR no `CMksAtrBrickSizer`. ATR sobre bricks fechados (Wilder), `IBrickSizer` ganha `OnBrick`, warm-up via `defaultSizePoints` para evitar deadlock.

**Consequências em código (2 commits, 934 inserções líquidas):**

- **`16c8e82`** — Extensão do `IBrickSizer` com `OnBrick(MksBrick&)` pure virtual (ADR-018 §2). `CMksFixedBrickSizer` ganha implementação no-op. `CMksRenkoBuilder.EmitBrick` chama `m_sizer.OnBrick(brick)` após notificar o sink. Compile clean nos 6 arquivos afetados; runtime do `Test_CMksRenkoBuilder` (428 assertions) **não rodado nesta sessão** — semanticamente neutro para sizer constante.

- **`3618e77`** — `CMksLogger` em `Core/Log/CMksLogger.mqh` (ADR-007 implementado). JSON-line com schema fixo, escape de paths via `MksJsonEscape`, header META com proveniência, helpers `Trace/Debug/Info/Warn/Error`. `ILogger` da Fase 1 ganhou nova assinatura `Log(level, module, msg, ctxJson)` — sem consumidor real prévio, sem breakage. `Producer.mq5` refatorado: todos os `Print`/`PrintFormat` substituídos por chamadas do logger; novo input `InpLogToFile`; `MKS-ULTIMATE\Logs\<symbol>_<TS>.log` criado em paralelo ao `.mksbk`. Validação empírica: 10 linhas JSON íntegras, parity entre sinks (writerCount=csBars=bricksTotal=10.074).

- **`7e08c58`** — `CMksAtrBrickSizer` em `Core/RenkoBuilder/CMksAtrBrickSizer.mqh` (ADR-018 implementado). ATR Wilder sobre bricks fechados, warm-up via `defaultSizePoints`, `IsReady=true` sempre (anti-deadlock), parâmetros: `atrPeriod=14`, `multiplier=0.5`, `defaultSize`, clamp `min/max`. Validação empírica via `Test_CMksAtrBrickSizer.mq5`: **72 assertions, 0 falhas** em 11 cenários (Validate, warm-up, transição, TR primeiro/com-gap, Wilder, clamp min/max, determinismo).

**Limitação conhecida** registrada no código (ADR-007): `CMksLogger.FormatTimestamp` produz `.000Z` fixo — MQL5 não expõe API para "TimeCurrent com millis" fora de `MqlTick.time_msc`. TODO para evolução futura quando caller puder passar `timeMsc` do tick corrente como contexto.

### Parte 6 — ADR-016 aceita + ISymbol/IAccount materializados + Producer refactor

ADR-016 (interfaces de mercado e conta) **redigida, aceita e materializada** em código testado, fechando uma das duas ADRs estruturais que sobravam pendentes pós-auditoria.

**ADR aceita (`27e28cc`):** duas interfaces puras (`ISymbol` com 16 métodos de ficha técnica do instrumento; `IAccount` com 10 métodos de estado da conta), enums nativos do MQL5, get-on-demand. Define `Core/Symbol/` e `Core/Account/` como pastas novas. 6 alternativas rejeitadas (interface única, funções livres, pular abstração, snapshot, Bid/Ask em ISymbol, cobertura completa da API).

**Implementação (`398501c`):**
- `Core/Interfaces/ISymbol.mqh` (56 linhas) — Name, Digits, Point, TickSize, TickValue, ContractSize, VolumeMin/Max/Step, StopsLevel, FreezeLevel, FillingMode, BaseCurrency, ProfitCurrency, MarginCurrency.
- `Core/Interfaces/IAccount.mqh` (46 linhas) — Login, Company, Currency, Balance, Equity, Margin, FreeMargin, Leverage, MarginMode, TradeMode.
- `Core/Symbol/CMksMt5Symbol.mqh` (105 linhas) — construtor `(string)`, delega para `SymbolInfo*`.
- `Core/Account/CMksMt5Account.mqh` (82 linhas) — delega para `AccountInfo*`. Usa `ACCOUNT_MARGIN_FREE` (não o deprecated `ACCOUNT_FREEMARGIN`).
- `Producer.mq5` refatorado: composition root instancia `g_iSymbol`/`g_iAccount`; `EnsureCustomSymbolReady` recebe `ISymbol*` em vez de `string`; ~8 chamadas a `SymbolInfo*`/`AccountInfo*` migraram para as interfaces.

**Consequências documentais (também neste commit ou no refresh seguinte):**
- `PROTOCOLOS.md` Protocolo 9: linhas de Mercado/Conta agora apontam para `ISymbol.*`/`IAccount.*` como **disponíveis** (com referência a `Core/Symbol/CMksMt5Symbol` e `Core/Account/CMksMt5Account`), não mais "pendentes".
- `ARCHITECTURE.md` §2 (árvore): pastas `Core/Symbol/` e `Core/Account/` adicionadas. Também `Core/Data/` (esquecida em refreshes anteriores).

**Validação empírica:** Producer atachou e completou OnInit. Header META do `.log` mostra `broker:"Exness Technologies Ltd"`, `account:277678478`, `symbol:"XAUUSDm"`, `digits:3` — todos obtidos via `g_iAccount.Company()`, `g_iAccount.Login()`, `g_iSymbol.Digits()` (não mais via API global). Custom Symbol `XAUUSDm.MKS_RKN3` criado e populado com bars via `EnsureCustomSymbolReady` consumindo `g_iSymbol.Digits/Point/TickSize/etc`. Historical fill de 7 dias: 1.785.559 ticks → 10.074 bricks emitidos. Comportamento semanticamente idêntico ao run anterior — refactor sem regressão.

**Pendência residual da ADR-016:** mocks `CMksFakeSymbol`/`CMksFakeAccount` para testes isolados — slice próprio quando primeiros testes de Trade Manager ou Risk Manager precisarem deles (relacionado à ADR-005).

### Parte 7 — ADR-017 aceita (broker execution confirmation model)

ADR-017 (modelo de confirmação de execução do broker) **redigida e aceita** em `679e77e`. Última ADR estrutural pendente do MVP. Apenas decisão arquitetural — implementação concreta (`CMksMt5Broker`, `CMksSimulatedBroker`, `CMksCostModel`) fica para slices próximos.

**Pesquisa de fundamentação** via subagent consultou `docs.mql5.com` sobre `OrderSend`, `OnTradeTransaction`, `SYMBOL_FILLING_MODE`, `ACCOUNT_MARGIN_MODE`, retcodes e propriedades de `DEAL`. Identificou 6 pitfalls conhecidos (race `OrderSend`/`OnTradeTransaction`, deviation=0 rejeitado, filling mismatch retorna INVALID_FILL 10030, netting/hedging confusion, etc.) e mapeou as 8 decisões críticas.

**8 decisões fixadas:**

1. **`Send`/`Close` síncronos lógicos** — bloqueia até `OnTradeTransaction` reportar `TRADE_TRANSACTION_DEAL_ADD`. `fillPrice` vem de `HistoryDealGetDouble(deal, DEAL_PRICE)`, não do `result.price` cru. Preserva paridade backtest/live (backtest é trivialmente síncrono).
2. **Broker per-símbolo** — `CMksMt5Broker(ISymbol*, IAccount*)`. Multi-símbolo é futuro.
3. **Timeout 5s configurável**, sem retry automático em timeout (fatal).
4. **Filling pré-detectado** via `m_symbol.FillingMode()` no `Init`, com fallback no primeiro `INVALID_FILL`. Cache do efetivo.
5. **Margin mode dual** — netting (ordem oposta) vs. hedging (ordem oposta com `position=ticket`).
6. **Retry interno** para REQUOTE/PRICE_CHANGED/PRICE_OFF: 3 tentativas, backoff 100ms. Configurável.
7. **Deviation default 10 points**, configurável. Nunca 0.
8. **CostModel classe separada** — passthrough no real (`HistoryDealGetDouble`); gerador no simulado (spread/slippage/commission/swap).

7 alternativas rejeitadas (IBroker assíncrono, OrderSend cru sem aguardar, OrderSendAsync, multi-symbol, retry hardcoded, tipos separados, tentar ordem para detectar filling).

**Consequências (trabalho futuro pós-aceite):**
- Faixa Broker 200–299: códigos 200–203 (TIMEOUT, INVALID_FILL, RETRY_EXHAUSTED, NOT_INITIALIZED).
- `MksExecutionResult` ganha campos `swap`, `dealId`, `attempts` (ciclo próprio).
- `MksOrderRequest` e `IBroker.Send/Close/Modify` não mudam.
- Pasta nova `Core/Broker/` com `CMksMt5Broker`, `CMksSimulatedBroker`, `CMksCostModel`.
- EA expõe `g_broker.OnTradeTransactionEvent(transaction, request, result)` chamado pelo `OnTradeTransaction` do programa.
- Teste de paridade: padrão do `Test_CMksRenkoBuilder` aplicado aos dois brokers.

**ADR-016 é pré-requisito direto** — broker consome `ISymbol.FillingMode/TickSize/Point/VolumeStep/StopsLevel` e `IAccount.MarginMode/FreeMargin`.

### Parte 8 — Implementação progressiva da Fase 4 (Broker abstractions)

ADR-017 começou a virar código. Implementação em 4 partes; **3 concluídas**, 1 pendente.

**Parte 1 — Tipos expandidos (`6ed70f8`):**
- `MksExecutionResult` ganha `swap`, `dealId`, `attempts` (ADR-017 §Consequências). Construtor zera. Consumidores existentes não quebram.
- 4 códigos novos na faixa Broker 200-299: `MKS_ERR_BROKER_TIMEOUT=200`, `MKS_ERR_BROKER_INVALID_FILL=201`, `MKS_ERR_BROKER_RETRY_EXHAUSTED=202`, `MKS_ERR_BROKER_NOT_INITIALIZED=203`.

**Parte 2 — `CMksCostModel` (`25df429`):**
- `Core/Broker/CMksCostModel.mqh` (118 linhas). Pasta nova `Core/Broker/`.
- Determinístico, sem RNG. Parâmetros: `spreadPoints`, `slippagePoints`, `commissionPerLot`, `swapLongPerDay`, `swapShortPerDay` (todos default 0 = sem custos).
- API: `Validate(err)`, `FillPriceFor(side, mid, pointValue)`, `Commission(lots)`, `SwapForDays(side, lots, days)`.
- BUY paga `mid + halfSpread + slip`; SELL recebe `mid - halfSpread - slip`. Slippage adverso ao trader.

**Parte 3 — `CMksSimulatedBroker` (`466d15d`):**
- `Core/Broker/CMksSimulatedBroker.mqh` (240 linhas) + `Test_CMksSimulatedBroker.mq5` (~440 linhas).
- Implementa `IBroker`. Construtor recebe `ISymbol*` + `CMksCostModel*`. EA chama `OnTick(tick)` antes de cada `Send/Close` para o broker conhecer o mid.
- `Send`: aplica costModel + cria position com ticket sequencial + computa SL/TP em preço absoluto. Retorna `MksExecutionResult` preenchido.
- `Close(positionId, lots)`: valida + aplica fill no lado oposto + reduz/zera position.
- `Modify(positionId, sl, tp)`: atualiza SL/TP em preço absoluto.
- **Simplificações deliberadas v1:** assume HEDGING (cada Send abre position nova); SL/TP armazenados sem auto-close (Trade Manager futuro monitora); sem cálculo automático de swap acumulado.
- **Validação empírica:** **51 assertions, 0 falhas** em 12 cenários (not_initialized, invalid_request, send sem custos / com spread / com slippage / com commission, SL/TP BUY+SELL, close full+partial, close inexistente, modify, hedging com 3 sends, determinismo entre 2 brokers).
- `CFakeSymbol` inline no teste (sem mock formal ainda — slice próprio quando ADR-005 for atacada).

**Parte 4 — `CMksMt5Broker` (pendente):**
- Broker real para live trading. Maior complexidade da Fase 4: race entre `OrderSend` síncrono e `OnTradeTransaction` assíncrono; fallback automático de filling; retry com backoff em retcodes retryable; espera por `TRADE_TRANSACTION_DEAL_ADD` para extrair preço executado real via `HistoryDealGetDouble(deal, DEAL_PRICE)`.
- Validação só é possível em demo MT5 real — não dá pra unit-testar.
- Trabalho de slice próximo, ~2-3h focadas.

---

## 4. Validação empírica

Run em XAUUSDm/Exness, conta `277678478`:
- 1.768.555 ticks históricos carregados (7 dias).
- 10.080 bricks gerados pelo historical fill.
- ~2 minutos de operação live geraram +6 bricks adicionais.
- **Total: 10.086 bricks gravados no `.mksbk` ≡ 10.086 bars empurradas no Custom Symbol ≡ 0 falhas em cada sink**. Multi-sink despachou cada brick para ambos sem perda.
- Chart do `XAUUSDm.MKS_RKN3` renderiza bricks Renko visualmente corretos, tamanho consistente, padrões de tendência/reversão visíveis.
- Zero erros 102/103/104.
- `ValidateProducerOutput` contra o `.mksbk` pós-OnDeinit: header íntegro, proveniência correta, integridade de tamanho do arquivo verde (`size == 256 + N*72 = 256 + 10086*72 = 726.448 bytes`).

Único WARN observado: `CustomRatesDelete falhou: lastErr=5019` no primeiro run da combinação símbolo/size. Benigno — não havia bars para apagar no CS recém-criado. Em runs subsequentes da mesma combinação, a chamada anterior ao `CustomRatesDelete` (no OnInit prévio) terá apagado as bars, e as chamadas `CustomSymbolSetInteger(SYMBOL_DIGITS/CHART_MODE)` reapagam por efeito colateral.

---

## 5. Descobertas operacionais do Slice 3b

### Custom Symbol API — pontos sutis (preservar para futuras edições)

- **Setar `SYMBOL_DIGITS`, `SYMBOL_POINT`, `SYMBOL_CHART_MODE`, `SYMBOL_TRADE_TICK_SIZE` apaga o histórico do CS.** Comportamento documentado pela MQL5; alinhado com a política da ADR-014 (sessão nova = histórico limpo), mas precisa ser sabido — chamar essas funções em runtime arbitrário destrói bars existentes sem aviso.
- **`CustomRatesUpdate` é upsert por timestamp.** Dois bricks com mesmo `MqlRates.time` → o segundo sobrescreve o primeiro. Sem o slot M1 monotônico, bricks de rajada se perdem.
- **`SymbolSelect(csName, true)` é necessário antes de qualquer feed.** Sem isso, `CustomRatesUpdate` falha silenciosamente em alguns builds. Consenso: fórum MQL5 + artigo prático `mql5.com/articles/8226`.
- **`CustomSymbolDelete` falha com chart do CS aberto** (erro 5306). Mantenha o CS, limpe bars via `CustomRatesDelete(0, LONG_MAX)`.
- **Limite de nome do Custom Symbol: 31 chars.** `XAUUSDm.MKS_RKN3` = 16 chars, dentro do limite com folga.

### Sync MT5 — junction nova para `Experts/`

A primeira vez que o repo criou um EA (`Producer.mq5`), foi preciso criar uma nova junction (`Include/MKS-ULTIMATE` já existia desde o Slice 1):

```powershell
New-Item -ItemType Junction `
  -Path 'C:\Users\<user>\AppData\Roaming\MetaQuotes\Terminal\<id>\MQL5\Experts\MKS-ULTIMATE' `
  -Target 'C:\dev\MKS-ULTIMATE\MQL5\Experts\MKS-ULTIMATE'
```

PowerShell `New-Item -ItemType Junction` preferível a `mklink /J` via bash MSYS (escaping causa "syntax incorrect").

### Inputs do EA no MetaEditor — UX

Quando o input do EA tem comentário (`input int InpHistoricalFillDays = 0; // descrição`), o MT5 mostra a **descrição** no diálogo de Parâmetros, não o nome `InpHistoricalFillDays`. Para próximas versões do Producer, considerar começar o comentário com o nome da variável: `// InpHistoricalFillDays: 0=...`.

---

## 6. Pendências persistentes

Estado das ADRs pendentes ao fim de 2026-05-21:

| ADR | Tema | Status |
|---|---|---|
| 005 | Framework de testes unitários | **Pendente** — não enfrentada. Testes atuais (`Test_CMksRenkoBuilder` 428 assertions, `Test_CMksBrickFile` 97, `Test_CMksAtrBrickSizer` 72) usam asserções inline, sem framework formal. |
| 008 | Reabertura de mercado no RenkoBuilder | **Pendente com evidência parcial registrada** (`CHECKPOINT-2026-05-20-slice2.md` §6): builder atual já trata gap de fim de semana via ADR-011 multi-threshold; teste de 7 dias incluindo gap de 49h gerou M=2 sem erros. Evidência insuficiente para generalizar (1 instrumento, 1 broker). |

ADRs aceitas no dia (movidas desta tabela): **014, 015, 007, 018, 016, 017** — ver §2 e §3 Partes 4 a 8. ADRs 014, 007, 018, 016 e parcialmente 017 também foram **materializadas em código testado** (ADR-017 tem 3 de 4 partes prontas — `CMksMt5Broker` é pendente). ADR-015 é decisão filosófica sem código.

Outras dívidas registradas:

- **`CMksMt5Broker` (Parte 4 da Fase 4)** — broker real para live trading. ADR-017 fixou todas as decisões; falta o código + validação empírica em demo MT5. Maior peça restante do MVP (~13% após ADR-017 parcialmente materializada).
- **Validação empírica do `Test_CMksRenkoBuilder` runtime** após a extensão do `IBrickSizer` (commit `16c8e82`) — só compile clean. Semanticamente neutro (no-op no sizer constante), mas vale rodar empiricamente quando voltar a essa região.
- **Validação empírica do `CMksAtrBrickSizer` em produção** — `Test_CMksAtrBrickSizer` cobre comportamento isolado (72 assertions). Falta swap experimental no Producer (substituir `CMksFixedBrickSizer` por `CMksAtrBrickSizer` e ver brick sizes adaptarem em 7 dias de dado real).
- **Recuperação de estado em restart do EA** — ADR-014 §Consequências adia explicitamente. Estado do builder zerado a cada `OnInit`; reconciliação parcial proibida por design.
- **Continuidade visual entre sessões no Custom Symbol** — ADR-014 §Consequências. Workaround: `InpHistoricalFillDays > 0` reconstrói N dias.
- **Limite de tentativas do retry de sufixo (`kMaxAttempts=100`)** — não-arquitetural, fixado no Producer.
- **WARN `CustomRatesDelete lastErr=5019`** no primeiro run de cada combinação símbolo/size — benigno.
- **Precisão de milissegundo no `CMksLogger.FormatTimestamp`** — atualmente `.000Z` fixo. MQL5 não expõe API para "TimeCurrent com millis". TODO no código: caller poderá passar `timeMsc` do tick corrente como contexto futuro.

---

## 7. O que pode vir a seguir

Não-prescritivo — depende da prioridade do dono. Caminhos naturais:

- **Fase 3 — Testes unitários do core (ADR-005 primeiro).** Formaliza framework de teste; reorganiza `Test_CMksRenkoBuilder` + `Test_CMksBrickFile` como suítes.
- **Slice 4 — `CMksAtrBrickSizer`.** Cobre o tamanho dinâmico do brick previsto na ADR-010. Adiciona um novo eixo de variação (Renko + ATR).
- **Slice 5 — Backtest via `.mksbk` replay.** `ITickSource` que lê `.mksbk` e produz bricks deterministicamente, sem tocar o broker. Pré-requisito para a Fase 7 (StressLab).
- **Fase 4 — Broker abstractions.** `CMksMt5Broker` (live) + `CMksSimulatedBroker` (backtest). Trabalho substancial; depende de definir custos (spread, slippage, comissão) primeiro.
- **ADR-007 — Formato do log estruturado.** Conforme volume de log cresce, `Print` vira ruído. Replace planejado de `Print*` por `ILogger` estruturado.

---

## 8. Regras operacionais lembradas

Sem mudança em relação aos checkpoints anteriores:

- Sem `Co-Authored-By` em commits (memória do projeto).
- `git restore .claude/settings.json` antes de cada `git add` — harness adiciona auto-allow rules indesejadas.
- Push só com autorização explícita ("aprovado", "push autorizado", "confirmo").
- Verificar empiricamente o sync MT5 ↔ repo via junction antes de declarar "pronto" — memória do projeto.
- Tom default: ácido-amigo (TOM-E-CHATS.md §1.1). SÉRIO TÉCNICO em risco operacional.

---

*Documento gerado em 21 de maio de 2026 — fechamento do Slice 3b.*
