---
@document: docs/CHECKPOINT-2026-07-22-stress-e-breaker.md
@project: MKS-ULTIMATE
@purpose: Handoff da sessão que começou 2026-07-21 (chegada em casa) e cruzou a meia-noite para 2026-07-22. Fechou o E6 (smoke MT5), entregou o RUNNER DE ESTRESSE liga/desliga inteiro (ADR-038 → Fase 9 Concluída), CALIBROU o StressLab ao broker real (ADR-039: spread + latência) e construiu+integrou o CIRCUIT BREAKER CORRETIVO (ADR-040, flatten-on-breach). 10 commits, todos em origin/main.
@audience: Próxima sessão (humano + IA), possivelmente noutro PC.
---

# CHECKPOINT — 2026-07-22 (runner de estresse + calibração + breaker corretivo)

**Regra:** CHECKPOINT é guia, código é verdade.

## 0. Como continuar

1. `git pull` em `C:\dev\MKS-ULTIMATE` — tudo desta sessão está em `origin/main` (último commit `b9940db`).
2. Se o terminal MT5 não mostrar a pasta MKS-ULTIMATE, recriar as 5 junctions (`docs/CHEATSHEET.md §9.5`). Antes de desinstalar qualquer MT5, ver §9.6 (a desinstalação atravessa junction viva e apaga o repo).
3. `tools/compile-all.ps1` — esperado **52 arquivos, 0/0**.
4. Ler este checkpoint + `docs/ROADMAP-CHECKLIST.md` (placar mensurável, melhor ponto de entrada) + as ADRs **038/039/040** + o `CHANGELOG.md [Não lançado]`.
5. **Próximo trabalho:** ver §4. As frentes seguintes dependem de **input do dono** (tese de edge para a Fase 10) ou de **dado a coletar** (slippage real para fechar a calibração).

## 1. Estado macro

- **E6 (produto operável) — FECHADO e MT5-verificado.** E6.1/E6.3 (superfície de inputs 3 níveis + preset por instrumento) provado no MT5; sub-item `InpHistoricalFillDays` documentado.
- **Runner de estresse liga/desliga (slice-2 da Fase 9 / Parte B) — ENTREGUE e provado → Fase 9 CONCLUÍDA.** ADR-038 **Aceita**.
- **Calibração do StressLab ao broker real (ADR-039, Proposta) — 2 de 3 eixos medidos E ligados** (spread + latência); só o slippage puro pende de dado.
- **Circuit breaker CORRETIVO (ADR-040, Proposta) — construído, integrado no ColorReversal e MT5-verificado no componente.**
- Repo: só `main`, tudo pushado. **52 arquivos compilam 0/0.**

## 2. O que foi feito (10 commits)

