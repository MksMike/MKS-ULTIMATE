---
@document: docs/CHECKPOINT-2026-07-21-e5-e6.md
@project: MKS-ULTIMATE
@purpose: Handoff da sessão do PC de casa (2026-07-21, à noite) — Fase E5 (gestão de trade integrada) FECHADA por completo (E5.1–E5.4, MT5-verificada) e Fase E6 (produto operável) substancialmente feita (E6.1–E6.4). Com o E5, o gate E1–E5 está cumprido → a Fase 10 (estratégias reais) está DESTRAVADA. Registra o que foi feito, o que foi verificado no MT5, o que ficou pendente, e o estado do git.
@audience: Próxima sessão (humano + IA).
---

# CHECKPOINT — 2026-07-21 (noite, PC de casa): E5 fechada + E6 quase toda

**Regra:** CHECKPOINT é guia, código é verdade.

Continuação direta de `CHECKPOINT-2026-07-21-hardening-e2-e4.md` (PC de trabalho), que terminou com "Próximo: Fase E5". **Esta sessão fechou a Fase E5 inteira e avançou muito na E6.** Com isso, **o gate E1–E5 está cumprido — a Fase 10 (estratégias reais) está destravada.**

## 0. Como continuar

1. `git pull` em `C:\dev\MKS-ULTIMATE`. Tudo em `origin/main` (últimos commits desta sessão: `8efd993`→`03c4964` + este checkpoint).
2. Se o terminal MT5 não mostrar a pasta MKS-ULTIMATE, recriar as 5 junctions (`docs/CHEATSHEET.md §9.5`). Antes de desinstalar qualquer MT5, ver §9.6.
3. `tools/compile-all.ps1` — esperado **48 arquivos, 0/0**.
4. Ler este checkpoint + **`docs/ROADMAP-CHECKLIST.md`** (inventário mensurável: o que está pronto vs o que falta, com critério de pronto — melhor ponto de entrada) + `docs/ROADMAP-CORE-HARDENING.md` (E5 ✅, E6 quase) + `CHANGELOG.md [Não lançado]` + as ADRs **035/036/037**.
5. **Pendência de verificação MT5 (única em aberto):** o smoke test do **E6.1/E6.3** — ver §5.
6. **Próximo trabalho JÁ DECIDIDO (ver §4):** o **runner de estresse liga/desliga + calibração ao broker real**. Começar por aí.

## 1. O que foi feito (4 commits, tudo em `origin/main`)

| Commit | Bloco | O quê | Verificação |
|---|---|---|---|
| `8efd993` | **ADR-035 / E5.1+E5.2** | `CMksTradeManager` provado num composition root REAL (`Test_TradeManagerIntegration.mq5`, 7 cenários) + partial close acumula fill parcial (fim do over-close em `MKS_EXEC_PARTIAL`) + `SetNextCloseStatus` one-shot no `CMksSimulatedBroker`. | **MT5: `Test_TradeManagerIntegration` 52/52 (7 tests), `Test_CMksTradeManager` 74/74 (28), `Test_CMksSimulatedBroker` 83/83 (20), 0 failed** ✅ |
| `cce28a9` | **ADR-036 / E5.3+E5.4** | Fim da exposição órfã dupla no flip do ColorReversal (Close falho MANTÉM o vínculo, não abre nova) + doc da semântica preventiva do breaker + `DayPnL` = equity flutuante (deliberado). | **MT5: `Test_CMksColorReversalStrategy` 22 tests, 0 failed** ✅ (2 novos + 20 sem regressão) |
| `0364579` | **E6.4 (parcial)** | Runbook de 1 página (`CHEATSHEET §9.8` — qual EA para quê, pré-requisitos, passo a passo, mapa das recusas do OnInit) + header do `ColorReversal` corrigido (não narra mais um stress runner inexistente). | docs/comentário; compila 0/0 |
| `03c4964` | **ADR-037 / E6.1+E6.3** | Superfície de ~31 inputs → 3 níveis (Básico/Avançado/Diagnóstico); K/L saem do dialog (const, valores mantidos → golden E2 intacto); preset por instrumento (`InpInstrumentPreset` Custom/XAU/EURUSD). | compila **0/0 (48 arquivos)**; **MT5 smoke test PENDENTE** (§5) |

Todas as peças de código **revisadas antes de commitar** (aritmética dos testes, disjunção do grafo do ColorReversal, semântica de fill parcial e de flip falho).

## 2. O MARCO: Fase E5 fechada → gate E1–E5 cumprido

**E1 ✅ · E2 ✅ (determinismo provado + golden) · E3 ✅ · E4 ✅ · E5 ✅** — todos os critérios de saída cumpridos, todos MT5-verificados (E6.1/E6.3 é o único código desta sessão ainda pendente de smoke test, e é E6, fora do gate). **A Fase 10 (estratégias reais) está liberada.**

O E5 era a peça que respondia à ausência que quebrou o V5 (gestão reativa). O `CMksTradeManager` saiu de "coberto só por mock" para provado na cadeia REAL (`CostModel → SimulatedBroker → RiskGatedBroker(+RiskManager+FixedLotSizer+SimPositionBook) → TradeManager`), incluindo BE/trailing/partial contra fills reais, auto-detach no SL hit, rejeições do gate, fill parcial acumulado e determinismo duplo-run.

