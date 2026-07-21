---
@document: docs/CHECKPOINT-2026-07-21-hardening-e2-e4.md
@project: MKS-ULTIMATE
@purpose: Handoff da sessão do PC de trabalho (2026-07-21) — E2 (paridade de DECISÃO) PROVADO sobre feed real + golden bundle versionado; E3 (motor) e E4 (eixo 3) corrigidos e MT5-verificados; SL da estratégia em bricks (ADR-032). Registra o que foi feito, o que foi verificado, e o PRÓXIMO PASSO EXATO (Fase E5) — para continuar no PC de casa.
@audience: Próxima sessão (humano + IA), no PC de casa.
---

# CHECKPOINT — 2026-07-21 (E2 provado + E3/E4 fechados no PC de trabalho)

**Regra:** CHECKPOINT é guia, código é verdade.

Este checkpoint é a **continuação** do handoff `CHECKPOINT-2026-07-21-sessao.md` (escrito em casa). Aquele deixou o E2.1 code-complete pedindo "a captura longa com flips"; **esta sessão fez a captura, provou o determinismo, e ainda fechou E3 e E4.**

## 0. Como continuar (no PC de casa)

1. `git pull` em `C:\dev\MKS-ULTIMATE`. **Tudo está em `origin/main`** (último commit `8b0a1f4`; a sessão de hoje são os 4 commits `189a502`→`8b0a1f4`).
2. Se o terminal MT5 não mostrar a pasta MKS-ULTIMATE, recriar as 5 junctions (`docs/CHEATSHEET.md §9.5`). **Antes de desinstalar qualquer MT5, ver §9.6** (desinstalação atravessa junction viva e apaga o repo).
3. `tools/compile-all.ps1` — esperado **47 arquivos, 0/0**.
4. Ler este checkpoint + `docs/ROADMAP-CORE-HARDENING.md` (Fase **E5**) + o `CHANGELOG.md [Não lançado]`.
5. Continuar do **§4 (Próximo passo: Fase E5)**.

