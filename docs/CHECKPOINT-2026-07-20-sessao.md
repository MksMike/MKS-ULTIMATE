---
@document: docs/CHECKPOINT-2026-07-20-sessao.md
@project: MKS-ULTIMATE
@purpose: Handoff de sessão longa (2026-07-19/20) — auditoria completa #2 + Fase E0 fechada + resgate de branch + início do gate central E2 (paridade de decisão). Registra o que foi feito, o que falta, o design do E2 (DDR + reframe honesto) e os próximos passos exatos, para continuar em OUTRA máquina.
@audience: Próxima sessão (humano + IA), possivelmente em outro PC.
---

# CHECKPOINT — 2026-07-19/20 (sessão longa: auditoria #2 → E0 → início do E2)

**Regra:** CHECKPOINT é guia, código é verdade.

## 0. Como continuar (no outro PC)

1. `git pull` em `C:\dev\MKS-ULTIMATE` (o repo é a fonte da verdade; o terminal MT5 recebe via junctions — ver `docs/CHEATSHEET.md §9.4/9.5`).
2. Se o terminal MT5 não mostrar a pasta MKS-ULTIMATE, recriar as 5 junctions (§9.5). **Antes de desinstalar qualquer MT5, ver §9.6** (a desinstalação atravessa junction viva e apaga o repo — aconteceu em 2026-07-19).
3. Ler este checkpoint + `docs/ROADMAP-CORE-HARDENING.md` (Fase E2) + a seção §4 abaixo (design do E2).
4. Rodar `tools/compile-all.ps1` para confirmar toolchain (esperado: 45 arquivos, 0/0).
5. Continuar do §5 ("Próximos passos exatos").

**Último commit ao escrever isto:** ver `git log --oneline -1`. Working tree deve estar limpo (tudo pushado).

## 1. Estado macro

- **Fase E0 (correções imediatas) — COMPLETA e validada no MT5.** Fechou as duas maiores exposições de dinheiro (piso de SL correto, reconciliação de posição órfã), corrigiu a decimação silenciosa do feed, e blindou os instrumentos de confiança (compile tools, verify-parity, test runner).
- **Fase E2 (paridade de decisão) — EM ANDAMENTO.** Design fechado (workflow adversário) + reframe aprovado pelo dono. E2.0 (fundação determinística) parcialmente entregue.
- Repo enxuto: só `main`, branch zumbi resgatada+deletada.

## 2. O que foi feito nesta sessão (por fase)

### Auditoria completa #2 (2026-07-19)
5 agentes releram o repo integralmente. Relatório: `docs/CHECKPOINT-2026-07-19-auditoria.md`. 2 achados ALTOS novos (H5 dedup do feed; H6 barras órfãs poluem indicadores no CS) + 16 médios. Plano norteador E0→E9 definido.

### Incidente operacional
Desinstalação do MT5 antigo atravessou as junctions e apagou o working tree (recuperado via git). Terminal Exness reinstalado (mesmo hash `53785E09...`), 5 junctions recriadas. Runbook de desinstalação segura em `CHEATSHEET §9.6`.

### Fase E0 — completa (commits `074e5fe`…`e6645e3`)
- **E0.1 (H5):** dedup de ticks por contagem na fronteira de ms (`Core/Data/TickBatchCursor.mqh`), nos 3 pumps (Producer/ColorReversal/TickRecorder). **MT5: 35/35** ✅.
- **E0.2 (M10/M19):** adoção de posição órfã no restart + flatten no halt de stream. **MT5: 89/89** ✅.
- **E0.3 (M12):** piso de SL ancorado em bricks, fail-closed, fonte única no RiskManager (design via workflow; StopsLevel fora do runtime, backstop no SimulatedBroker). **MT5: RiskManager 119/119, SimBroker 83/83** ✅.
- **E0.4 (M23/M18/M20):** compile tools não dão mais falso-OK com log vazio; verify-parity não passa no vácuo; TestRunner não aprova suíte vazia/teste sem assertion. **Meta-teste 6/6, sem "1 FAILED" espúrio** ✅.
- **E0.5 (M24/M25):** sync de status doc↔código; `settings.local.json` destrackeado.
- **E0.6:** runbook de desinstalação segura + `tools/backup-captures.ps1` (backup dos `.mkstick`/`.mksbk` para fora do terminal).
- **E0.7:** deletados `ValidateRenkoBuilder.mq5` + 3 dashboards V5 duplicados/vazios; corrigido div-por-zero no `DumpMksTick`; removido `InpComment` morto.
- **Achado pré-existente corrigido:** testes de auto-trigger do SimulatedBroker assumiam `point=1.0` sem setá-lo → 3 falhas reveladas ao rodar no MT5; corrigido com `SetPoint(1.0)`. **MT5: 83/83** ✅.

