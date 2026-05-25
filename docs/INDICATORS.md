---
@document: docs/INDICATORS.md
@project: MKS-ULTIMATE
@purpose: Catálogo de indicadores customizados, princípio brick-driven e protocolo de validação
@audience: Dono do projeto, assistentes de IA, contribuidores futuros
---

# MKS-ULTIMATE — Indicadores

Indicadores customizados que rodam sobre o Custom Symbol do MKS-ULTIMATE. Cada um respeita um princípio comum (§1) e passa por um protocolo de validação (§3) antes de ser considerado pronto. O catálogo (§4) lista os indicadores aceitos e o estado de cada um.

---

## 1. Princípio: brick-driven, sem ATR

Os indicadores deste diretório são **brick-driven puros**: trabalham sobre o stream de bricks do CS sem usar ATR.

A razão é estrutural, não estilística. Com `CMksFixedBrickSizer` (único sizer em produção hoje), todos os bricks têm o mesmo tamanho em pontos. O True Range de cada brick ≈ tamanho do brick, então `ATR(N bricks) ≈ brickSize × constante`. A informação de volatilidade já foi absorvida pela própria construção do Renko. Multiplicador × ATR vira, na prática, constante × brickSize — e o ATR fica como decoração com custo de cálculo.

A consequência é uma decisão de design: quando um indicador clássico tem `multiplier × ATR` na fórmula (Chandelier, SuperTrend), no MKS-ULTIMATE ele vira `InpOffsetBricks × brickSize × _Point`. Honestidade arquitetural: o que o indicador faz em Renko é explícito, sem indireção.

Indicadores que **não usam ATR mesmo no original** (RSI, MACD, EMA) seguem a forma canônica clássica, sem mudança conceitual.

ATR baseado em tempo real (do símbolo base via M1) é um caminho válido em tese mas exige mapeamento `triggerTime ↔ tempo real` por brick, que hoje não está exposto no CS. Quando entrar (mudança no `CMksCustomSymbolSink` para gravar `triggerTime` em `real_volume`, ADR a fazer), indicadores time-aware passam a ser possíveis. Até lá, brick-driven é o padrão fechado.

### 1.1 Indicadores são camada de visualização — paridade pelo lado da estratégia

Indicadores deste diretório leem o CS via API global do MQL5 (`iOpen`/`iClose`/`iHigh`/`iLow`/`CopyRates`) — é onde o trabalho de visualização vive. A nota de esclarecimento da ADR-020 (2026-05-25, em `docs/ARCHITECTURE.md` §3) restringe o alcance da regra 1 ao caminho `Strategy → iCustom(indicator) → CS`; indicadores como visualização humana sobre o CS ficam **fora** do escopo da regra 1.

A paridade backtest/live da estratégia é protegida pelo lado da estratégia, não pelo lado do indicador: a `REGRAS.md` §1.9 (tabela de APIs proibidas em código de estratégia) lista `iCustom` como **proibido**. Estratégia que precisa de RSI/MACD/etc. calcula sobre `MksBrick` direto (consumindo `IRenkoSink::OnBrickClose`), não via `iCustom`. Quando o trabalho duplicado virar dor real, ADR futura pode introduzir família brick-driven (`IRenkoIndicator`) para reuso entre estratégias.

## 2. Estrutura

Cada indicador vive como par de arquivos:

```
MQL5/Indicators/MKS-ULTIMATE/CMks<Nome>.mq5      ← o indicador
MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMks<Nome>.mq5  ← validador
```

Naming, paths e diretórios sincronizados com MT5 via junctions (mesmo padrão de `Include/`, `Scripts/`, `Experts/`). A junction `MQL5/Indicators/MKS-ULTIMATE` foi criada manualmente; novos subdiretórios do repo seguem mesma criação via `New-Item -ItemType Junction`.

O watcher `tools/watch-compile.ps1` cobre `MQL5/Indicators/MKS-ULTIMATE/` desde a Slice deste bundle — `.mq5` salvos lá compilam automaticamente.

Convenções de inputs herdadas do padrão:

- **Cálculo** vem primeiro, agrupado.
- **Visual** vem por último, agrupado.
- Visual mínimo: par de cores `InpColorBull` / `InpColorBear`, `InpLineWidth`, `InpLineStyle`. Indicadores compostos (MACD com 3 elementos) podem expandir, mas mantêm os nomes consistentes.
- `InpBrickSizePts = 0.0` significa **auto-inferir** do CS (via `|close[1]−open[1]|`, ADR-022 §8); valor > 0 sobrescreve.

## 3. Protocolo de validação

Inspeção visual no chart **não basta**. A semântica do CS tem armadilhas — timestamp M1 fictício (ADR-020), `tick_volume` sobrescrito com `thresholdsCrossed` (ADR-011), High/Low dependentes de `showWicks`. Um indicador pode estar visualmente plausível e numericamente errado num off-by-one de janela. O `Test_*.mq5` é obrigatório.

### Recipe do Test_*.mq5

1. Carrega o indicador via `iCustom(_Symbol, _Period, "MKS-ULTIMATE\\CMks<Nome>", ...inputs...)`
2. Espera `BarsCalculated(handle) >= bars` (loop com `Sleep` curto, ~5s max)
3. Lê os buffers visíveis e os hidden via `CopyBuffer` com `ArraySetAsSeries(buf, true)`
4. Calcula a "verdade" por método independente (cálculo manual sobre `iHigh`/`iLow`/`iClose`, OU comparação contra indicador nativo equivalente)
5. Compara conforme invariantes do tipo (§3.2)
6. Reporta `OK: N bars verificadas, zero divergencia (...)` ou primeira divergência com valores

