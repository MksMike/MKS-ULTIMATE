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

## 2. Estado do código (HEAD do dia = `4756e8e`)

Slice 3b proper fecha em `a06cbe9`. Após o slice, na mesma sessão, foi feita a **integração da auditoria MQL5** (commit `4756e8e`) — distribuição dos 4 sinais novos da auditoria nos documentos existentes, sem criar arquivo de auditoria separado. Ver §3.4 abaixo.

| Camada | Item | Estado |
|---|---|---|
| Slice 3a | `MQL5/Include/MKS-ULTIMATE/Core/Data/` — formato `.mksbk` + writer + reader | feito + testado (97 assertions) |
| Slice 3a | `MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksBrickFile.mq5` — golden file | feito + verde |
| Slice 3b parte 1 | `MQL5/Experts/MKS-ULTIMATE/Producer.mq5` — EA fundido | **feito + validado** |
| Slice 3b parte 1 | `MQL5/Scripts/MKS-ULTIMATE/ValidateProducerOutput.mq5` — leitor | **feito** |
| Slice 3b parte 2 | Custom Symbol no Producer (`CCustomSymbolSink` + `CMultiSink`) | **feito + validado** |
| ADR-014 | Política de rotação e naming do `.mksbk` | **Aceita** |
| Auditoria MQL5 | Integração nos docs (ARCHITECTURE §2/§4, Protocolo 9, §6 deste CHECKPOINT) | **feita** (commit `4756e8e`) |

### ADRs — só o que mudou desde o checkpoint anterior

| ADR | Tema | Status |
|---|---|---|
| 014 | Política de rotação e naming do `.mksbk` | **Aceita** (`8e30554`) |
| 015 | Strategy Tester nativo como ferramenta vs. fonte de verdade | **Aceita** (commit deste aceite) |
| 016 | Interfaces `ISymbol`/`IAccount` + checklist API globais | **Pendente** — adicionada pós-auditoria |
| 017 | Modelo de confirmação de execução do `CMksMt5Broker` | **Pendente** — adicionada pós-auditoria |
| 018 | Cálculo do ATR no `CMksAtrBrickSizer` | **Pendente** — adicionada pós-auditoria |

ADRs 001–013 sem alteração.

### Códigos de erro — só o que foi adicionado

- `MKS_ERR_DATA_FILE_EXISTS = 806` em `Core/Types/Error.mqh` (faixa Data). Consequência da ADR-014 §4 cláusula 4.

---

## 3. O que foi feito no Slice 3b + housekeeping pós-fechamento

6 commits sobre HEAD `918c45f` (5 do slice + 1 da integração da auditoria, mais este próprio CHECKPOINT em `f734464`):

```
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

Estado das ADRs pendentes, atualizado pós-Slice 3b:

| ADR | Tema | Status pós-Slice 3b |
|---|---|---|
| 005 | Framework de testes unitários | **Pendente** — não enfrentada. Testes atuais (`Test_CMksRenkoBuilder` 428 assertions, `Test_CMksBrickFile` 97 assertions) usam asserções inline, sem framework formal. |
| 007 | Formato do log estruturado | **Aceita** (commit deste aceite). JSON-line + destino dual (Print+FileWrite) + hot path mudo + arquivo por sessão. Bloqueia implementação de `CMksLogger` mas destrava arquitetura. |
| 008 | Reabertura de mercado no RenkoBuilder | **Pendente com evidência parcial registrada** (`CHECKPOINT-2026-05-20-slice2.md` §6): o builder atual já trata gap de fim de semana via ADR-011 multi-threshold; teste de 7 dias incluindo gap de 49h gerou M=2 sem erros. Evidência insuficiente para generalizar (1 instrumento, 1 broker). |
| 016 | Interfaces `ISymbol`/`IAccount` + checklist API globais | **Pendente** — adicionada pós-auditoria MQL5. Protocolo 9 já estabelece a fronteira; falta a ADR formal e as interfaces. Bloqueia `CMksTradeManager`/`CMksRiskManager`/estratégias. |
| 017 | Modelo de confirmação de execução do `CMksMt5Broker` | **Pendente** — adicionada pós-auditoria MQL5. Bloqueia Fase 4 (Broker abstractions). Inclui síncrono vs. assíncrono via `OnTradeTransaction`, filling mode, netting vs. hedging. |
| 018 | Cálculo do ATR no `CMksAtrBrickSizer` | **Pendente** — adicionada pós-auditoria MQL5. ADR-010 §Consequências adiou explicitamente. Três alternativas mapeadas em `ARCHITECTURE.md` §4. |

Outras dívidas registradas:

- **Recuperação de estado em restart do EA** — ADR-014 §Consequências adia explicitamente. Estado do builder é zerado a cada `OnInit`; reconciliação parcial é proibida por design.
- **Continuidade visual entre sessões no Custom Symbol** — ADR-014 §Consequências. Workaround atual: `InpHistoricalFillDays > 0` reconstrói N dias no `OnInit`.
- **Limite de tentativas do retry de sufixo (`kMaxAttempts=100`)** — não-arquitetural, fixado no `Producer.mq5`. Revisitar se 100 colisões num segundo for cenário real.
- **WARN `CustomRatesDelete lastErr=5019`** no primeiro run de cada combinação símbolo/size — benigno (CS recém-criado sem bars). Pode ser suprimido em futuro polish.

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
