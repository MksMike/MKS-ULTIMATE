---
@document: docs/CHECKPOINT-2026-05-20.md
@project: MKS-ULTIMATE
@purpose: Snapshot pós-Slice 1 e ponto de partida para o próximo chat
@audience: Próxima sessão (humano + IA)
---

# CHECKPOINT — 2026-05-20

Estado do MKS-ULTIMATE ao fim da sessão de Slice 1 (motor + testes). Este documento é o handoff: o novo chat começa daqui, não relê a conversa anterior.

**Regra:** CHECKPOINT é guia, **código é verdade**. Se este documento divergir do `git log` ou do conteúdo de um `.mqh`, o código manda. Esse princípio existe porque uma sessão anterior afirmou erradamente "builder é esqueleto" sem ler o arquivo. Não repetir.

---

## 1. Para iniciar um novo chat: leia ESTES 3 arquivos

1. **`README.md`** — o que o projeto é.
2. **`docs/CHECKPOINT-2026-05-20.md`** (este) — onde estamos e o que ficou decidido.
3. **O arquivo sob trabalho no slice atual.** No Slice 2, o script de validação em XAUUSD real (a criar em `MQL5/Scripts/MKS-ULTIMATE/`).

Outros documentos (`docs/REGRAS.md`, `docs/ARCHITECTURE.md`, `docs/V5-POSTMORTEM.md`, etc.) são **referência sob demanda** — abrir quando o trabalho atual cruzar com o que eles cobrem, não toda sessão.

---

## 2. Estado do código (verificado contra `git log`, não memória)

HEAD: `bfd1378 test: add Test_CMksRenkoBuilder with 14 cases` — pushado em `origin/main`.

| Camada | Item | Estado |
|---|---|---|
| `Core/Types/` | `Tick`, `Brick`, `OrderRequest`, `ExecutionResult`, `Error`, `RenkoGeometry`, `FormingBrick` | feito |
| `Core/Interfaces/` | `IBroker`, `IClock`, `ILogger`, `ITickSource`, `IRenkoSink`, `IBrickSizer` | feito |
| `Core/RenkoBuilder/` | `CMksFixedBrickSizer` | feito |
| `Core/RenkoBuilder/` | `CMksRenkoBuilder` | **feito e testado** — guarda ADR-006, formação ADR-010, multi-threshold ADR-011, `IsStreamCorrupt()`, `GetFormingBrick()` |
| Testes | `Test_CMksRenkoBuilder.mq5` — 14 testes, 428 assertions, 0 falhas no MetaEditor | feito |
| Produtor (Custom Symbol) | qualquer arquivo | **não existe** — Slice 3 |
| EA / estratégias | qualquer arquivo | zero |
| Broker / Trade / Risk / StressLab | qualquer arquivo | zero |

### ADRs (em `docs/ARCHITECTURE.md` §3)

| ADR | Tema | Status |
|---|---|---|
| 001–003 | SemVer / Conventional Commits / Idioma | Aceita |
| 004 | Polimorfismo (classe abstrata + 7 convenções) | Aceita |
| 005 | Framework de testes | **Pendente** |
| 006 | Tick inválido (corrigiu "phantom") | Aceita |
| 007 | Formato de log estruturado | **Pendente** |
| 008 | Reabertura de mercado | **Pendente** |
| 009 | `MksError` estruturado | Aceita |
| 010 | Parametrização RenkoBuilder + mid-driver | Aceita |
| 011 | Multi-threshold (1 brick, `thresholdsCrossed`, K) | Aceita |
| 012 | Fonte de dados histórica + integridade | **Proposta** |

ADR aceita **não se reescreve**. Esclarecimento vai como **nota datada** anexada após a ADR (padrão já em ADR-004, ADR-010, ADR-011).

---

## 3. Roadmap por slices — um chat por slice

Acordo: **Definition of done = compila + teste passa**. Documentação nova não é pré-requisito.