**Sobre as capturas ao trocar de PC:** os `.mkstick`/journals vivem em `<terminal>\MQL5\Files\` (gitignorados, locais por máquina) — **NÃO vêm pelo git**. Mas o **golden bundle do E2.2 JÁ está versionado** em `tests/golden/e2-decision/` (o fixture entrou no repo), então não precisa re-capturar pra reproduzir o E2.

## 1. O que foi feito hoje (4 commits, tudo em `origin/main`)

| Commit | Bloco | O quê | Verificação |
|---|---|---|---|
| `189a502` | **ADR-032** | SL da estratégia em **bricks** (broker-agnóstico), não em pontos. `InpSlPoints`→`InpSlBricks` (default 10), convertido em pontos no composition root (`slPoints = InpSlBricks·brickSize/Point()`). Simétrico em `ColorReversal` + `DecisionReplayer`. | compila 0/0; provado no replay (`slPts:30000`=10 bricks em digits=3) |
| `adc10fa` | **ADR-033 / E3** | Deadlock do soft-recovery (código 105) em rampa monotônica corrigido: âncora fixa `m_kFirstMid`→deslizante `m_kPrevMid`. + E3.3 (reset de `m_lastDirection` no reanchor). + blindagem do invariante (`mid==lastClose` zera o run). Recovery saiu de cobertura ZERO → 7 testes. | **MT5: `Test_CMksRenkoBuilder` 497/497 assertions, 29 tests, 0 failed** ✅ |
| `51eccb2` | **ADR-034 / E4** | Eixo 3: comissão deixa de ser computada-e-descartada. `CMksTradeJournal` vira money-aware (`SetMoneyConversion` + `NetPnLCurrency`); `CMksStressLabReport` surfacea moeda; E4.3 warning de spread inerte no `CMksStressLabBroker`. Swap segue OFF (v1, ADR-030) mas swap-aware. | **MT5: `Test_CMksTradeJournal` 49/49 (21 tests) + `Test_CMksStressLabReport` 42/42 (8 tests), 0 failed** ✅ |
| `8b0a1f4` | **E2.1 + E2.2** 🎯 | **Determinismo da DECISÃO provado sobre feed REAL** + golden bundle versionado + docs (ADRs). | **`verify-parity` exit 0** (ver §2) |

Todas as peças de código **revisadas adversarialmente** antes de commitar (agentes independentes traçaram a aritmética dos testes + a disjunção do grafo + o determinismo) — **0 defeitos reais sobreviveram**, confirmado depois pelos testes verdes no MT5.

## 2. O MARCO: E2 provado (§ o que o dono mais temia)

O `ColorReversal` capturou **33.546 ticks reais** do XAUUSDm (Exness, digits=3) num `.mkstick` (32 bricks, 17 flips). O `DecisionReplayer` (config `InpSlBricks=10`) montou o grafo DDR inteiro sobre esse feed real e:

- **Baseline (gates de conta inativos):** 2 replays → `verify-parity` **exit 0, "decision journals IDÊNTICOS (33 decisões)"**.
- **Gate-crossing (`InpMinEquityAbs=9990`):** o **breaker de conta dispara** (código 409 `min_equity_breached`) após o 1º trade e rejeita todo Send seguinte — **a proteção que faltou no V5**. 2 replays → `verify-parity` **exit 0 (18 decisões)**.

**O determinismo da camada de decisão — do brick à execução ao breaker de conta — deixa de ser teorema e vira fato demonstrado sobre feed real.** É o gate central do E2.

**Golden bundle versionado:** `tests/golden/e2-decision/` = o fixture `.mkstick` (2,1 MB) + `baseline.golden.tsv` (33 decisões) + `gate-minequity.golden.tsv` (18 decisões) + `README.md` (as 2 configs + a reprodução `verify-parity` run↔run e run↔golden).

## 3. Estado do gate de endurecimento (E1–E5 → Fase 10)

- **E1** ✅ · **E2** 🟢 (determinismo provado + golden; faltam pontas do §5) · **E3** ✅ (MT5) · **E4** 🟢 (MT5) · **E5** ⬜ (não iniciado).
- **E1–E5 são gate bloqueante da Fase 10** (estratégias reais). Falta só o **E5**.

## 4. PRÓXIMO PASSO: Fase E5 — gestão de trade integrada

O `CMksTradeManager` (BE/trailing/partial + auto-detach) tem unit tests mas **nunca rodou num composition root real** — é a peça que responde à ausência que quebrou o V5 (gestão reativa). Ver `docs/ROADMAP-CORE-HARDENING.md` Fase E5. Quatro sub-itens:

- **E5.1** — TradeManager integrado fim-a-fim: runner/EA que compõe `CMksTradeManager` sobre `CMksSimulatedBroker` + auto-close, exercitando BE/trailing/partial contra fills reais + o interplay com auto-detach e `CMksRiskGatedBroker`.
- **E5.2** — partial close trata fill parcial (`MKS_EXEC_PARTIAL`) — acumular `filledLots`, recalcular sobre o residual + teste com `SetNextCloseStatus(MKS_EXEC_PARTIAL)`.
- **E5.3** — exposição órfã no flip: no `CMksColorReversalStrategy`, se o `Close` no flip falhar, NÃO abrir nova posição no mesmo brick (deixar auto-detach/risk reconciliar) ou logar WARN.
- **E5.4** — semântica do circuit breaker: documentar que é preventivo (entrada), não corretivo; avaliar `flatten-on-breach`; decidir semântica de `DayPnL` (equity flutuante vs balance realizado).

### ⚠️ Disjunção do grafo do ColorReversal (CRÍTICO se for capturar)

Recompilar um arquivo no grafo de `#include` do `ColorReversal.mq5` **recarrega o EA anexado** (fragmenta a captura). Pelo fecho de includes mapeado na sessão do E4 (**confirmar antes de editar**):

| Item E5 | Arquivos | No grafo do ColorReversal? |
|---|---|---|
| **E5.1** (runner novo) + **E5.2** (`CMksTradeManager`, `CMksSimulatedBroker`) | Trade/StressLab/sim | **FORA** → seguro editar mesmo com a captura viva |
| **E5.3** (`CMksColorReversalStrategy`) | Strategy | **DENTRO** → recompila o ColorReversal |
| **E5.4** (`CMksRiskManager`, `CMksAccountSnapshot`) | Risk/Account | **DENTRO** → recompila o ColorReversal |

