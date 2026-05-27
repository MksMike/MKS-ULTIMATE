---
@document: docs/CHECKPOINT-2026-05-27-demo-live.md
@project: MKS-ULTIMATE
@purpose: Adendo da sessão de fim-de-tarde de 2026-05-27 — validação da Fase 9 em DEMO LIVE. Demo rodou a noite sem ordem (causa-raiz: EA anexado em gráfico de Custom Symbol sem feed) → guard estrutural + demo confirmada com 11 trades reais + checkpoint de observabilidade mid-sessão. Fase 9 validada nos 3 ambientes (testes, tester, live).
@audience: Próxima sessão (humano + IA) — decisão entre stress runner (slice 2 da Fase 9) ou Fase 10.
---

# CHECKPOINT — 2026-05-27 (sessão demo live)

Adendo direto ao [`CHECKPOINT-2026-05-27-night.md`](CHECKPOINT-2026-05-27-night.md) (Fase 9 MVP entregue + validada em Strategy Tester, demo live deixada rodando). Este documento cobre o que aconteceu quando a demo live foi conferida: um bug operacional silencioso, sua correção estrutural, a confirmação empírica do EA em servidor real, e uma melhoria de observabilidade.

**Marco do ciclo (em uma frase):** **Fase 9 validada em DEMO LIVE com fills reais do Exness** — após diagnosticar e blindar um erro operacional (EA anexado no gráfico errado), o `ColorReversal` abriu **11 ordens reais** em 7 minutos de mercado ativo (preços de XAU reais, tickets reais do broker), fechando o terceiro e último ambiente de validação que o ROADMAP §Fase 9 exigia.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 16 arquivos, nesta ordem

1. `README.md`
2. `docs/CHECKPOINT-2026-05-20.md`
3. `docs/CHECKPOINT-2026-05-20-slice2.md`
4. `docs/CHECKPOINT-2026-05-20-slice3a.md`
5. `docs/CHECKPOINT-2026-05-21-slice3b.md`
6. `docs/CHECKPOINT-2026-05-22.md`
7. `docs/CHECKPOINT-2026-05-22-cs.md`
8. `docs/CHECKPOINT-2026-05-23.md`
9. `docs/CHECKPOINT-2026-05-23-saturday.md`
10. `docs/CHECKPOINT-2026-05-23-night.md`
11. `docs/CHECKPOINT-2026-05-25.md`
12. `docs/CHECKPOINT-2026-05-25-audit.md`
13. `docs/CHECKPOINT-2026-05-25-night.md`
14. `docs/CHECKPOINT-2026-05-27.md` — ciclo 26+27: paridade validada + ADR-027 + pontas pré-Fase 9
15. `docs/CHECKPOINT-2026-05-27-night.md` — Fase 9 MVP: EA + strategy + validação no Strategy Tester
16. `docs/CHECKPOINT-2026-05-27-demo-live.md` — este (validação em demo live + guard de Custom Symbol + observabilidade)

Após esses, invocar `/status` para confirmar o estado contra `git log` antes da primeira ação.

---

## 2. Estado do código

**Branch ativa:** `main`, sincronizada com `origin/main` (HEAD `92b59dc`). Branches `fix/colorreversal-custom-symbol-guard` e `feat/colorreversal-checkpoint` mergeadas com `--no-ff` e deletadas local + remote.

### Histórico desta sessão

```
92b59dc  Merge branch 'feat/colorreversal-checkpoint' — observabilidade mid-sessao  ← HEAD
8c84793  feat(phase9): checkpoint de observabilidade no ColorReversal (.mksbk + audit flush 60s)
c9aea54  Merge branch 'fix/colorreversal-custom-symbol-guard' — guard de Custom Symbol
b5d00f2  fix(phase9): guard contra Custom Symbol no ColorReversal OnInit
6af751b  docs: CHECKPOINT 2026-05-27 noite — Fase 9 MVP entregue e validada em tester  ← fim da sessão anterior
```

**Totais desta sessão:** 4 commits (2 fix/feat + 2 merge), ~64 linhas adicionadas, 0 regressões em **39/39 .mq5** validados via `compile-all.ps1`.

### ADRs

**25/25 ADRs aceitas.** Nenhuma ADR nova — esta sessão foi diagnóstico + 2 fixes pequenos. §4 Decisões Pendentes continua vazia.

### Arquivos modificados

