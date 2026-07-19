---
@document: docs/CHECKPOINT-2026-07-19-auditoria.md
@project: MKS-ULTIMATE
@purpose: Auditoria completa #2 (2026-07-19) — leitura integral do repo por 5 agentes de área + verificação manual dos achados altos. Reconcilia o estado real contra o ROADMAP-CORE-HARDENING (E1 feito, E2–E8 abertos), registra os achados novos (2 altos, ~16 médios) e define o plano norteador frente aos objetivos do dono: projeto institucional, lucrativo, paridade nas EAs, indicadores perfeitos no CS, dashboard profissional.
@audience: Dono do projeto e sessões futuras (humano + IA) que executarão o fechamento do core.
---

# CHECKPOINT — 2026-07-19 (auditoria completa #2 + plano norteador)

**Regra:** CHECKPOINT é guia, código é verdade.

**Contexto:** o dono pediu auditoria completa com quatro objetivos declarados: (1) tornar o projeto **substancial e institucional**, (2) torná-lo **lucrativo**, (3) **paridade backtest/live** nas EAs, (4) **indicadores perfeitos no Custom Symbol** e um **dashboard profissional**. A auditoria verifica cada arquivo, decide o que melhorar e o que eliminar, e norteia o projeto daqui em diante.

---

## 0. Incidente operacional do dia (registrado antes da auditoria)

A desinstalação do terminal MT5 antigo (`53785E09...`) **seguiu as 5 junctions e apagou o conteúdo de `MQL5/*/MKS-ULTIMATE` dentro do repo**. Recuperação: `git checkout HEAD -- MQL5/` (HEAD era idêntico ao GitHub; nada foi perdido — mas trabalho não commitado teria morrido). Lições operacionais, incorporadas ao plano (§8): runbook de desinstalação segura (remover junctions com `rmdir` ANTES de desinstalar), backup dos dados de captura (`.mkstick`/`.mksbk` vivem só na árvore do terminal), e avaliação de deploy por cópia (`robocopy /MIR`) no lugar de junctions. As junctions serão recriadas quando o terminal Exness novo estiver instalado (hash novo).

---

## 1. Método

- **5 agentes de área**, cada um lendo integralmente os arquivos da sua dimensão contra ADRs/REGRAS/V5-POSTMORTEM e contra a auditoria de 2026-06-02 (para verificar status, não re-reportar): (a) motor Renko + dados/clock/paridade; (b) broker/trade/risk/account; (c) StressLab + camada de testes (26 suítes, 928 call-sites de assert); (d) CS/indicadores/estratégia/sensores/visualização; (e) docs/tools/higiene institucional.
- **Verificação manual** (esta sessão) dos 2 achados ALTOS novos, por leitura direta dos trechos (`Producer.mq5:892-910`, `CMksCustomSymbolSink.mqh:101-194`) — ambos **confirmados**.
- **Disclaimer:** auditoria estática (leitura de código; sem execução no MT5 — o terminal estava desinstalado no dia). Convergência independente reforça os achados centrais: o dedup (H5) e a posição órfã (M10) foram encontrados por dois agentes distintos por caminhos diferentes.

---

## 2. Veredito geral

O diagnóstico da auditoria de 2026-06-02 permanece válido: **o framework é estruturalmente sólido** — os 4 eixos do V5 seguem fechados no código, a higiene é nível institucional (111/111 headers com as 6 tags verazes, zero "AzInvest", zero bifurcação de ambiente na lógica), e a camada de testes é genuinamente forte (maioria das suítes com verdade independente).

Os problemas são de outra natureza:

1. **O trabalho parou.** Último commit de código: 2026-06-02. Do hardening, **E1 está feito** (E1.1–E1.4, com ressalvas) — **E2, E3, E4, E5, E6, E8 estão 100% não iniciados** e E7 parcial. Seis semanas de meias-noites reais passaram sem o gate E7.1 (barato) capturar o dado.
2. **Dois achados altos novos** escaparam da auditoria anterior — um corrói a verdade dos dados de paridade (H5), o outro bloqueia diretamente o objetivo "indicadores perfeitos no CS" (H6).
3. **Uma família nova de riscos médios**: estados que ninguém adota/reconcilia (posição órfã pós-restart, halt com posição aberta, timeout-com-fill) — a versão "posição" do invariante 5 do postmortem.
4. **Instrumentos de confiança com falso-OK**: test runner aprova suíte vazia, compile tools reportam OK com log vazio, verify-parity passa "no vácuo" — a classe exata "parece validado e não está".