| Commit | Bloco | O quê |
|---|---|---|
| `9221e74` | **E6** | Smoke MT5 do ColorReversal fechou E6.1/E6.3 (dialog 3 níveis sem K/L; preset XAU sobrepõe → S:3.00000, CS `MKSCR_3`; Custom preserva) + `InpHistoricalFillDays` documentado (difere por PAPEL: Producer 30 / ColorReversal 3 / DecisionReplayer 0). |
| `461d828` | **ADR-038** fatias 1-2 | `CMksTradeJournalingBroker` (decorator IBroker que alimenta o `CMksTradeJournal` no Send/Close FILLED) + `CMksStressRunner` (orquestrador de 1 nível: grafo `CostModel→Sim→StressLab→RiskGated→journaling→estratégia→builder`, drena auto-close do stress). +testes. |
| `059ffe5` | **ADR-038** fatia 3 | `StressReplayer.mq5` — EA que replaya 1 `.mkstick` alimentando N runners em paralelo (None→Nightmare) numa passada + imprime `MksStressLabPrintComparison`. |
| `7a6a938` | **slice-2 fechado** | Smoke verde do StressReplayer sobre o golden (33.546 ticks, 17 flips): tabela None→Nightmare. Fase 9 → Concluída. |
| `5cb42ff` | **ADR-038 Aceita** | Flip Proposta→Aceita após o smoke. |
| `78e8ad3` | **ADR-039** spread | Spread real Exness XAU **medido = 240 pts (0.24 USD)** de 417k ticks (parser `.mkstick` fora do MT5, `tools/calibration/`), ancorado no StressReplayer (`InpSpreadPts`/`InpBaselineSpreadPts=240`). |
| `122251f` | **ADR-039** latência | Drift de latência **medido = ~0.25 pts/ms adverso** (deslocamento líquido, NÃO velocidade ingênua) e **ligado** (`latencyDriftPointsPerMs` no runner + `InpLatencyDriftPtsPerMs=0.25`). +teste. |
| `21ff142` | **ADR-040** breaker | `CMksCircuitBreaker` (decorator IBroker + OnTick: breach→trip sticky→flatten) + refactor `CMksRiskManager.AccountBreached` (predicado único preventivo/corretivo, behavior-preserving) + `Test_CMksCircuitBreaker`. |
| `654834d` | **ADR-040** integração | Breaker plugado no `ColorReversal.mq5` (input `InpEnableCorrectiveBreaker`, default ON; broker mais externo; `OnTick()` por tick antes do `IngestOne`). Muda o comportamento live (fecha+trava no breach). |
| `b9940db` | **ADR-040** MT5-verde | Registro dos testes verdes (ver §3). |

Cada peça code-complete + compilada 0/0 antes de commitar.

## 3. Validação MT5 já feita nesta sessão

- **E6.1/E6.3:** smoke do ColorReversal (dialog 3 níveis, preset XAU sobrepõe, Custom preserva, OnInit limpo) ✅
- **`Test_CMksTradeJournalingBroker`: 27/27** (8 testes) ✅
- **`Test_CMksStressRunner`: 17/17** (na época; depois +1 teste de latência → **re-rodar, agora 5 testes**) ✅
- **Smoke do StressReplayer** sobre o golden: tabela None→Nightmare (None 16 trades net −10661 pts slip 0; Light/Medium/High mesmos 16 trades com slippage crescente e net degradando; **Nightmare 9 trades net +1777** — as 7 rejeições bloquearam entradas numa estratégia perdedora → artefato `robustez ≠ lucratividade`). ✅
- **`Test_CMksCircuitBreaker`: 18/18** (3 testes — trip+flatten+block+sticky+reset) ✅
- **`Test_CMksRiskManager`: 119/119** (70 testes) + **`Test_CMksRiskGatedBroker`: 23/23** (10 testes) — **refactor `AccountBreached` provado SEM regressão** ✅

**O que NÃO foi verificado ainda:** re-rodar `Test_CMksStressRunner` (5 testes, o de latência é novo); o smoke do ColorReversal com o breaker DISPARANDO live (demo opcional — exige depósito/lote que façam a perda cruzar o limite: Deposit=1000 + lote 0.1, ou `InpMinEquityAbs` determinístico); e o slippage real da calibração.

## 4. Próximo passo / o que falta

Não há mais fatia de código óbvia e desbloqueada no arco atual. As frentes seguintes dependem de:

1. **Fase 10 — edge (o maior espaço em branco).** Precisa de uma **tese de estratégia** do dono (por que um padrão teria vantagem). Sem hipótese, construir estratégia é overfitting. Discutir no modo `##Estrategia##`. O gate E1–E5 está cumprido; a fundação está pronta e o StressLab agora tem um pé no dado real.
2. **Fechar a calibração (ADR-039) — eixo slippage.** Precisa de **dado de ordem real** (requested vs filled) — só há 11 trades do demo da Fase 9. Coletar via demo longa ou EA de medição. Spread e latência já estão calibrados+ligados.
3. **(opcional) MT5-verde restante:** re-rodar `Test_CMksStressRunner` (5 testes); ver o breaker do ADR-040 disparar num tester/demo (aceitar a ADR-040 → Aceita quando confortável).

