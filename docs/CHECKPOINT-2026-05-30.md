---
@document: docs/CHECKPOINT-2026-05-30.md
@project: MKS-ULTIMATE
@purpose: Handoff da sessão de auditoria 2026-05-29/30 + alinhamento do estado divergente entre sessões paralelas. Cobre: auditoria completa do projeto, ADR-029 (hedging-only), ADR-030 (StressLab credível parte 2), e o diagnóstico do Custom Symbol quebrado em produção (visual, não-trading → ADR-031).
@audience: Próxima sessão (humano + IA) que precise REALINHAR o projeto após desenvolvimento paralelo em múltiplas sessões.
---

# CHECKPOINT — 2026-05-30 (auditoria + alinhamento pós-sessões-paralelas)

**Regra:** CHECKPOINT é guia, código é verdade.

**Contexto desta sessão:** o dono pediu uma **auditoria completa e crítica** do projeto. Durante/após a auditoria, abriu **outras sessões em paralelo** que desenvolveram outras partes (visualização, sensores, indicadores) — e o estado divergiu. Este checkpoint registra o que ESTA sessão produziu e, principalmente, **alinha o quadro geral** para a próxima sessão não se perder.

---

## 1. ⚠️ ESTADO DE PRODUÇÃO E ALINHAMENTO (leia primeiro)

> **NOTA (2026-06-02) — reversão do diagnóstico do CS (este checkpoint é histórico; o texto abaixo é preservado).** Três coisas registradas aqui foram revertidas/refutadas depois:
>
> 1. **Não é "bug de container incondicional do MT5 na virada de dia" (REFUTADO).** O V5 usava o **mesmo** `CustomRatesUpdate` e atravessava meia-noites de server **sem morrer**. As causas reais eram **auto-infligidas**: CS criado **sem sessões 24/7** (causa-raiz — MT5 recusa o update na virada de dia; o V5 setava 24/7), specs reaplicadas a cada `OnInit` apagando o histórico no re-attach, e sink sem recovery. A corrupção citada no fórum é **condicional a múltiplos custom symbols** (sem repro com CS único). "Independente de barra-no-futuro" e "`CustomRatesReplace`/`CustomTicksAdd` compartilham o container bugado" eram conjectura sem fonte.
> 2. **Decisão REVERTIDA — NÃO aposentar o CS** (linha 25 abaixo / próximos passos §4). ADR-031 passa a significar **"manter+corrigir o CS"** (ainda não é ADR escrita). ADR-020/021/023/023-A **não** são superseded; o cap da ADR-023-A fica como higiene.
> 3. **GATE:** 4 fixes aplicados (sessões 24/7; specs só na criação; recovery no sink; marcador em `sink.lastBarTime`), compilam 0/0; **0 `CS UPDATE FAIL` em 06-02** nos restarts confirma o fix do re-attach; sobrevivência à meia-noite (06-02→06-03) **pendente de dado**. A moldura "CS quebrado é VISUAL, não trading; `.mksbk`/audit são a verdade" **continua correta**. Detalhe na nota REVERSÃO 2026-06-02 da ADR-023-A (`ARCHITECTURE.md`).

### Produção: o que está rodando e o que quebrou
- **`ColorReversal.mq5` está rodando LIVE agora** (demo Exness, XAUUSDm) — o log da sessão `20260529T153935` estava com lock de escrita no momento deste checkpoint.
- **O Custom Symbol `XAUUSDm.MKSCR_1` está visualmente quebrado** — gaps no eixo de tempo + bricks desalinhados (ver imagem reportada, 29/05 ~21:45–21:57).
- **DIAGNÓSTICO: é falha de VISUALIZAÇÃO, não de trading.** Razões (verificadas, não inferidas):
  1. A estratégia **nunca lê o CS** (ADR-020 §1) — constrói os próprios bricks dos ticks e grava no `.mksbk`. **CS quebrado ≠ trade quebrado.** O `.mksbk` + audit TSV (registro real) estão íntegros.
  2. Causa do visual: renderizar Renko (price-driven) num CS **baseado em tempo (M1)** via timeline híbrida (ADR-023/023-A) é estruturalmente frágil — gaps em minutos sem brick, bump espalhando bricks por minutos futuros, colisões no mesmo minuto sobrescrevendo (upsert por `time`), + o **bug de container do MT5 na virada de dia** (`CustomRatesUpdate` retorna -1 com `GetLastError()=0`).
  3. **NÃO é regressão das sessões paralelas no caminho de trading** — `git diff` dos últimos 8 commits mostra `CMksRenkoBuilder`, `CMksColorReversalStrategy`, `CMksRiskManager`, `CMksRiskGatedBroker`, sizers e position book com **zero mudança**. As paralelas tocaram visualização + branches próprias.
