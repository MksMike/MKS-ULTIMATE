---
@document: docs/AUDITORIA-2026-05-25.md
@project: MKS-ULTIMATE
@purpose: Auditoria técnica completa — arquivo por arquivo, falhas, lacunas,
          divergências e robustez. Estado HEAD = 45c3a67.
@audience: Dono do projeto, assistentes de IA
---

> **⚠️ NOTA DE RESGATE (2026-07-19) — documento HISTÓRICO, não estado atual.**
> Esta auditoria detalhada (arquivo por arquivo) vivia só na branch descartável
> `claude/check-ultimate-access-5kshn` (rodada automática de 25/05, HEAD=`45c3a67`)
> e nunca subira para `main` — apenas o seu resumo/handoff (`CHECKPOINT-2026-05-25-audit.md`)
> estava versionado. Resgatada para main antes de deletar a branch zumbi, por
> completude histórica. **Os achados aqui são de 25/05 e em sua maioria já foram
> tratados** (o naming "Pts", SL vs stops level etc. viraram ADRs e foram
> resolvidos no E1/E0). Para o estado corrente, ver `docs/CHECKPOINT-2026-07-19-auditoria.md`
> e `docs/ROADMAP-CORE-HARDENING.md`. Leia isto como registro de evolução, não como fila de trabalho.

# MKS-ULTIMATE — Auditoria Técnica Completa (2026-05-25)

Auditoria de **todos os 60 arquivos versionados** (~11.110 linhas), confrontando
cada um contra os 18 ADRs de `ARCHITECTURE.md`, os 4 eixos do `V5-POSTMORTEM.md`,
os invariantes da §1 e as REGRAS. Branch `claude/check-ultimate-access-5kshn`.

**Método:** leitura integral de cada arquivo + verificação empírica de invariantes
via grep (bifurcação de ambiente, hardcode de broker, `Sleep`, `AzInvest`).

**Veredito de uma linha:** a fundação é sólida e disciplinada — os invariantes
estruturais que mataram o V5 estão honrados —, mas há **uma confusão de unidades
sistêmica** e **duas divergências de paridade na camada de execução** que precisam
de decisão antes de qualquer estratégia real tocar dinheiro.

---

## 0. O que está CORRETO (a favor do projeto)

Verificado empiricamente, não por confiança:

- **Zero bifurcação de ambiente.** `grep` por `MQL5_TESTING`/`IsTesting`/`MQLInfoInteger` em `MQL5/` → nada. Eixo 4 do V5 fechado.
- **Produtor único de bricks.** `CMksRenkoBuilder.IngestTick` é o único caminho; o `Producer` alimenta histórico (`CopyTicksRange`) e live (`OnTick`) pela mesma porta (`IngestOne`). Eixo 2 fechado.
- **Preço observado gravado.** `MksBrick.triggerPrice`/`triggerTickId`/`Overshoot()` carregam o tick real; o `close` é explicitamente marcado "NÃO usar para decisão". Eixo 1 fechado.
- **Zero hardcode de broker** em `Include/`. Zero "AzInvest" em código (só em docs, como referência negativa).
- **`Sleep` só no broker** (retry/fallback), nunca após toda ordem como no V5.
- **Determinismo testado** — golden-file byte-a-byte (`Test_CMksBrickFile`), dois builders idênticos (`Test_CMksRenkoBuilder`), dois brokers/sizers idênticos.
- **Modelo de erro limpo** (`MksError` não loga; macro captura `__FILE__/__LINE__`; faixas por módulo).
- **Lição empírica do broker aplicada** — `HistoryDealSelect(res.deal)` direto em vez de Sleep-loop (evita o deadlock single-threaded). Documentada em nota da ADR-017.

O projeto faz o difícil (disciplina arquitetural) bem. Os problemas abaixo são
de **precisão**, não de fundação.

---

## 1. Pilares do framework e suas funções

