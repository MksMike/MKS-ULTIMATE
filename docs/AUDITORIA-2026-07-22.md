---
@document: docs/AUDITORIA-2026-07-22.md
@project: MKS-ULTIMATE
@purpose: Auditoria completa multi-agente (17 auditores + verificação adversarial de 3 lentes) do core, do Custom Symbol e dos indicadores. Motivada pelo dono após 2 bugs do CS passarem despercebidos ("quantos bugs escondidos existem?"). Registro dos achados com status de verificação honesto.
@audience: Dono + próximas sessões (humano + IA).
---

# Auditoria completa — 2026-07-22

**Regra:** CHECKPOINT/auditoria é guia, código é verdade. Todo achado cita `file:line`.

## 0. Como esta auditoria foi feita (e seus limites)

- **17 auditores em paralelo** (`high`), leitura INTEGRAL: 13 áreas do código + 4 varreduras transversais (simetria de caminhos gêmeos, falhas silenciosas, ciclo de vida de estado, determinismo/paridade). As varreduras miram exatamente as **classes** dos bugs que passaram (a flag `showWicks` num caminho e não no gêmeo; escrita sem guarda corrompendo estado).
- **Verificação adversarial:** cada achado passaria por **3 céticos** (o código sustenta? o impacto se materializa? alguma ADR sanciona?), maioria decide.
- **48 achados brutos → 43 únicos.** A verificação adversarial **foi INTERROMPIDA pelo limite de sessão** após confirmar 9. Por isso:
  - **9 CONFIRMADOS** = sobreviveram às 3 lentes. Alta confiança.
  - **27 SINALIZADOS** = achados reais no código, mas a verificação adversarial **não completou** (a maioria ficou `UNVERIFIED`). São candidatos, não veredito — precisam de confirmação (retomar o workflow após o reset, ou revisão manual).
  - **6 KNOWN-OPEN** redescobertos (itens já rastreados: H6, timeline horizontal, etc.).
- **Limites:** auditoria estática de código-fonte. NÃO exercita runtime no MT5, NÃO usa dados live, NÃO prova ausência de bugs — prova a PRESENÇA dos listados.

## 1. Veredito executivo

Respondendo direto à pergunta do dono ("quantos bugs escondidos existem?"):

- **O motor de decisão está sólido.** Builder, brokers, risco, estratégia, runners — a leitura integral achou **quase nada** de correctness aqui: 1 melhoria defensiva (geometria sem `Validate`) e 1 gap de config no ATR sizer. A cobertura de teste pesada do core se confirma na prática. **Confie nele.**
- **Os bugs se concentram na CAMADA DE DESENHO — exatamente onde a suspeita estava:** Custom Symbol + Producer + indicadores. 8 dos 9 confirmados vivem aqui. É a camada thin-em-teste (chamadas MT5 não unit-testáveis), validada por olhômetro — e foi onde os 2 bugs anteriores moraram.
- **Há 3 plausíveis-não-verificados que tocam DINHEIRO ou INTEGRIDADE de dados** e merecem verificação prioritária: BE do TradeManager além do mercado, mapeamento de partial fill no Mt5Broker, e crash-tolerance dos readers de arquivo. Um deles (BE) eu já verifiquei manualmente = real (ver §3).
- **Indicadores AINDA NÃO casam com o CS** (§5) — há divergências concretas, mas todas na camada visual, nenhuma afeta trading/paridade.

**Tradução honesta:** o CORE que decide e executa trade é confiável; a PORTA DE ENTRADA visual (CS + indicadores) tem dívida real e concreta, agora mapeada com `file:line`. Nenhum achado é gambiarra minha desta sessão quebrando outra coisa — os 4 códigos novos (breaker, stress runner, auto-recovery, guardas do CS) saíram sem defeito confirmado (o breaker gerou 1 plausível de bifurcação backtest/live, §4).

## 2. CONFIRMADOS (9 — verificados a 3 lentes)