- **Correção decidida (nota ADR-023-A, 2026-05-30):** aposentar o CS do caminho de visualização → **ADR-031** (renko brick-native em indicador/objetos no chart do símbolo REAL, que tem eixo de tempo auto-mantido e sobrevive à meia-noite). Em elaboração.

### Divergência entre sessões (o que precisa ser reconciliado)
Branches existentes no momento deste checkpoint:
- **`feat/phase9-trade-visualization`** (ATIVA, = `origin`, HEAD `2251a5a`) — onde rodou esta auditoria + a viz + ADR-023-A/031. É a branch que está em produção.
- **`feat/sensors-foundation`** (local + `origin`) — trabalho paralelo de "sensores" (não auditado nesta sessão).
- **`origin/feat/indicators-bundle-1`** — bundle de indicadores (paralelo, não auditado nesta sessão).
- **`feat/hedging-only-guard`** — branch da ADR-029, já mergeada na phase9 (pode ser deletada).
- **`main`** — bem atrás da phase9 (todo o trabalho de Fase 9 + viz + ADR-029/030 está só na feature branch; **nada disso foi mergeado em main**).

**Risco de alinhamento:** `sensors-foundation` e `indicators-bundle-1` NÃO estão mergeadas na phase9 — então **não contaminam** o EA em produção. Mas o projeto tem 3+ frentes de trabalho divergentes em branches separadas + `main` defasada. **Antes de avançar, decidir a ordem de merge e o que vai pra `main`.**

---

## 2. O que ESTA sessão (auditoria) produziu

### 2.1 Auditoria completa (entregue)
Auditoria crítica dos 5 eixos pedidos (divergências, bugs arquiteturais/lógica, alinhamento doc↔código, contexto+melhorias, integridade), pilares principais vs secundários, comportamento por arquivo. Método: leitura integral do core + **verificação adversária** de 12 candidatos (1 refutado pelo próprio filtro — `Slippage()` não estava "sujo") + sweep de cobertura/alinhamento. **18 achados ranqueados** (alto→cosmético).

Achado meta mais importante: a **documentação canônica tinha derivado do código** — a `ROADMAP.md` dizia "Fase 9: Não iniciada" quando ela já estava validada em 3 ambientes. Corrigido nesta sessão.

### 2.2 ADR-029 — hedging-only (entregue, validado, commitado, pushado)
Framework v1 suporta só conta **hedging**; netting/exchange é detectada e **recusada** (`CMksMt5Broker.Init` → erro 204; `ColorReversal.OnInit` fail-fast com `Alert`). Validado no MT5: **`Test_CMksMt5Broker` 11/11, 0 falhas**. Commits `939d0d1`/`22ab838`/`224e958`, mergeado em `908197f`.

### 2.3 ADR-030 — StressLab credível parte 2 (entregue, validado, commitado, pushado)
Fechou os 3 furos do StressLab que a auditoria achou (pré-requisito do stress runner / Fase 9 slice 2):
- **#1 saídas estressadas** — `Close` e auto-close SL/TP agora sofrem slip adverso (antes só a entrada).
- **#2 requote independente do underlying** — modelado como sorteio interno (antes era knob morto contra o broker simulado, que sempre preenche).
- **#3 teste do report real** — `Test_RPT_CaptureFromRealPipeline` roda o pipeline de verdade (antes métricas hand-built).
- Coupling opcional `exitSim` (`CMksSimulatedBroker*`); `CMksSimulatedBroker` **intocado**. Validado no MT5: **`Test_CMksStressLabBroker` 112/112 (19 tests)** + **`Test_CMksStressLabReport` 32/32 (5 tests)**, 0 falhas. ADR-030 em `ARCHITECTURE.md`. Commitado pelo dono em `4c0d328` (junto com a ADR-023-A), pushado.