### Branch zumbi resgatada
`origin/claude/check-ultimate-access-5kshn` tinha 1 commit único (a auditoria detalhada de 25/05). Resgatado para `docs/AUDITORIA-2026-05-25.md` (marcado histórico) antes de deletar a branch. Repo agora só tem `main`.

## 3. Pendências de verificação no MT5 (o dono precisa rodar)

Compilar não é executar. Rodar no MetaTrader (Navigator → Scripts → MKS-ULTIMATE/Tests) e conferir o `Summary`:

- **`Test_CMksSimAccount`** (E2.0) — esperado ~ todos verdes (10 tests).
- **`Test_CMksSimPositionBook`** (E2.0) — esperado verdes (5 tests + FeedClock).
- **`Test_CMksDecisionJournal`** (E2.0) — esperado verdes (determinismo byte-a-byte).

(As suítes do E0 já foram validadas nesta sessão.)

## 4. E2 — o design (DDR + reframe honesto)

Fonte: workflow de design adversário (2026-07-19). **Este é o registro durável do design** — o resto vive no código.

### 4.1 O reframe (decisão do dono, ACEITA)
Paridade de decisão bit-a-bit entre a estratégia REAL (broker real) e o replay (sim) é **estruturalmente impossível**: o SL real dispara em tick/preço que o sim não reproduz (spread variável, gap, requote, slippage vs half-spread constante do sim). Então o E2 prova:
1. **Paridade feed→brick** live↔replay (bit-a-bit, `.mksbk`, com âncora).
2. **Determinismo da camada de decisão** (bit-a-bit, runner↔runner e runner↔golden): mesmo `.mkstick` + config pinada → mesmo decision journal.
E **nomeia** o gap sim↔real como risco do StressLab (eixo 3). **PROIBIDO** em qualquer doc futuro dizer "H4 fechado" ou "paridade de decisão live↔replay = fato".

**Swap:** OFF em v1 (swap-free, marcado no journal; accrual fica para o E4).

### 4.2 Arquitetura DDR (MKS Deterministic Decision Runner)
Núcleo reutilizável `CMksDecisionRunner` dirige (helper de ordem-por-tick, ÚNICO, anti-bifurcação):
```
source(.mkstick) → CMksRenkoBuilder (produtor único) → CMksColorReversalStrategy (INTOCADA)
  → CMksJournalingBroker (decorator IBroker, fora do gate: grava SEND/CLOSE/REJECT + alimenta a conta)
  → CMksRiskGatedBroker + CMksRiskManager
  → CMksSimulatedBroker (+CMksCostModel)
  → CMksSimPositionBook (IPositionBook lastreado no sim)
  → CMksAccountSnapshot alimentado por CMksSimAccount + IClock derivado do feed
  → CMksDecisionJournal (TSV determinístico)
```
Ordem por-tick load-bearing (num único helper): `clock.SetNow → simAccount.SetMid → simBroker.OnTick → drena PollAutoCloses (alimenta conta+journal) → builder.IngestTick (brick → contextSink → estratégia) → snapshot.Update`.