---

## 3. Achados ALTOS novos (2) — verificados manualmente

| ID | Achado | Evidência |
|----|--------|-----------|
| **H5** `same-ms-dedup-decimates-feed` | **O dedup por `time_msc` descarta TODOS os ticks do mesmo milissegundo exceto o primeiro — dentro do batch, não só na fronteira do `CopyTicks`.** `g_lastSeenMsc` é atualizado por tick e comparado com `<=`; o comentário admite que a intenção era só a fronteira. Consequências: (a) o `.mkstick` do TickRecorder **não é captura crua** (viola ADR-012 §1 — perda irreversível no artefato canônico); (b) fill histórico (`CopyTicksRange`, sem dedup) ingere o feed completo enquanto o live ingere o feed decimado — **duas granularidades de dados sob o mesmo builder** (eixo 2 do V5 reintroduzido pelos dados); (c) em burst (XAU/notícia), o brick pode fechar em tick diferente do que o mercado imprimiu (`triggerPrice`/`triggerTickId` divergentes do real). **Invisível ao `verify-parity`** porque Producer e Recorder decimam identicamente. **Pré-requisito de E2.2:** gravar o golden fixture com o dedup atual congelaria o defeito como "correto". Fix: dedup por contagem-no-boundary-ms (padrão canônico do CopyTicks), idêntico em Producer e Recorder, + teste same-ms. | `Producer.mq5:892-910`, `TickRecorder.mq5:199-233` |
| **H6** `orphan-forming-bars-pollute-indicators` | **Barras órfãs de formação poluem os 6 indicadores no CS.** Em mercado calmo (`realTime > nextBarTime`, ADR-023 r.2/r.3), o brick fecha num slot NOVO (`brickTime`) e o slot da bar parcial (`nextBarTime` antigo) **nunca é sobrescrito** — fica uma bar não-brick permanente na série, ~1 por brick em regime calmo, **com wicks mesmo com `showWicks=false`** (`OnBrickForming` grava `fb.high/fb.low` incondicionalmente) e close = mid arbitrário. Donchian/Chandelier/SuperTrend ancoram canais/stops em wicks que a ADR-020 r.3 suprime dos bricks; RSI/MACD contam a órfã como brick; o auto-infer (`probe = rates_total-2`) pode cair numa órfã e cachear brickSize errado. O fato "órfã existe" era conhecido como cosmético; a consequência sobre os indicadores não tinha sido ligada — **é o bloqueador nº 1 de "indicadores perfeitos no CS"**, acima do M3 (M>1/ATR). Fix barato: órfã tem `tick_volume=0` (bricks têm ≥1) — sink deleta o slot órfão no `OnBrickClose` (`CustomRatesDelete`) ou indicadores filtram `tick_volume==0`. Decidir dentro do E8.1. | `CMksCustomSymbolSink.mqh:111-113,166-167,175-194` |

---

## 4. Achados MÉDIOS novos (16)