### Altos
| file:line | Achado | Impacto | Fix |
|---|---|---|---|
| `Producer.mq5:799` | Modo paridade grava `.mkstick` em `MKS-ULTIMATE\Ticks\` mas o Producer **nunca cria essa pasta** (só cria `MKS-ULTIMATE`, `Bricks`, `Logs`). `FileOpen` não cria subpasta. | `InpParityRunMode=true` em máquina limpa (ex.: troca de PC) → `INIT_FAILED`, EA não sobe. O modo de teste de paridade canônica (ADR-024) fica inutilizável. | `FolderCreate("MKS-ULTIMATE\\Ticks")` antes do `g_tickWriter.Open`, espelhando `ColorReversal.mq5:569` e `TickRecorder.mq5:288`. |

### Médios
| file:line | Achado | Impacto | Fix |
|---|---|---|---|
| `Producer.mq5:771` | `g_nextBarTime = AlignDownToM1(TimeCurrent())` **viola ADR-023 regra 1** (exige `= 0`). No fill, todo brick histórico tem `realTime < nextBarTime` → cai sempre no bump e clampa em `realTime+6h`. | Série histórica desenhada **no futuro** (banda de ~6h), não distribuída nos 30 dias reais. **É a raiz do desalinhamento horizontal do CS.** Também torna a guarda `nextBarTime>0` (2026-07-22) inerte no Producer. | Trocar por `g_nextBarTime = 0;`. O 1º brick semeia o slot com `closeTimeMsc` real. |
| `Producer.mq5:783` | ATR sizer + CS: `brickSizePts` capturado **uma vez** (warm-up) e usado fixo pra toda barra; em `SIZER_MODE_ATR` o tamanho real varia. | CS mostra caixinhas de tamanho uniforme cujo `close` diverge do `brick.close` do `.mksbk` — reintroduz "preço fictício" no desenho. Só visual. | Em modo ATR, sink desenhar com `brick.close` real (ou `brickSizePts=0` → fallback), ou bloquear ATR+CS por ADR. |
| `CMksDonchian.mq5:104` (+ Chandelier, SuperTrend) | Barras de warm-up **nunca escritas** ficam em `0.0` (buffer novo). RSI/MACD limpam com `EMPTY_VALUE`; esses três **não**. O ramo que escreveria `EMPTY_VALUE` é inalcançável. | Canto esquerdo do chart: a linha **mergulha até zero** (~20-22 barras). Testes não pegam (só leem a região calculada). Visualização enganosa. | Limpar `[0..start-1]` com `EMPTY_VALUE` (como RSI/MACD) ou `PlotIndexSetInteger(PLOT_DRAW_BEGIN, start)` no `OnInit`. |
| `CMksMACD.mq5:204` | Semente da EMA por **SMA-de-N**; o `iMACD` nativo semeia `price[0]` e recorre desde a barra 1. Definições diferentes → convergem só após ~350 bricks. Header alega paridade que não vem da semente. | Em CS jovem/recriado, os primeiros ~350 bricks divergem visivelmente do `iMACD` nativo; `Test_CMksMACD` daria FALSE FAIL se rodado cedo. Warm-up não documentado. | Semear `Fast/Slow[0]=Price(0)` e recorrer de `i=1` (paridade bit-exata), OU remover a alegação + documentar warm-up + o teste pular as 1as barras. |

### Baixos / melhoria
| file:line | Achado |
|---|---|
| `Producer.mq5:916` | Transição fill→live ancora no tick "agora"; ticks chegados **durante** o processamento do fill (segundos) são descartados. Só visual, só `fillDays>0`. Fix: ancorar no fim da janela do fill. |
| `CMksCustomSymbolSink.mqh:197` | `lastBarTime`/`nextBarTime` avançam **mesmo quando `CustomRatesUpdate` falha** → marcador de trade (ADR-028) ancora em slot sem barra. Fix: `lastBarTime` só no ramo de sucesso. |
| `CMksAtrBrickSizer.mqh:79` | `Validate()` não garante `defaultSize ∈ [minSize,maxSize]`; bricks de warm-up furam o teto configurado (afeta a ESTRATÉGIA, não só o CS). Fix: rejeitar `defaultSize` fora do range. |
| `CMksRenkoBuilder.mqh:183` (melhoria) | Builder copia `MksRenkoGeometry` **sem chamar `Validate()`**; geometria inválida (po≥1) degrada em silêncio (nenhum brick, nenhum erro). Fix: `geometry.Validate()` no construtor + fail alto. |

## 3. SINALIZADOS — verificação adversarial INTERROMPIDA (27)

Achados reais no código, **mas não confirmados pelas 3 lentes** (o limite cortou). Tratar como candidatos priorizados, não veredito. **Prioridade de verificação: os que tocam dinheiro/dados.**

### Tocam DINHEIRO ou INTEGRIDADE (verificar primeiro)
| file:line | Achado | Nota |
|---|---|---|
| `CMksTradeManager.mqh:231` | `Validate` aceita `beOffset >= beActivation` → BE põe SL além do mercado (ordem inválida/stop-out). | **VERIFICADO MANUALMENTE = REAL** (gap de config). Rebaixado ALTO→MÉDIO: exige má-config **e** TM não está no live atual (ColorReversal manda ordem direto). Fix: `if(beEnabled && beOffset >= beActivation) reject`. |
| `CMksMt5Broker.mqh:346` | Mapeia `DONE_PARTIAL`→`FILLED` (Send/Close), apagando o status PARTIAL que o contrato do header promete. | A confirmar. Se real, o E5.2 (acúmulo de fill parcial) nunca é exercitado em live real. |
| `CMksMt5Broker.mqh:371` | Fallback de filling avança só UM passo por vida do broker: `FOK→IOC→RETURN` nunca chega a RETURN se IOC falhar. | A confirmar. |
| `CMksTickFileReader.mqh:165` | Reader rejeita o arquivo INTEIRO se há records órfãos além do último `Checkpoint` (`totalSize != expected`). | Relaciona ao known-open #6, mas com mecanismo concreto: crash do Recorder → dia inteiro de captura ilegível. Fix: `totalSize < expected` (só rejeita se FALTAM records). Mesmo em `CMksBrickFileReader.mqh:159`. |
| `TickRecorder.mq5:53` | `seq` reinicia em 0 a cada processo; após crash-restart no mesmo dia, o `MultiFileTickSource` vê `seq` não-monotônico cross-file e **aborta o replay** na fronteira (metade do dia não reproduzida). | A confirmar. Fix: validar continuidade por `time_msc` (global) em vez de `seq` (intra-arquivo). |
| `CMksBrickFileWriter.mqh:194` | `WriteBrick` ignora o retorno dos `FileWrite*` e **sempre retorna true** em falha de I/O; `writeFailures` é código morto. | A confirmar. Falha silenciosa na persistência de bricks. |

### Ciclo de vida de estado (a classe da varredura)
| file:line | Achado |
|---|---|
| `ColorReversal.mq5:651` / `Producer.mq5:950` | `g_streamHalted` (e `g_tickRecFailed`) **nunca re-zerados no OnInit** → reinit por troca de input deixa o EA **mudo em silêncio**. |
| `ColorReversal.mq5:962` | Falha de `SymbolInfoTick` na âncora deixa o cursor em epoch → 1º `OnTick` reprocessa **todo o cache** como live. (Espelha um risco do Producer.) |
| `ColorReversal.mq5:1017` | Halt de stream no fill histórico trava o trading live, mas `OnInit` retorna `INIT_SUCCEEDED`. |
| `Test_MksMt5BrokerLive.mq5:111` | `g_testDone` persiste entre reinits; "mude o input pra disparar" só funciona uma vez. |

### CS / visualização / logging (a maioria)
| file:line | Achado |
|---|---|
| `CMksCustomSymbolSink.mqh:165` | `showWicks=true` em geometria median/custom (PO>0) → barra OHLC inválida (`high < close`). Não atingível pelo Producer (classic-only); atingível por renderizador de `.mksbk` median antigo. |
| `CMksCustomSymbolSink.mqh:183` | Recovery `SymbolSelect+retry` por brick sem throttle (o log é throttled) — martela a API no pior momento. |
| `ColorReversal.mq5:617` | ColorReversal **ignora** o erro do wipe do CS (o Producer agora auto-recupera — **assimetria**: o mesmo bug do dono existe no EA live). |
| `CMksAuditLogSink.mqh:78` | Audit TSV aberto sem `FILE_SHARE_READ` contradiz o `Flush()` documentado pra inspeção mid-sessão. |
| `CMksAuditLogSink.mqh:107` | Coluna `seq` emite `triggerTickId` (== coluna `tickId`), divergindo do formato documentado. |
| `CMksLogger.mqh:97` | Duas funções de escape JSON idênticas (`MksJsonEscape` livre vs `EscapeJson` membro) — hazard de divergência gêmea. |
| `CMksChartPainter.mqh:70` | `m_digits` armazenado mas nunca usado; `LogDraw` hardcoda `%.5f`. |
| `CMksRecordingBroker.mqh:105` | Getters sem guarda de índice (oob quando vazio). |
| `ColorReversal.mq5:609` | ColorReversal não valida nome do CS >32 chars; Producer tem a guarda. |
| `CMksMt5Broker.mqh:294` | SL/TP ao `OrderSend` sem `NormalizeDouble`/alinhamento ao grid — risco latente eixo-2. |

### Paridade / observabilidade
| file:line | Achado |
|---|---|
| `ColorReversal.mq5:851` | Breaker corretivo só no live; ausente de runners/replayers → **bifurcação backtest/live** (o breaker fecha posição no live mas não no replay). Decisão consciente possível, mas não registrada em ADR. |
| `ColorReversal.mq5:1155` | Live avança `feedClock`/`breaker.OnTick` em ticks que o DecisionRunner trata como inválidos — assimetria de caminho. |
| `CMksStressRunner.mqh:399` | StressRunner não tabula desfechos K102/K105 que o DecisionRunner expõe. |
| `CMksTradeJournal.mqh:137` | `RecordOpen` sobrescreve `positionId` já aberto: trade anterior some do diário sem virar closed. |
| `CMksTradeManager.mqh:53` | Contradição doc↔código: comentário diz "partialClosePct 100 = fecha tudo" mas `Validate` rejeita ≥100. |

## 4. Meu código NOVO desta sessão

Auditado adversarialmente com instrução explícita anti-autocomplacência. Resultado: **zero defeito confirmado** no `CMksCircuitBreaker`, `CMksTradeJournalingBroker`, `CMksStressRunner`, e nas guardas novas do CS. Um **plausível** contra a integração do breaker (`ColorReversal.mq5:851` — bifurcação backtest/live, §3) — a confirmar e, se real, decidir por ADR se o breaker entra nos runners.

## 5. Veredito INDICADORES ↔ CS (a pergunta central do dono)

**Ainda NÃO casam.** Divergências concretas, todas visuais (nenhuma afeta trading/paridade — a estratégia não lê o CS):

1. **Warm-up mergulha a zero** (Donchian/Chandelier/SuperTrend, confirmado) — a linha cai até 0.0 no canto do chart.
2. **MACD diverge do nativo** por ~350 bricks (confirmado) — semente errada.
3. **Barras órfãs de formação poluem os indicadores** (known-open H6): `CMksChandelier:182` e `CMksReversalRegime:124` contam barras `tick_volume==0` como bricks reais → HH/LL e state machine viciados.
4. **O próprio CS está desalinhado** (`nextBarTime` no futuro, §2) e com órfãs no slot (known-open) — o "chão" sobre o qual os indicadores calculam já está torto.
5. **RSI é o único limpo** (semente Wilder casa com o nativo).

**Para "impecável" (E7/E8), a ordem certa é:** primeiro deixar o **CS correto** (fix `nextBarTime=0`; resolver órfãs de formação; ATR+CS size), DEPOIS os indicadores (limpar warm-up; semente MACD; discriminador de órfã `tick_volume==0`). Calcular indicador sobre um CS torto é construir no torto.

## 6. Known-open redescobertos (6) — já rastreados, não são novos

`CMksCustomSymbolSink.mqh:225` (órfãs de formação / desalinhamento horizontal) · `CMksChandelier.mq5:182` + `CMksReversalRegimeDebug.mq5:124` (H6, órfãs poluem indicadores) · `CMksSimAccount.mqh:143` (OnClose ignora `lots` em partial) · `CMksTradeManager.mqh:331` (BE move SL sem ratchet) · `CMksLogger.mqh:31` (escape JSON incompleto: falta `\b \f` e controles).

## 7. Plano de ataque recomendado

**Lote A — rápidos e isolados (não tocam paridade), alto valor:**
1. `Producer.mq5:771` → `nextBarTime=0` (mata a raiz do desalinhamento do CS). *[P, toca ADR-023 — reler a regra 1 antes.]*
2. `Producer.mq5:799` → `FolderCreate(Ticks)`. *[P]*
3. Warm-up dos 3 indicadores → `EMPTY_VALUE`/`PLOT_DRAW_BEGIN`. *[P]*
4. `CMksAtrBrickSizer:79` + `CMksRenkoBuilder:183` → `Validate` defensivo. *[P — core, com teste]*
5. `CMksCustomSymbolSink:197` → `lastBarTime` só no sucesso. *[P]*

**Lote B — precisam de decisão/ADR:** ATR+CS size (`783`); breaker nos runners (`851`); MACD seed vs alegação de paridade (`204`).

**Lote C — verificar antes de consertar (retomar o workflow):** os 3 que tocam dinheiro/dados (TradeManager BE já confirmado; Mt5Broker partial; crash-tolerance dos readers). São os de maior severidade potencial e os menos verificados.

**Lote D — E7/E8 (a raiz do CS):** órfãs de formação (eixo por índice?) + discriminador de órfã nos indicadores (H6).

## 8. Próximo passo

A verificação adversarial dos 27 sinalizados **não completou** (limite de sessão, reseta 22:10 Tóquio). Retomar o workflow (`resumeFromRunId`, cache dos finders + 9 confirmados) fecha essa verificação a custo fracionado. Até lá, os 9 confirmados e o TradeManager BE (verificado à mão) são acionáveis com confiança.

## 9. Lote C — veredictos da verificação manual (2026-07-22)

Verificação à mão (leitura de código, sem workflow) dos 5 achados de dinheiro/dados do §7. **Regra do dono: verificar ANTES de consertar.** Resultado:

| # | Achado | Veredito | Severidade | Nota |
|---|---|---|---|---|
| 1 | `CMksMt5Broker:346` — DONE_PARTIAL mapeado como FILLED | **REFUTADO como afirmado** | — (latente baixo) | `ReadDealInto:135` lê `DEAL_VOLUME` real; `MakeFilledResult:170` usa `m_pendingDealVolume` (volume real), não `request.lots`; `fillPrice:168` também é o real. **Volume e preço estão corretos.** O status `FILLED` (não `PARTIAL`) é benigno: com FOK/IOC o resto é cancelado, então a posição É `filledLots`. Único resíduo latente: fill em **múltiplos deals** (`res.deal` = só o 1º) subcontaria — raro, só lote grande; não alcançável no uso atual (0.01). **O achado original estava errado — quase virei um "fix" de não-bug.** |
| 2 | `CMksMt5Broker:371` — fallback de filling incompleto | **CONFIRMADO** | Média | `m_fillingFallbackDone` só reseta no `Init:245` (e ctor), **não por Send**; `ResetPending` (chamado por Send) não o toca. Após o 1º `INVALID_FILL`, o broker trava em IOC e **nunca chega a RETURN** — nem no mesmo Send (a flag bloqueia o 2º passo `IOC→RETURN`), nem em Sends futuros. Dispara só se o broker recusar FOK **e** IOC (raro). **Fix:** resetar a flag no início de cada Send. |
| 3 | `CMksTickFileReader:165` (+`CMksBrickFileReader:159` por analogia) — cauda órfã rejeita o arquivo inteiro | **CONFIRMADO = known-open #6** | Média (durabilidade) | Validação estrita `totalSize != header + N*record` → rejeita o dia inteiro se um crash do recorder deixar registro parcial. **Falha-alto** (reporta `MKS_ERR_DATA_TRUNCATED`, não corrompe silenciosamente). É a face-leitora do known-open #6 (WriteTick parcial), não bug novo. A estritez é **correta para paridade**; o gap é a ausência de um caminho de recuperação/reparo separado. Item de durabilidade (Lote D). |
| 4 | `TickRecorder:53` — `g_seq` reseta por processo → MultiFile aborta replay | **CONFIRMADO** | Média (durabilidade) | `g_seq` é global iniciado em 0, **sem persistência**; restart do recorder (crash/reinício/novo dia) zera o seq. `CMksMultiFileTickSource:204` exige seq **global monotônico** cross-file (`tick.seq <= m_lastSeqGlobal → abort`). Descasamento design↔implementação: MultiFile assume seq global, TickRecorder produz seq process-local. Quebra quando um restart do recorder gera `_2.mkstick` (mesmo dia) e o replay encadeia `_1`+`_2`. **Falha-alto** (aborta + `SeqDiscontinuityDetected()`), não corrompe. **Fix:** persistir/rehidratar o seq no open (ler max seq do arquivo existente). Item de durabilidade. |
| 5 | `CMksTradeManager.mqh:231` — `Validate` sem `beOffset < beActivation` | **CONFIRMADO** (verificado antes) | Média | `Validate` (216-260) não checa `beOffset < beActivation` → BE pode ser configurado atrás do gatilho. TM **não está no caminho live** (ColorReversal envia ordens direto), por isso média. **Fix:** adicionar o check ao `Validate`. |

**Saldo do Lote C:** de 5 achados, **1 refutado** (Mt5Broker partial — o de maior severidade *alegada* era falso alarme), **4 confirmados** — nenhum é corrupção-silenciosa-de-dinheiro: os 2 de dados **falham-alto** (reportam e param), os 2 restantes (fallback de filling, BE validate) têm gatilho raro / fora do caminho live. **Nenhum exige ação de emergência.**

**Método (lição da retrospectiva aplicada):** peguei o dado (código real) ANTES de consertar. O achado #1 prova o valor disso — a auditoria o pintou como o pior risco de dinheiro e era o único falso. Consertar-no-chute teria "corrigido" um `filledLots` que já estava certo.

**Fixes recomendados (Lote C-fix, a greenlight do dono):** #2 (reset da flag por Send) e #5 (check no Validate) são pontuais e de baixo risco. #3 e #4 são durabilidade (Lote D, junto do known-open #6). **Não apliquei nada** — Lote C é verify-only por instrução; e sem MT5-verde à mão eu não toco no caminho do broker live no escuro.

## 10. Lote C-fix — aplicado (2026-07-23)

Aplicados os fixes confirmados no §9, **após verificação adversarial dos patches** (workflow de 5 lentes: terminação, caminhos-gêmeos, invariante, varredura-de-config, crítico-de-completude — consenso `patchSafe` nas 5, zero regressões). `compile-all`: **52/52 limpos, 0/0**.

**Aplicado:**

1. **`CMksMt5Broker` Send() — removido o gate `!m_fillingFallbackDone` (linha 371).** A cadeia FOK→IOC→RETURN agora percorre inteira num único Send (termina porque `TryFillingFallback` devolve `false` em RETURN; cadeia finita, máx 2 avanços). Estritamente mais completo que o "resetar a flag por Send" cogitado no §9 — aquele ainda travava o 2º degrau IOC→RETURN dentro do mesmo Send. O membro/getter foram **renomeados** `m_fillingFallbackDone`→`m_fillingFallbackUsed` / `FillingFallbackUsed()` (viraram puramente observáveis; o nome "Done" induziria um leitor futuro a reintroduzir o gate — armadilha).

2. **`CMksMt5Broker` Close() — espelhado o mesmo branch de fallback (BLOCKER descoberto na verificação).** Close **não tinha** fallback de INVALID_FILL: o `FlattenAll` do circuit breaker (ADR-040) re-tenta Close a cada tick e, se o broker recusasse o filling, receberia INVALID_FILL **para sempre → nunca fecharia** — a defesa central contra a lição do V5 falhava em silêncio. É a lição #2 da retrospectiva (Send↔Close, checar os dois lados) na prática. Agora simétrico.

3. **`CMksTradeManager` Validate() — adicionado `beOffsetPoints >= beActivationPoints → reject`.** Invariante matematicamente exato (operador `>=`: no gatilho `profit>=beActivation`, então `beOffset>=beActivation` poria o SL no/acima do preço). Cobre BUY e SELL (a álgebra bid/ask se cancela). + 2 casos em `Test_CMksTradeManager.mq5` (`>` e o boundary `==`). Varredura confirmou: **nenhuma config existente** (testes/EAs/runners) usa `beOffset>=beActivation` → zero regressão.

**Follow-ups análogos descobertos pelo crítico-de-completude (NÃO aplicados — precisam de decisão):**

| Item | Classe | Nota |
|---|---|---|
| **StopsLevel no Modify de BE/trail** (`CMksTradeManager`) | validador insuficiente | O check `beOffset<beActivation` não cobre `SYMBOL_TRADE_STOPS_LEVEL`: se `(beActivation−beOffset) < StopsLevel`, o broker recusa o Modify e o **BE falha em silêncio** (ramo WARN 327-344; posição segue com o SL original, mais frouxo — degrada, não perde). **Sensível a paridade:** o projeto mantém StopsLevel fora do runtime de propósito (backtest não modela StopsLevel; usá-lo bifurcaria live↔sim = eixo-2 do V5). **Decisão de ADR**, não fix silencioso. |
| **`CMksRiskManager` `maxDailyLossPct`/`maxDrawdownPct` sem teto** | validador sem limite superior (classe do bug B) | Validados só contra piso (`<0`). Um valor `>=100` passa mas é **estruturalmente inerte** (drawdown não excede ~100%) → gate de segurança silenciosamente desligado. Contraste: `partialClosePct` e `riskPercent` já têm teto. Fix candidato: rejeitar `>=100`. |
| **`CMksRenkoBuilder` `m_streamCorrupt` latch sem recovery** | latch terminal (classe do bug A) | Após L ticks inválidos, `IngestTick` retorna `false` para sempre, sem recovery — assimétrico ao run de K-exceeded (que reancoragem via `kRecoverAfter`). Provável intenção (ADR-006 §5: feed corrupto = terminal). **Confirmar intenção** antes de mexer. |

Os follow-ups entram no radar do Lote D / decisões de ADR. O `beOffset` e o `maxDailyLossPct/maxDrawdownPct` são a mesma família do bug B (validador de dinheiro sem teto) — vale um sweep dedicado nos validators do core.

### Atualização 2026-07-23 — fechamento dos 3 follow-ups

- **RiskManager teto pct → CORRIGIDO.** `Validate` agora rejeita `maxDailyLossPct >= 100` e `maxDrawdownPct >= 100` (limite inerte: o broker liquida antes de 100%; provável typo desligaria o disjuntor em silêncio). +2 testes. Varredura confirmou zero config existente afetada (inputs default 5/10; runners 0). Mesma família do bug B, agora fechada junto com o `beOffset`.
- **`m_streamCorrupt` latch → CONFIRMADO INTENCIONAL, não-bug.** ADR-006 §5 ("interrupção reportada, não emissão") e §6 ("continuar/parar/notificar é da camada de EA, não do builder") cravam o término terminal. A assimetria com o K-run é correta (K = condição normal → recupera; corrupção = anormal → o builder não adivinha). Comentário do código reforçado citando §5/§6 para não ser "consertado" no futuro. Zero mudança de comportamento.
- **StopsLevel no Modify de BE/trail → ADR (Opção A, âncora em bricks).** Furo de paridade latente (live rejeita Modify perto demais, sim aceita → saídas divergem = eixo-2 do V5), hoje **dormente** (TradeManager fora do caminho live). O projeto já tem o padrão: piso de SL ancorado em bricks, StopsLevel só como fail-fast de anexação (ADR-032 / header do RiskManager). Estender esse padrão ao BE/trail é decisão de ADR — proposta separada. **Não aplicado** (código só após o aceite da ADR).
