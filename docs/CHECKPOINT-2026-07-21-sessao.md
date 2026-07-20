---
@document: docs/CHECKPOINT-2026-07-21-sessao.md
@project: MKS-ULTIMATE
@purpose: Handoff de sessão (2026-07-21) — E2.0 fechado e validado no MT5, E2.1 code-complete e smoke-tested sobre ticks REAIS, E2.4 (clock swap). Registra o que foi feito, o que foi verificado no MT5, o PRÓXIMO PASSO EXATO (a captura longa com flips) e as decisões em aberto — para continuar em OUTRO PC.
@audience: Próxima sessão (humano + IA), em outro PC.
---

# CHECKPOINT — 2026-07-21 (E2.0 fechado no MT5 → E2.1 code-complete → E2.4; falta a captura longa)

**Regra:** CHECKPOINT é guia, código é verdade.

## 0. Como continuar (no outro PC)

1. `git pull` em `C:\dev\MKS-ULTIMATE` (o repo é a fonte da verdade; tudo desta sessão está em `origin/main`, último commit `6a32210`).
2. Se o terminal MT5 não mostrar a pasta MKS-ULTIMATE, recriar as 5 junctions (`docs/CHEATSHEET.md §9.5`). **Antes de desinstalar qualquer MT5, ver §9.6** (a desinstalação atravessa junction viva e apaga o repo).
3. `tools/compile-all.ps1` — esperado **47 arquivos, 0/0**.
4. Ler este checkpoint + `docs/ROADMAP-CORE-HARDENING.md` (Fase E2) + o `CHANGELOG.md [Não lançado]` (blocos E2.0 fatia 2, E2.1 slice-1/cauda, E2.4).
5. Continuar do **§4 (Próximo passo exato: a captura longa)**.