## 3. Estado do gate de endurecimento (E1–E8)

- **E1** ✅ · **E2** ✅ · **E3** ✅ · **E4** ✅ · **E5** ✅ — **gate de estratégias CUMPRIDO.**
- **E6** 🟢 (E6.1/E6.2/E6.3 feitos, E6.4 quase — falta o sub-item de `InpHistoricalFillDays`; E6.1/E6.3 pendem do smoke test MT5). Pré-requisito de operação real.
- **E7** ⬜ (CS/meia-noite — 4 fixes aplicados; sobrevivência à virada de dia pende de DADO de captura cruzando a meia-noite. ADR-031 não escrita).
- **E8** ⬜ (fundação de indicadores — depende do E7).

## 4. Próximo passo: runner de estresse liga/desliga + calibração (DECIDIDO)

O debate de rumo aconteceu ao fim desta sessão. **Desfecho (decisões do dono):**
- **Edge:** SEM hipótese concreta ainda ("só possibilidades"). → **NÃO** construir estratégia agora (seria overfitting). Quando houver tese, dissecar no modo `##Estrategia##`. A Fase 10 fica em espera **do dono**, não do código.
- **StressLab liga/desliga:** SIM, é o próximo trabalho. O dono quer poder rodar uma estratégia **sem** o StressLab, depois **com**, e **comparar** — como um liga/desliga fácil de operar. Na prática é o **slice-2 da Fase 9** (runner que pluga `CMksColorReversalStrategy` sobre `CMksSimulatedBroker` + `CMksStressLabBroker` por níveis None→Nightmare e agrega via `CMksStressLabReport`). **+ Calibrar** os presets ao broker real (medir spread/slippage/latência da Exness XAU) — é o que dá sentido a "sobreviveu ao Nightmare".
- **Dashboard (E9):** adiado — só depois de haver EA/indicador substancial.

**Portanto, o trabalho concreto para a próxima sessão é o runner de estresse liga/desliga (Parte 2 §B do `ROADMAP-CHECKLIST.md`), com a calibração desenhada junto.**

Insumos criados nesta sessão para o debate: `docs/ROADMAP-CHECKLIST.md` (inventário mensurável) e um panorama visual para leigo (Artifact privado; não versionado no repo).

## 5. Pendências

- **E6.1/E6.3 — smoke test no MT5 (dono):** anexar o `ColorReversal` e conferir (a) dialog nos 3 níveis, sem K/L; (b) preset `XAU` sobrepõe (log `starting` mostra `preset:XAU, S:3.00000, slBricks:10.00`); (c) `Custom` (default) preserva o comportamento anterior; (d) um tester run abre/fecha ordens como antes. Só então o E6.1/E6.3 vira "MT5-verificado". **Committado já** (a pedido do dono, com a pendência anotada na ADR-037/CHANGELOG).
- **E6.1 sub-item:** unificar o default de `InpHistoricalFillDays` entre Producer e ColorReversal (ou documentar por que diferem). Pequeno.
- **Preset EURUSD:** valores iniciais (brick 0.0010 / SL 10 bricks) **não validados com dado** — ajustar quando EURUSD entrar em uso real.
- **`flatten-on-breach` (breaker corretivo):** decisão de design em ABERTO (ADR-036/E5.4) — o breaker hoje é só preventivo (bloqueia entrada, não fecha posição ao cruzar o limite). Adiado conscientemente; registrado na §4 de `ARCHITECTURE.md`.
- **E7 (dado):** sobrevivência do CS à meia-noite pende de uma captura cruzando a meia-noite do servidor. E7.3 (ADR-031) depende disso.
- **Lacuna de cadência do snapshot (herdada do E2):** o runner/golden atualiza `snapshot.Update()` por tick; o ColorReversal live só no Send. Decisão de design do dono, não urgente.

## 6. Estado do git

`main == origin/main` no fim da sessão (push feito). Working tree limpo. Commits desta sessão: `8efd993`, `cce28a9`, `0364579`, `03c4964` + este checkpoint.

## 7. Reframe honesto (MANTIDO — inegociável)

O E2 prova **DETERMINISMO da camada de decisão** (sim↔sim) + paridade feed→brick — **NÃO** fidelidade ao broker real. **PROIBIDO** dizer "H4 fechado" ou "paridade live↔replay = fato". O gap sim↔real segue nomeado como risco do StressLab (eixo 3).

---

**Resumo em 3 linhas:** (1) **Fase E5 fechada por completo** (E5.1–E5.4, ADRs 035/036, todos MT5-verificados) → **gate E1–E5 cumprido, Fase 10 destravada.** (2) **Fase E6 quase toda** (ADR-037: superfície de inputs enxuta + presets; runbook; header) — falta só o smoke test MT5 do E6.1/E6.3 e um sub-item pequeno. (3) **Próximo é decisão de rumo** (Fase 10 vs fechar E6 vs E7/E8) — debate pedido pelo dono. Reframe honesto MANTIDO.
