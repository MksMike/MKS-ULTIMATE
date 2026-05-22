---
@document: docs/CHECKPOINT-2026-05-23.md
@project: MKS-ULTIMATE
@purpose: Adendo do dia 2026-05-23 — auditoria V5/Renko-MQL5, ADR-023 (Timeline híbrida) adiada, painel SaaS Navy + Producer refactor OnInit→OnTimer
@audience: Próxima sessão (humano + IA)
---

# CHECKPOINT — 2026-05-23 (painel UX + Producer refactor)

Adendo a [`CHECKPOINT-2026-05-22-cs.md`](CHECKPOINT-2026-05-22-cs.md). Cobre exclusivamente o trabalho deste ciclo: auditoria das pastas de referência (V5/, Renko-MQL5/), ADR-023 registrada como Proposta (implementação adiada para fase de produto), painel UX `CMksProgressPanel` no estilo SaaS Navy, e refactor do `Producer` para processar fill histórico em chunks via `OnTimer`.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 8 arquivos, nesta ordem

1. `README.md`
2. `docs/CHECKPOINT-2026-05-20.md` — base, convenções, estado pós-Slice 1
3. `docs/CHECKPOINT-2026-05-20-slice2.md` — adendo pós-Slice 2
4. `docs/CHECKPOINT-2026-05-20-slice3a.md` — formato `.mksbk`
5. `docs/CHECKPOINT-2026-05-21-slice3b.md` — Producer + Custom Symbol + ADRs 015/007/018/016/017
6. `docs/CHECKPOINT-2026-05-22.md` — pós-validação ADR-005 (framework de teste)
7. `docs/CHECKPOINT-2026-05-22-cs.md` — Custom Symbol completo + Fases 5a/6.1
8. `docs/CHECKPOINT-2026-05-23.md` — este, incremental

Sub-artefatos não-essenciais: `docs/CHECKPOINT-2026-05-22-adr005.md` (test plan ADR-005 arquivado).

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação.

---

## 2. Estado do código (HEAD = `6dd3bd6`)

3 commits sobre `bbe93e8` (último checkpoint), em uma única frente de trabalho — Custom Symbol UX e arquitetura de inicialização do Producer:

| Commit | O quê |
|---|---|
| `835803a` | docs: propose ADR-023 (Timeline híbrida, implementação adiada) |
| `a28510c` | feat(output): `CMksProgressPanel` (SaaS Navy + spinner Braille) |
| `6dd3bd6` | refactor(producer): `OnInit → OnTimer` chunks + painel integrado |

### Arquivos novos / mudados

| Arquivo | Mudança | Linhas |
|---|---|---|
| `docs/ARCHITECTURE.md` | +ADR-023 (Proposta) | +90 |
| `Core/Output/CMksProgressPanel.mqh` | novo (~400 linhas) | +396 |
| `Experts/MKS-ULTIMATE/Producer.mq5` | refactor + 6 hooks de painel + funções de chunk | +207 / -20 |
| `.gitignore` | +V5/, +RENKO-MQL5/, +Renko-MQL5/, +Renko-Ultimate/ | +7 |

### ADRs movimentadas

| ADR | Tema | Status |
|---|---|---|
| **023** | Timeline híbrida no Custom Symbol (real + bump) | **Proposta** (adiada para fase de produto) |

ADRs 001-022 sem alteração. ADR-020 e ADR-022 já carregavam discussão da timeline; ADR-023 consolida formalmente sem executar.

### Decisões operacionais

- **`V5/`, `Renko-MQL5/`, `Renko-Ultimate/` adicionadas ao `.gitignore`**. São referências locais (V5 antigo do dono, projeto Renko community do MQL5, e code-review V5). Auditadas integralmente neste ciclo — material extraído está em ADRs/comentários do código atual. Não vão pro repo público.
- **`MQL5_TESTING` → `MQL_TESTER`** no Producer (constante MQL5 deprecated em builds recentes).
- **Histórico default 30 dias** já aplicado desde ADR-022. Sem mudança neste ciclo.

---

## 3. Auditorias do ciclo

### 3.1 V5/V5-Dashboard.mq5 (3.069 linhas)

Extração do estilo SaaS Navy/Slate para o `CMksProgressPanel`:

- Paleta: bg `C'15,17,23'` / card `C'22,27,38'` / borda `C'70,75,90'` / texto `C'200,205,215'` / accent azul `C'0,150,255'` / verde `C'0,200,120'` / vermelho `C'230,60,60'`.
- Padrão de objetos: prefixo `MKSD_` (V5) → `MKS_PANEL_` (nosso). Atributos `CORNER_LEFT_UPPER`, `BACK=false`, `SELECTABLE=false`, `HIDDEN=true`.
- Tipos: `OBJ_RECTANGLE_LABEL` (cards) + `OBJ_LABEL` (textos).
- Fontes: Segoe UI 9pt base + Consolas para dados monoespaçados.
- Cleanup: percorre `ObjectsTotal()` por prefixo.