**Sobre as capturas `.mkstick`/journals ao trocar de PC:** elas vivem em `<terminal>\MQL5\Files\MKS-ULTIMATE\` — **gitignoradas, locais por máquina**. As capturas do PC anterior (só smoke tests curtos de 306 ticks — nada precioso) NÃO vêm pelo git. No PC novo, **re-capturar do zero** (§4). `tools/backup-captures.ps1` preserva capturas se um dia houver algo que valha a pena guardar.

## 1. Estado macro

- **E2.0 (fundação determinística da paridade de decisão) — COMPLETA e validada no MT5.** O grafo DDR inteiro monta e roda; o `Test_CMksDecisionRunner` passou 36/36.
- **E2.1 (replay da decisão + captura) — CODE-COMPLETE e smoke-tested sobre ticks REAIS.** O `DecisionReplayer` rodou de ponta a ponta sobre um `.mkstick` real capturado pelo `ColorReversal` (marco: o grafo DDR montou pela 1ª vez sobre o XAUUSDm real da Exness). Falta só a **captura longa com flips** para a prova de determinismo (verify-parity exit 0).
- **E2.4 (clock de decisão derivado do feed) — commitado.** ColorReversal usa `CMksFeedClock` no snapshot; verificação (sessão cruzando meia-noite) pendente de dado.
- Repo: só `main`, tudo pushado.

## 2. O que foi feito nesta sessão (4 commits)

| Commit | Fatia | O quê |
|---|---|---|
| `3116ce5` | E2.0 fatia 2 | `Core/Trade/CMksJournalingBroker.mqh` (decorator IBroker mais externo: grava SEND/CLOSE/REJECT + alimenta a conta) + `Strategy/Runner/CMksDecisionRunner.mqh` (dono do grafo DDR + helper de ordem-por-tick ÚNICO, anti-bifurcação) + `Test_CMksDecisionRunner.mq5` (determinismo byte-a-byte + `Test_DriveOrder`). **MT5: 36/36.** |
| `dae04d5` | E2.1 slice-1 | `Experts/DecisionReplayer.mq5` (EA que dirige o runner sobre `.mkstick` → decision journal; fail-fast se numéricos do símbolo = 0) + `verify-parity.ps1` ganha diff do decision journal (`-JournalA/-JournalB`, anti-vácuo, `.mksbk` opcional). |
| `cacae71` | E2.1 cauda | `ColorReversal.mq5` grava o `.mkstick` EXATO do feed live (`InpRecordMkstick`, default false; best-effort — falha de I/O nunca para o trading; fail-fast se `InpHistoricalFillDays≠0`). |
| `6a32210` | E2.4 | `ColorReversal.mq5` troca `CMksMt5Clock`→`CMksFeedClock` no snapshot (fronteira de dia UTC deriva do feed, não de TimeCurrent). |

**Cada peça revisada adversarialmente** (workflow de 5 lentes no E2.0; agentes focados no DecisionReplayer, no recording e na camada de risco do E2.4) — 0 defeitos reais sobreviveram; o fail-fast do símbolo no DecisionReplayer e a lacuna de cadência do E2.4 (§5) vieram das reviews.

## 3. Validação MT5 já feita nesta sessão

- **`Test_CMksDecisionRunner`: 36/36 (4 tests, 0 failed)** ✅ — determinismo byte-a-byte (flips + SL-hit) + `Test_DriveOrder` (contrato de ordem load-bearing).
- Os 3 pendentes da fatia 1 re-verificados: **`Test_CMksSimAccount` 27/27, `Test_CMksSimPositionBook` 17/17, `Test_CMksDecisionJournal` 10/10, 0 failed** ✅ — toda a fundação E2.0 MT5-verificada.
- **Gravação do `.mkstick` provada:** sessão de smoke gravou 306 ticks reais da Exness, `recFailed:false`, fechou limpo (`mkstick recording closed, ticksRecorded:306`).
- **DecisionReplayer smoke sobre `.mkstick` REAL (1ª vez):** abriu o arquivo de 306 ticks (`symbolSelected:true`), o **`runner.Init` teve sucesso** montando o grafo DDR inteiro sobre o XAUUSDm real, processou os 306 ticks (`ticksInvalid:0, bricksSeen:0, journalEvents:0` — 0 flips porque a captura foi curta, ~2 min), `balance:10000/equity:10000`, self-removeu limpo. **Determinístico:** dois runs do mesmo arquivo deram resultado idêntico. `bricksSeen:0` do replay bate com `bricks:0` do ColorReversal (mesmo feed → mesma contagem).
- **verify-parity vácuo (esperado, a confirmar):** dois journals de 0-decisão → `exit 2, "passe vácuo"` é o resultado CORRETO (a guarda anti-vácuo se recusa a dizer "OK" com 0 decisões). Confirmar no PC novo é opcional.

**O que NÃO foi verificado ainda (precisa da captura longa):** o determinismo da decisão sobre um feed com FLIPS (verify-parity exit 0). É o único elo que falta.

## 4. Próximo passo EXATO: a captura longa (o dono roda no MT5)

Todo o resto do E2 depende disto. O código está pronto e smoke-tested; falta tempo de mercado.

### Fase A — Capturar (ColorReversal, demo/hedging)
1. Gráfico do **símbolo REAL** (`XAUUSDm`), **não** o Custom Symbol. AutoTrading ligado.
2. Inputs (config canônica, já validada — ver §7): mudar só **`InpRecordMkstick=true`** e **`InpHistoricalFillDays=0`** (obrigatório — senão o EA recusa anexar).
3. Deixar rodar **≥1h em horário ATIVO** (precisa o XAU andar vários blocos de 3 USD e reverter → flips). O CS preto vai ganhando caixinhas conforme os bricks live formam.
4. **Remover o EA do gráfico** (o `OnDeinit` fecha o `.mkstick`). Conferir no log: `mkstick recording closed` com `ticksRecorded` alto.
5. Arquivo: `MQL5\Files\MKS-ULTIMATE\Ticks\XAUUSDm_CR_<stamp>.mkstick`.

### Fase B — Replayar 2× (DecisionReplayer, EA)
Arrastar o `DecisionReplayer` em qualquer gráfico, **rodar 2×, inputs IDÊNTICOS**, só mudando o journal:
- `InpTickFilePath = MKS-ULTIMATE\Ticks\XAUUSDm_CR_<stamp>.mkstick` (o da Fase A)
- brick/SL/magic/lote/risco = **os mesmos da Fase A** (§7); custo pode ser 0 (`InpSpreadPts/SlipPts/CommPerLot=0`)
- Run 1: `InpJournalPath = MKS-ULTIMATE\Journals\run1.tsv`; Run 2: `run2.tsv`.
- Cada run self-remove no EOF. Conferir `replay summary` com `journalEvents > 0`.

### Fase C — Verificar (determinismo)
```powershell
powershell -ExecutionPolicy Bypass -File c:\dev\MKS-ULTIMATE\tools\verify-parity.ps1 `
  -JournalA "<...>\MQL5\Files\MKS-ULTIMATE\Journals\run1.tsv" `
  -JournalB "<...>\MQL5\Files\MKS-ULTIMATE\Journals\run2.tsv"