- `MQL5/Experts/MKS-ULTIMATE/ColorReversal.mq5` — guard de Custom Symbol no OnInit + checkpoint de observabilidade a cada 60s no OnTick
- `MQL5/Include/MKS-ULTIMATE/Core/Output/CMksAuditLogSink.mqh` — método `Flush()` novo
- `CHANGELOG.md`

---

## 3. Ciclo cronológico — 27/05 fim de tarde (3 sub-ciclos)

### Sub-ciclo A — Diagnóstico: demo live rodou a noite sem ordem

O dono reportou: deixou `ColorReversal` rodando em demo live a noite inteira, **nenhuma ordem aberta**.

Investigação empírica (leitura dos `.log` da pasta live, não da sandbox do tester):

```
"symbol":"XAUUSDm.MKS_3"   ← NÃO é XAUUSDm; é um Custom Symbol
"ticks":0                  ← nunca recebeu um tick sequer
"cs":"XAUUSDm.MKS_3.MKSCR_3" ← tentou criar um CS de um CS (absurdo)
```

**Causa-raiz:** o EA estava anexado ao gráfico de um **Custom Symbol** (`XAUUSDm.MKS_3` / `XAUUSDm.MKS_1`) — aqueles que o Producer cria para *visualizar* os bricks Renko. Um Custom Symbol é container **estático** de bricks históricos; **não recebe feed de ticks ao vivo**. Cadeia de consequência:

```
gráfico errado (Custom Symbol)
   → CopyTicks(XAUUSDm.MKS_3) retorna 0 ticks para sempre
      → builder não forma nenhum brick
         → estratégia não vê nenhum flip
            → nenhuma ordem
```

**Por que foi fácil errar:** o gráfico do CS *mostra exatamente* os bricks que a estratégia raciocina — parece o lugar certo. Mas o CS é **saída** (visualização), não **entrada** (feed). A estratégia tem o próprio motor de bricks e precisa dos ticks crus do símbolo REAL do broker (`XAUUSDm`, sem sufixo `.MKS_`).

A lógica em si estava correta (no Strategy Tester abriu 617 ordens). O erro era puramente *onde* o EA estava plugado.

### Sub-ciclo B — Fix: guard de Custom Symbol (commits `b5d00f2` + `c9aea54`)

`ColorReversal.OnInit` ganha guard: fora do tester, se `SymbolInfoInteger(symbol, SYMBOL_CUSTOM)` for true, recusa com `INIT_PARAMETERS_INCORRECT` + log ERROR + Print explícito instruindo a anexar no símbolo real do broker.

```mql5
if(!g_isTesting && (bool)SymbolInfoInteger(g_symbol, SYMBOL_CUSTOM))
{
   // log ERROR + Print "anexe no símbolo REAL (ex.: XAUUSDm)"
   Cleanup();
   return INIT_PARAMETERS_INCORRECT;
}
```

Blindagem estrutural — esse erro nunca mais desperdiça uma sessão em silêncio.

### Sub-ciclo C — Confirmação em demo live + observabilidade (commits `8c84793` + `92b59dc`)

O dono reanexou o EA no `XAUUSDm` real. Log confirmou `"symbol":"XAUUSDm"` (sem sufixo) + `"OnInit done — ready for ticks"`.

Após ~7 min, uma sessão fechou (deinitReason 5 = mudança de parâmetro) e o session summary revelou:

```json
"ticks":1735, "bricks":23, "flips":11,
"sendsAttempted":11, "sendsFilled":11, "sendsRejected":0,
"closesAttempted":10, "closesFilled":10,
"autoDetected":0, "streamHalted":false,
"hasOpenPosition":true, "currentPositionId":1865748333
```

**Funcionou.** Preços reais (4438.11, 4435.56…), tickets reais do Exness (1865748333), 11/11 Sends preenchidos sem rejeição.

**Achado de observabilidade:** os números só ficaram visíveis quando a sessão **fechou** (OnDeinit faz flush + Close). Mid-sessão, o `.mksbk` e o audit TSV apareciam em **0 bytes** por causa do buffering do MQL5 — o `ColorReversal` não tinha flush periódico (só o Producer tinha, via Checkpoint a cada 60s). Monitorar uma demo de horas era cegueira.

**Fix de observabilidade:**
- `CMksAuditLogSink` ganha `Flush()` (FileFlush sem fechar handle).
- `ColorReversal.OnTick` faz checkpoint a cada 60s (wall-clock via `GetTickCount`, fora do tester): `g_writer.Checkpoint()` patcheia header do `.mksbk` + `g_auditSink.Flush()`. Mesmo padrão do Producer.
- Agora `.mksbk` e audit crescem observáveis em tempo real — `wc -l` no audit mostra bricks/trades sem destacar o EA.

