---
@document: docs/CHECKPOINTS.md
@project: MKS-ULTIMATE
@purpose: Índice cronológico dos checkpoints de sessão (handoffs entre chats)
@audience: Próxima sessão (humano + IA) que precise rastrear evolução histórica
---

# MKS-ULTIMATE — Índice de Checkpoints

Cada checkpoint é o **handoff de uma sessão** (humano + IA) para a próxima. São registros datados do que mudou em cada ciclo de trabalho — **não fontes da verdade sobre o estado atual**.

**Regra:** CHECKPOINT é guia, código é verdade. Para o estado canônico do projeto consulte, em ordem, `docs/Projeto.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md` e o `git log`. Checkpoints respondem *"como o projeto chegou ao estado de hoje?"*, não *"qual é o estado de hoje?"*.

Checkpoints **NÃO estão na ordem de leitura padrão** definida no `CLAUDE.md` — só são consultados sob demanda histórica.

---

## Cronologia

| Data | Checkpoint | Marco |
|---|---|---|
| 2026-05-20 | [`CHECKPOINT-2026-05-20.md`](CHECKPOINT-2026-05-20.md) | Slice 1 fechado — motor `CMksRenkoBuilder` + testes inline + tipos Tick/Brick/Error |
| 2026-05-20 | [`CHECKPOINT-2026-05-20-slice2.md`](CHECKPOINT-2026-05-20-slice2.md) | Slice 2 — validação do builder sobre ticks reais (`CopyTicksRange`), gap de fim de semana absorvido |
| 2026-05-20 | [`CHECKPOINT-2026-05-20-slice3a.md`](CHECKPOINT-2026-05-20-slice3a.md) | Slice 3a — formato binário `.mksbk` v1 + serializador + golden file test |
| 2026-05-21 | [`CHECKPOINT-2026-05-21-slice3b.md`](CHECKPOINT-2026-05-21-slice3b.md) | Slice 3b — EA `Producer.mq5` fundido (Builder + Sizer + Writer + Custom Symbol); ADR-014 aceita |
| 2026-05-22 | [`CHECKPOINT-2026-05-22.md`](CHECKPOINT-2026-05-22.md) | Pós-validação ADR-005 — framework de teste em `Core/Testing/`, 4 suítes migradas |
| 2026-05-22 | [`CHECKPOINT-2026-05-22-adr005.md`](CHECKPOINT-2026-05-22-adr005.md) | ADR-005 validada empiricamente no MT5 (5 scripts, 0 erros, 0 warnings) |
| 2026-05-22 | [`CHECKPOINT-2026-05-22-cs.md`](CHECKPOINT-2026-05-22-cs.md) | Slices 5a + 6.1 abertos; Custom Symbol completo via ADRs 020/021/022 |
| 2026-05-23 | [`CHECKPOINT-2026-05-23.md`](CHECKPOINT-2026-05-23.md) | Painel UX `CMksProgressPanel` SaaS Navy + refactor do Producer (`OnInit` → `OnTimer` em chunks); ADR-023 registrada como Proposta |
| 2026-05-23 | [`CHECKPOINT-2026-05-23-saturday.md`](CHECKPOINT-2026-05-23-saturday.md) | ADR-024 aceita + slices 24a/b/c; Fase 5b + 6.2 + 6.3 fechadas — toda a ADR-019 materializada |
| 2026-05-23 | [`CHECKPOINT-2026-05-23-night.md`](CHECKPOINT-2026-05-23-night.md) | Fase 7 StressLab (7a + 7b), ADR-008 aceita; §4 Decisões Pendentes do `ARCHITECTURE.md` vazia pela primeira vez |
| 2026-05-25 | [`CHECKPOINT-2026-05-25.md`](CHECKPOINT-2026-05-25.md) | Sessão atravessando 24→25/05 — auditoria profunda P0/P1/P2/P3 + pipeline ADR-024 completo em código (slices 24c-24f), pronto para validação empírica |
| 2026-05-25 | [`CHECKPOINT-2026-05-25-audit.md`](CHECKPOINT-2026-05-25-audit.md) | Auditoria completa de 10 pilares + Lote A (sync documental) + Lote B2/B3 (notas ADR-020/013); B1 suspenso após dono apontar padrão de 3 erros analíticos consecutivos. Próximo passo fixado: validação empírica E2E. |
| 2026-05-25 | [`CHECKPOINT-2026-05-25-night.md`](CHECKPOINT-2026-05-25-night.md) | Tentativa de validação empírica ADR-024 (bloqueada por holiday US/UK) + 2 bugs descobertos in-vivo e corrigidos (Replayer PathStem, Producer histDays=0) + auditoria forense 3 frentes (median ok, "Pts" enganoso, ATR sizer ocioso) + refactor Producer expondo `CMksAtrBrickSizer` via input. PreloadHistory + DumpMksTick adicionados. |
| 2026-05-26 + 27 | [`CHECKPOINT-2026-05-27.md`](CHECKPOINT-2026-05-27.md) | **Ciclo de 2 dias.** Paridade canônica validada empiricamente (T132858 exit 0) + pipeline 1-EA `InpParityRunMode` + `CMksAuditLogSink` + soft K-recovery (ADR-011 nota → implementada) + `Checkpoint()` no BrickFileWriter + **ADR-027** (StressLab credível: latência aplicada, spread composto, SL/TP auto-disparados) + TradeManager auto-detach via `IPositionBook.IsOpen` + RiskManager snapshot fresh em CheckOrder. **Fase 9 plenamente desbloqueada.** 12 commits, 14 testes novos, 25/25 ADRs aceitas. |
| 2026-05-27 | [`CHECKPOINT-2026-05-27-night.md`](CHECKPOINT-2026-05-27-night.md) | **Fase 9 MVP entregue e validada empiricamente em Strategy Tester.** `CMksColorReversalStrategy` (IRenkoSink, close-and-reverse, auto-detach via IPositionBook) + `ColorReversal.mq5` (composition root completo: builder + sinks + risk 3-camadas + Mt5Broker gateado). 3 fixes descobertos rodando no tester (CustomSymbol skip via MQL_TESTER, EnsureCustomSymbolReady canônica, broker.Init + OnTradeTransaction wiring). Backtest 5 dias XAU: 1.112.064 ticks, 1.275 bricks, 617 flips, 617/617 Sends, 297 auto-trigger SL — auto-detach engatado em batalha pela primeira vez. Net -16.26 USD (sem edge por design). Demo live deixada rodando à noite. |
| 2026-05-27 | [`CHECKPOINT-2026-05-27-demo-live.md`](CHECKPOINT-2026-05-27-demo-live.md) | **Fase 9 validada em DEMO LIVE (servidor real).** Demo rodou a noite sem ordem — causa: EA anexado em gráfico de Custom Symbol (`XAUUSDm.MKS_*`), que é saída/visualização sem feed live → `ticks:0`. **Guard adicionado** (OnInit recusa símbolo custom fora do tester). Reanexado no `XAUUSDm` real: **11 ordens reais no Exness** em 7 min (preços/tickets reais, 0 rejeições). **Checkpoint de observabilidade** (60s flush do `.mksbk` + audit) para monitorar demo de horas sem destacar o EA. Fase 9 validada nos 3 ambientes (testes 46/46, tester 617, live 11). Falta slice 2 (stress runner). |
| 2026-05-29/30 | [`CHECKPOINT-2026-05-30.md`](CHECKPOINT-2026-05-30.md) | **Auditoria completa (5 eixos, 18 achados, 12 candidatos verificados adversarialmente) + ADR-029** (hedging-only: recusa netting/exchange, 11/11 no MT5) **+ ADR-030** (StressLab credível p2: saídas estressadas + requote interno + report sobre pipeline real — 112/112 + 32/32 no MT5). **Diagnóstico do CS quebrado em produção:** falha VISUAL (gaps/desalinhamento), NÃO de trading — a estratégia não lê o CS (ADR-020 §1); o `.mksbk` é a verdade → ADR-031 (na época: aposentar CS — **revertida em 2026-06-02: MANTER+CORRIGIR o CS**; a morte à meia-noite era auto-infligida, não bug incorrigível — o V5 sobrevivia com o mesmo `CustomRatesUpdate`; 4 fixes aplicados, sobrevivência à meia-noite pendente de dado). **Alinhamento:** 3+ frentes em branches separadas (`phase9-viz`, `sensors-foundation`, `indicators-bundle-1`) + `main` defasada — decidir ordem de merge. |
| 2026-06-02 | [`CHECKPOINT-2026-06-02-auditoria.md`](CHECKPOINT-2026-06-02-auditoria.md) | **Auditoria completa multi-agente (10 dimensões, leitura integral do core, verificação adversária de cada achado alto/médio + cross-check independente).** 58 achados: **4 altos** (paridade real-tick sem teste automatizado; soft-recovery 105 sem cobertura; `InpSlPoints=30` causa INVALID_STOPS sem broker validar stops level; paridade de DECISÃO nunca comparada live↔replay), **9 médios** (comissão/swap fora do PnL — eixo 3 latente; recovery trava em rampa monotônica; CS fictício em M>1/ATR; eixo 3 sem assert de equity; ADR-024 com códigos `MKS_ERR_TICKFILE_*` fantasmas; watcher cego aos Experts…), **45 baixos/cosméticos; 1 refutado.** Veredito: core estruturalmente sólido (4 eixos do V5 fechados no código) mas **paridade mais estreita que os docs afirmam** (provada só em `fillDays=0`, stream de bricks). **Decisão do dono:** fechar o core 100% robusto antes de estratégias/indicadores → plano em `ROADMAP-CORE-HARDENING.md` (fases E1–E8; E1–E5 gate de estratégias, E8 gate de indicadores). |
| 2026-07-19 | [`CHECKPOINT-2026-07-19-auditoria.md`](CHECKPOINT-2026-07-19-auditoria.md) | **Auditoria completa #2 (5 agentes de área + verificação manual dos altos) + incidente das junctions.** Desinstalação do MT5 atravessou as junctions e apagou o working tree (recuperado via git; capturas `.mkstick` perdidas); terminal reinstalado (mesmo hash), 5 junctions recriadas, 42 arquivos compilam 0/0. Status real do hardening: **E1 feito** (com ressalvas), E2–E6/E8 não iniciados, E7 parcial. **2 achados ALTOS novos** (H5: dedup por `time_msc` decima o feed live no Producer/TickRecorder — invisível ao verify-parity, pré-requisito de E2.2; H6: barras órfãs de formação com wicks poluem os 6 indicadores no CS — bloqueador nº 1 de "indicadores perfeitos", fix barato via `tick_volume==0`) + **16 médios** (posição órfã não adotada no restart; `WaitForDealAdd` impossível sob OnTick; gate E1.1 no-op com stopsLevel=0; crash-recovery do `Checkpoint()` inexistente; test runner aprova suíte vazia; compile tools com falso-OK…). Plano norteador definido frente aos 4 objetivos do dono (institucional, lucrativo, paridade, CS+dashboard): **fase E0** (correções imediatas) → E2–E5 → E7+H6/E8 → **E9 dashboard** (`CMksStatusPanel`, spec no relatório) → Fase 10. |

---

## Como usar

- **Início de sessão nova:** **NÃO ler checkpoints por default**. Seguir a ordem de leitura do `CLAUDE.md` (Projeto → REGRAS → ROADMAP → ARCHITECTURE → V5-POSTMORTEM → PROTOCOLOS → CHANGELOG → TOM-E-CHATS). O estado atual do projeto deriva desses, não dos checkpoints.
- **Sob demanda histórica:** se a conversa referencia "o que fizemos no slice X" ou "quando aceitamos a ADR Y", abrir o checkpoint correspondente da tabela acima.
- **Auditoria de evolução:** ler em ordem cronológica para ver como o projeto chegou ao estado atual.

## Convenção

Novos checkpoints seguem o naming `CHECKPOINT-YYYY-MM-DD[-suffix].md` no diretório `docs/`. Esta tabela é atualizada a cada novo checkpoint criado.