| Pilar | Arquivos-chave | Função |
|---|---|---|
| **Tipos (POD)** | `Core/Types/*` | Vocabulário de dados: `MksTick`, `MksBrick`, `MksFormingBrick`, `MksRenkoGeometry`, `MksOrderRequest`, `MksExecutionResult`, `MksError`. Autocontidos, sem lógica de negócio. |
| **Contratos (interfaces)** | `Core/Interfaces/*` | 8 interfaces puras (ADR-004): `IBroker`, `ITickSource`, `IClock`, `ILogger`, `IRenkoSink`, `IBrickSizer`, `ISymbol`, `IAccount`. Ponto de injeção que separa backtest de live. |
| **Motor Renko** | `Core/RenkoBuilder/*` | Coração. `CMksRenkoBuilder` (state machine mid-driven) + sizers (`Fixed`, `Atr`). Transforma ticks em bricks deterministicamente. |
| **Execução** | `Core/Broker/*` | `CMksMt5Broker` (real), `CMksSimulatedBroker` (backtest), `CMksCostModel` (custos). A camada onde o V5 mentiu. |
| **Persistência** | `Core/Data/*` | Formato binário `.mksbk` versionado + writer/reader, com proveniência e integridade. |
| **Borda MT5** | `Core/Symbol/*`, `Core/Account/*` | `CMksMt5Symbol`/`CMksMt5Account` — delegam à API global; isolam a lógica do MT5. |
| **Observabilidade** | `Core/Log/*` | `CMksLogger` — JSON-line, destino dual, arquivo por sessão. |
| **Testes** | `Core/Testing/*` + `Scripts/Tests/*` | Framework próprio (`Asserts`, `TestRunner`, mocks) + 4 suítes + smoke. |
| **Produção/validação** | `Experts/Producer.mq5`, `Scripts/Validate*` | EA produtor (fusão completa) + scripts de validação empírica. |

---

## 2. Achados transversais, por severidade

### 🔴 CRÍTICO

#### C1 — Confusão sistêmica de unidades: "points" que são preço. ADR-010 §7 violada.

**Onde:** `CMksRenkoBuilder.mqh:53-64` (thresholds somam `size` direto a `m_lastClose`, que é preço), `CMksFixedBrickSizer.mqh:30`, `CMksAtrBrickSizer.mqh:60`, e toda a cadeia `SizePoints()`.

**Fato:** O builder calcula `contThr = base + (1-PO)*size` somando `size` a um **preço** (`mid`), **sem nunca multiplicar por `Point()`**. Logo `SizePoints()` é consumido como **distância em preço**, não em pontos MT5. A prova está na própria documentação do projeto:
- `CHECKPOINT-2026-05-20.md:179`: *"S (tamanho-base do brick em pontos) = 3 ... Corpo efetivo = **1.5 USD** (PO=0.5)"*. Para XAUUSDm com `digits=3` (`Point=0.001`), 3 pontos MT5 = 0,003 USD — não 1,5 USD. Só fecha se S=3 for **preço**.
- `CHECKPOINT-...-slice2.md:112`: *"K · (1−PO) · S = 20 · 0.5 · 3.0 = **30 USD**"* — a conta do próprio projeto trata S como USD.
- Testes: `MakeTickByMid(2000.0)` + `sizer(10.0)` → asserta `close=2005` (degrau 5 = preço).

**Contraste interno que agrava:** `CMksCostModel.FillPriceFor` (`CMksCostModel.mqh:88`) **converte** `spreadPoints`/`slippagePoints` corretamente via `* pointValue`. Então no mesmo framework "points" significa **duas coisas**: preço no RenkoBuilder, ponto-MT5 no CostModel.

**Por que é crítico (risco financeiro):**
- Funciona hoje no XAUUSDm **por acidente de auto-consistência** (backtest e live usam o mesmo builder, então a paridade bit-a-bit se mantém). Não há bug numérico *neste* símbolo *hoje*.
- Mas viola diretamente ADR-010 §7 ("unidade interna é o ponto; pip/price convertidos na borda") — **não existe conversão na borda nenhuma**.
- É landmine de portabilidade: trocar de instrumento ou de broker (XAUUSD com `digits=2` vs `3`) muda `Point()` e, se alguém em algum momento introduzir a conversão "correta" (honrando o rótulo), **todos os tamanhos de brick mudam por um fator de `Point()`** — quebrando todo `.mksbk` histórico e toda calibração. Um operador que configura "300 pontos" esperando 3 USD recebe bricks de 300 USD.