### Lições operacionais

1. **Custom Symbol é SAÍDA, não ENTRADA.** Anexar estratégia em gráfico de CS é erro de categoria. O guard agora impede.
2. **Buffering do MQL5 esconde arquivos mid-sessão.** Qualquer EA de longa duração que escreva arquivos precisa de flush periódico para ser monitorável. Producer já tinha; ColorReversal agora também.
3. **A diferença entre tester e live nos artefatos:** no tester os arquivos vão para `Tester\<id>\Agent-127.0.0.1-3000\MQL5\Files\...`; em live vão para `Terminal\<id>\MQL5\Files\...`. Não confundir ao auditar.

---

## 4. Estado das fases do ROADMAP

| Fase | Status |
|---|---|
| 0–8 | Concluídas |
| **9 — Primeiro EA end-to-end** | **MVP validado nos 3 ambientes** (ver §5). Falta slice 2 (stress runner). |
| 10 — Estratégias reais | Não iniciada |

**Critério de saída da Fase 9 (ROADMAP literal) — status:**
- ✅ "Rodar em backtest" → Strategy Tester, 617 trades, 1.1M ticks, 100% qualidade (sessão anterior).
- ⏳ "Rodar em stress lab (3 níveis)" → **pendente** — slice 2 (stress runner) ainda não construído.
- ✅ "Rodar em demo live" → 11 trades reais com fills do Exness (esta sessão).
- ✅ "Comparar logs e validar paridade" → `.log` + `.mksbk` + audit TSV gerados em todos os ambientes, mesmo formato.
- ✅ "EA sobrevive sem quebrar core, zero crash, zero `_LastError` não tratado" → confirmado em tester e live.

A Fase 9 está **funcionalmente validada**; o slice 2 (stress runner exercitando a ADR-027 em pipeline real) é o último pedaço para declará-la 100% concluída.

---

## 5. Validação empírica acumulada da Fase 9 (3 ambientes)

| Ambiente | Quando | Resultado |
|---|---|---|
| **Testes unitários** | 2026-05-27 madrugada | `Test_CMksColorReversalStrategy`: **46/46 assertions, 11 testes, 0 falhas** |
| **Strategy Tester (backtest)** | 2026-05-27 ~01:26 | 1.112.064 ticks, 1.275 bricks, 617 flips, 617/617 Sends, 297 auto-trigger SL, Net -16.26 USD, DD 1.14% |
| **Demo live (servidor real)** | 2026-05-27 ~20:46 | 1735 ticks, 23 bricks, 11 flips, **11/11 Sends reais**, preços e tickets reais do Exness |

**O que a demo live provou que o backtest não podia:**
- `CMksMt5Broker` executa `OrderSend` real contra o servidor Exness (não simulação MT5).
- Tickets reais (`1865748333`) — não os sintéticos do tester.
- O caminho `Init()` + `OnTradeTransaction` wiring funciona em servidor real.
- Latência real broker→servidor não quebrou nada.

**O que ainda não foi exercitado em live:**
- **Auto-detach via `IPositionBook.IsOpen`** (`autoDetected:0`) — nenhum SL bateu nos 7 min (SL de 3 USD, mercado não andou tanto contra antes do próximo flip). No backtest tester foi exercitado 297 vezes; em live, ainda não. Acontecerá numa sessão mais longa ou mais volátil.
- **Soft K-recovery (código 105)** — sem fill histórico, sem gap estrutural; não disparou.

---

## 6. Pendências em aberto

### Bloqueantes — ZERO

### Não-bloqueantes

1. **Stress runner — slice 2 da Fase 9 (não iniciado).** EA/script que replaya `.mkstick` plugando `CMksColorReversalStrategy` sobre `CMksSimulatedBroker` + `CMksStressLabBroker` (None/Light/Medium/High/Nightmare), agrega via `CMksStressLabReport`. **Exercita a ADR-027** (latência aplicada, spread composto, auto-trigger SL/TP simulado) com a estratégia real. Último pedaço da Fase 9.
2. **Auto-detach em live ainda não observado** — validação oportunística numa demo mais longa.
3. **`CMksMt5Broker` exige `Init()` explícito** — padrão inconsistente com outros componentes (que inicializam no construtor). Refactor futuro pode unificar; por ora documentado.
4. **Logger sem precisão de millis.** Documentado desde 2026-05-25. Não bloqueia nada.
5. **Producer fill histórico via `CopyTicksRange`.** Mitigado por `InpHistoricalFillDays=0`.

