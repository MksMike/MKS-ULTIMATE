---
@document: docs/CHECKPOINT-2026-05-22.md
@project: MKS-ULTIMATE
@purpose: Adendo pós-validação ADR-005 — framework de teste materializado e provado no MT5
@audience: Próxima sessão (humano + IA)
---

# CHECKPOINT — 2026-05-22 (pós-validação ADR-005)

Adendo a [`CHECKPOINT-2026-05-21-slice3b.md`](CHECKPOINT-2026-05-21-slice3b.md). Cobre exclusivamente o que mudou desde o fechamento do slice3b: ADR-005 aceita, framework de teste em `Core/Testing/` implementado, 4 suítes migradas, validação empírica completa no MT5, branch de trabalho fechada.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 6 arquivos, nesta ordem

1. `README.md`
2. `docs/CHECKPOINT-2026-05-20.md` — base, convenções, estado pós-Slice 1
3. `docs/CHECKPOINT-2026-05-20-slice2.md` — adendo pós-Slice 2
4. `docs/CHECKPOINT-2026-05-20-slice3a.md` — formato `.mksbk`
5. `docs/CHECKPOINT-2026-05-21-slice3b.md` — Producer + Custom Symbol + ADRs 015/007/018/016/017
6. `docs/CHECKPOINT-2026-05-22.md` — este, incremental

Sub-artefato desta rodada: `docs/CHECKPOINT-2026-05-22-adr005.md` (test plan arquivado com tabela de resultados — consultar apenas se precisar re-rodar o ciclo de validação ADR-005).

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação.

---

## 2. Estado do código (HEAD = `2a2f4b9`)

A rodada do dia 2026-05-22 cobriu **14 commits**, em três blocos:

1. **Alinhamento prévio do ROADMAP** (`0a6218a`) — Fase 2 marcada Concluída, Fase 3 declarada Parcialmente concluída (com nota explicando que dependia da ADR-005), Fase 4 marcada Concluída com nota da ADR-017.
2. **ADR-005 + materialização** (`7197a07` → `45c3a67`, 11 commits) — proposta, aceitação, CHANGELOG catch-up, framework (`Asserts.mqh` + `TestRunner.mqh`), mocks (`CMksCapturingSink`/`CMksFakeSymbol`/`CMksFakeAccount`), smoke test, migração das 4 suítes existentes, test plan para validação empírica.
3. **Validação empírica + cleanup** (`63788b9` + `2a2f4b9`) — Mike rodou os 5 scripts no MT5 EXNESS, todos passaram, plano arquivado como `CHECKPOINT-2026-05-22-adr005.md`, branch remota deletada.

Origem dos commits: 12 do agente remoto (`Claude <noreply@anthropic.com>`, branch `claude/check-ultimate-access-5kshn` agora deletada) + 2 locais do dono (housekeeping pós-validação).

### Inventário do framework de teste (novo em `MQL5/Include/MKS-ULTIMATE/Core/Testing/`)

| Arquivo | Linhas | Função |
|---|---|---|
| `Asserts.mqh` | 110 | Macros `MKS_ASSERT_TRUE`, `MKS_ASSERT_FALSE`, `MKS_ASSERT_EQ_INT/LONG/STR/DOUBLE`, `MKS_ASSERT_NEAR_DOUBLE`, `MKS_ASSERT_GT_DOUBLE`, `MKS_ASSERT_LT_DOUBLE`. Cada macro propaga `__FILE__:__LINE__` na falha. Tolerância default 1e-9 em `EQ_DOUBLE` (configurável por chamada em `NEAR_DOUBLE`). |
| `TestRunner.mqh` | 105 | `CMksTestRunner` global (`g_mksTestRunner`). API: `Begin(name)` / `End()` / `Fail(reason)` / `Summary()`. Macros `MKS_RUN(funcname)` que estringifica o nome via `#funcname` (registra antes de chamar), e `MKS_SUMMARY()` que imprime e dispara `Alert` quando há falha. Contadores: `PassedAssertions` / `FailedAssertions` / `PassedTests` / `FailedTests`. |
| `Mocks/CMksCapturingSink.mqh` | 42 | Implementa `IRenkoSink::OnBrickClose` armazenando bricks em array dinâmico. Substitui o `CCapturingSink` inline que existia em `Test_CMksRenkoBuilder`. |
| `Mocks/CMksFakeSymbol.mqh` | 95 | Implementa `ISymbol` com setters fluentes. Substitui o `CFakeSymbol` inline de `Test_CMksSimulatedBroker`. |
| `Mocks/CMksFakeAccount.mqh` | 74 | Implementa `IAccount`. Disponível mas ainda não consumido pelas 4 suítes atuais (preparação para testes que dependem de `IAccount`). |

### Suítes migradas (`MQL5/Scripts/MKS-ULTIMATE/Tests/`)

| Suíte | Asserts | Tests | Redução de linhas (antes → depois) |
|---|---|---|---|
| `Test_MksTestFramework` (novo, smoke) | 11 (10 PASS + 1 FAIL sintética intencional) | 4 | — (suíte nova) |
| `Test_CMksSimulatedBroker` | 51 | 12 | 257 → 95 (-63%) |
| `Test_CMksAtrBrickSizer` | 72 | 11 | 173 → 78 (-55%) |
| `Test_CMksBrickFile` | 97 | 4 | 186 → 79 (-58%) |
| `Test_CMksRenkoBuilder` | 428 | 14 | 371 → 121 (-67%) |
| **Total (excl. smoke)** | **648** | **41** | — |