**Solução sem gambiarra (decisão de dono, vira ADR):** escolher UM dos dois caminhos e aplicar consistente:
- **(A) Assumir preço como unidade interna** (o que o código já faz): renomear `SizePoints()`→`SizePrice()`, `InpBrickSizePts`→`InpBrickSizePrice`, campo `.mksbk` `brickSizePoints`→`brickSizePrice`, e **emendar ADR-010 §7** para registrar que a unidade interna é preço, não ponto. Menor risco (zero mudança de comportamento), só verdade nos nomes.
- **(B) Honrar "pontos" de verdade:** converter na borda — o builder recebe `ISymbol*` e faz `size_price = sizer.SizePoints() * m_point` antes da aritmética de threshold. Muda comportamento numérico (precisa recalibrar e regravar históricos). Só vale se houver intenção real de configurar em pontos-MT5.

Recomendação: **(A)** — alinha nome à realidade sem tocar comportamento nem invalidar dados. Mas é decisão arquitetural; não fazer edit silencioso.

#### C2 — Paridade quebrada na execução: `requestedPrice` difere entre os dois brokers.

**Onde:** `CMksMt5Broker.mqh:270` (`refPrice = ASK/BID`) vs `CMksSimulatedBroker.mqh:186` (`requestedPrice = m_lastMid`).

**Fato:** O broker real preenche `MksExecutionResult.requestedPrice` com **ask (compra)/bid (venda)**; o simulado preenche com **mid**. Logo `MksExecutionResult.Slippage()` (`= fillPrice − requestedPrice`) significa coisas diferentes: no simulado embute meio-spread, no real não. Qualquer métrica de release ou lógica que use `Slippage()`/`requestedPrice` diverge backtest↔live por ~meio-spread — exatamente a classe de divergência silenciosa que o projeto existe para eliminar (eixo 3 do V5).

**Solução sem gambiarra:** fixar UMA definição canônica de `requestedPrice` e aplicá-la nos dois brokers. O simulado já deriva fill de `mid ± halfSpread`; faça-o reportar `requestedPrice = mid ± halfSpread` (a cotação que a ordem mira), igual ao real. Adicionar então o **teste de paridade cross-broker** que a ADR-017 §Consequências exige (mesma sequência de requests → `MksExecutionResult` idêntico campo-a-campo) — hoje inexistente.

#### C3 — `DONE_PARTIAL` tratado como `FILLED`; `MKS_EXEC_PARTIAL` nunca emitido; fill parcial multi-deal subnotificado.

**Onde:** `CMksMt5Broker.mqh:334-343`.

**Fato:** O caminho de sucesso aceita `DONE`, `DONE_PARTIAL` e `PLACED` e devolve sempre `MakeFilledResult` com `status = MKS_EXEC_FILLED`. Isso (a) **contradiz o próprio comentário do arquivo** (`:44` "partial vira ERROR"); (b) **nunca** produz `MKS_EXEC_PARTIAL` (o enum existe e fica morto); (c) lê só `res.deal` (o primeiro deal) — um preenchimento parcial que gera múltiplos deals reporta `filledLots` do primeiro deal e rotula FILLED. O EA acha que preencheu 1,0 lote quando preencheu 0,3 → erro de tamanho de posição = risco direto de capital.

**Solução sem gambiarra:** ramo explícito para `DONE_PARTIAL` → `status = MKS_EXEC_PARTIAL`, `filledLots` = volume real preenchido (somar deals da ordem via `HistorySelectByPosition`/iteração de deals, não só `res.deal`). `PLACED` (ordem pendente colocada, sem deal) não deveria cair no caminho de fill em v1 market-only — tratar como rejeição/erro explícito em vez de virar timeout silencioso.

### 🟠 ALTO

#### H1 — SL/TP server-side não modelado no broker simulado → divergência garantida.

**Onde:** `CMksSimulatedBroker.mqh:24-27` (SL/TP armazenados, auto-close "não é responsabilidade v1").

**Fato:** Em live, o servidor fecha a posição no SL/TP **mesmo com o EA offline, intratick**. No backtest, o simulado só fecha em `Close()` explícito. Real envia SL/TP ao servidor (`CMksMt5Broker.mqh:311`); simulado os ignora. Resultado: qualquer estratégia que dependa de stop server-side terá backtest ≠ live. É assimetria de execução — a doença do V5 em outra dimensão.

**Solução sem gambiarra (vira ADR):** decidir a semântica canônica de stop e torná-la simétrica. Duas opções limpas:
- O framework **não usa stop server-side**: o real envia `SL=TP=0` e um futuro `CMksTradeManager` fecha por lógica (idêntico nos dois ambientes). Coerente com a filosofia "decisão sobre preço observado".
- OU o simulado passa a **auto-fechar intratick** comparando SL/TP contra cada `OnTick` (e o real mantém server-side) — mais difícil de manter paritário por causa do intratick.
A primeira é a mais fiel ao DNA do projeto.