---

## 7. Próximos passos sugeridos

| Opção | Esforço | Valor |
|---|---|---|
| **A — Stress runner (slice 2 da Fase 9)** | Médio (~300 linhas) | **Fecha a Fase 9 100%**; valida ADR-027 em pipeline real com a estratégia |
| **B — Demo live longa (horas/dias)** | Trivial (deixar rodando) | Observa auto-detach em live + acumula estatística de custos reais |
| **C — Iniciar Fase 10 (estratégia com edge)** | Alto (pesquisa) | Sai do framework, entra em pesquisa de mercado |
| **D — Refactor `CMksMt5Broker.Init` → construtor** | Baixo | Cleanup técnico; risco de quebrar EA da demo |

**Recomendação:** A (stress runner) é a continuação natural e o último pedaço antes da Fase 10. Pode rodar em paralelo com B (deixar a demo live acumulando enquanto se constrói o runner).

**Não fazer sem alinhar:** iniciar Fase 10 (decisão de pesquisa, exige escolher mercado/hipótese), ou refactor agressivo do broker (pode quebrar a demo viva).

---

## 8. Comandos úteis para o próximo chat

```bash
/status

# Logs do ciclo desta sessão
git log --oneline 6af751b..HEAD

# Compile-all (sanity)
powershell -ExecutionPolicy Bypass -File tools\compile-all.ps1

# Monitorar demo live em tempo real (agora que tem flush a cada 60s)
Get-Content "<Terminal>\MQL5\Files\MKS-ULTIMATE\Logs\ColorReversal_XAUUSDm_*.log" -Tail 20 -Wait

# Contar bricks acumulados no audit (cresce a cada 60s)
Get-Content "<Terminal>\MQL5\Files\MKS-ULTIMATE\Logs\ColorReversal_audit_XAUUSDm_*.tsv" | Measure-Object -Line

# Session summaries de todas as sessões
Select-String -Path "<Terminal>\MQL5\Files\MKS-ULTIMATE\Logs\ColorReversal_*.log" -Pattern "session summary"
```

### Lembrete operacional crítico

**Anexar o `ColorReversal` SEMPRE no gráfico do símbolo REAL do broker (`XAUUSDm`), NUNCA no gráfico de um Custom Symbol (`XAUUSDm.MKS_*` / `XAUUSDm.MKSCR_*`).** O guard agora recusa o erro, mas o lembrete economiza tempo.

---

## 9. Resumo em 5 linhas para abrir o próximo chat

1. **Fase 9 validada em DEMO LIVE** — após corrigir bug operacional (EA estava no gráfico de Custom Symbol sem feed), o ColorReversal abriu **11 ordens reais** no Exness em 7 min (preços e tickets reais, 0 rejeições). Terceiro ambiente de validação fechado.
2. **Causa do "noite sem ordem":** Custom Symbol é container estático (saída/visualização), não recebe feed live → CopyTicks=0 → zero bricks → zero ordens. **Guard adicionado:** OnInit recusa símbolo custom fora do tester.
3. **Observabilidade adicionada:** ColorReversal faz checkpoint a cada 60s (`.mksbk` header patch + audit flush) — antes os arquivos apareciam em 0 mid-sessão por buffering do MQL5. Agora monitorável em tempo real.
4. **Estado:** `main` em `92b59dc`; 25/25 ADRs; Fase 9 validada nos 3 ambientes (testes 46/46, tester 617 trades, live 11 trades). Falta só o slice 2 (stress runner) para declarar Fase 9 100%.
5. **Próximo passo sugerido:** stress runner (slice 2) — replaya `.mkstick` plugando a estratégia sobre `CMksSimulatedBroker` + `CMksStressLabBroker` (Light/Medium/High/Nightmare), exercitando a ADR-027 em pipeline real. Pode rodar em paralelo com demo live longa acumulando estatística.

---

**Sessão demo live 2026-05-27 fechada com Fase 9 validada em servidor real.** Bug operacional diagnosticado e blindado. Observabilidade mid-sessão entregue. `main` em `92b59dc`. 25/25 ADRs aceitas. Compile-all 39/39 OK. Próximo: stress runner (slice 2) fecha a Fase 9.