### 2.4 Sessões paralelas (NÃO desta sessão de auditoria)
Commitado na phase9 por sessões paralelas: viz styling (`347f140` — setas/halo/dash/cores por input, ADR-028), ADR-023-A (cap de drift) e a nota de correção ADR-023-A→ADR-031 (`2251a5a`). Branches `sensors-foundation` e `indicators-bundle-1` são frentes separadas.

---

## 3. Estado do git (snapshot)
```
2251a5a  docs(adr): ADR-023-A — cap nao basta; causa-raiz e bug de container do MT5 (ADR-031)   ← HEAD = origin
347f140  feat(viz): setas menores+borda, linha dash, cores por input (ADR-028)
4c0d328  feat: ADR-030 StressLab p2 + ADR-023-A cap drift timeline do CS
908197f  Merge feat/hedging-only-guard — ADR-029 hedging-only guard
```
Branch ativa `feat/phase9-trade-visualization` == `origin` (0/0). Working tree limpo (só `.claude/scheduled_tasks.lock`, artefato de sessão).

---

## 4. Pendências e próximos passos (para REALINHAR)

### Bloqueante de credibilidade visual (produção)
1. **ADR-031 — aposentar o CS da visualização.** É o fix estrutural do CS quebrado. Em elaboração. Renko brick-native no chart do símbolo real + promover família `IRenkoIndicator`. ADR-020/021/023/023-A viram candidatas a *superseded* no caminho visual (ADR-020 §1 — estratégia nunca lê o visual — sai **fortalecida**).
2. **`Test_CMksCustomSymbolSink_Timeline`** (ADR-023-A) — ainda com ⚠️ "validação pendente em MT5" no CHANGELOG (o dono rodou as suítes do StressLab, talvez não esta).

### Alinhamento de branches (decisão do dono)
3. Decidir ordem de merge: `phase9-trade-visualization` → `main`? `sensors-foundation` e `indicators-bundle-1` entram quando/como? `main` está muito defasada.
4. `feat/hedging-only-guard` pode ser deletada (já mergeada).

### Dívidas menores da auditoria (não-bloqueantes)
5. Logger ignora `IClock` (ts do replay é wall-clock — não afeta paridade). Watcher de compile com pontos cegos (includes quote-style; Experts/Services não observados). Swap=0 no broker simulado. Drift de comentários/códigos de erro. Bug do `DumpMksTick` (divisão por zero com `InpPrintLastN=0`).

---

## 5. Como realinhar (handoff)
1. Ler `docs/Projeto.md`, `REGRAS.md`, `ROADMAP.md`, `ARCHITECTURE.md` (ADRs até 031), `V5-POSTMORTEM.md`, `PROTOCOLOS.md`, `CHANGELOG.md` — depois este checkpoint.
2. `git log --oneline -10` + `git branch -a` para ver as frentes divergentes.
3. **Não tratar o CS quebrado como emergência de trading** — é visual; o `.mksbk`/audit são a verdade. A urgência real é decidir a ADR-031 e a ordem de merge das branches.
4. Confirmar que o EA em produção roda da branch certa e que `sensors`/`indicators` não foram mergeados sem querer.

---

**Resumo em 3 linhas:** (1) Auditoria completa entregue + ADR-029 (hedging-only) e ADR-030 (StressLab credível) implementadas, validadas no MT5 e pushadas. (2) O CS quebrado em produção é **falha visual, não de trading** — a estratégia não lê o CS; o fix é a ADR-031 (aposentar o CS do visual). (3) Há 3+ frentes em branches separadas (`phase9-viz`, `sensors`, `indicators`) + `main` defasada — **decidir a ordem de merge antes de avançar.**