#### H2 — SL/TP "presos" ao preço original no retry do broker real.

**Onde:** `CMksMt5Broker.mqh:277-292` (slPrice/tpPrice calculados **antes** do loop) vs `:308` (req.price recalculado **dentro** do loop).

**Fato:** Em requote, a ordem reenvia com preço de mercado fresco, mas SL/TP continuam ancorados no `refPrice` da primeira tentativa. Como `slPoints`/`tpPoints` são **distâncias da entrada**, após o requote o stop absoluto não corresponde mais à distância pedida.

**Solução:** recalcular `slPrice`/`tpPrice` a partir do `req.price` fresco dentro do loop, a cada tentativa.

#### H3 — Ticks fora de ordem / duplicados não tratados — exigido por REGRAS §1.8 e ROADMAP Fase 2.

**Onde:** `CMksRenkoBuilder.IngestTick` — processa na ordem de chegada, sem checar `seq`/`timeMsc` monotônicos. `Tick.mqh:15` chama `seq` de "fonte de verdade do determinismo", mas nada o aplica.

**Fato:** `ROADMAP.md` Fase 2 lista "Ticks fora de ordem (se o ITickSource entregar)" como caso de tratamento; `REGRAS.md:94` exige cobertura de teste para "ticks fora de ordem". Nenhum dos dois existe. Um tick atrasado/duplicado vira brick/reversão fantasma, e backtest (de `.mksbk` ordenado) vs live (tempo real) podem divergir.

**Solução sem gambiarra:** guarda de monotonicidade no `IngestTick` (descartar e reportar tick com `seq <= lastSeq` ou `timeMsc < lastTimeMsc`, com código de erro novo na faixa RenkoBuilder), + teste. Ou fixar formalmente que `ITickSource` garante ordem e o builder confia — mas então o teste vira teste do `ITickSource`.

### 🟡 MÉDIO

- **M1 — `ts` do logger em precisão de segundo (`.000Z`), viola ADR-007 §1 (ms).** `CMksLogger.mqh:79-87`. Quebra o log-diff (ferramenta-fim de paridade): eventos no mesmo segundo são indistinguíveis. Documentado como TODO. **Fix:** overload de `Log` aceitando `timeMsc` explícito (o tick corrente tem ms); eventos pós-brick passam `brick.closeTimeMsc`.
- **M2 — Escape JSON incompleto + ctxJson escapado pelo caller (frágil).** `CMksLogger.mqh:92-101` cobre só `\\ \" \n \r \t` — falta `\b`, `\f`, controles U+0000–001F. E o contrato `ILogger` empurra escaping de `ctxJson` ao caller; um `MksJsonEscape` esquecido → linha JSON inválida → log-diff quebra. **Fix:** cobrir todos os controles; oferecer API de contexto tipado (key/value) que escapa internamente (já previsto em ADR-007 §Consequências).
- **M3 — Broker simulado é hedging-only; conta netting diverge.** `CMksSimulatedBroker.mqh:56`. Em conta netting, ordens opostas se compensam no live, mas abrem posições separadas no simulado. **Fix:** implementar netting no simulado (ler `IAccount.MarginMode()`), ou recusar/avisar quando usado contra conta netting.
- **M4 — `brick.high/low` excluem o overshoot do trigger e enviesam o ATR.** `CMksRenkoBuilder.mqh:77-78` + teste `:284`. Para um brick bull, o mid máximo observado (o trigger) **não** está em `high` — é carregado ao próximo brick em formação. É intencional/testado, mas surpreende consumidores OHLC e o `CMksAtrBrickSizer` calcula TR sobre high/low subestimados (ATR viesado para baixo). **Fix:** decisão de dono — documentar alto e claro, ou incluir `triggerPrice` em high/low do brick emitido.

### 🟢 BAIXO (drift de doc, higiene, tooling)

