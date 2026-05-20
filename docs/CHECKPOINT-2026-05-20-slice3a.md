---
@document: docs/CHECKPOINT-2026-05-20-slice3a.md
@project: MKS-ULTIMATE
@purpose: Adendo pós-Slice 3a — formato binário .mksbk, serializador, golden file test
@audience: Próxima sessão (humano + IA)
---

# CHECKPOINT — 2026-05-20 (pós-Slice 3a)

Adendo a [`CHECKPOINT-2026-05-20.md`](CHECKPOINT-2026-05-20.md) e [`CHECKPOINT-2026-05-20-slice2.md`](CHECKPOINT-2026-05-20-slice2.md). Este documento cobre exclusivamente o que mudou desde o fechamento do Slice 2: housekeeping pós-aceite de ADRs, Slice 3a (formato binário + serializador + golden file test), e o ponto de partida para o Slice 3b. Convenções operacionais, decisões anteriores e princípios invariantes dos checkpoints anteriores **continuam valendo sem alteração** — não são replicados aqui.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 4 arquivos, nesta ordem

1. `README.md`
2. `docs/CHECKPOINT-2026-05-20.md` — base, convenções, estado pós-Slice 1
3. `docs/CHECKPOINT-2026-05-20-slice2.md` — adendo pós-Slice 2 (validação contra dado real, ADR-012 aceita depois)
4. `docs/CHECKPOINT-2026-05-20-slice3a.md` — este, incremental

Os demais documentos (`docs/REGRAS.md`, `docs/ARCHITECTURE.md`, `docs/V5-POSTMORTEM.md`, etc.) seguem como referência sob demanda.

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação (registrado no `CLAUDE.md`).

---

## 2. Estado do código (HEAD = `42372f7`)

| Camada | Item | Estado |
|---|---|---|
| Slice 2 | `MQL5/Scripts/MKS-ULTIMATE/ValidateBuilderOnRealTicks.mq5` | feito + validado |
| Slice 3a | `MQL5/Include/MKS-ULTIMATE/Core/Data/` — formato `.mksbk` + writer + reader | **feito + testado (97 assertions, 0 falhas)** |
| Slice 3a | `MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksBrickFile.mq5` — golden file test | **feito + verde** |
| Slice 3b | Produtor fundido (EA) + Custom Symbol no MT5 | **próximo** |

### ADRs — só o que mudou desde o checkpoint anterior

| ADR | Tema | Status |
|---|---|---|
| 012 | Fonte histórica de ticks + contrato de integridade | **Aceita** (era Proposta em slice2 CHECKPOINT; aceita em `cc8129c`) |
| 013 | Independência de broker, proveniência | **Aceita** (era Proposta; aceita em `7ca4f71`) |

ADRs 001–011 sem alteração.

### Tipos do core — consequência da ADR-012

- `MksTick` ganhou `uint flags` (commit `c246646`). Bitmask dos `TICK_FLAG_*` do MT5; preservado por auditoria irreversível mesmo que o builder atual (mid-driven, ADR-010) não consuma. `ValidateBuilderOnRealTicks.mq5` propaga `mt.flags` em `ToMksTick`. Default `flags=0` no construtor — não quebra os 428 testes do `CMksRenkoBuilder`.

---

## 3. O que foi feito no Slice 3a

### Housekeeping (3 commits curtos)

- **`7ca4f71`** — ADR-013 promovida Proposta → Aceita. Decisão de papel; nenhum código tocado.
- **`c246646`** — campo `uint flags` no `MksTick` (consequência registrada em ADR-012 §4 §Consequências, ciclo próprio). Consumidor único atualizado.
- **`924153d`** — faixa 800–899 reservada em `Error.mqh` via comentário-âncora. ADR-012 explicitamente proíbe fixar números no vazio; o comentário registra a reserva, os códigos concretos vêm com o serializador (commit seguinte).

### Slice 3a propriamente (commit `42372f7`)

- **`Core/Data/BrickFileFormat.mqh`** — constantes (magic `MKSBRK01`, sizes, version, offsets) e doc-comment com layout campo-a-campo. Header 256 bytes (200 usados + 56 reservados zero-fill); brick record 72 bytes; little-endian.
- **`Core/Data/CMksBrickFileWriter.mqh`** — `Open` / `WriteHeader` / `WriteBrick` / `Close`. Header inicial grava `brickCount=0` e tempos zerados; `Close` faz `FileSeek` de volta e patcheia com valores reais. Modo `FILE_READ | FILE_WRITE | FILE_BIN` para permitir o seek. `Close` aceita `createdAtMscOverride` opcional para golden file test determinístico.
- **`Core/Data/CMksBrickFileReader.mqh`** — `Open` valida magic, formatVersion, recordSize, headerSize e tamanho total do arquivo == `header + N*record` (rejeita truncamento via `MKS_ERR_DATA_TRUNCATED`). Expõe proveniência via getters (broker, account, symbol, digits, geometry, brickSize, brickCount, times).
- **`Core/Types/Error.mqh`** — códigos concretos 800–805 na faixa Data, substituindo o comentário-âncora: `FILE_IO`, `INVALID_MAGIC`, `UNSUPPORTED_VERSION`, `HEADER_INVALID`, `TRUNCATED`, `STATE_INVALID`.
- **`Scripts/MKS-ULTIMATE/Tests/Test_CMksBrickFile.mq5`** — 4 cenários:
  1. Roundtrip campo-a-campo — proveniência + 5 bricks variados (direções, M, valores), asserção por campo.
  2. Golden file rewrite — write → read → re-write em arquivo B → compara A vs B byte-a-byte.
  3. Magic inválido rejeitado — corrompe primeiro byte e verifica que `Open` falha com `MKS_ERR_DATA_INVALID_MAGIC`.
  4. ReadNext além de `brickCount` falha com `MKS_ERR_DATA_TRUNCATED`.