| ID | Achado | Evidência |
|----|--------|-----------|
| **M10** `orphan-position-not-adopted` | Restart do EA com posição aberta (mesmo symbol+magic): estratégia nasce com `positionId=0`, nunca adota nem fecha a posição antiga; com `maxOpenPositions=1` o book conta a órfã → **todo Send novo leva 405 e o EA fica mudo** até o SL da órfã (3000 pts, sem TP — pode levar dias). Reconstrução parcial de estado = classe do `SyncWithExisting` do V5 (invariante 5). Fix: OnInit varre o book e adota (pid/side/lots) ou fecha com log; no mínimo `Alert`. | `CMksColorReversalStrategy.mqh:141,160,263-268` |
| **M11** `waitfordealadd-cannot-work-from-ontick` | O fallback de confirmação (`res.deal==0`/PLACED) espera `OnTradeTransaction` num loop `Sleep` — mas o evento fica enfileirado até o handler corrente retornar; chamado do OnTick, **nunca** completa: queima 5 s e retorna TIMEOUT mesmo com ordem executada → posição real sem vínculo → dupla exposição no flip (bloqueada depois pelo 405, silenciosamente). Fix: polling de histórico pelo ticket dentro do timeout; em timeout, reconciliar contra o book. | `CMksMt5Broker.mqh:147-156,357-367,460-464` |
| **M12** `e1.1-noop-on-stopslevel-zero` | O gate de SL (410) usa `minSlPoints = StopsLevel()`, que é **0 na Exness/XAU** — o broker que motivou o H3. Com stops level 0 o servidor ainda exige SL fora do spread; `InpSlPoints` pequeno passa no OnInit e leva 10016 em toda ordem live enquanto o backtest preenche — divergência bt/live na camada de decisão. Além: `FreezeLevel` não é lido em lugar nenhum; stops level lido 1× no OnInit (news intraday muda). Fix: mínimo = `max(stopsLevel, spread típico + folga)`. | `ColorReversal.mq5:587-606` |
| **M13** `trailing-sell-never-arms` | `TrailWouldImproveSl` para SELL exige `candidateSl < m_currentSl`; com `initialSl=0` nenhum preço positivo satisfaz — **trailing morto para sempre em SELL sem SL inicial** (BUY funciona). Latente até E5.1; vira crítico quando TradeManager for wired. Fix: tratar `m_currentSl==0` como "sem SL" + teste dos 4 quadrantes. | `CMksTradeManager.mqh:174-179` |
| **M14** `partial-close-volume-and-partial-status` | Partial close: (a) `closeLots = initialLots·pct/100` sem normalizar por VolumeStep/Min → live rejeita 10014 e o manager **re-tenta a cada tick** (spam), enquanto o SimulatedBroker preenche sem reclamar (bt "funciona", live nunca); (b) `MKS_EXEC_PARTIAL` é **inalcançável** — nenhum broker o emite (`MakeFilledResult` sempre FILLED; DONE_PARTIAL tratado como sucesso cheio, contradizendo o header). Fix: floor para step, pular se < VolumeMin, não re-tentar em rejeição não-retryable; mapear DONE_PARTIAL→PARTIAL. | `CMksTradeManager.mqh:341-361`, `CMksMt5Broker.mqh:43-44,165,346-355` |
| **M15** `checkpoint-crash-recovery-inexistente` | A crash-recovery prometida pelo `Checkpoint()` não existe: readers exigem `FileSize == header + count·record` **exato** e recusam o arquivo inteiro (TRUNCATED) — pós-crash o arquivo tem bytes extras. Agravante: em parity mode o Producer nunca chama `Checkpoint()` no tickWriter (só `Flush`) → header com `tickCount=0` → **crash perde a captura inteira**. Fix: reader aceita `size >= expected` com WARN; Checkpoint no ciclo de 60s. | `CMksTickFileReader.mqh:161-172`, `Producer.mq5:983-984` |
| **M16** `recorder-restart-breaks-multiday-replay` | Reopen-append da ADR-024 §2 nunca implementado; cada restart do Service reinicia `g_seq` em 1 → validação cross-file (`seq <= lastSeqGlobal` → halt 810) **quebra o replay multi-dia que atravesse qualquer restart** (update do Windows no meio da semana = semana irreplayável). Fix: reopen-append com continuação de seq, ou relaxar cross-file p/ reinício de seq com timeMsc contínuo (WARN), ou emendar a ADR. | `TickRecorder.mq5:51,114-130`, `CMksMultiFileTickSource.mqh:204-215` |
| **M17** `atr-session-unreplayable` | Producer expõe `SIZER_MODE_ATR`, mas o Replayer só monta `CMksFixedBrickSizer` — **sessão ATR é irreplayável por construção**, e nada impede o operador de ligar ATR + parity mode (verify nunca pode passar). Fix: fail-fast no OnInit (ATR incompatível com parity mode) até E2.3 (snapshot do sizer no header). | `Replayer.mq5:42,330` vs `Producer.mq5:63-78` |
| **M18** `verify-parity-log-diff-vacuous-or-spurious` | O passo 4 (diff de logs) compara conjuntos assimétricos: Producer loga 102/103, Replayer não; o 104 do Producer não casa com o pattern, o do Replayer casa; 105 invisível nos dois. Sessão normal → exit 2 espúrio; sessão limpa → "IDÊNTICOS (0 decisões)" (passe vácuo, sem warning). Fix: comparar os `audit.tsv` (simétricos por construção) e falhar quando 0 linhas casarem. | `tools/verify-parity.ps1:236-272` |
| **M19** `stream-halt-abandons-open-position` | Halt do stream (104) para o pipeline com posição aberta sem `Alert` e sem flatten — posição fica sem gestão até o SL de 3000 pts. Fix: em halt com `HasOpenPosition()`, flatten ou `Alert` (coerente com E5.4). | `ColorReversal.mq5:837-852` |
| **M20** `testrunner-approves-empty-suite` | Teste sem nenhuma assertion e suíte vazia contam como "pass" (`0/0 in 0 tests`, sem Alert) — refactor que apaga `MKS_RUN` produz suíte verde sem cobertura. E o meta-teste **sempre** dispara `Alert("1 FAILED")` em run saudável (falha sintética fica nos contadores; não há `Reset()`) — dessensibiliza e quebra grep por "FAILED". | `TestRunner.mqh:49-58,73-83`, `Test_MksTestFramework.mq5:101-127` |
| **M21** `recordingbroker-blind-to-send-request` | O mock oficial não grava a `MksOrderRequest` do Send; os testes de estratégia verificam `slPoints`/`magic` lendo getters **da própria estratégia** (tautologia) — estratégia que montasse `req.slPoints=0` passaria a suíte. Fix: gravar `{request, result}` no mock; de graça elimina o `CMockBroker` inline duplicado do Test_RiskGatedBroker. | `CMksRecordingBroker.mqh:60-70`, `Test_CMksColorReversalStrategy.mq5:175-177` |
| **M22** `sensors-in-main-zero-tests` | `CMksReversalRegime` entrou na `main` (ADR-025) com **cobertura zero** e sem guarda de range (`endIdx < period-1` → out-of-range) — viola "testes antes de EA" para um componente que tende a virar insumo de decisão. Fix: suíte unitária + guarda antes de qualquer consumo. | `CMksReversalRegime.mqh:49-55` |
| **M23** `compile-tools-false-ok-empty-log` | Se o MetaEditor falha ao iniciar ou o log sai vazio, watcher e compile-all contam 0 erros e reportam **"OK"/"TODOS COMPILAM LIMPOS"** (exit 0); exit code do MetaEditor nunca checado. Mesma classe do M9. Fix: log vazio/ausente = falha. | `tools/watch-compile.ps1:98-134`, `tools/compile-all.ps1:129-160` |
| **M24** `phase-status-lies` | Tracker E1 diz "Não iniciada" com E1.1–E1.3 commitados; `ARCHITECTURE.md §4` afirma "nenhuma decisão pendente" com a ADR-031 pendente (entregável E7.3) — a skill `/status` reportaria zero pendências; Fase 9 do ROADMAP ainda narra os 3 furos do StressLab como abertos (ADR-030 os fechou com testes). Fix: sync + check anti-drift no `/status`. | `ROADMAP-CORE-HARDENING.md:34`, `ARCHITECTURE.md:2351-2353`, `ROADMAP.md:305,315` |
| **M25** `settings-local-json-tracked` | `.claude/settings.local.json` (permissões machine-specific) está trackeado no git — ruído permanente de working tree entre as 2 máquinas. Fix: `git rm --cached` + `.gitignore`. | `.claude/settings.local.json` |

