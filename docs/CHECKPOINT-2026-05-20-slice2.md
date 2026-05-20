---
@document: docs/CHECKPOINT-2026-05-20-slice2.md
@project: MKS-ULTIMATE
@purpose: Adendo ao CHECKPOINT-2026-05-20 — fechamento do Slice 2 e ponto de partida para o Slice 3
@audience: Próxima sessão (humano + IA)
---

# CHECKPOINT — 2026-05-20 (pós-Slice 2)

Adendo ao [`CHECKPOINT-2026-05-20.md`](CHECKPOINT-2026-05-20.md). Este documento cobre exclusivamente o que mudou desde o fechamento do Slice 1: o trabalho do Slice 2, os resultados empíricos e o ponto de partida para o Slice 3. As convenções operacionais, decisões anteriores e princípios invariantes do checkpoint anterior **continuam valendo sem alteração** — não são replicados aqui.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Para iniciar um novo chat — leia ESTES 3 arquivos, nesta ordem

1. `README.md`
2. `docs/CHECKPOINT-2026-05-20.md` — base, convenções e estado pós-Slice 1
3. `docs/CHECKPOINT-2026-05-20-slice2.md` — este, incremental

Os demais documentos (`docs/REGRAS.md`, `docs/ARCHITECTURE.md`, `docs/V5-POSTMORTEM.md`, etc.) seguem como referência sob demanda.

---

## 2. Estado do código (HEAD = `0280c0c`)

| Camada | Item | Estado |
|---|---|---|
| Slice 2 | `MQL5/Scripts/MKS-ULTIMATE/ValidateBuilderOnRealTicks.mq5` | **feito + validado contra stream real** |
| Slice 2 | Diagnóstico de spread + builder bid-driven (embutido no script) | feito + analisado |
| Slice 3 | Produtor fundido / Custom Symbol | **próximo** |

### ADRs — só o que mudou desde o checkpoint anterior

| ADR | Tema | Status |
|---|---|---|
| 013 | Independência de broker, proveniência no rastro de auditoria | **Proposta** (publicada em `5d3afb7`) |

ADRs 001–012 sem alteração.

---

## 3. O que foi feito no Slice 2

- **ADR-013 publicada como Proposta** em `docs/ARCHITECTURE.md`. Fixa que o framework é broker-agnóstico por construção e que todo artefato persistido carrega proveniência `(broker, account, symbol)` capturada em runtime. Detecção e perfil estruturado de broker (camada `IBrokerEnvironment` ou similar) ficam como dívida explícita pós-Slice 3.

- **`ValidateBuilderOnRealTicks.mq5`** — script de validação em `MQL5/Scripts/MKS-ULTIMATE/`. Lê ticks reais via `CopyTicksRange`, alimenta `CMksRenkoBuilder` com preset median e `CMksFixedBrickSizer(S=3)`, reporta no painel Experts:
  - Proveniência (broker, account, símbolo, digits) — em runtime, conforme ADR-013.
  - Janela temporal e total de ticks carregados.
  - Bricks: total, BULL/BEAR, distribuição `thresholdsCrossed` (M=1, 2..5, 6..10, >10).
  - Erros: 102, 103, 104.
  - Gaps de tempo entre ticks consecutivos (descontinuidade > N min, com N configurável).
  - Range de preço (mid).
  - **Stats de spread** (min/max/mean + buckets em 5 faixas).
  - **Diagnóstico mid vs bid**: builder paralelo bid-driven, ratio mid/bid no relatório. Viola intencionalmente a ADR-010 mas só dentro do script — diagnóstico descartável, não candidato a alternativa arquitetural.
  - Primeiro e último brick (open/close/dir/M/time).

---

## 4. Resultados empíricos

Run de referência: XAUUSDm na Exness, janela `2026-05-13 12:46 → 2026-05-20 12:46`. Parâmetros: `S=3.0`, preset median, `K=20`, `L=10`, `gapThreshMin=30`.

**Stream:**
- Total: **1.676.426 ticks** em 7 dias
- Broker: `Exness Technologies Ltd`
- Símbolo no Market Watch: `XAUUSDm` (variante de conta micro/cent)
- Precisão de preço: `digits=3` (passo de 0.001 USD)

**Bricks:**
- Total: **9.672**
- BULL: 4.776 — BEAR: 4.896 (distribuição equilibrada)
- `thresholdsCrossed`: `M=1: 9.671` — `M=2..5: 1` — `M=6..10: 0` — `M>10: 0`

**Erros:** 102=0, 103=0, 104=no — **zero erros, incluindo o atravessamento do gap de fim de semana de 49h**.

**Gaps detectados:**
- 1 gap de **49h** (fim de semana 15→17 mai, absorvido sem 102)
- 4 gaps de **~62 min** em horários `~22h GMT` (rollovers diários da Exness)

**Range de preço (mid):** `min=4453.503 USD`, `max=4719.079 USD` — ~265 USD em 7 dias.

**Spread (USD):** `min=0.280`, `max=0.660`, `mean=0.310`.
- 99.91% dos ticks com spread ≤ 0.5 USD (1.674.878 de 1.676.426)
- Zero ticks com spread acima de 1.0 USD
- Variação máxima do spread na semana inteira: 0.38 USD