- **Replayer** é ESTENDIDO para instanciar o runner (revive o `g_clock` morto).
- **ColorReversal** NÃO vira replay: mantém responsabilidade única (trada no broker real), só passa a gravar o `.mkstick` exato + trocar `CMksMt5Clock` por `CMksFeedClock`.
- Rede de regressão permanente: **golden headless** (`Test_DecisionGolden`) roda o MESMO runner byte-a-byte, sem sessão live.

### 4.3 Formato do decision journal (determinístico)
`Core/Trade/CMksDecisionJournal.mqh` (TSV, `%.6f`, `\r\n`, header `#` ignorado no diff, rodapé total). Colunas:
```
ord  ev  status  brickIdx  triggerTickSeq  side  posOrdinal  lots  slPoints  tpPoints  retcode
```
- `posOrdinal` NORMALIZADO (1,2,3…) atribuído no 1º SEND FILLED — remove o ticket não-determinístico.
- `triggerTickSeq`: SEND/CLOSE = `brick.triggerTickId` do flip; AUTOCLOSE = seq do tick que cruzou SL/TP.
- Preço/custo/equity ficam FORA do journal comparado (vão para ledger informacional).
- **Acoplamento honesto:** o journal é função de (feed + CostModel + modelo-de-conta + config-da-estratégia) — SEND-vs-REJECT depende de equity→gate; lots sob PERCENT depende de balance→sizer. O golden pina esse bundle inteiro.

## 5. E2.0 — o que está feito e o que FALTA

### Feito (commitado)
- `Core/Account/CMksSimAccount.mqh` (+ `Test_CMksSimAccount.mq5`, 10 testes) — equity=realizado+MTM, convenção do sizer, swap OFF v1.
- `Core/Position/CMksSimPositionBook.mqh` (+ `Test_CMksSimPositionBook.mq5`) — `IsOpen(?)=false` como o book real.
- `Core/Clock/CMksFeedClock.mqh` — clock do feed (base do E2.4).
- `Core/Broker/CMksSimulatedBroker.mqh` — `+triggerTickSeq` no auto-close + `OpenPositionByIndex`.
- `Core/Trade/CMksDecisionJournal.mqh` (+ `Test_CMksDecisionJournal.mq5`) — journal TSV determinístico.

### FALTA (próximo sub-slice do E2.0)

> **[ATUALIZAÇÃO 2026-07-21] Os 3 itens abaixo foram ENTREGUES e VERIFICADOS NO MT5** (`CMksJournalingBroker` em `Core/Trade/`, `CMksDecisionRunner` em `Strategy/Runner/`, `Test_CMksDecisionRunner.mq5` com `Test_DriveOrder`). Compila 0/0 (46 arquivos); revisão adversária de 5 lentes sem achados; **MT5: DecisionRunner 36/36 (4 tests), + SimAccount 27/27, SimPositionBook 17/17, DecisionJournal 10/10, 0 failed**. E2.0 fechado. Ver `CHANGELOG.md [Não lançado]` (bloco "E2.0 fatia 2"). Próximo: E2.1 (instanciar o runner no `Replayer.mq5`; `verify-parity.ps1` sobre o decision journal).

1. **`Core/Trade/CMksJournalingBroker.mqh`** — decorator `IBroker` que envolve o gated broker. Em `Send`/`Close`: chama o inner, grava no journal (`RecordSend`/`RecordClose` com o `brokerRetcode` como `retcode`) E alimenta o `CMksSimAccount` (`OnOpen` no Send-fill com `r.fillPrice`/`r.filledLots`/`r.commission`; `OnClose` no Close-fill). Ponteiros para journal + simAccount (simAccount opcional/NULL). Deve ser o broker MAIS EXTERNO que a estratégia chama (para enxergar REJECTED do gate).
2. **`Core/Runner/CMksDecisionRunner.mqh`** (ou `Strategy/Runner/`) — monta o grafo e tem o helper de ordem-por-tick (§4.2). Inclui um "context sink" (IRenkoSink) que roda ANTES da estratégia no MultiSink e faz `brickIdx++; journal.SetBrickContext(brickIdx-1, brick.triggerTickId)`. No drain de PollAutoCloses: `simAccount.OnClose(ev...)` + `journal.RecordAutoClose(ev.side, ev.positionId, ev.lots, ev.triggerTickSeq)`.
3. **`Test_CMksDecisionRunner.mq5`** (headless) — roda o runner sobre uma sequência sintética de ticks 2× e assere journal byte-a-byte idêntico (determinismo); + **`Test_DriveOrder`**: assere que a ordem `broker.OnTick ANTES de builder.IngestTick` é respeitada e QUEBRA se invertida (o contrato load-bearing).