---

## 5. Achados BAIXOS novos (compacto)

**Motor/dados/paridade:** flags do MultiFileTickSource nunca inicializadas no construtor (+ comentário "Reporta via Print" mente) `CMksMultiFileTickSource.mqh:274-279`; janela morta fill→live (ticks entre `toMsc` e o anchor live nunca processados) `Producer.mq5:447,850-852`; fill 30d carrega ~GBs de `MqlTick` em RAM de uma vez (V5 fazia chunking) `Producer.mq5:450`; erro de I/O mid-file vira EOF silencioso `CMksFileTickSource.mqh:130-139`; `DumpMksTick` divide por zero com `InpPrintLastN=0` + `prevSeq` morto; `m_lastMid` atualizado antes da rejeição 102 (forming expõe mid de outlier) `CMksRenkoBuilder.mqh:232-233`; header do `CMksMt5Clock` menciona uso que não existe + `g_clock` do Replayer é objeto morto; runbook no header do `verify-parity.ps1` descreve pipeline que gera falso-negativo garantido (seqs independentes Producer vs Recorder).

**Execução/risco:** SL/TP não recomputados no retry pós-requote `CMksMt5Broker.mqh:288-322`; SimulatedBroker aceita volume/SL que o servidor real rejeitaria (mecanismo que converte M12/M14 em divergência bt/live); peak equity amostrado só em flips (drawdown subestimado, fail-open) — `snapshot.Update()` deveria rodar no OnTick; logger rotula "Z" mas usa `TimeCurrent()` (fuso do servidor); `Test_MksMt5BrokerLive` fecha com `InpLots` em vez de `filledLots`.