**Confirmação:** Dashboard.mq5 e Dashboard2.mq5 são **bit-a-bit idênticos** (149.893 bytes). A "versão avançada" mencionada é o mesmo arquivo duplicado.

### 3.2 V5/V5-ProgressPanel.mqh (~303 linhas)

Classe `CProgressPanel` do V5 serviu como referência direta de API (Init, UpdateStatus, Finish, ShowError, Clear). Adotamos a estrutura mas trocamos:
- Paleta `clrBlack` + `clrLimeGreen` → SaaS Navy/Slate
- Único modo (init) → dois modos (init + live)
- Sem spinner → spinner Braille Unicode (10 frames `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏`)
- `Print()` em erro → `g_panel.ShowError()` muda cor/texto in-place

### 3.3 Renko-MQL5/renko2.mq5 + RenkoCharts.mqh (~70KB)

**Auditoria:** projeto community MQL5, amador na arquitetura mas com **3 pérolas** relevantes:

1. **Algoritmo de timeline `real + bump`** (`RenkoCharts.mqh:172-177`) — usa tempo real do tick quando não colide, bump +60s quando colide. Padrão adotado na ADR-023 (Proposta, adiada).
2. **Wicks ativos por padrão** (`RenkoCharts.mqh:52-53`) — input `RenkoWicks`. Decidimos manter `showWicks=false` default no MKS-ULTIMATE (ADR-022 §3) pela coerência visual de Median Renko.
3. **Inicialização de 2 bricks âncora** (`RenkoCharts.mqh:240-256`) — invariante estrutural mais robusta que nosso "switch + walking_direction" no `CMksRenkoBuilder`. **Não adotado** — refactor não-trivial sem ganho funcional.

**Pontos negativos do Renko-MQL5** (rejeitados): bifurcação live/histórico sem sync (exatamente o Eixo 2 do V5-POSTMORTEM), sem validação de tick, `MessageBox` em erro, sem persistência `.mksbk`, reversão binária.

**Veredito:** zero valor arquitetural; valor pedagógico em 2 detalhes que ficaram registrados em ADR-023 (timeline) e CHECKPOINT (referência futura para o item de wicks).

---

## 4. Slices entregues

### Slice 23a — ADR-023 (Timeline híbrida, Proposta)

Decisão tomada com base em discussão técnica profunda sobre os impactos da **timeline fake** atual:

- Tempo `nextBarTime += 60s` por brick (independente de tempo real) gera fricções:
  - Múltiplos CSs com sizes diferentes não comparam visualmente
  - Sessões de mercado (Sydney/Tokyo/London/NY) somem do eixo X
  - Notícias / eventos econômicos não alinham
  - Bricks históricos de 30d aparecem em 6.5 dias no futuro fake
- **Solução adotada (não implementada):** `time = max(realTime, lastSlot + 60s)`, igual Renko-MQL5.
- **Implementação adiada** para fase de produto — custo trivial (~20 linhas), benefício alto de UX, sem urgência técnica.
- Critério para promover de Proposta para Aceita: produtizar framework, primeira demo externa, integração com calendar API, ou suporte a CSs comparativos lado-a-lado.

### Slice 23b — `CMksProgressPanel` (SaaS Navy + spinner Braille)

Novo arquivo `Core/Output/CMksProgressPanel.mqh` (~400 linhas). Cobre dois modos de UI:

**Modo init** — durante setup + fill histórico (20-40s):
- Cabeçalho com título + spinner Braille rotativo
- Subtítulo dinâmico ("Carregando 30 dias de histórico...")
- Barra de progresso (0-100%) com preenchimento azul accent
- 4 estatísticas: Ticks processados/total, Bricks emitidos, Tempo decorrido, Velocidade tps

**Modo live** — após CS aberto:
- Bolinha verde fixa (indicador de "operando")
- Symbol → CS name, Type + Size, "Gerado em DATA HORA"
- Ticks/sec, último brick, sync status (verde OK / vermelho DRIFT)

**Detalhes técnicos relevantes:**
- Strings por valor em toda assinatura pública/privada — MQL5 não aceita rvalues (`StringFormat`, `Spinner(idx)`) em `const string &`.
- Cleanup percorre `ObjectsTotal()` filtrando por prefixo `MKS_PANEL_*`.
- Backtest guard: painel não é criado quando `MQLInfoInteger(MQL_TESTER) == 1`.

### Slice 23c — `Producer.mq5` refactor `OnInit → OnTimer`

Refactor obrigatório para o painel funcionar com progresso visível: `OnInit` precisa retornar rápido para o MT5 renderizar a UI; o loop pesado do fill histórico (1.7M ticks) movido para `OnTimer`.

**Mudanças:**

1. Detecta `MQL_TESTER` no início (substitui `MQL5_TESTING` deprecated).
2. `g_panel.InitMode(...)` na linha 1 quando não-teste.
3. `UpdateSubtitle` em cada passo lento (logger init, abrir .mksbk, criar CS, wipe, "Carregando N dias...").
4. `RunHistoricalFill` (síncrono) substituído por trio:
   - `StartHistoricalFill(days)`: chama `CopyTicksRange` (síncrono, ~1-3s), grava estado.
   - `ProcessHistoricalChunk()`: processa 10k ticks por chamada do timer.
   - `FinalizeHistoricalFill()`: libera `SetEmitForming(true)`, loga totais.