### Depois do E2.0
- **E2.1:** instanciar o runner no `Replayer.mq5`; `ColorReversal.mq5` grava `.mkstick`; `verify-parity.ps1` substitui o log-diff stub pelo diff do decision journal (runner↔golden), preservando o guard anti-vácuo. **[a captura de `.mkstick` real depende do dono no MT5]**
- **E2.3:** âncora `seedMid`/`seedTickSeq` no header do `.mksbk` (`BrickFileFormat.mqh` zona reservada @192/@200, FORA da exclusão wall-clock 184-191); fail-fast se `InpHistoricalFillDays>0` ou sizer=ATR no modo paridade; replay lê+asserta a proveniência do header do journal.
- **E2.4:** `ColorReversal` troca `CMksMt5Clock`→`CMksFeedClock` (alimentado por tick); snapshot lê o `CMksSimAccount`; `snapshot.Update()` por tick no runner. Critério: sessão cruzando meia-noite UTC → 0 diff run↔run.
- **E2.2:** fixture golden real-tick — **DEPENDE DE CAPTURA NO MT5 PELO DONO.** Commitar bundle versionado (fixture `.mkstick` + CostModel + modelo-de-conta + config + decision journal golden + `.mksbk` golden). OBRIGATÓRIO ≥1 fixture cuja sessão CRUZE `maxDailyLossPct`/drawdown (senão o golden prova determinismo de uma proteção que nunca dispara). `Test_DecisionGolden.mq5` no CI.
- **E2.5 (opcional, decisão do dono):** modo captura-shadow em tempo real no ColorReversal.

## 6. Decisões do dono ainda em aberto (para fatias futuras)
- **Golden lot mode:** FIXED (recomendado canônico) + um 2º golden PERCENT? (E2.2)
- **Construir o modo captura-shadow (E2.5)?** Recomendado SIM, em demo/lote mínimo, após E2.0–E2.2 verde.
- **Disciplina de re-baseline do golden** (fixture+config+golden versionados juntos, com changelog).

## 7. Riscos residuais NOMEADOS (não fechados pelo E2)
1. **Gap sim↔real permanece aberto** (eixo 3): o P&L live do EA real pode divergir forte de qualquer backtest. O E2 NÃO reduz isso — nomeia e confina ao StressLab. Nunca ler "journal bate" como "meu EA real é reprodutível".
2. **Gate validado sobre custo incompleto** (swap OFF): fecha só quando o E4 (custo→equity) completar.
3. **Fragilidade da ordem por-tick:** se um runner futuro bypassar o helper único, divergência silenciosa. Mitigado por `Test_DriveOrder`.
4. **Golden acoplado à config:** invalida a cada mudança de CostModel/conta/estratégia — precisa de disciplina de re-baseline.

---

**Resumo em 3 linhas:** (1) E0 fechada e validada no MT5; repo limpo (só `main`). (2) E2 (gate central) com design DDR fechado + reframe honesto aceito (E2 prova determinismo + brick-parity, NÃO fidelidade ao broker real — proibido dizer "H4 fechado"); E2.0 fundação parcialmente entregue (SimAccount, SimPositionBook, FeedClock, DecisionJournal + testes). (3) FALTA no E2.0: `CMksJournalingBroker` + `CMksDecisionRunner` + `Test_DecisionRunner/DriveOrder`; depois E2.1–E2.4 e o fixture golden (E2.2, depende de captura real no MT5).
