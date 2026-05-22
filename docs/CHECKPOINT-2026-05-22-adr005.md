# Test Plan — ADR-005 (Core/Testing framework + migração das suítes)

**Status:** validação pendente (você sem PC no momento da migração)
**Branch:** `claude/check-ultimate-access-5kshn`
**Commits da rodada:** `e6e6c4d` → `b122690` (7 commits)

## Por que este documento existe

A rodada de implementação do framework de teste (ADR-005) e migração das 4 suítes existentes foi feita sem rodar uma única linha no MT5. Toda a paridade de comportamento está em **crença**, não em **fato**. Este plano transforma essa crença em fato, em etapas pequenas, isolando o ponto exato de qualquer falha.

## Pré-requisitos

1. `git pull` no PC para puxar os 7 commits novos.
2. O `watch-compile.ps1` (auto-start via VSCode) deve compilar todos os scripts limpos. Se houver erro de compilação em qualquer um, **pare e me cole a mensagem** — não passe para a fase 1 de execução.
3. Confirme que estes 5 scripts existem em `MQL5/Scripts/MKS-ULTIMATE/Tests/`:
   - `Test_MksTestFramework.mq5`
   - `Test_CMksSimulatedBroker.mq5`
   - `Test_CMksAtrBrickSizer.mq5`
   - `Test_CMksBrickFile.mq5`
   - `Test_CMksRenkoBuilder.mq5`

## Fase 0 — Compile gate (passivo, watch-compile)

| Checkpoint | Esperado | Se falhar |
|---|---|---|
| 0.1 | Todos os 5 `.mq5` compilam sem erro | Cole a mensagem do MetaEditor — quase certamente fix simples (override mal escrito, include errado) |
| 0.2 | Sem warnings novos além dos pré-existentes | Cole warnings novos — pode indicar tipo errado em macro |

## Fase 1 — Smoke test do framework (validação raiz)

**Rodar:** arrastar `Test_MksTestFramework.mq5` em qualquer gráfico do MT5.

Este script é a **fundação** — se ele falhar, todas as 4 suítes migradas estão suspeitas.

### Esperado no Journal

```
=== Smoke test: Core/Testing framework ===
PASS: 8 macros incrementaram PassedAssertions (delta=8, esperado=8)
PASS: MKS_RUN propagou nome via stringification (capturado='TestSmokeStringification')
PASS: PassedTests incrementou em 1 após teste passante (delta=1)
PASS: CurrentTest vazio após End (corrente='')
--- a próxima linha 'FAIL' no journal é esperada (Phase 5) ---
FAIL [smoke_phase5_fail_path] synthetic failure | <file>:<line>
PASS: Fail() incrementou FailedAssertions em 1 (delta=1)
PASS: FailedTests >= 1 após teste com Fail (failed=1, total=4)

=== Smoke test meta: 6/6 checks ok ===
=== 8/9 assertions in 4 tests (1 failed) ===
MKS Tests: 1 FAILED  <-- Alert popup esperado, é a Fail() sintética
```

### Checkpoints

| # | Verificação | Se falhar |
|---|---|---|
| 1.1 | `=== Smoke test meta: 6/6 checks ok ===` aparece com 6/6 | Algum check do framework está quebrado — ver qual `FAIL: ...` apareceu |
| 1.2 | A linha de Phase 2 mostra `capturado='TestSmokeStringification'` (não `'<not_set>'` nem `'funcName'`) | **CRÍTICO**: `MKS_RUN(#funcName)` não estringificou. Todas as 4 suítes migradas precisam de fix (mass find/replace para passar o nome literal). Pare antes da Fase 2 |
| 1.3 | Alert popup "MKS Tests: 1 FAILED" aparece e é a Fail() sintética intencional da Phase 5 | Caminho de falha do runner não funciona — investigar `CMksTestRunner::Fail` |

**Se Fase 1 passar → siga.** Se falhar em 1.2 especificamente, **NÃO siga** — me avise e ajusto.

## Fase 2 — Suítes individuais (menor → maior)

Rodar **uma de cada vez**, arrastando o `.mq5` no gráfico. Cada uma deve terminar com `=== N/N assertions in K tests (0 failed) ===` e **nenhum** Alert popup.

### 2.1 — `Test_CMksSimulatedBroker.mq5` (51 assertions, 12 tests)

| Checkpoint | Esperado |
|---|---|
| 2.1.a | `=== 51/51 assertions in 12 tests (0 failed) ===` |
| 2.1.b | Nenhuma linha `FAIL [...]` no Journal |
| 2.1.c | Sem Alert popup |

**Se falhar:** o que quebra aponta direto pro defeito. Falhas mais prováveis:
- `CMksFakeSymbol` com algum default diferente do `CFakeSymbol` inline original → corrigir defaults no mock
- Override de virtual mal escrito → corrigir no mock