| Slice | Conteúdo | Status |
|---|---|---|
| 1 | Motor (`CMksRenkoBuilder`) + testes de determinismo, formação, guardas | **fechado** |
| 2 | Motor sobre dado real — `CopyTicksRange` → motor → validação visual em XAUUSD | **próximo** |
| 3 | Produtor fundido (Generator + LiveEngine num único programa) → Custom Symbol | depois |
| 4 | EA-casca — símbolo real, motor embutido, `OnTick`, desenha bricks/marcadores | depois |
| 5 | Estratégias e indicadores Renko | depois |
| 6 | Camada de risco / circuit breaker | depois |

---

## 4. Convenções operacionais (vinculantes)

### Git
- **Conventional Commits** (REGRAS §3.3): `feat:` `fix:` `refactor:` `docs:` `test:` `chore:` `perf:` `style:`. Inglês por default; ADR docs em português é aceito.
- **Uma coisa por commit** (REGRAS §3.2). Aceite de ADR e código que dela decorre são commits separados.
- **Sem `Co-Authored-By` trailer** — preferência durável, em memória.
- **`git restore .claude/settings.json`** antes de cada `git add`. O harness adiciona auto-allow rules nesse arquivo conforme comandos novos rodam; sempre limpar antes do commit.
- **`git add` explícito** por path. Nunca `git add .` ou `-A`.
- **`git diff --staged`** antes de `git commit`, sempre.
- **`git log origin/main..HEAD --oneline`** antes de `git push` — confirma a carga exata.
- **Push só com autorização explícita** ("aprovado", "push autorizado", "confirmo"). Nunca `--force` sem instrução direta.

### Nomenclatura (ADR-004 §5)
- `I*` — interfaces (classe abstrata, virtuais puros, zero campos, destrutor virtual vazio).
- `CMks*` — classes concretas com estado.
- `Mks*` — structs POD.
- `ENUM_MKS_*` — enums; constantes com `MKS_*` (sem `ENUM_`).

### Headers de arquivo (REGRAS §1.6)
Todo `.mqh`/`.mq5`:
```
//| @file           : NomeDoArquivo.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Categoria / Submódulo
//| @responsibility : 1–2 linhas
//| @depends_on     : Interfaces/classes principais
//| @install_path   : MQL5/Include/MKS-ULTIMATE/...
```
Versão/data nunca no header — git cuida.

### Includes
Sempre absoluto: `#include <MKS-ULTIMATE/Core/Types/Error.mqh>`. Nunca relativo.

### Comentários (REGRAS §1.5)
Explicam *por quê*, não *o quê*. Decisão não-óbvia ganha uma linha citando ADR aplicável.

### Códigos de erro (`ENUM_MKS_ERROR_CODE`)
- `0`: `MKS_ERR_NONE`
- `1–99`: Core (`MKS_ERR_CORE_INVALID_ARGUMENT = 1`)
- `100–199`: RenkoBuilder — `100` geometria, `101` brick size, `102` threshold K, `103` tick inválido, `104` stream corrupt
- `200–299` Broker, `300–399` Trade, `400–499` Risk, `500–599` StressLab, `600–699` Log, `700–799` Testing
- Faixa nova reservada quando módulo novo é criado.

---

## 5. MetaEditor + MT5 (junctions e armadilhas)

### Junctions ativas

```
MT5\Include\MKS-ULTIMATE      →  c:\dev\MKS-ULTIMATE\MQL5\Include\MKS-ULTIMATE\
MT5\Scripts\MKS-ULTIMATE      →  c:\dev\MKS-ULTIMATE\MQL5\Scripts\MKS-ULTIMATE\
```

Pasta de dados do MT5:
```
C:\Users\mikem\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06\MQL5\
```

Arquivo novo no repo dentro de `Core/` ou `Scripts/MKS-ULTIMATE/` aparece **automaticamente** no MetaEditor via junction. **F5 no Navigator** se não aparecer (cache).

### `_compile_check.mq5`