### 3.1 Tolerância por família

- **Sem smoothing recursivo** (Donchian, Chandelier, SuperTrend — só max/min e aritmética não-recursiva): `tolerance = 0.0` é o default. Validado empiricamente.
- **Com smoothing recursivo** (RSI/Wilder, MACD/EMA, ATR — qualquer coisa que use `state[i] = state[i-1] × peso + novo × peso2`): `tolerance = 1e-10` é o default. Mesmo a fórmula matematicamente idêntica diverge em ~1e-14 a 1e-15 por ordem de operações FP. **Reduzir ruído primeiro pelo lado do indicador** usando a forma canônica (`(prev × (N-1) + novo) / N` para Wilder, `(price × k) + (prev × (1-k))` para EMA — uma única divisão, ordem que bate com `iRSI`/`iMA` nativos). Tolerância é margem de segurança, não desculpa pra forma errada.

O report do test deve sempre incluir `diff_max` quando houver smoothing — torna visível o quanto sobra de margem.

### 3.2 Invariantes por tipo de indicador

**Linhas estáticas (Donchian)** — 2 buffers visíveis, sempre ambos preenchidos. Invariante única:
- **value** — buffer do indicador == cálculo manual independente

**Flipping com ratchet (Chandelier, SuperTrend)** — 2 buffers visíveis (1 por vez) + 2 hidden (Trend, ActiveStop). Quatro invariantes:
- **visibility** — exatamente um dos buffers visíveis tem valor; o outro é `EMPTY_VALUE`, conforme `Trend[i]`
- **equality** — `ActiveStop[i]` == valor do buffer visível ativo
- **math** — dado `Trend[i-1] → Trend[i]`, `ActiveStop[i]` bate com `candidate` (no flip), `max/min(candidate, ActiveStop[i-1])` (na continuação com ratchet)
- **flip** — se `Trend[i] != Trend[i-1]`, `close[i]` cruzou `ActiveStop[i-1]` na direção certa

**Osciladores com color-by-zone (RSI)** — 1 buffer visível com `DRAW_COLOR_LINE` + color index + N hidden de estado. Duas invariantes:
- **value** — RSI do indicador == referência (nativa ou manual)
- **color** — color index == regra de zona (0 ou 1 conforme RSI ≥ threshold)

**Composto com histograma (MACD)** — 2 linhas + 1 histograma colorido + N hidden. Quatro invariantes:
- **macd line** == nativa
- **signal line** == nativa
- **hist consistency** — `Hist[i] == MACD[i] − Signal[i]` (consistência interna)
- **color** == regra de sinal positivo/negativo

## 4. Catálogo

| Indicador        | Tipo            | Janela    | Tolerância | Status | Truth do teste              |
|------------------|-----------------|-----------|------------|--------|-----------------------------|
| `CMksDonchian`   | linhas estáticas| chart     | 0.0        | ✓ 165 bars | iHigh/iLow manual       |
| `CMksChandelier` | flipping+ratchet| chart     | 0.0        | ✓ 499 bars | HH/LL ± offset manual   |
| `CMksSuperTrend` | flipping+ratchet| chart     | 0.0        | ✓ 499 bars | midpoint ± offset manual|
| `CMksRSI`        | oscilador       | separate  | 1e-10      | ✓ 500 bars | iRSI nativo (bate 0.0)  |
| `CMksMACD`       | composto        | separate  | 1e-10      | ✓ 500 bars | iMACD nativo (~1e-15)   |

Para cada um, o arquivo header explica responsabilidade, fórmulas usadas, inputs e qualquer TODO arquitetural pendente.

## 5. Como adicionar um novo indicador

1. **Decidir o tipo** (linhas estáticas, flipping+ratchet, oscilador, composto) — define o set de invariantes do teste.
2. **Decidir o source** — quais campos do CS o indicador consome (close, midpoint, HH/LL, etc).
3. **Mapear ATR-clássico → brick-native** se for indicador da família de stops/bands. Geralmente `multiplier × ATR` vira `InpOffsetBricks × brickSize × _Point`.
4. **Copiar template do mais próximo** dos 5 atuais — naming de inputs, ordem dos buffers, OnInit/OnCalculate skeleton.
5. **Implementar** seguindo a forma canônica de smoothing (se aplicável) pra evitar drift FP.
6. **Criar o Test_*.mq5** com as invariantes do tipo escolhido. Tolerância 0.0 ou 1e-10 conforme §3.1.
7. **Compilar headless** via watcher (auto) ou manualmente:
   ```powershell
   & "C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe" /compile:c:\dev\MKS-ULTIMATE\MQL5\Indicators\MKS-ULTIMATE\CMks<Nome>.mq5
   ```
8. **Anexar ao chart do CS** + rodar o Test_*. Esperado: `OK: ... zero divergencia`.
9. **Adicionar ao catálogo (§4)** desta doc.

Indicadores que falhem qualquer invariante numérica não devem ser usados em estratégia. Falha visual aceitável (cor, estilo) é decisão visual e fica fora deste protocolo.