**Recomendação:** começar por **E5.1 + E5.2** (são o headline do E5 e são seguros — não tocam o EA da captura). Fazer **E5.3/E5.4** com a captura parada (ou aceitar o reload). Rodar a **disjunção fresca** (um agente Explore computando o fecho de includes do ColorReversal) no início do E5 pra confirmar a tabela.

## 5. Pontas pequenas pendentes (não bloqueiam o E5)

- **Teste headless do golden E2.2** — hoje a verificação é o procedimento manual + `verify-parity`; automatizar exigiria o fixture em `MQL5\Files\` no setup (`Files/` é gitignorado). Ver README do bundle.
- **E4.2 sub-teste** — "`slip>0` reduz estritamente o `NetPnLCurrency`" (a comissão já está fechada e provada; falta só o eixo do slip no resultado em moeda).
- **E3 critério de saída** — atualizar o Protocolo 1 (`docs/PROTOCOLOS.md`) para exigir teste duplo-run em "determinismo verificado".
- **E2.3** — âncora `seedMid`/`seedTickSeq` no header do `.mksbk` (zona reservada @192/@200) + replay asserta a proveniência (reforça o golden).
- **E2.4** — verificação na virada de dia UTC (só se prova com captura cruzando meia-noite).
- **Lacuna de cadência do snapshot (§5.1 do checkpoint `-sessao`)** — decisão de design do dono: o runner/golden atualiza `snapshot.Update()` **por tick**; o `ColorReversal` live só **no Send**. Fechar = per-tick no live (mais protetor) OU tirar o per-tick do runner. Não urgente — o golden usa a cadência do runner nos dois runs.

## 6. Notas operacionais

- **Reload gotcha (importante):** recompilar (via `compile-all` **ou** o watcher do VSCode ao salvar) qualquer arquivo no grafo do ColorReversal **recarrega o EA anexado** (`OnDeinit`→fecha o `.mkstick`, `OnInit`→abre outro). Aconteceu 1× hoje (~10:41) e fragmentou a captura em 2 arquivos. Se for capturar E mexer em código do grafo: **remova o EA do gráfico antes**, ou edite só fora do grafo. Editar/compilar arquivos FORA do grafo (Trade/StressLab/sim/testes) é seguro — usar o **compile dirigido** (só os `.mq5` afetados) em vez do `compile-all`.
- **Carimbar testes sem `compile-all`:** os test `.ex5` já compilados podem ser arrastados como **Scripts** num gráfico do MT5 — rodam sem recompilar, sem tocar a captura.
- **Captura de hoje:** a sessão 2 (`XAUUSDm_CR_20260721T014124.mkstick`, ~16,5k ticks) congelou às 11:55 — ou o mercado ficou quieto, ou o EA foi removido. Irrelevante pro E2 (o golden já está versionado). As capturas não vêm pelo git.
- **Git:** `main == origin/main` no fim da sessão (push feito). O PC de casa é só `git pull`.

## 7. Reframe honesto (MANTIDO — inegociável)

O E2 prova **DETERMINISMO da camada de decisão** (sim↔sim: runner↔runner e runner↔golden) + paridade feed→brick — **NÃO** fidelidade ao broker real. A paridade live-broker↔replay é **estruturalmente impossível** (o SL real dispara em tick/preço que o sim não reproduz). **PROIBIDO** dizer "H4 fechado" ou "paridade de decisão live↔replay = fato". O gap sim↔real segue nomeado como risco do StressLab (eixo 3).

---

**Resumo em 3 linhas:** (1) O marco do E2 caiu — **determinismo da decisão provado sobre feed REAL** (`verify-parity` exit 0, baseline 33 decisões + gate-crossing 18 com o breaker 409), golden bundle versionado. (2) De brinde: **E3** (deadlock do motor corrigido, MT5 497/497) e **E4** (eixo 3 do custo fechado, MT5 49/49+42/42) + **SL em bricks** (ADR-032). Tudo em `origin/main` (`8b0a1f4`). (3) **Próximo: Fase E5** (gestão de trade integrada) — começar por E5.1+E5.2 (seguros); E5.3/E5.4 tocam o grafo do ColorReversal. Reframe honesto MANTIDO.