Cada `.mq5` migrado segue o mesmo padrão: `#include` das macros + mocks, função por teste registrada via `MKS_RUN(NomeDaFuncao)`, `MKS_SUMMARY()` no fim de `OnStart()`.

### ADRs — só o que mudou desde o checkpoint anterior

| ADR | Tema | Status |
|---|---|---|
| 005 | Framework próprio mínimo para testes unitários do core | **Aceita** (`890f56c`), materializada e **validada empiricamente em 2026-05-22** |

ADRs 001–004 e 006–018 sem alteração nesta rodada.

### Códigos de erro — sem adições nesta rodada

Nenhum código novo. Framework de teste não emite códigos via `MksError` (usa `Print`/`Alert` direto, conforme decisão da ADR-005 §3).

---

## 3. Validação empírica — resultado bruto

Rodada executada por Mike no PC, MT5 EXNESS, em 2026-05-22 entre 17:10 e 17:16 (horário local).

| Fase | Critério | Resultado |
|---|---|---|
| 0 — compile gate | 5 scripts compilam sem erro/warning | ✅ 0 errors, 0 warnings em todos os 5 (logs via MetaEditor headless) |
| 1 — smoke framework | meta 6/6 ok + 1 fail sintética + stringification OK | ✅ `10/11 in 4 tests (1 failed)`, `capturado='TestSmokeStringification'`, Alert popup esperado disparou |
| 2.1 — SimulatedBroker | 51/51 in 12 tests, sem Alert | ✅ idêntico |
| 2.2 — AtrBrickSizer | 72/72 in 11 tests, sem Alert | ✅ idêntico |
| 2.3 — BrickFile | 97/97 in 4 tests + 6 `.mksbk` gerados | ✅ 97/97 + 6 arquivos de 616 bytes cada em `MQL5/Files/MKS-ULTIMATE/` |
| 2.4 — RenkoBuilder | 428/428 in 14 tests, sem Alert | ✅ idêntico |
| 3 — agregado | 648/648 in 41 tests | ✅ idêntico |

Discrepância benigna observada: o plano original dizia `8/9 assertions` no smoke; veio `10/11`. Subestimação do plano (3 checks meta extras), não defeito — meta-sanidade bateu 6/6.

Detalhes completos em `docs/CHECKPOINT-2026-05-22-adr005.md` (test plan arquivado).

---

## 4. Decisões operacionais desta rodada

- **Branch de trabalho fechada.** `claude/check-ultimate-access-5kshn` foi mergeada via fast-forward em `main`, depois deletada local e remotamente. Os 12 commits do agente remoto agora vivem em `main`.
- **Test plan virou checkpoint.** `docs/TEST-PLAN-ADR005.md` foi renomeado (`git mv`) para `docs/CHECKPOINT-2026-05-22-adr005.md` e ganhou tabela de resultados no topo. Conteúdo original preservado abaixo como referência para re-execução futura.
- **Política de Co-Authored-By respeitada.** Nenhum dos 14 commits da rodada (12 do agente remoto + 2 locais) carrega o trailer `Co-Authored-By:` — convenção do projeto mantida.

---

## 5. Pendências abertas (pequenas, não-bloqueantes)

Mantidas em §Pendências do `CHECKPOINT-2026-05-22-adr005.md` para detalhes; resumo aqui:

1. **`Test_All.mq5` unificado.** Exigiria extrair cada conjunto de testes de `Test_*.mq5` para `Test_*_Suite.mqh` e renomear helpers (`MakeTick`/`MakeBrick` têm assinaturas conflitantes entre arquivos). Vale fazer quando rodar 4 scripts manualmente virar dor.
2. **`Fixtures.mqh` canônico.** Unificar `MakeTick`/`MakeBrick`/`BuildSampleBricks` em `Core/Testing/Fixtures.mqh`. Exige decidir assinatura única e atualizar 3 arquivos.
3. **ROADMAP — Fase 3.** Está marcada **Parcialmente concluída** com nota dizendo que o framework formal "depende da ADR-005". Agora a ADR-005 está aceita, implementada e validada — a Fase 3 pode ser marcada **Concluída**. Decisão de quando flippar fica com Mike (não fiz nesta rodada para não inflar o escopo do "fechar a rodada").

---

## 6. Próximos passos sugeridos (não fechados)

- Atualizar o status da Fase 3 do `ROADMAP.md` para **Concluída** (ver §5 ponto 3).
- Iniciar Fase 5 (Trade Management) ou Fase 6 (Risk Management) — ambas independentes da Fase 5 do ponto de vista de dependência, mas Risk Management precede StressLab no ROADMAP. Decisão de Mike.
- O diretório `Renko-Ultimate/` segue untracked no working tree (fora do escopo deste projeto). Sem ação requerida.

---

## 7. Comandos úteis para próximo chat

```powershell
# estado atual
git log --oneline -5

# rodar uma suíte manualmente no MT5 (via MetaEditor headless)
& "C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe" /compile:<caminho do .mq5>

# re-validar tudo: arrastar cada um dos 5 Test_*.mq5 no gráfico, ver Toolbox > Experts
#  - Test_MksTestFramework
#  - Test_CMksSimulatedBroker
#  - Test_CMksAtrBrickSizer
#  - Test_CMksBrickFile
#  - Test_CMksRenkoBuilder
```

Estado limpo. Próxima rodada começa de `main @ 2a2f4b9`.