### 2.2 — `Test_CMksAtrBrickSizer.mq5` (72 assertions runtime, 11 tests)

| Checkpoint | Esperado |
|---|---|
| 2.2.a | `=== 72/72 assertions in 11 tests (0 failed) ===` |
| 2.2.b | Nenhuma linha `FAIL` |
| 2.2.c | Sem Alert popup |

**Se falhar:** não usa mocks — falha aqui indica problema na conversão `AssertEqualDouble` → `MKS_ASSERT_EQ_DOUBLE` (tolerância default 1e-9, deve bater com o inline original).

### 2.3 — `Test_CMksBrickFile.mq5` (97 assertions runtime, 4 tests)

| Checkpoint | Esperado |
|---|---|
| 2.3.a | `=== 97/97 assertions in 4 tests (0 failed) ===` |
| 2.3.b | Nenhuma linha `FAIL` |
| 2.3.c | Sem Alert popup |
| 2.3.d | Arquivos de teste em `MQL5/Files/MKS-ULTIMATE/` foram criados (test_brickfile_*.mksbk) |

**Se falhar:** ver se a tolerância 1e-12 do `BRICKFILE_DOUBLE_TOL` foi aplicada nos `MKS_ASSERT_NEAR_DOUBLE`. Falhas em campos de double indicam perda de precisão na migração.

### 2.4 — `Test_CMksRenkoBuilder.mq5` (428 assertions runtime, 14 tests)

| Checkpoint | Esperado |
|---|---|
| 2.4.a | `=== 428/428 assertions in 14 tests (0 failed) ===` |
| 2.4.b | Nenhuma linha `FAIL` |
| 2.4.c | Sem Alert popup |

**Se falhar:** maior teste, falha mais provável em `Test_Determinism` (loop com 16+ bricks × 8 asserts). Ver se `CMksCapturingSink` está capturando e armazenando idêntico ao `CCapturingSink` inline. Cada um dos 14 testes está isolado — a função que falha aponta o defeito direto.

## Fase 3 — "Conjunto completo" (passada final)

**Limitação técnica:** cada `.mq5` no MT5 cria seu próprio `g_mksTestRunner`. Não há como ter **um único Summary consolidado** dos 4 scripts sem extrair os testes para `.mqh` e criar um `Test_All.mq5` que inclui todos (follow-up — ver §Pendências).

**O que fazer no lugar:** rodar os 4 scripts da Fase 2 em sequência rápida (sem reiniciar o MT5 entre eles) e tabular os números totais.

### Checkpoint agregado

Some os Summaries dos 4 scripts. Esperado:

```
SimulatedBroker:  51/51 in 12 tests
AtrBrickSizer:    72/72 in 11 tests
BrickFile:        97/97 in  4 tests
RenkoBuilder:    428/428 in 14 tests
─────────────────────────────────────
TOTAL:           648/648 in 41 tests
```

| # | Verificação | Se falhar |
|---|---|---|
| 3.1 | Soma final = `648/648 in 41 tests` | Algum script falhou — qual? Volta pra Fase 2.x específica |
| 3.2 | Nenhum Alert acumulou | Mesmo que (3.1) |

## Pendências (não bloqueiam a fase atual)

1. **`Test_All.mq5` unificado** — exige extrair as funções de cada `Test_*.mq5` para um `Test_*_Suite.mqh` (e renomear helpers `MakeTick`/`MakeBrick` para evitar conflito de assinatura). Vale fazer quando virmos que dor de rodar 4 scripts vira chato. Não é necessário pra validação inicial.
2. **Unificação de helpers de fixture** — `MakeTick` tem 2 assinaturas diferentes (3 args vs 4 args). `MakeBrick` aparece em 2 testes. Extrair pra `Core/Testing/Fixtures.mqh` reduz duplicação, mas exige decidir uma assinatura canônica (e atualizar 3 arquivos).
3. **Cleanup deste documento** — após Fase 3 passar 100%, arquivar este `.md` (renomear `docs/CHECKPOINT-2026-05-22-adr005.md`) ou deletar.

## Para reportar o resultado

Cole no chat o **último Summary de cada um dos 5 scripts**, na ordem que rodou. Algo como:

```
[Test_MksTestFramework]
=== Smoke test meta: 6/6 checks ok ===
=== 8/9 assertions in 4 tests (1 failed) ===

[Test_CMksSimulatedBroker]
=== N/N assertions in 12 tests (X failed) ===

[Test_CMksAtrBrickSizer]
=== N/N assertions in 11 tests (X failed) ===

[Test_CMksBrickFile]
=== N/N assertions in 4 tests (X failed) ===

[Test_CMksRenkoBuilder]
=== N/N assertions in 14 tests (X failed) ===
```

E se houver linhas `FAIL [...]`, cole também — elas apontam direto pra função e pro campo defeituoso.