- **L1 — Watcher de compile não cobre `Experts/`.** `watch-compile.ps1:55` só varre entry points em `Scripts/`. `Producer.mq5` (607 linhas, integra o stack inteiro) e `Test_MksMt5BrokerLive.mq5` nunca são compilados pelo watcher. Somado a `_compile_check.mq5` não incluir o builder (`CHECKPOINT-2026-05-20.md:139`), a rede de segurança de compile tem furos. **Fix:** adicionar `Experts/MKS-ULTIMATE` à varredura de entry points.
- **L2 — Parser de include do watcher ignora include por aspas.** `watch-compile.ps1:30` só casa `<MKS-ULTIMATE/...>`. `Asserts.mqh` inclui `"TestRunner.mqh"` por aspas → editar `TestRunner.mqh` não dispara rebuild dos testes. **Fix:** casar também `#include "..."` relativo.
- **L3 — `.gitattributes` não marca `.mksbk` como `binary`.** Com `* text=auto`, um fixture binário versionado por engano sofreria normalização de EOL e corromperia. Mitigado (`Files/` no `.gitignore`), mas higiene preventiva: `*.mksbk binary`, `*.tks binary`.
- **L4 — Doc do formato `.mksbk` mente sobre `direction`.** `BrickFileFormat.mqh:41` diz "0=BULL, 1=BEAR"; o enum real é `BULL=1, BEAR=-1`. Writer/reader concordam no cast, mas uma ferramenta externa seguindo a spec leria errado. **Fix:** corrigir o comentário para os valores reais.
- **L5 — Glossário desatualizado.** `Projeto.md:121` "Brick ... tamanho fixo" contradiz ADR-011 (multi-threshold) e o ATR sizer (dinâmico). **Fix:** "tamanho-base; pode ser múltiplo em cruzamento multi-threshold (ADR-011) ou dinâmico (ATR, ADR-018)".
- **L6 — PROTOCOLOS §9 desatualizado.** `:176` diz "ADR-018 pendente" (aceita); `:183` documenta `IBroker.Send(request, result, err)` — assinatura ≠ implementada (`Send(request)→result`). **Fix:** alinhar.
- **L7 — CHEATSHEET contradiz a disciplina de git do projeto.** `CHEATSHEET.md:36` ensina `git add .`; `CHECKPOINT-2026-05-20.md:82` proíbe (`git add` explícito, nunca `.`). **Fix:** corrigir o cheatsheet.
- **L8 — `.mksbk` sem checksum/CRC.** Validação só por magic+tamanho (`CMksBrickFileReader`). Bit-flip que preserva o tamanho passa despercebido. Decisão consciente de v1 (`CHECKPOINT-...-slice3a.md:107`); registrar como dívida para v2 se houver corrupção real.
- **L9 — `MksExecutionResult.Slippage()` é sem-sinal.** `ExecutionResult.mqh:51` `fillPrice − requestedPrice` não considera buy/sell, então o sinal não é "adverso vs favorável". Só diagnóstico — documentar.
- **L10 — Comentário enganoso nos mocks.** `CMksFakeSymbol.mqh:77` "setters fluentes (retornam ponteiro)" — retornam `void`.
- **L11 — Skill `adr-novo` ambígua.** "última ADR + 1" não bate com a numeração não-sequencial (maior é 018, mas ADR-008 segue em aberto).
- **L12 — Skill `protocolo-1` omite `@depends_on`** no checklist de header e referencia diretório `tests/` (real: `Scripts/Tests/`).
- **L13 — CHANGELOG levemente atrás.** `:64` ainda descreve "CFakeSymbol inline" (já migrado para `CMksFakeSymbol`); e a materialização da ADR-005 (framework + 4 migrações desta rodada) ainda não entrou em "Não lançado".

---

## 3. Relatório arquivo por arquivo

Legenda: **R** = responsabilidade · **+** = pontos fortes · **−** = achados · **→** = ação.

### Tipos — `Core/Types/`

**`Version.mqh`** · R: versão única SemVer. + autocontido, guard correto. − nenhum. → ok.

**`Error.mqh`** · R: `MksError` + enum por faixas + macro de localização. + separa representação de log (ADR-009); faixas coerentes; `ToString` útil. − nenhum funcional. → ok.

**`Tick.mqh`** · R: cotação crua + `seq`. + `IsValid()` correto (`bid>0 && ask>0 && ask>=bid`), base da ADR-006; `flags` preservado (ADR-012). − `seq`/`timeMsc` documentados como verdade do determinismo, mas nenhum consumidor impõe monotonicidade (ver H3). → guarda de ordem no builder.

**`Brick.mqh`** · R: brick fechado. + `triggerPrice`/`triggerTickId`/`Overshoot()` respondem ao eixo 1; comentário do `close` é didático. − semântica de `high/low` (M4) não é óbvia no tipo. → comentar que high/low são extremos de formação, sem o overshoot do trigger.