**CS/indicadores/sensores:** contador `updateFailures` compartilhado forming/close distorce o gate de log (1ª falha de close pode logar como "#500"); o desenho do gate E7.1 não cobre a config real **multi-CS** na virada de dia (condição admitida da corrupção); `CMksReversalRegimeDebug` inclui a bar em formação no score (inconsistente com o probe-2 do catálogo); `InpComment` é input morto; `m_magic` da estratégia nunca aplicado a ordens; `g_nextBarTime` global inútil.

**StressLab/testes:** caminho "requote parcial → fill com slip composto" sem teste; `maxRequotes<=0` desliga requote em silêncio; `CMksFakePositionBook.IsOpen(id desconhecido)==true` inverte o contrato do book real (mascara divergência); precedência SL>TP no mesmo tick (ADR-027 §7.3) e `commissionClose` do auto-close sem assert; `OnBrickClose` do MultiSink sem teste (só forming); LCG não pinado a golden constants; 2 asserts vazios no Test_StressLabReport; helpers duplicados entre suítes (candidato a `Tests/Helpers`).

**Docs/tools/institucional:** CLAUDE.md e CHEATSHEET descrevem o watcher pré-E1.2; CHEATSHEET usa input renomeado (`InpBrickSizePts`) e ensina o fluxo antigo de 2 artefatos em vez do `InpParityRunMode`; `protocolo-1` defasado (omite `@depends_on`, cita paths/classes errados); README fraco/defasado; árvore §2 do ARCHITECTURE lista `logs/` e `reference/Renko-MQL5` inexistentes; `watch-compile.ps1` sem BOM UTF-8 (mojibake no PS 5.1); zero git tags; `.gitignore` com bloco morto e padrões (`Files/`, `*.log`) que podem engolir os fixtures golden do E2.2; branch remota zumbi `claude/check-ultimate-access-5kshn`; `[Não lançado]` do CHANGELOG com ~280 linhas e blocos repetidos.

---

## 6. Status consolidado E1–E8 (verificado contra código e git)