5. `OnInit` dispara `EventSetMillisecondTimer(50)` e retorna `INIT_SUCCEEDED`.
6. `OnTimer`:
   - Fase fill: `ProcessHistoricalChunk` + `UpdateProgress` no painel; quando termina, `FinishInitAndGoLive`.
   - Fase live: `UpdateLive` no painel a 1Hz com ticks/sec, último brick, sync (`writer.BrickCount() == sink.bricksWritten`).
7. `FinishInitAndGoLive`: ChartOpen(M1) + `g_panel.LiveMode` + troca timer para 1Hz.
8. `OnTick`: ignora durante `g_fillRunning`.
9. `OnDeinit`: `EventKillTimer` + `g_panel.Clear()` antes do cleanup atual.

**Compile gate:** Producer + 8 testes existentes, todos `0/0`.

---

## 5. Cobertura de teste

Sem mudança no número total — slice deste ciclo é UX/lifecycle, não lógica testável em isolamento.

| Suíte | Asserts | Tests |
|---|---|---|
| `Test_MksTestFramework` (smoke) | 11 | 4 |
| `Test_CMksSimulatedBroker` | 51 | 12 |
| `Test_CMksAtrBrickSizer` | 72 | 11 |
| `Test_CMksBrickFile` | 97 | 4 |
| `Test_CMksRenkoBuilder` | ~440 | 22 |
| `Test_CMksPositionSizer` | 61 | 30 |
| `Test_CMksRiskManager` | 33 | 21 |
| `Test_CMksRiskGatedBroker` | 23 | 10 |
| **TOTAL (excl. smoke)** | **~810** | **~110** |

**Lacunas conhecidas que continuam não-bloqueantes:**
- `CMksProgressPanel`: sem unit test (depende de API gráfica global do MT5; cobertura empírica via Producer no chart real).
- `CMksMt5Symbol`, `CMksMt5Account`, `CMksMt5Broker`, `CMksLogger`: idem — dependem de API MT5 global.

---

## 6. Pendências em aberto

### 🟡 Médio (não-bloqueante)

- **ADR-023 (Timeline híbrida)** — Proposta, implementação adiada para fase de produto.
- **Script `MksCleanupCustomSymbols.mq5`** (ADR-020 regra 8, dívida desde 2026-05-22).
- **Slice 6.2 — Risk Por Estratégia**: max posições simultâneas, exposure total.
- **Slice 6.3 — Risk Por Conta**: daily loss limit, max drawdown, circuit breaker.
- **Slice 5b — `CMksTradeManager`**: state machine + BE + trailing + partial close.
- **Log-diff tool** (Fase 8 fechar) — script que compara `.log` de backtest com live.
- **CHANGELOG.md catch-up** — ADRs 019-023 e slices recentes não documentados lá. ~15-30 min.

### 🟢 Baixo

- Template `.tpl` para chart do CS (ADR-022 §9, dívida).
- `Test_All.mq5` unificado (carry-over).
- `Core/Testing/Fixtures.mqh` canônico (carry-over).
- Tooltip enriquecido nos inputs do Producer (apenas grupos hoje).

---

## 7. Próximos passos sugeridos (não fechados)

1. **Slice 6.2 ou 5b** — Mike escolhe a ordem. ADR-019 sugere 6.2 antes de 5b (Risk antes de Trade), mas qualquer um dos dois é coerente arquiteturalmente.
2. **CHANGELOG catch-up** — uma rodada de housekeeping documentando ADRs 019-023 e slices 5a/6.1/20/21/22/23. Vale fazer antes de abrir nova frente.
3. **Decisão final sobre referências locais**: `V5/`, `Renko-MQL5/` ficam no `.gitignore` (já feito). Posso apagar do disco se você quiser, ou manter como material de referência futura.
4. **Quando produtizar o framework:** promover ADR-023 para Aceita e executar (~20 linhas).

---

## 8. Comandos úteis para próximo chat

```powershell
# estado atual
git log --oneline -10
git status

# rodar testes existentes (em ordem)
# arrastar cada Test_*.mq5 no chart MT5, ver Toolbox > Experts

# rodar Producer (já com painel + auto-open CS)
# arrastar Experts > MKS-ULTIMATE > Producer no chart base XAUUSDm
# popup nativo do MT5 mostra inputs em 4 grupos
# painel aparece imediatamente no canto sup esq
# após fill terminar, chart do CS abre automaticamente em M1

# compile headless de um .mq5
& "C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe" /compile:<caminho>

# verificar sync junctions (regra de memória)
ls "$env:APPDATA\MetaQuotes\Terminal\<id>\MQL5\Include\MKS-ULTIMATE\Core"
```

Estado limpo. Próxima rodada começa em `main @ 6dd3bd6` (após este checkpoint, em `main @ <novo-hash>`).