**`FormingBrick.mqh`** · R: brick em formação (ADR-010 §6). + tipo próprio, não reusa `MksBrick`. − nenhum. → ok.

**`RenkoGeometry.mqh`** · R: triplo (PO,PRO,revSizeRatio) + presets. + `Validate` via `MksError`; presets como fábricas (sem enum de modo). − nenhum. → ok.

**`OrderRequest.mqh`** · R: intenção de ordem. + `IsValid()` defensivo; `slPoints`/`tpPoints` como distância. − a unidade desses "Points" é genuína (×Point no broker), mas o nome colide com o "Points" falso do RenkoBuilder (ver C1) — confusão de vocabulário. → desambiguar nomes ao resolver C1.

**`ExecutionResult.mqh`** · R: desfecho de execução. + campos completos (swap/dealId/attempts). − `Slippage()` sem-sinal (L9); `MKS_EXEC_PARTIAL` existe mas nunca é emitido (C3). → C3.

### Interfaces — `Core/Interfaces/` (todas ADR-004-compliant: prefixo `I`, zero campos, dtor virtual vazio, tudo `=0`, `const` correto)

**`IBroker`** · + síncrono lógico, mínimo. − `Send` retorna `MksExecutionResult` (sem out-param `err`) — diverge do que PROTOCOLOS §9 documenta (L6). → alinhar doc.
**`ITickSource`** · + mínimo; comentário cita invariante 2. − contrato diz "em ordem de seq" mas não é verificado a jusante (H3). 
**`IClock`** · + limpo. − ainda sem implementação concreta nem consumidor (o builder usa `tick.timeMsc`, não `IClock`); aceitável nesta fase.
**`ILogger`** · + schema documentado. − delega escaping de `ctxJson` ao caller (M2).
**`IRenkoSink`** · + mínimo. − nenhum.
**`IBrickSizer`** · + `OnBrick` (ADR-018), `IsReady` anti-deadlock bem explicado. − `SizePoints()` carrega o nome enganoso (C1).
**`ISymbol`/`IAccount`** · + escopo focado (ADR-016); enums nativos; get-on-demand. − nenhum.

### Motor — `Core/RenkoBuilder/`

**`CMksRenkoBuilder.mqh`** · R: ticks→bricks. + guarda ADR-006 (103/104) correta; multi-threshold com limiar K e caminhada de escada (ADR-011); primeiro brick tratado (nota ADR-011); reset do forming cobre overshoot; loops com teto K (sem loop infinito). − **C1 (unidades)**; **M4 (high/low)**; **H3 (ordem)**; `size <= 0` em runtime é silenciosamente engolido (`:162`) em vez de virar `MKS_ERR_RENKO_INVALID_BRICK_SIZE`. → C1/M4/H3 + considerar erro explícito em size≤0.

**`CMksFixedBrickSizer.mqh`** · R: tamanho fixo. + simples, `IsReady=true`, `Validate` correto. − nome `SizePoints` (C1). → C1.

**`CMksAtrBrickSizer.mqh`** · R: ATR Wilder sobre bricks. + fórmula Wilder correta; warm-up SMA→Wilder; `IsReady=true` anti-deadlock; clamp; determinístico. − opera em preço (C1); herda viés de high/low (M4); `period=0` sem `Validate` prévio causaria divisão por zero em runtime (mitigado se o composition root chamar `Validate`). → C1 + garantir `Validate` no composition root (o `Producer` chama para o Fixed; faltará para o ATR quando trocar).

### Execução — `Core/Broker/`

**`CMksMt5Broker.mqh`** · R: IBroker real. + lição do `HistoryDealSelect` direto bem aplicada; fallback de filling; retry de retryables; margin mode dual; observabilidade. − **C2** (`requestedPrice`=ask/bid), **C3** (partial), **H2** (SL/TP no retry); `WaitForDealAdd` (`:147`) é efetivamente morto sob `OnTick` (single-threaded) — só funciona fora de `OnTick`; documentar que o fallback `res.deal==0` sempre dará timeout em chamada de `OnTick`. → C2/C3/H2.

**`CMksCostModel.mqh`** · R: custos do simulado. + determinístico; converte pontos→preço **corretamente** (×pointValue); slippage adverso. − ironicamente, é o único lugar que usa "points" certo — contraste que evidencia C1. → ok (usar como referência ao resolver C1).