| Fase | Status real | Evidência-chave |
|------|-------------|-----------------|
| **E1** higiene | **FEITO** (com ressalvas) | E1.1 no Risk (410 + OnInit fail-fast + 6 testes; desvio de desenho registrado — gate no Risk, não no broker; ressalvas: M12, FreezeLevel nunca lido). E1.2 verificado no watcher. E1.3 conferido campo a campo (ADR-024 ↔ `Error.mqh` 1:1). E1.4 quase (resta branch remota zumbi). **Tracker desatualizado (M24).** |
| **E2** paridade de decisão | **NÃO INICIADO** (0/4) | Replayer segue sem estratégia/broker; nenhum fixture/golden versionado; parity mode não força `fillDays=0`; clock segue wall-clock. **H5 é pré-requisito novo do E2.2.** |
| **E3** robustez do motor | **NÃO INICIADO** (0/3) | Soft-recovery 105 segue com zero testes (H2); rampa monotônica segue travando (M2); comentários "variância" seguem mentindo. |
| **E4** eixo 3 completo | **NÃO INICIADO** (0/3) | `RecordClose` sem comissão; `r.swap=0` sempre; `SwapForDays` sem nenhum chamador (knob morto); teste "commissionPerLot diferente → netPnL diferente" daria idêntico hoje. |
| **E5** gestão integrada | **NÃO INICIADO** (0/4) | TradeManager referenciado só pelo próprio teste; PARTIAL inalcançável (M14 piora o diagnóstico do E5.2); flip com Close falho segue abrindo; breaker segue só preventivo. **+ M10/M13/M19 entram aqui.** |
| **E6** UX/produto | **NÃO INICIADO** | ~30 inputs; `InpComment` morto; runbook defasado. |
| **E7** CS gate empírico | **PARCIAL** | 4 fixes da reversão presentes e corretos no código; E7.1 sem dado (6 semanas de meias-noites perdidas; default `ResetBars=true` mascara persistência), E7.2 0/3 (timeline avança em falha; forming muda; comentários mentem), E7.3 ADR-031 não escrita. **+ H6 e o cenário multi-CS entram no desenho do gate.** |
| **E8** fundação de indicadores | **NÃO INICIADO** (0/4) | `tick_volume` ignorado pelos 5; auto-infer frágil (agravado por H6); testes de Chandelier/SuperTrend seguem ancorados nos buffers do próprio indicador; decisão CS vs `IRenkoIndicator` não tomada. |
| **3 furos do StressLab** (Fase 9) | **FECHADOS** | ADR-030 implementada com testes que provam (saídas estressadas, requote interno, report de pipeline real) — o ROADMAP Fase 9 precisa ser atualizado (M24). Resta: stress runner (= E2.1). |

---

## 7. O que está genuinamente BEM-FEITO

- **Anti-V5 continua real no código:** produtor único, `triggerPrice`/`triggerTickId`, custo no fill, zero bifurcação de ambiente na lógica (re-verificado por grep pelos 5 agentes).
- **Serialização determinística** conferida offset a offset contra os formatos; exclusão wall-clock do verify-parity correta.
- **Camada de testes forte:** maioria das 26 suítes com verdade independente; `Test_CMksRiskManager` é a melhor suíte do repo; TickFile/BrickFile são referência de qualidade (roundtrip byte-a-byte + golden 10k).
- **StressLab pós-ADR-030 credível** (adversidade simétrica, requote interno, pipeline real no teste do report).
- **Higiene institucional de código:** 111/111 headers verazes, zero AzInvest, `reference/V5` perfeitamente isolado (0 includes cruzados, 0 credenciais).
- **Indicadores matematicamente corretos** sobre a série que leem (Wilder/MACD/Donchian/ratchets canônicos) — o defeito está na série (H6/M3), não na matemática.
- **E1 executado com qualidade** — inclusive com solução melhor que a letra do roadmap (gate de SL no Risk, simétrico bt/live).

---

## 8. Plano norteador (frente aos 4 objetivos do dono)

### E0 — Correções imediatas (novo; dias, não semanas)
Protege dinheiro e a verdade dos dados **antes** de retomar o hardening:
1. **H5** — dedup correto (Producer + Recorder) + teste same-ms. *Bloqueia E2.2.*
2. **M10 + M19** — adoção de posição órfã no OnInit + Alert/flatten no halt. *Protege dinheiro em live.*
3. **M12** — mínimo de SL espread-aware (caso Exness stopsLevel=0). *Destrava operação real.*
4. **M20 + M23** — integridade dos instrumentos de confiança (runner, meta-teste, compile tools, passo 4 do verify-parity → audit TSV [M18]).
5. **M24 + M25** — sync de status (tracker, ARCHITECTURE §4, ROADMAP Fase 9, docs do watcher) + untrack `settings.local.json`.
6. **Operacional:** recriar junctions no terminal novo; CHEATSHEET §9.6 "desinstalação segura"; backup automático dos `.mkstick`/`.mksbk` para fora da árvore do terminal (matéria-prima insubstituível da paridade).
7. **Eliminações** da §9 (baixo risco, commit dedicado).