---

## 4. Resultados empíricos

**Compilação:** zero erros, zero warnings (watcher auto-compile + F7 manual no MetaEditor).

**Testes:**
- `Test_CMksBrickFile`: **97 assertions, 0 falhas** — golden file byte-a-byte verde.
- `Test_CMksRenkoBuilder` (regressão pós-MksTick.flags): **428 assertions, 0 falhas** — o campo novo com default `0` não quebrou nenhum teste de Slice 1.

**Golden file determinismo:** prova empírica de que `write → read → re-write` com a mesma entrada produz bytes idênticos. O serializador é determinístico bit-a-bit, atendendo o princípio invariante 4 (determinismo) e o requisito que ADR-012 §Consequências exigia (teste golden próprio).

---

## 5. Critério de saída do Slice 3a — atendido

Acordo: "Definition of done = compila + teste passa".

- ✓ Compila sem warnings.
- ✓ 97 testes verdes (Slice 3a) + 428 testes de regressão verdes (Slice 1).
- ✓ Golden file byte-a-byte: dois writes do mesmo input geram bytes idênticos.

---

## 6. Decisões de implementação (sem ADR formal)

ADR-012 §5 explicitamente delega layout binário a "engenharia de dados, commit do serializador". Decisões fixadas no commit:

- **Magic `MKSBRK01` ASCII** — 8 bytes, version major.minor embutida para sanity humano. v2 vira `MKSBRK02`. Redundante com `formatVersion` (uint16) — duplicação intencional para detecção rápida.
- **Header de 256 bytes fixo** — 200 usados + 56 reservados zero-fill. Adição de campos em v1.x cabe no reserved sem bumping de version; v2 com layout novo bumps magic + version.
- **Brick record 72 bytes exatos** — sem padding entre campos. Mudança de tamanho de record bumps version.
- **Little-endian** — Windows nativo, projeto é Windows-only por construção (MT5).
- **`createdAtMsc` patchado no Close** — só conhecido quando o último brick foi escrito. Override opcional via parâmetro de `Close` para testes reproduzíveis.
- **Folder default**: `MQL5/Files/MKS-ULTIMATE/`. Writer **não** auto-cria subpastas — caller faz `FolderCreate` antes de `Open`. Decisão de mantê-lo testável (sem side effect).
- **Sem checksum/CRC** nesta versão — validação por tamanho de arquivo + magic. CRC pode ser adicionado em v2 se vir necessidade empírica (corrupção em produção).
- **Modo `FILE_READ | FILE_WRITE | FILE_BIN`** no writer — permite `FileSeek` de volta para patchear o header no Close. Sem isso, brickCount/times ficariam zerados no arquivo.

---

## 7. Pegadinhas confirmadas nesta sessão

- **`pwsh` ≠ `powershell`.** PowerShell 7+ (`pwsh`) vem como install separado; Windows tem PowerShell 5.1 nativo (`powershell`). Watcher e doc revisados para usar `powershell -ExecutionPolicy Bypass`.
- **Variáveis automáticas do PowerShell.** `$matches`, `$_`, `$args`, etc. são reservadas — atribuir a elas causa warning do PSScriptAnalyzer. Renomeei `$matches` → `$includeMatches`.
- **Verbos aprovados do PowerShell.** `Build-X`, `Make-X` etc. emitem warning; usar `Get-`, `New-`, `Update-`, etc. Watcher usa `Get-ReverseMap`.
- **`FolderCreate` é necessário** antes do primeiro `FileOpen` em subpastas — MT5 não auto-cria.
- **Junctions são transparentes para o watcher.** O polling por `LastWriteTimeUtc` no path do repo detecta saves vindos do MetaEditor (que escreve via junction) sem precisar observar o lado MT5. Confirmado empiricamente.

---

## 8. Próximo trabalho — Slice 3b

Restam 2 dos 4 sub-objetivos originais do Slice 3 (CHECKPOINT-2026-05-20 §3, slice2 §8):

**Slice 3b — Produtor fundido (EA) + Custom Symbol.**