- Vive em `MT5\Scripts\_compile_check.mq5` (cópia plana manual, gitignored).
- Inclui tipos + interfaces + `CMksFixedBrickSizer` — **não inclui `CMksRenkoBuilder`**. Recompilar `_compile_check` valida o restante do core, não o builder. Para validar mudança no builder, recompilar `Test_CMksRenkoBuilder` ou `ValidateRenkoBuilder` direto.

### Compilação

- O assistente **não compila MQL5**. Apenas o MetaEditor (lado do dono) compila.
- Após editar `.mqh`, **recompilar com F7** antes de rodar. `.ex5` stale já foi armadilha real.
- Compilação verifica integração; teste verifica comportamento. Os dois são necessários.

### Pegadinhas conhecidas

- **`.claude/settings.json` drift** — harness mexe sozinho. Sempre `git restore` antes de commit.
- **Arquivo aberto no MetaEditor pode sobrescrever edição no disco** quando o dono salva pela IDE. Aconteceu 3× com `Error.mqh`. Fix: fechar o arquivo no MetaEditor antes de o assistente editar.
- **Warnings EOL** (`LF will be replaced by CRLF`) são esperados — `.gitattributes` define CRLF para `.mq5`/`.mqh`, LF para docs/configs.
- **Phantom modifications** após `.gitattributes` aplicar: `git add --renormalize Core/` limpa.
- **Renko-Ultimate/** untracked na raiz do repo existe desde antes do MKS-ULTIMATE — fora do escopo, ignorar.

---

## 6. Memória persistente

`C:\Users\mikem\.claude\projects\c--dev-MKS-ULTIMATE\memory\`:

- **`feedback_commit_trailers.md`** — sem `Co-Authored-By` trailer neste projeto.

---

## 7. Decisões recentes que não estão em ADR (mas vivem)

### Decisões de implementação no `CMksRenkoBuilder` (documentadas no código)

1. **Modelo de threshold:** `Continuação = lastClose ± (1-PO)·S`; `Reversão = lastClose ∓ (1-PRO)·S·revSizeRatio`. Median (0.5, 0.5, 1.0) → 0.5·S em ambos os lados; classic (0, 0, 1.0) → S simétrico.
2. **L = 10** ticks inválidos consecutivos para disparar 104 (ADR-006 §5).
3. **K = 20** thresholds em um único tick para disparar 102 (ADR-011 §4).
4. **Primeiro brick** (path `!m_hasFirstBrick`): direção pelo sinal de `mid - lastClose`, sem conceito de reversão; todos os degraus usam `(1-PO)·size`. Registrado em nota da ADR-011.
5. **Igualdade exata** (`mid == threshold`) conta como cruzamento. Decisão determinística.
6. **Reset do forming brick após emissão:** `MathMax/Min(walkClose, mid)` — captura overshoot e preserva invariante `formingLow ≤ lastClose ≤ formingHigh`.
7. **`brick.volume = 0`** em todos os bricks emitidos pelo builder — agregação por brick adiada (não implementada nesta fatia).

### Configuração de produção

- **`S` (tamanho-base do brick em pontos) = 3** para XAUUSD median. Corpo efetivo = 1.5 USD (PO=0.5). Decisão: alvo do dono é 2–3 USD; brick menor = entrada antes = maior fração capturada (~57–67% vs ~40–50% com S=6).
- Testes do builder **parametrizam S** — usam S=10 ou S=4 nos cenários canônicos, valores limpos para aritmética. Constante de produção é independente dos testes.

### Pendências estratégicas do dono (antes de qualquer EA)

- **Stop loss** — não definido. R:R indefinível sem ele.
- **Disciplina de perdedor** — confirmar se 30 min vale igual para ganhador e perdedor (padrão ganho-pequeno/perda-grande zerou o V5).
- **Hipótese de mercado** — não articulada. O que se repete no XAUUSD Renko? Observação do dono, não ferramenta.

---

## 8. Pontos cegos — visão periférica

Não fazer agora; ter consciência:

1. **Gap sinal → fill.** Brick fecha num preço; ordem preenche em outro (bid/ask reais, slippage). Camada de execução / cost model.
2. **Recuperação de estado no restart.** Posições do broker sobrevivem; estado interno em memória, não. Reconciliação no `OnInit` do EA.
3. **Camada de risco / circuit breaker** separada da estratégia. O que teria salvado o V5.
4. **Framework ≠ estratégia.** Backtest fiel de estratégia sem edge mostra fielmente que ela perde. Sucesso do framework é não mentir.
5. **Provas de fidelidade:** (a) reconstrução dupla idêntica; (b) live de um dia == reconstrução do histórico daquele dia; (c) backtest vs demo trade a trade.
6. **XAUUSD-específicos:** gap de fim de semana (ADR-008 pendente), notícias (NFP/FOMC/CPI), variação de spread por sessão e broker.
7. **IA:** monitoramento e regime *fora* do path do trade = OK. LLM ou online learning *no* path do sinal = NÃO (quebra determinismo). ONNX congelado como **um** input entre regras = possível, muito depois, nunca como oráculo.

---

## 9. Slice 2 — escopo

**Objetivo:** validar que o motor consome dado real do broker corretamente.

**Entregáveis:**
- Script em `MQL5/Scripts/MKS-ULTIMATE/` (nome a decidir, ex.: `ValidateOnXAUUSD.mq5`) que:
  - Chama `CopyTicksRange` para um intervalo de XAUUSD do broker conectado.
  - Alimenta os ticks resultantes ao `CMksRenkoBuilder` via `IngestTick`.
  - Captura bricks emitidos via `IRenkoSink` concreto.
  - Reporta: contagem de bricks, distribuição de `thresholdsCrossed`, contagem de erros 102/103/104, sequência de direções, ranges de preço.
- Validação visual: conferir contra gráfico do XAUUSD no MT5 que o número de bricks e os pontos de viragem são plausíveis para o range temporal escolhido.

**Critério de saída:** script roda sem 102/103/104 sob dado normal, contagem coerente com magnitude do movimento, conferência visual aprovada pelo dono.

**Fora do escopo do Slice 2:** persistir os bricks em arquivo, criar Custom Symbol (Slice 3), executar ordens.

---

## 10. Comandos úteis (referência rápida)

```bash
# Antes do commit
git restore .claude/settings.json
git add <paths-explícitos>
git diff --staged
git status

# Carga do push
git log origin/main..HEAD --oneline

# Push (após autorização explícita)
git push origin main

# Inspecionar junction
powershell -NoProfile -Command "Get-Item 'CAMINHO' | Format-List Name,LinkType,Target,Mode"

# Listar ADRs e status
grep -E "^### ADR-|^\*\*Status:\*\*" docs/ARCHITECTURE.md

# Validar EOL state de .mqh
git ls-files --eol MQL5/Include/MKS-ULTIMATE/Core/
```

---

## 11. Princípios invariantes (do `docs/ARCHITECTURE.md` §1)

Nunca violados:

1. **Paridade backtest/live** — mesmo feed produz mesmo resultado.
2. **Caminho de código único** — nenhuma bifurcação `if(MQL5_TESTING)`, input, flag ou compilação condicional na lógica de trading.
3. **Abstrações antes de implementações** — interfaces injetadas.
4. **Determinismo** — mesma entrada, mesma saída.
5. **Zero dependência de código fechado** para construção de bricks.

---

## 12. Como este documento evolui

- Próximo CHECKPOINT vira `docs/CHECKPOINT-YYYY-MM-DD.md` ao final do próximo slice fechado.
- O anterior **não é apagado** — vira histórico. Apenas o `CLAUDE.md` (ou a instrução de entrada do novo chat) aponta para o mais recente.
- Mudanças que justificam novo CHECKPOINT: slice fechado, decisão arquitetural significativa, ou após mais de ~5 dias de trabalho condensado.