**Diagnóstico mid vs bid:**
- Bricks mid-driven: **9.672**
- Bricks bid-driven (diagnóstico, `ask:=bid`): **9.698**
- Ratio mid/bid: **0.997**
- **Veredito:** os bricks correspondem a movimento real do preço, não a wiggle de spread. Hipótese de spread-noise refutada empiricamente.

---

## 5. Critério de saída do Slice 2 — atendido

CHECKPOINT-2026-05-20 §9 definia:
> *Script roda sem 102/103/104 sob dado normal, contagem coerente com magnitude do movimento, conferência visual aprovada pelo dono.*

Todos os pontos atendidos:
- ✓ Zero erros 102/103/104, mesmo cobrindo o gap de fim de semana.
- ✓ Contagem (9.672 bricks) coerente — validada empiricamente via ratio mid/bid e por conferência visual contra gráfico M15 (range, direção, gap absorvido).
- ✓ Conferência visual aprovada pelo dono (extremos do mid batem com os do M15; primeiro/último brick BEAR consistentes com tendência geral de baixa).

---

## 6. Decisões registradas (sem ADR formal)

- **Caminho de validação (b)** — escolhido pelo dono: janela de 7 dias corridos incluindo gap de fim de semana **propositalmente**, para gerar evidência empírica para a futura ADR-008.
- **Material para a futura ADR-008** — para XAUUSDm na Exness em condições típicas, o gap de fim de semana fica bem abaixo do produto `K · (1−PO) · S = 20 · 0.5 · 3.0 = 30 USD`. O gap observado (~5–10 USD) foi absorvido como brick multi-threshold modesto (M=2 ou similar). O default `K=20` é confortável para esse instrumento neste broker.
- **Buckets de M no relatório** — `1` (normal), `2..5` (salto modesto), `6..10` (salto significativo), `>10` (perto do limiar K). Faixas escolhidas para reportar concentração sem ruído de granularidade.
- **Threshold de detecção de gap** — default `30 min` pega rollovers diários da Exness (~62 min) e o gap semanal (49h). Para janela mais limpa, subir para `90+ min` filtra rollovers diários e deixa só o gap semanal.

---

## 7. Pegadinhas confirmadas nesta sessão

- **`.ex5` stale** — caso real recorrente, materializou-se duas vezes na sessão. Sequência: assistente edita `.mq5` no disco → dono não recompila (`F7`) → MT5 executa o `.ex5` antigo → output não reflete as edições. Fix preventivo: comparar `LastWriteTime` de `.mq5` vs `.ex5` antes de cada run; pedir `F7` explícito com a aba do arquivo certo em foco.
- **PowerShell e `$_`** — comandos no padrão `Get-ChildItem ... | ForEach-Object { $_.Property }` chamados via Bash tool em ambiente PowerShell são massacrados — o `$_` é interpretado por uma camada intermediária e vira `extglob.Property`. Usar `Get-ChildItem ... -Name` para nomes relativos, ou Glob nativo do harness.
- **Junctions funcionando corretamente** — `Include/MKS-ULTIMATE` e `Scripts/MKS-ULTIMATE` confirmadas via SHA256 idênticos dos dois lados. Junction é link, não cópia.

---

## 8. Próximo trabalho — Slice 3

Conforme `ROADMAP.md` e CHECKPOINT-2026-05-20 §3:

**Slice 3 — Produtor fundido + Custom Symbol.** Generator e LiveEngine num único programa que:

1. Consome ticks reais via `CMksRenkoBuilder` (mesmo motor validado no Slice 2).
2. Grava o histórico de bricks em arquivo binário, com header de proveniência conforme **ADR-012**.
3. Publica o arquivo como **Custom Symbol** acessível no MT5 (Symbols → Custom).
4. Permite plotar e operar sobre o Custom Symbol como qualquer instrumento padrão.

**Dependências de decisão antes de começar o Slice 3:**

- **ADR-012 (proposta)** — aceitar formalmente antes do Slice 3. Define formato binário, header de proveniência, contrato de integridade (ticks crus, broker-locked). Sem aceite, o Slice 3 não tem fonte autoritativa pra ler/gravar.
- **ADR-005 (pendente)** — framework de testes formal. Não bloqueia Slice 3, mas tem dívida acumulando.
- **ADR-008 (pendente)** — reabertura de mercado / gap. Não bloqueia Slice 3 — basta gerar Custom Symbol que reproduz o que o tick stream traz. Pode ficar como dívida persistente. O material empírico desta sessão (§6) alimenta a futura decisão.

**Pendências estratégicas — não bloqueiam Slice 3, mas precisam emergir antes de qualquer estratégia real (Slice 5):**
- Stop loss — ainda indefinido. Sem ele, R:R é ficção.
- Disciplina de perdedor — 30 min vale igual para ganhador e perdedor?
- Hipótese de mercado — o que se repete no XAUUSD Renko? Observação do dono, não ferramenta.

---

## 9. Carga do `git log` desde o CHECKPOINT anterior

```
0280c0c feat: add ValidateBuilderOnRealTicks (Slice 2)
5d3afb7 docs: propose ADR-013 (broker independence, audit-trail provenance)
abc0363 docs: add CHECKPOINT 2026-05-20 (handoff after Slice 1)
```

---

## 10. Como este documento evolui

- Próximo checkpoint vira `docs/CHECKPOINT-AAAA-MM-DD-sliceN.md` ao final do próximo slice fechado.
- Este documento não é apagado — vira histórico, como os anteriores.
- Apenas a instrução de entrada do próximo chat aponta para o checkpoint mais recente.