1. **EA produtor** (`MQL5/Experts/MKS-ULTIMATE/Producer.mq5` ou similar):
   - Embute `CMksRenkoBuilder` + `CMksFixedBrickSizer` + `CMksBrickFileWriter`.
   - `OnInit`: opcionalmente preenche histórico via `CopyTicksRange` (mesma fonte do Slice 2), feedeia o builder, escreve bricks históricos no `.mksbk`.
   - `OnTick`: alimenta builder com cada tick em runtime, captura bricks emitidos via sink, escreve no `.mksbk` e empurra para Custom Symbol.
   - `OnDeinit`: `Close` do writer (patcheia header com `brickCount` final).
   - **Produtor único** — combate ao eixo 2 do V5: histórico e live saem do MESMO motor, no MESMO programa, sem fallback condicional.

2. **Custom Symbol** (`CustomSymbolCreate` + `CustomRatesUpdate`):
   - Cria símbolo Custom (ex.: `XAUUSDm.RKN3`) no MT5.
   - Cada brick vira uma barra: `open=brick.open`, `close=brick.close`, `high=brick.high`, `low=brick.low`, `time=closeTimeMsc/1000`, `volume=brick.volume`.
   - Pesquisar API: `CustomRatesUpdate` aceita batch de `MqlRates[]`; bricks não têm timeframe fixo, mas barras Custom podem ter time arbitrário.
   - Validar plotabilidade — abrir gráfico do Custom Symbol e verificar visualmente.

**Dependências de decisão antes do Slice 3b:**

- **Política de retomada/rotação do `.mksbk`** — se o EA cai e reinicia, abre arquivo novo ou continua o anterior? Slice 3b precisa decidir. Sugestão para arquitetura no vazio: nome do arquivo carimba `(symbol, broker, accountLogin, sessionStartTimeMsc)` — restart gera arquivo novo, retomada do builder em runtime é assunto separado (provavelmente dívida arquitetural).
- **Naming do Custom Symbol** — convenção (sufixo `.RKN3` para Renko S=3? `.RKNM` para median?). Não há ADR, decisão livre.
- **`ENUM_SYMBOL_CHART_MODE`** — Custom Symbol precisa decidir como o MT5 trata o preço (BID/LAST). Pesquisar.
- **Reconciliação de estado em restart do EA** — pendência arquitetural antiga (registrada no slice 1 CHECKPOINT §8). Slice 3b pode tocar levemente (apenas detectar "houve restart" e gravar marker no log) ou adiar inteiro.

**Não-objetivos do Slice 3b:**
- Replay/backtest a partir do `.mksbk` — isso vira a implementação de `ITickSource` de backtest, depois.
- Stop loss, gestão de trade, qualquer execução de ordem — não toca neste slice.

**Pendências estratégicas que NÃO bloqueiam Slice 3b mas precisam emergir antes de Slice 5:**
- Stop loss (R:R indefinível sem ele).
- Disciplina de perdedor (30 min vale igual ganhador e perdedor?).
- Hipótese de mercado (o que se repete no XAUUSD Renko?).

---

## 9. Tooling de desenvolvimento adicionado nesta sessão

Antes do Slice 3a, dois commits de tooling (não-código de framework):

- **`765ce1a`** — `tools/watch-compile.ps1` + `.vscode/tasks.json`. Watcher de compile incremental: detecta saves em `.mqh`/`.mq5`, monta grafo reverso de `#include` (rebuild a cada ciclo com mudanças — pega arquivos novos), compila os `.mq5` afetados via `MetaEditor64.exe /compile:` headless, parseia log e reporta verde/amarelo/vermelho. VSCode auto-start via `"runOn": "folderOpen"` em terminal dedicado silencioso.
- **`35930c7`** — registra fluxo operacional no `CLAUDE.md`: skills do projeto (`/status`, `/protocolo-1`, `/adr-novo`), invocação de `/status` no início de cada chat, e doc do watcher.

Esses commits ficam no histórico mas não fazem parte da Slice 3 — são suporte de produtividade.

---

## 10. Carga do `git log` desde o CHECKPOINT anterior

```
42372f7 feat(data): add brick file serializer with golden file test (Slice 3a)
924153d docs(core): reserve error code range 800-899 for Data per ADR-012
c246646 feat(core): add flags field to MksTick (ADR-012 consequence)
7ca4f71 docs: accept ADR-013 (broker independence, audit-trail provenance)
35930c7 docs: register operational flow (status skill + watcher) in CLAUDE.md
765ce1a chore: add MQL5 compile watcher with VSCode auto-start task
cc8129c docs: accept ADR-012 (historical tick source + integrity contract)
```

---

## 11. Como este documento evolui

- Próximo checkpoint vira `docs/CHECKPOINT-AAAA-MM-DD-slice3b.md` ao final do Slice 3b.
- Este documento não é apagado — vira histórico, como os anteriores.
- Apenas a instrução de entrada do próximo chat aponta para o checkpoint mais recente.