**`CMksSimulatedBroker.mqh`** · R: IBroker backtest. + determinístico; custos no fill (eixo 3 respeitado); SL/TP em preço absoluto. − **C2** (`requestedPrice`=mid), **H1** (sem auto-close SL/TP), **M3** (hedging-only); array `m_positions` nunca encolhe → busca O(n) cresce sem limite em backtest longo (perf, não correção). → C2/H1/M3 + considerar compactar posições fechadas.

### Persistência — `Core/Data/`

**`BrickFileFormat.mqh`** · R: layout `.mksbk`. + offsets batem com o writer (header termina em 256); magic embute versão. − **L4** (doc de `direction` errada). → corrigir comentário.

**`CMksBrickFileWriter.mqh`** · R: serializa bricks. + guarda anti-sobrescrita (806, ADR-014); patch de header no Close; golden-file via override; offsets corretos. − truncamento de UTF-8 multibyte em `WriteFixedString` (broker names ASCII → benigno); destruição sem `Close` deixa header com count=0 (degradação aceitável). → ok.

**`CMksBrickFileReader.mqh`** · R: lê/valida `.mksbk`. + valida magic/version/recordSize/headerSize + integridade de tamanho; proveniência via getters. − sem CRC (L8); não compara proveniência (delegado ao consumidor — `ValidateProducerOutput` faz). → ok.

### Borda — `Core/Symbol/`, `Core/Account/`

**`CMksMt5Symbol.mqh`** / **`CMksMt5Account.mqh`** · R: impl ISymbol/IAccount via API global. + delegação direta limpa, get-on-demand, `ACCOUNT_MARGIN_FREE` (não o deprecated). − nenhum. → ok.

### Observabilidade — `Core/Log/`

**`CMksLogger.mqh`** · R: ILogger JSON-line. + destino dual; META header; flush por linha (crash-safe); helpers por nível. − **M1** (segundo, não ms), **M2** (escape incompleto + caller escapa ctx); `MksJsonEscape` e `EscapeJson` são duplicados idênticos. → M1/M2 + unificar as duas funções de escape.

### Testes — `Core/Testing/` + `Scripts/Tests/`

**`Asserts.mqh`** / **`TestRunner.mqh`** · + vocabulário uniforme, tolerância default explícita, `MKS_RUN` com stringification, singleton deliberado (ADR-005). − `Asserts` inclui `TestRunner` por aspas (afeta L2). → ok.

**Mocks** (`CMksCapturingSink`, `CMksFakeSymbol`, `CMksFakeAccount`) · + defaults sensatos, setters. − comentário "fluente" errado (L10). → trivial.

**`Test_MksTestFramework.mq5`** · + bootstrap honesto (não usa as próprias macros para se validar); cobre stringification, contadores, caminho de falha. − nenhum. → ok.

**`Test_CMksRenkoBuilder.mq5`** (14 testes, 428 asserts) · + cobre determinismo, continuação, reversão, multi-threshold, overshoot, guardas 102/103/104, classic/median, primeiro brick. − **não cobre ticks fora de ordem** (H3, exigido por REGRAS §1.8); não cobre `size≤0` em runtime. → adicionar.

**`Test_CMksSimulatedBroker.mq5`** (12, 51) · + cobre custos, SL/TP, close full/partial, hedging, determinismo. − não cobre netting (M3); confirma `requestedPrice=mid` (C2); sem cross-test de paridade com o broker real (C2). → adicionar paridade.

**`Test_CMksAtrBrickSizer.mq5`** (11, 72) · + cobre Validate, warm-up, transição, TR/Wilder, clamp, determinismo. − não exercita o viés de high/low real (usa bricks sintéticos limpos). → ok p/ unit; validação em produção pendente.

**`Test_CMksBrickFile.mq5`** (4, 97) · + roundtrip campo-a-campo, golden byte-a-byte, magic inválido, truncamento. − não testa version incompatível nem header corrompido além do magic. → opcional.

### Produção/validação — `Experts/`, `Scripts/`

**`Producer.mq5`** · R: EA fundido (builder+sizer+writer+CustomSymbol+logger). + produtor único (eixo 2); retry de sufixo (ADR-014); multi-sink limpo; cleanup ordenado; proveniência no header. − fora do watcher (L1); `InpBrickSizePts` carrega C1; `CCustomSymbolSink` perde bricks de rajada por upsert de timestamp (documentado, slot M1 monotônico mitiga). → L1/C1.