## 5. Decisões / lacunas em aberto

1. **ADR-039 e ADR-040 seguem Proposta** — aceite explícito do dono pendente. A ADR-040 já está MT5-verde no componente + refactor; falta só (se o dono quiser) ver o disparo live antes de aceitar.
2. **Calibração — eixo slippage** pendente de dado (ADR-039 §Decisão 3; `ARCHITECTURE.md §4`).
3. **Comentários de `InpMaxDailyLossPct`/`InpMaxDrawdownPct`** no ColorReversal ainda dizem "trava NOVAS entradas" — descreviam só o comportamento PREVENTIVO; com o breaker corretivo ligado (ADR-040), os mesmos limites também disparam o flatten. Ajuste cosmético de doc futuro.
4. **Integração do breaker no stress runner** — deixada opcional/futura (o `CMksStressRunner` não usa o breaker; só o ColorReversal live).
5. **Lacuna de cadência do snapshot (herdada do E2)** — o breaker do ADR-040, ao chamar `AccountBreached` por tick, atualiza o snapshot per-tick no live quando ligado (fecha a lacuna para o propósito do breaker). O runner/golden já era per-tick.

## 6. Reframe honesto (MANTIDO — inegociável)

- O E2 prova **DETERMINISMO da camada de decisão** (sim↔sim) + paridade feed→brick — **NÃO** fidelidade ao broker real. **PROIBIDO** dizer "H4 fechado" ou "paridade live↔replay = fato".
- O StressLab mede **degradação sob stress MODELADO**. "Sobreviveu ao Nightmare" só ganha sentido absoluto com a calibração — hoje spread e latência estão ancorados em dado real (240 pts / 0.25 pts-ms), o slippage puro ainda não.
- **Robustez ≠ lucratividade:** o ColorReversal é não-lucrativo por design (net −10661 pts no baseline do golden). A Fase 9 valida o CORE, não a lucratividade. O Nightmare "lucrativo" no smoke é artefato (menos trades numa estratégia perdedora), não robustez.

## 7. Estado do git

`main == origin/main` no fim da sessão (push feito). Working tree limpo. Commits desta sessão: `9221e74` → `b9940db` (10) + este checkpoint. **52 arquivos, 0/0.**

Novos arquivos-fonte da sessão: `Core/Trade/CMksTradeJournalingBroker.mqh`, `Strategy/Runner/CMksStressRunner.mqh`, `Experts/MKS-ULTIMATE/StressReplayer.mq5`, `Core/Risk/CMksCircuitBreaker.mqh`, + 3 testes (`Test_CMksTradeJournalingBroker`, `Test_CMksStressRunner`, `Test_CMksCircuitBreaker`) + `tools/calibration/` (spread_stats.py, displacement.py, README). Refatorado: `CMksRiskManager` (predicado `AccountBreached`), `ColorReversal.mq5` (breaker + calibração), `StressReplayer.mq5` (calibração).

---

**Resumo em 3 linhas:** (1) E6 fechado no MT5 + **runner de estresse liga/desliga inteiro** (ADR-038, `CMksStressRunner`+`StressReplayer`) → smoke verde sobre o golden → **Fase 9 Concluída**. (2) **StressLab calibrado ao broker real** (ADR-039): spread 240 pts e latência 0.25 pts/ms medidos de 417k ticks reais e ligados; só o slippage pende de dado. (3) **Circuit breaker CORRETIVO** (ADR-040, `CMksCircuitBreaker` + refactor `AccountBreached` fonte-única + integração no ColorReversal) — MT5-verde (18/18 + refactor 119/119 + 23/23 sem regressão); a resposta à lição do V5 (a conta quebrou com posição ABERTA). Próximo: Fase 10 precisa da tese do dono; o slippage precisa de dado. Reframe honesto MANTIDO.
