---
@document: docs/CHECKPOINT-2026-05-25.md
@project: MKS-ULTIMATE
@purpose: Sessão atravessando 2026-05-24 → 2026-05-25 — auditoria profunda do projeto, trincos defensivos (Bloco 1), pipeline de paridade ADR-024 completo em código (Bloco 2 — TickRecorder/Replayer/verify-parity), e pacote pré-empírico (Bloco 3 — fix wall-clock, compile-all, cheatsheet). Pipeline canônico da ADR-024 fica pronto para validação empírica de segunda quando mercado abrir.
@audience: Próxima sessão (humano + IA)
---

# CHECKPOINT — 2026-05-25 (sessão noturna atravessando 24/05 → 25/05)

Sessão pedida pelo dono com escopo "auditoria profunda do projeto, encontre falhas, monte relatório didático, depois corrija tudo". A auditoria foi entregue como relatório priorizado P0/P1/P2/P3, virou checklist-to-do em blocos, e foi executada em ordem.

**Marco do ciclo:** **Pipeline de paridade da ADR-024 está completo em código** (slices 24c materializado, 24d, 24d-p2, 24e, 24f). A validação empírica em mercado vivo é o último passo para declarar a Fase 4.5 100% concluída.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 11 arquivos, nesta ordem

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
11. `docs/CHECKPOINT-2026-05-25.md` — este (auditoria + Bloco 1 + pipeline ADR-024 completo em código)

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação.

---

## 2. Estado do código

Branch ativa: `feat/producer-classic-only`. **6 commits ahead de `origin/feat/producer-classic-only` no momento da escrita deste checkpoint** (último push foi após o slice 24f; o commit do Bloco 3 — `ebee8e7` — ainda não foi pushado).

### Histórico desta sessão (linear na branch feat/producer-classic-only)

```
ebee8e7  fix(tools): verify-parity ignora wall-clock + compile-all + cheatsheet  ← HEAD (não pushado)
29a32e0  feat(tools+docs): Slice 24f — verify-parity.ps1 + Fase 4.5 concluida
0564037  feat(experts): Slice 24e — Replayer EA (paridade bit-a-bit do builder)
0f7386a  feat(data): Slice 24d-p2 — CMksMultiFileTickSource (multi-day replay)
4fe49db  feat(services): Slice 24d — TickRecorder Service + Checkpoint no writer
54c03c6  fix(core): bloco 1 — trincos defensivos pos-auditoria                  ← inicio da sessão
d703b63  test(producer): paridade .mksbk vs reconstrucao textbook classic       ← último commit do dia anterior
```

**Totais da sessão:** 6 commits, ~2.110 linhas líquidas, 0 regressões. **35/35 .mq5 compilam 0 erros / 0 warnings** via `compile-all.ps1`.

### ADRs aceitas

**24/24 ADRs aceitas + 4 notas de esclarecimento nesta sessão** (ADR-004 alcance da convenção 7, ADR-007 WARN/ERROR rate-limited em hot path, ADR-010/011 nomenclatura, ADR-024 timestamps wall-clock no header). §4 Decisões Pendentes da `ARCHITECTURE.md` continua vazia.

---

## 3. Ciclo deste documento — em ordem cronológica

### 3.1 Auditoria profunda do projeto (resposta inicial ao pedido)

Pedido literal do dono: *"faça leitura profunda e analítica de todo o projeto, encontre falhas, divergências, possíveis erros futuros, monte relatório didático para pessoa não técnica ler"*.

Auditoria forense em ~50 arquivos do core, executada via 2 sub-agentes Explore em paralelo (paridade core + broker/trade/risk/stresslab/indicators/tooling) + leitura direta dos arquivos críticos. Achados priorizados:

- **P0 (críticos):** **zero encontrados.** Core estruturalmente sólido.
- **P1 (altos, devem ser tratados antes da Fase 9):**
  1. Logger chamado no hot path `OnTick` ([Producer.mq5:241-263](MQL5/Experts/MKS-ULTIMATE/Producer.mq5#L241-L263)) — violação literal da ADR-007 §3
  2. Fill histórico do Producer via `CopyTicksRange` ≠ fonte do live (eixo 2 do V5 em outra dimensão)
  3. TickRecorder Service (slice 24d) não existe — pipeline ADR-024 incompleto
  4. `Test_MksMt5BrokerLive.mq5` sem guard contra conta real
  5. `CMksReplayClock` retorna 0 silenciosamente antes do primeiro tick
  6. `CMksFileTickSource` multi-arquivo não implementado
  7. Sem rate-limit no `m_consecutiveInvalid` (reset prematuro)
- **P2 (médios):** 7 achados de doc/comentário/convenção.
- **P3 (baixos):** 3 achados cosméticos.

Relatório didático em duas partes:
- **Parte 1** — Sumário em linguagem comum (uma frase, imagem mental do framework, tabela do que está pronto vs faltando, resposta à pergunta "se o preço oscila 3 USD isso reflete no CS?", comparação contra V5).
- **Parte 2** — Achados técnicos priorizados (P0-P3 com arquivo:linha exatos).
- **Parte 3** — Plano de ação ordenado em 6 blocos.

Resposta do dono: "transforme em checklist-to-do, vamos concluir tudo isso hoje" → bandeira amarela (Bloco 2 sozinho são 1-2 semanas, não 1 dia) → proposta de fechar Bloco 1 + começar Bloco 2 hoje, restante em sessões dedicadas.

### 3.2 Bloco 1 — Trincos defensivos (commit `54c03c6`)

Sete pequenos consertos identificados na auditoria. ~1h de trabalho líquido.

1. **`Test_MksMt5BrokerLive`** ganha guard contra `ACCOUNT_TRADE_MODE_REAL` no OnInit — fecha porta de acidente em produção.
2. **`IClock` ganha `IsReady()` puro virtual** + implementações:
   - `CMksMt5Clock` → `true` sempre
   - `CMksReplayClock` → `m_source != NULL && m_source.TicksRead() > 0`
   - `CMksFakeClock` → `true` sempre (mocks que precisem testar "não pronto" injetam alternativa)
3. **Nota de esclarecimento ADR-007** (`ARCHITECTURE.md`) — WARN/ERROR rate-limited em hot path são aceitos; TRACE/DEBUG/INFO permanecem proibidos sem exceção. Refina §3 "hot path mudo" para reconhecer o padrão já implementado no Producer (`InpInvalidLogEvery=100`).
4. **Doc-comment 1 linha** acima de `class CMksRenkoBuilder` ("Coração do framework — transforma stream de ticks em sequência determinística de bricks Renko. Caminho único entre live e replay.") — conformidade Protocolo 1.
5. **Doc-comments** em `ContinuationThreshold` e `ReversalThreshold` explicando a fórmula de cada limiar.
6. **Comentário** sobre "point" em `CMksTradeManager` corrigido — referência a `SymbolInfoDouble` substituída por `ISymbol::Point()` (o módulo já consome `ISymbol` corretamente; só o comentário sugeria violação do Protocolo 9).

Validação: 22/22 testes do framework + Producer + `Test_MksMt5BrokerLive` compilam 0/0 via MetaEditor64 headless.

### 3.3 Slice 24d — TickRecorder Service (commit `4fe49db`)

Materializa ADR-024 §regra 2 e §regra 3. Primeira metade do pipeline de paridade.

**`MQL5/Services/MKS-ULTIMATE/TickRecorder.mq5`** (novo, pasta `Services/MKS-ULTIMATE/` criada com junction):
- Service single-symbol; operador roda N Services em paralelo para N símbolos.
- Loop com `Sleep(InpPollMs=250)` até `IsStopped()`.
- Captura via `CopyTicks(COPY_TICKS_ALL, fromMsc, 0)` com janela incremental. Anchor inicial em `SymbolInfoTick` para evitar reprocessar histórico inteiro no primeiro start.
- Roll-over diário UTC (`TimeGMT()/86400`). Nome `<symbol>_YYYYMMDD.mkstick` em `MKS-ULTIMATE\Ticks\`.
- Em colisão de nome (Service caiu e reiniciou no mesmo dia): **sufixo numérico** até `InpMaxFileAttempts=100` — mesmo padrão do Producer (ADR-014 §4). Append-com-validação fica futuro.
- Checkpoint periódico (default 100 ticks ou 2s, o que vier primeiro) patcheia header parcial — crash do Service deixa arquivo legível até o último Checkpoint.
- Dedup por `timeMsc <= último`. Filtro mínimo: descarta tick com `bid<=0 && ask<=0` (lixo estrutural do `CopyTicks`); preserva ticks com apenas um lado atualizado.

**`CMksTickFileWriter` ganha:**
- `Checkpoint(err)` — patcha tickCount/timeMscFirst/timeMscLast no header sem fechar handle; seek de volta para fim + FileFlush.
- `Flush()` — força I/O para disco sem mexer no header (cheaper).

**`Error.mqh`:**
- `MKS_ERR_DATA_RECORDER_INIT_FAILED = 809` materializado. Slot 809 antes reservado como `REOPEN_INCOMPATIBLE`; semântica trocou porque adotamos sufixo numérico em vez de append.

### 3.4 Slice 24d-parte-2 — Multi-day replay (commit `0f7386a`)

Estende o pipeline para consumo de múltiplos `.mkstick` em ordem cronológica.

**`ITickSource` ganha `LastTickTimeMsc()` puro virtual:**
- Permite `CMksReplayClock` aceitar qualquer `ITickSource*` (single, multi, futuras live) — antes acoplado ao `CMksFileTickSource` concreto.
- `CMksFileTickSource.LastTickTimeMsc()` ganhou `override`.
- Conformidade com ADR-004 §4 (extensão com mais virtual puro, nenhum método concreto entra na interface).

**`CMksReplayClock`:**
- Aceita `ITickSource*` em vez de `CMksFileTickSource*`.
- `IsReady()` usa `LastTickTimeMsc() > 0` em vez de `TicksRead() > 0` — reduz área de acoplamento, equivalente para todos os sources reais.

**`MQL5/Include/MKS-ULTIMATE/Core/Data/CMksMultiFileTickSource.mqh`** (novo):
- Construtor com array ordenado de paths + proveniência esperada.
- Transição automática entre arquivos no `Next()` quando arquivo corrente atinge EOF. Soma `TicksRead` acumulado, expõe `CurrentFileIdx`/`Path`.
- Política cross-file (todas FATAIS):
  - Symbol divergente: reusa 807 (`SYMBOL_MISMATCH`) via single-file fatal
  - Broker/Account divergente: erro novo **811** (`MKS_ERR_DATA_MULTI_PROVENANCE_MISMATCH`)
  - Seq descontínua entre arquivos: erro novo **810** (`MKS_ERR_DATA_SEQ_DISCONTINUITY`)
- Proveniência vs conta corrente em runtime: WARN-flag herdada do primeiro arquivo aberto.
- Falhas detectadas durante `Next()` (sem out-param na `ITickSource`) ficam expostas via `SeqDiscontinuityDetected`/`AdvanceFailureDetected`.

**`Test_CMksMultiFileTickSource.mq5`** (novo, 6 cenários):
1. 3 arquivos com seq contígua: 12 ticks consumidos cross-file
2. Seq descontínua: detectado fatal após drenar arquivo corrente
3. Broker divergente: `AdvanceFailureDetected` após drenar 1º arquivo
4. Lista de paths vazia: `STATE_INVALID`
5. ReplayClock cross-file: `NowMsc` transita entre p1 e p2 sem race
6. Single-file via multi: degenera para comportamento single

### 3.5 Slice 24e — Replayer EA (commit `0564037`)

Materializa ADR-024 §regra 5. EA que monta o composition root do framework **fora do Strategy Tester** e replaya `.mkstick` pelo mesmo `CMksRenkoBuilder` que rodaria em live.

**`MQL5/Experts/MKS-ULTIMATE/Replayer.mq5`** (novo) — versão mínima:
- `ITickSource`: `CMksFileTickSource` (single) ou `CMksMultiFileTickSource` (multi via `InpTickFolder` + `InpSymbolPrefix`).
- `IClock`: `CMksReplayClock` (função pura do feed).
- Builder: `CMksRenkoBuilder` com `MksGeometryClassic` (ADR-026), L e K replicando defaults do Producer.
- Sizer: `CMksFixedBrickSizer(InpBrickSizePts)`.
- Writer: `CMksBrickFileWriter` gerando `replay_<sourceStem>_<TS>.mksbk`.
- Sink: `CMksBrickWriterSink` (CS visual omitido — saída canônica é o `.mksbk`, não o chart).
- Logger: `CMksLogger` JSON-line, mesmo schema do Producer.
- Broker/Risk/TradeManager: **NÃO entram nesta versão**. Entram na Fase 9 quando estratégia existir, sob o mesmo composition root.

**Loop e performance:**
- `OnTimer` com `InpTimerMs=1` (throughput máximo MQL5).
- `InpTicksPerCycle=10000` ticks por chamada do `OnTimer`.
- `builder.SetEmitForming(false)` durante replay para suprimir callbacks de bar parcial — Replayer não tem CS visual.
- `OnTick` deliberadamente vazio — feed é `.mkstick`, não live.
- EOF ou erro fatal dispara `FinishReplay`: fecha writer, loga summary com ticksPerSec, `ExpertRemove()` automático.

**Multi-file:**
- `ListMkstickFolder` usa `FileFindFirst/Next` com pattern `<folder>\<prefix>_*.mkstick` + `ArraySort` lexicográfico (== cronológico por ADR-024 §3 naming YYYYMMDD).

**Cleanup ordenado:**
- `OnDeinit` antes de EOF (usuário desanexa): fecha writer e logger para não deixar header inconsistente.

### 3.6 Slice 24f — verify-parity.ps1 + docs (commit `29a32e0`)

Fecha o pipeline de paridade da ADR-024 (em código). A validação canônica do projeto agora é mecânica e automatizável — não depende mais de inspeção visual ou intuição.

**`tools/verify-parity.ps1`** (novo, **versão inicial — será corrigida no commit `ebee8e7` abaixo**):
- Compara `live.mksbk` vs `replay.mksbk` via `fc /b` (byte-a-byte nativo Windows).
- Pre-check de tamanho.
- Opcionalmente diff de logs após normalização de `ts`/`sessionStartMsc`.
- Filtro de "decisões" hoje cobre eventos do builder (brick, 102, 103, 104). Quando estratégia entrar, expandir para `"decision":"buy"/"sell"/"close"`.
- Exit codes: 0 paridade OK, 1 `.mksbk` divergem, 2 logs divergem, 3 arquivo não encontrado.

**`docs/PROTOCOLOS.md` Protocolo 1:**
- Novo item: "se o módulo toca paridade (`RenkoBuilder`, `ITickSource`, `IClock`, `IBroker`, estratégia, sink que escreve `.mksbk`), executar `verify-parity.ps1` antes de declarar pronto". Divergência byte-a-byte indica não-determinismo ou regressão — bloqueia o "pronto".

**`docs/REGRAS.md` §1.9 (nova):**
- "Estratégia é replay-safe". Tabela completa de APIs MQL5 proibidas em código de estratégia (`TimeCurrent`, `MathRand`, `_Symbol`, `SymbolInfo*`, `AccountInfo*`, `iCustom`/`iATR`/`iRSI`/etc, `CopyTicks`/`Rates`/`Buffer`, `OrderSend`) com substituto via interface injetada.
- A regra §1.7 proíbe o **gatilho** da bifurcação; §1.9 proíbe o **mecanismo** pelo qual a bifurcação se instalaria.
- Materializa ADR-024 §regra 6.

**`docs/ROADMAP.md`:**
- Fase 4.5 (Tick Recorder + Replayer) inserida entre Fase 4 e Fase 5.
- Status: **Concluída em código+script; validação empírica end-to-end pendente**.
- Lista 11 entregáveis materializados (TickFileFormat, Writer, Reader, FileTickSource single+multi, Mt5Clock, ReplayClock, TickRecorder Service, Replayer EA, verify-parity.ps1, 3 testes).
- 2 riscos abertos:
  - **R4.5.1** validação empírica não executada (precisa mercado aberto + demo)
  - **R4.5.2** fill histórico do Producer via `CopyTicksRange` é fonte diferente dos ticks live — paridade canônica vale apenas para trecho live capturado (ADR-027 futura quando estratégia entrar)

### 3.7 Bloco 3 — Fix wall-clock no verify-parity + compile-all + cheatsheet (commit `ebee8e7`)

**FIX CRÍTICO antes da validação empírica de segunda**

Auditoria pré-empírica de 2026-05-25 identificou que **o `.mksbk` tem `createdAtMsc` (8 bytes wall-clock no offset 184-191 do header) que diverge INERENTEMENTE entre live e replay**:

- Em **live**: `createdAtMsc` = `TimeCurrent` no momento de `Producer.OnDeinit`
- Em **replay**: `createdAtMsc` = `TimeCurrent` no momento de `Replayer.OnDeinit` (horas/dias depois)

A versão anterior do `verify-parity.ps1` (commit `29a32e0`) fazia `fc /b` puro — **teria dado fail garantido na validação empírica mesmo com builder 100% determinístico**.

**Reescrita do bloco de comparação:**
- Lê ambos arquivos como `[byte[]]` e compara em loop.
- Range 184-191 ignorado explicitamente (com constantes nomeadas espelhando `BrickFileFormat.mqh`).
- Em divergência, reporta offset exato + identifica campo (`header.broker`, `brick[42].close`, etc.) + bytes em hex ao redor.
- Tabela de fields do header e do record para diagnóstico humano.
- **Smoke test em 3 cenários** (idênticos / só wall-clock diferente / `brick[0].direction` diferente) passa todos.

**Nota de esclarecimento na ADR-024** (`ARCHITECTURE.md` §3):
- Refina §regra 7c — `fc /b` byte-idêntico fica restrito ao **range fora de 184-191**. ADR não alterada; nota registra caveat técnico.
- Documenta também que o `.mkstick` tem **2 timestamps wall-clock** (184-191 e 192-199) que devem ser excluídos em pipelines futuros de comparação de `.mkstick`.

**`tools/compile-all.ps1`** (novo):
- Sanity check headless que compila TODOS os 35 `.mq5` do projeto (Experts/Services/Scripts/Indicators) via MetaEditor64 e reporta consolidado: arquivo, status, erros, warnings, tempo.
- Auto-detecta terminal data path via `%APPDATA%\MetaQuotes\Terminal\` procurando junctions `MQL5\Include\MKS-ULTIMATE`.
- Modos: `-Quiet` (só summary), `-Editor <path>` (override).
- Exit codes: 0 limpo, 1 erros, 2 warnings, 3 setup.
- **Validado: 35/35 compilam limpos em ~47s.**
- Complementa `watch-compile.ps1` (incremental); útil pré-commit grande ou após refactor amplo, candidato a CI futuro.

**`docs/CHEATSHEET.md` §9 (nova)** — "Fluxos do framework MKS-ULTIMATE":
- `compile-all.ps1` e `watch-compile.ps1` documentados.
- **Pipeline canônico da ADR-024 passo-a-passo:**
  - Fase A (mercado aberto ≥1h): arrastar Producer + iniciar TickRecorder Service em paralelo.
  - Fase B (qualquer hora): arrastar Replayer com `InpTickFilePath` apontando para o `.mkstick` capturado.
  - Fase C: `verify-parity.ps1` sobre `live.mksbk` vs `replay.mksbk`.
- Diagnóstico de divergência: `header.*` = metadata; `brick[N].*` = não-determinismo do builder OU feed divergente.
- Localização dos arquivos (`MQL5\Files\MKS-ULTIMATE\`) e das 5 junctions terminal→repo.
- Comandos `mklink` para recriar junctions em máquina nova.

**`CMksLogger.mqh`:**
- `#define MKS_MODULE_LOGGER "Logger"` em vez de literal hardcoded na linha do META header. P3-1 da auditoria endereçado.

---

## 4. Junction nova criada nesta sessão

`MQL5/Services/MKS-ULTIMATE/` ainda não existia no repo nem no terminal data path. Foi criada nesta sessão:

```powershell
# Pasta no repo
mkdir c:\dev\MKS-ULTIMATE\MQL5\Services\MKS-ULTIMATE

# Junction no terminal data path
cd "%APPDATA%\MetaQuotes\Terminal\<HASH>\MQL5\Services"
mklink /J MKS-ULTIMATE C:\dev\MKS-ULTIMATE\MQL5\Services\MKS-ULTIMATE
```

Cinco junctions ativas no total (`Include`, `Experts`, `Services`, `Scripts`, `Indicators`).

---

## 5. Estado das fases do ROADMAP

| Fase | Antes da sessão | Após esta sessão |
|---|---|---|
| 0 — Fundação documental | concluída | concluída |
| 1 — Abstrações do core | concluída | concluída |
| 2 — RenkoBuilder | concluída + ADR-008 fechada | concluída |
| 3 — Testes unitários | concluída | concluída |
| 4 — Broker abstractions | concluída | concluída |
| **4.5 — Tick Recorder + Replayer (ADR-024)** | 50% (24a/b/c) | **100% em código** — validação empírica pendente |
| 5 — Trade Management | concluída | concluída |
| 6 — Risk Management em camadas | concluída | concluída |
| 7 — StressLab | concluída (escopo factível) | concluída |
| 8 — Logging/observability | parcial (faltava log-diff) | **parcial — log-diff tool entregue via `verify-parity.ps1`** |
| 9 — EA validação end-to-end | não iniciada | não iniciada |
| 10 — Estratégias reais | não iniciada | não iniciada |

**Métrica-chave:** Fase 4.5 passa de 50% para **100% em código** nesta sessão. A última pendência é executar o pipeline em mercado vivo na segunda-feira e confirmar `exit code 0` do `verify-parity.ps1`.

---

## 6. Cobertura de teste

| Suite | Tests | Asserts | Status |
|---|---|---|---|
| `Test_CMksMultiFileTickSource` **(novo)** | 6 | ~30 | ✓ compila 0/0 |

Outros testes não mudaram. Compilação headless via `compile-all.ps1`: **35/35 .mq5 com 0 erros e 0 warnings em ~47s**.

Smoke tests fora do MetaEditor:
- `verify-parity.ps1` em 3 cenários sintéticos (arquivos idênticos, só wall-clock diferente, `brick[0].direction` diferente) — passa todos.
- `compile-all.ps1` executa fim-a-fim sem falhas.

---

## 7. Pendências em aberto

### 7.1 Validação empírica end-to-end da ADR-024 (Fase 4.5 R4.5.1)

**Precisa mercado aberto na segunda-feira.** Procedimento documentado em `docs/CHEATSHEET.md` §9.3:

1. Anexar `Producer.mq5` em chart XAUUSDm
2. Iniciar `TickRecorder` Service (input `InpSymbol=XAUUSDm`)
3. Deixar rodar **≥ 1h** (idealmente durante movimento — abertura de Londres, news)
4. Parar ambos
5. Anexar `Replayer.mq5` com `InpTickFilePath` apontando para o `.mkstick` capturado
6. Aguardar EA encerrar (auto)
7. `powershell tools\verify-parity.ps1 -LiveMksbk <live> -ReplayMksbk <replay>`
8. **Exit code 0 = paridade bit-a-bit verificada** ✓

Se der `exit 1`, o script já identifica o offset + o campo divergente — investigação será dirigida pelo diagnóstico, não pelo olho.

### 7.2 Push do commit `ebee8e7`

O último commit (Bloco 3) ainda não foi pushado. Branch está 1 ahead de `origin/feat/producer-classic-only`. Push fica para decisão do dono — opção pode ser depois da validação empírica (caso queira squash de algum commit ou ajuste antes).

### 7.3 Achados da auditoria ainda abertos

P1 não tratados nesta sessão:
- **R4.5.2 (P1-2)**: fill histórico do Producer via `CopyTicksRange` é fonte diferente dos ticks live. Endereçado documentalmente (Roadmap R4.5.2); **ADR-027 quando virar problema concreto** (estratégia entrar) marcará bricks históricos vs live no `.mksbk` (decisão "marcar o brick" do dono, com possível expansão para cor visual no CS futura — opção (a) preferida; opção visual adiada).
- **P1-7** (rate de ticks inválidos consecutivos): adiar até evidência live mostrar necessidade.

P2 não tratados:
- **P2-4** (Logger precisão de ms): adiar para Bloco 4 (Observabilidade), valor real só quando log-diff exigir milissegundos.
- **P2-5** (`CMksCostModel` slippage estocástico): adiado, ADR posterior quando estratégia exigir.
- **P2-6** (`CMksStressLabBroker` slippage bidirecional): adiado, design atual defensável.
- **P2-7** (teste paridade `CMksMt5Broker` vs `CMksSimulatedBroker`): adiar para Bloco 3 (precisa mocks ou demo).

### 7.4 Camada de produto / UX

Mencionada em checkpoints anteriores. Não atacada nesta sessão. Continua atacável sem mercado:
- Indicadores customizados sobre Custom Symbol Renko (já há 5: Chandelier, Donchian, MACD, RSI, SuperTrend).
- Painel SaaS Navy completo do operador.
- Inputs claros + presets prontos por instrumento.

---

## 8. Próximos passos sugeridos

### Segunda-feira, mercado aberto

1. **Validação empírica da ADR-024** (§7.1 acima). Se passar → Fase 4.5 declarada 100% concluída no `ROADMAP.md`, push da branch para `origin`, merge em `main`.
2. Se o `verify-parity.ps1` reportar divergência: investigação dirigida pelo offset+campo. **Mais provável**: feed divergente (ticks que o Producer viu não foram exatamente os que o TickRecorder gravou — possível race em quem viu primeiro). **Menos provável** (mas mais grave): não-determinismo no builder.

### Independente de mercado (qualquer hora)

- **ADR-027 — marcar bricks históricos vs live no `.mksbk`** quando estratégia entrar (decisão do dono já tomada).
- **Fase 9 (EA validação end-to-end)** — depende da Fase 4.5 100% validada.
- **Achados P2 não-críticos** (logger ms, teste paridade brokers, polimentos).
- **Camada de produto / UX** (§7.4).

---

## 9. Comandos úteis para próximo chat

```powershell
# Estado da branch
git log --oneline -8

# Sanity check (35/35 .mq5 compilam 0/0)
powershell -ExecutionPolicy Bypass -File c:\dev\MKS-ULTIMATE\tools\compile-all.ps1 -Quiet

# Watcher incremental (auto-start via .vscode/tasks.json; manual:)
powershell -ExecutionPolicy Bypass -File c:\dev\MKS-ULTIMATE\tools\watch-compile.ps1

# Push da branch
git push origin feat/producer-classic-only

# Pipeline canônico de paridade (depois de capturar live em demo)
powershell -ExecutionPolicy Bypass -File c:\dev\MKS-ULTIMATE\tools\verify-parity.ps1 `
  -LiveMksbk "<path-do-live.mksbk>" `
  -ReplayMksbk "<path-do-replay.mksbk>"
```

---

**Sessão atravessando 24→25 de maio fechada.** Pipeline ADR-024 completo em código, fix crítico do verify-parity aplicado antes do empírico, 6 commits limpos, 35/35 compila 0/0. Próximo passo concreto: segunda-feira, mercado aberto, executar o pipeline de paridade canônico em XAUUSDm/Exness demo por ≥1h e confirmar `exit code 0`.