### Objetivo "paridade nas EAs" → E2 + E3 (o gate central, inalterado + aditivos)
E2 ganha: M15 (crash-recovery real), M16 (recorder-restart), M17 (fail-fast ATR), M18 (audit TSV como oráculo). E3 inalterado (H2/M2/E3.3). Critérios de saída do ROADMAP-CORE-HARDENING mantidos.

### Objetivo "lucrativo" → E4 + E5, depois Fase 10
Honestidade primeiro: **nada no repo hoje é desenhado para ser lucrativo** — ColorReversal é EA de validação (não-lucrativa por design). Lucratividade vem da Fase 10 (estratégias reais), que está — corretamente — bloqueada pelo gate E1–E5. O caminho responsável mais curto: E4 (custo em moeda no resultado; sem isso o StressLab como oráculo de "ir pra live" é estruturalmente otimista — eixo 3) + E5 (gestão integrada, agora incluindo M13/M14) → Fase 10 com StressLab como critério de aprovação. Atalhos aqui repetem o V5.

### Objetivo "indicadores perfeitos no CS" → H6 + E7 + E8
Ordem: fix do H6 (barato: `tick_volume==0`) + E7.2 (robustez do sink) → gate E7.1 na config real (**incluindo ≥2 CS ativos** na virada, cenário A5) → ADR-031 (E7.3) → E8 (política M>1, auto-infer robusto, testes independentes, decisão CS vs `IRenkoIndicator`). Só então o catálogo expande.

### Objetivo "dashboard profissional" → nova fase **E9 — CMksStatusPanel** (após E4; esqueleto pode antes)
- **Contrato de paridade inegociável:** observador passivo injetado no composition root; consome apenas os objetos do root (nunca GlobalVariables — o defeito do `V5-PanelBridge` —, nunca releitura do terminal, nunca o CS); garantia mecânica painel ON/OFF → `.mksbk` byte-idêntico (padrão ADR-028 §7).
- **v1 com o que o core já expõe (~80%):** posição atual + idade em bricks; PnL do dia/%; drawdown vs pico; budget de risco consumido (% dos limites 407-409); métricas da estratégia (flips/fills/rejeições **por código 400-410**); saúde do CS (`barsPushed` vs writer, `updateFailures`, idade do último update); saúde do feed (ticks/s, idade do último tick, `g_streamHalted`); badge do envelope de paridade (fillDays/modo); sync de artefatos; uptime.
- **Requer 3 aditivos pequenos no core:** getter de estado do breaker no RiskManager; latência de roundtrip no Mt5Broker; `netPnL` em moeda no Journal (= E4.1).
- **Arquitetura:** `Core/Output/CMksStatusPanel.mqh` reusando primitivas do ProgressPanel; struct tipado de status preenchido a 1 Hz via OnTimer; um card = uma função; sem abas nem botões de comando na v1 (comando = ADR própria futura).

### Objetivo "institucional" → processo (paralelo, incremental)
1. **CI em fases:** (1) GitHub Actions com validadores estáticos (6 tags, greps de proibição — `MQL5_TESTING` na lógica, AzInvest, `TimeCurrent` fora de Clock —, grafo de includes, links de docs); (2) compile via **self-hosted runner** nesta máquina (`compile-all.ps1` já é o job, pós-M23); (3) testes headless via terminal — aspiração pós-E2.
2. **Tags/releases:** `v6.0.0-alpha.1` no fechamento de E0; cortar o `[Não lançado]` do CHANGELOG por marco.
3. **Branch protection** na `main` (bloquear force-push/deleção); **LICENSE** (all rights reserved).
4. **Backup dos dados de captura** (robocopy diário para fora do terminal + nuvem).
5. **Anti-drift:** check no `/status` — "status E0–E9 bate com `git log`?".