```
- **exit 0 + "decision journals IDÊNTICOS (N decisões)"** → 🎯 **determinismo da decisão sobre feed REAL provado. O marco central do E2.**
- **exit 2 "vácuo"** → captura sem flip; recapture mais longo/ativo.
- **exit 2 "linha divergente"** → **bug real de não-determinismo** — cola a saída, caçar a causa-raiz.

Quando der exit 0: comitar o bundle golden (fixture `.mkstick` + config + journal golden) = **E2.2**. OBRIGATÓRIO ≥1 fixture cuja sessão CRUZE `maxDailyLossPct`/drawdown (senão o golden prova determinismo de uma proteção que nunca dispara).

## 5. Decisões / lacunas em aberto

1. **Lacuna de cadência do snapshot (finding da review do E2.4) — decisão de design do dono.** Trocar o clock igualou o *tipo*, não a **cadência** do `snapshot.Update()`: o runner/golden atualiza **por tick**, o ColorReversal live só **no Send**. Logo o gate de drawdown do LIVE é **menos protetor** que o golden, e o decision journal do `.mkstick` pode não reproduzir a decisão Por-Conta do live. Fechar = `snapshot.Update()` per-tick no `OnTick` do ColorReversal (mais protetor + consistente) OU tirar o per-tick do runner. **Recomendação da sessão:** decidir DEPOIS de a captura validar o pipeline (não empilhar mudança de risco não-verificada). Registrado no `CHANGELOG` (bloco E2.4).
2. **E2.3 — NÃO iniciado** (exceto o fail-fast `fillDays=0`, já embutido no recording do ColorReversal). Falta: âncora `seedMid`/`seedTickSeq` no header do `.mksbk` (`BrickFileFormat.mqh` zona reservada @192/@200, FORA da exclusão wall-clock 184-191); replay lê+asserta a proveniência do header do journal (o bundle pinado).
3. **E2.4 — verificação pendente de dado:** o critério (sessão cruzando **meia-noite UTC** → 0 diff run↔run) só se prova com uma captura que atravesse a virada de dia.
4. **Fragilidade pré-existente registrada (fora de escopo):** um `WriteTick` que falha no meio de um record deixa bytes órfãos e o `CMksTickFileReader` rejeita o arquivo INTEIRO (compartilhada com o TickRecorder). Item de hardening futuro ("recuperar até o último record íntegro").

## 6. Reframe honesto (MANTIDO — inegociável)

O E2 prova **DETERMINISMO da camada de decisão** (sim↔sim: runner↔runner e runner↔golden) + paridade feed→brick — **NÃO** fidelidade ao broker real. A paridade de decisão live-broker↔replay é **estruturalmente impossível** (o SL real dispara em tick/preço que o sim não reproduz). **PROIBIDO** em qualquer doc/afirmação futura dizer "H4 fechado" ou "paridade de decisão live↔replay = fato". O gap sim↔real segue nomeado como risco do StressLab (eixo 3).

## 7. Config canônica da captura (validada pelo dono nesta sessão)

Brick: `InpBrickSize=3.0`, `L=10`, `K=20`. Estratégia: `InpMagicNumber=527001`, `InpSlPoints=3000` (=10 bricks; ≥ piso 300). Sizing: FIXED `InpFixedLots=0.01`. Risco: `InpMinSlBricks=1`, `InpMaxOpenPositions=1`, `InpMaxLotsPerTrade=1.0`, `InpMaxTotalLots=1.0`, `InpMaxDailyLossPct=5.0`, `InpMaxDrawdownPct=10.0`, `InpMinEquityAbs=0`. **Paridade: `InpRecordMkstick=true`, `InpHistoricalFillDays=0`.** Ambiente confirmado: Exness, conta demo hedging, XAUUSDm digits=3 (~4008 USD).

---

**Resumo em 3 linhas:** (1) E2.0 fechado e MT5-verificado (runner DDR 36/36); E2.1 code-complete e **smoke-tested sobre ticks reais** (o grafo DDR montou e rodou sobre o XAUUSDm real da Exness — determinístico); E2.4 (clock do feed) commitado. (2) **Próximo passo é a captura longa com flips** (Fase A/B/C do §4) → `verify-parity` exit 0 = determinismo da decisão sobre feed real = o marco do E2; depois commitar o golden (E2.2). (3) Em aberto: a lacuna de cadência do snapshot (§5.1, decisão do dono), o E2.3 (âncora do `.mksbk`), e a verificação do E2.4 na virada de dia — todos gatados na captura. Reframe honesto MANTIDO (proibido "H4 fechado").