**`Test_MksMt5BrokerLive.mq5`** · R: validação empírica do broker. + plumbing mínimo, roteia `OnTradeTransaction`. − fora do watcher (L1). → ok.

**`ValidateRenkoBuilder.mq5`** · R: validação informal por cenários. + inspeção legível; reforça semântica price-unit (S=100→degrau 50). − nenhum. → ok.

**`ValidateBuilderOnRealTicks.mq5`** · R: builder sobre ticks reais. + proveniência runtime (ADR-013); diagnóstico mid vs bid; stats de spread/gap. − builder bid-driven paralelo viola ADR-010 **de propósito** (diagnóstico, bem rotulado). → ok.

**`ValidateProducerOutput.mq5`** · R: lê `.mksbk` e valida. + **implementa a comparação de proveniência warn-only** que ADR-012/013 exigem; busca o mais recente por ordem lexicográfica. − nenhum. → ok.

### Documentação e config

`ARCHITECTURE.md` (18 ADRs, rigoroso) · + livro-razão exemplar. − ADR-010 §7 contradiz o código (C1). 
`ROADMAP.md` · + fases claras. − lista "ticks fora de ordem" (Fase 2) como caso a tratar — não implementado (H3).
`Projeto.md` · − glossário "tamanho fixo" (L5).
`REGRAS.md`/`TOM-E-CHATS.md` · + contrato de conduta/voz sólido. − §1.8 exige teste de ordem ausente (H3).
`V5-POSTMORTEM.md` · + gabarito dos 4 eixos; honra a regra "código é verdade".
`PROTOCOLOS.md` · + 9 protocolos. − §9 stale (L6).
`CHEATSHEET.md` · − ensina `git add .` (L7).
`CHANGELOG.md` · − levemente atrás (L13).
4 `CHECKPOINT-*` · + handoffs ricos e honestos (registram débitos: re-validação runtime do builder pós-`OnBrick`, ATR ainda não usado em produção). São a melhor fonte de verdade histórica.
`watch-compile.ps1` · − L1, L2.
`.gitattributes` · − L3. `.gitignore`/`.vscode/tasks.json`/`.claude/*` · ok (permissões de segurança sensatas).

---

## 4. Stress-test: modos de falha que custam dinheiro

| Cenário | O que acontece hoje | Severidade |
|---|---|---|
| Trocar de instrumento/broker e configurar "em pontos" | bricks errados por fator `Point()` (C1) | 🔴 |
| Estratégia mede slippage/usa `requestedPrice` | backtest mente vs live por meio-spread (C2) | 🔴 |
| Ordem grande com preenchimento parcial | EA acha que preencheu tudo; tamanho de posição errado (C3) | 🔴 |
| Estratégia com stop server-side | backtest nunca dispara o stop que o live dispara (H1) | 🟠 |
| Requote em mercado volátil | SL/TP em distância errada da entrada real (H2) | 🟠 |
| Feed entrega tick fora de ordem/duplicado | brick/reversão fantasma, possível divergência (H3) | 🟠 |
| Conta live é netting | posições do backtest (hedging) ≠ live (M3) | 🟡 |
| Auditoria de paridade via log-diff | timestamps de segundo escondem ordem intra-segundo (M1) | 🟡 |
| Valor de contexto de log com aspas/quebra | linha JSON inválida, log-diff quebra (M2) | 🟡 |

---

## 5. Recomendação de sequência (sem gambiarra)

1. **Decidir C1** (unidade: preço vs ponto) — vira ADR; é pré-requisito conceitual de tudo na camada de preço. Recomendo opção (A): renomear para preço + emendar ADR-010 §7.
2. **Fechar C2 + C3 + escrever o teste de paridade cross-broker** que a ADR-017 já exige. É a prova de que a camada de execução não repete o V5.
3. **Decidir H1** (semântica de stop) — vira ADR; bloqueia o `CMksTradeManager` (Fase 5).
4. **H2, H3** — fixes localizados + testes (H3 fecha um item de REGRAS §1.8 hoje em aberto).
5. **M1/M2** quando o log-diff virar ferramenta ativa (Fase 8).
6. **Lote de higiene L4–L13** — um commit `docs:`/`chore:` de baixo risco.

Nenhum desses é "consertar para o erro sumir": cada um ataca causa-raiz (unidade real, definição canônica de preço de referência, semântica de stop, contrato de ordem do feed).