**Ordem geral:** E0 → E2/E3 (paridade) e E4/E5 (dinheiro) — podendo intercalar — com E7(+H6)/E8 e institucional em paralelo → E9 (dashboard v1) → **GATE** → Fase 10 (estratégias, a fase que paga).

---

## 9. Eliminar / arquivar (decisão desta auditoria)

| Item | Ação | Justificativa |
|------|------|---------------|
| `Scripts/ValidateRenkoBuilder.mq5` | **Eliminar** | 0 asserts (M6); todos os cenários têm asserts reais em `Test_CMksRenkoBuilder`; puro falso senso de cobertura |
| `Scripts/ValidateBuilderOnRealTicks.mq5` | Renomear `Diag*` agora; aposentar pós-E2.2 | Nome "Validate" mente (0 asserts); valor residual só diagnóstico |
| `Tests/Test_Producer.mq5` | Aposentar **somente** após golden E2.2 existir | Hoje é a última linha de defesa real-tick, ainda que rascunho |
| `reference/V5/V5-Dashboard2.mq5` | **Eliminar** | Byte-idêntico ao `V5-Dashboard.mq5` (150KB duplicados) |
| `reference/V5/MKS-Dashboard.mq5` + `MKS-Dashboard2.mq5` | **Eliminar** | 0 bytes |
| `docs/BRIEFING-PROXIMA-SESSAO-CS.md` | Arquivar após migrar §5 (questionário viz) e 2 dívidas não rastreadas (`DumpMksTick` div/0; logger ignora IClock) | Estado de branches/watcher que descreve não existe mais |
| Branch remota `claude/check-ultimate-access-5kshn` | **Deletar** | Zumbi de 05-25 |
| Código morto: `InpComment`, `g_clock` (Replayer), `prevSeq` (DumpMksTick), `g_nextBarTime`, `m_magic` (estratégia), 2 asserts vazios, bloco morto do `.gitignore` | **Eliminar** (commit de limpeza) | Inputs/objetos que mentem sobre a superfície |
| `CMksCostModel.SwapForDays` | Wire no E4.1 **ou** eliminar | Zero chamadores; "custo modelado sem efeito" embrionário |
| Maquinaria `WaitForDealAdd`/`m_pending*` do Mt5Broker | Substituir por polling de histórico (M11) | Rede de segurança que não pode funcionar = falsa confiança |
| `.claude/settings.local.json` | Untrack (M25) | Machine-specific |
| **Manter:** 20 CHECKPOINTs (indexados, links), CHEATSHEET §§1-8, resto do `reference/V5`, `ISensor`/`SensorState` (fundação ADR-025 — ressalva correta é M22, não "código morto"), ramo netting dormente (ADR-029), `PreloadHistory`/`ValidateProducerOutput`/`DumpMksTick` (utilitários reais) | — | — |

---

**Resumo em 3 linhas:** (1) O core segue estruturalmente sólido e o E1 foi bem executado — mas o hardening parou em 06-02: E2–E8 seguem abertos, e 2 achados altos novos surgiram: o **feed live é decimado silenciosamente** (H5 — invisível ao verify-parity, pré-requisito de E2.2) e **barras órfãs poluem os indicadores no CS** (H6 — o bloqueador real de "indicadores perfeitos", com fix barato). (2) Família nova de riscos médios: estados órfãos (posição pós-restart, halt, timeout-com-fill) e instrumentos de confiança com falso-OK (runner, compile tools, verify-parity) — a classe exata "parece validado e não está". (3) Plano: **E0** (correções imediatas + operacional pós-incidente das junctions) → E2–E5 (gate de paridade e dinheiro) com E7+H6/E8 (CS/indicadores) e institucional (CI faseada, tags, backup) em paralelo → **E9 dashboard** (spec definida, ~80% dos dados já expostos) → Fase 10, a fase que paga.
