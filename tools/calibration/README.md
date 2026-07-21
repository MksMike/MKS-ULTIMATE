# Calibração do StressLab ao broker real (ADR-039)

Scripts de medição que derivam os parâmetros do StressLab a partir de capturas
`.mkstick` reais (fora do MT5, Python 3, só `struct`/`statistics` — sem deps).

## Scripts

- **`spread_stats.py`** — distribuição do spread real (`(ask−bid)/point` por tick).
  Resultado XAUUSDm/Exness (2026-07-20, 417k ticks de 3 capturas):
  **baseline = 240 pts = 0.24 USD** (mediana/moda, sd 1–20 pts), p95 260, p99 280,
  pico 700. → `InpSpreadPts=240` + `InpBaselineSpreadPts=240` no `StressReplayer`.

- **`displacement.py`** — drift de latência via **deslocamento líquido**
  `|mid(t+L)−mid(t)|` sobre janela de L ms (NÃO a velocidade ingênua `|Δmid|/Δt`,
  que superestima 20–50× por somar o bounce de quote em vez do deslocamento).
  Resultado: **~0.5 pts/ms total / ~0.25 adverso** na janela ~260ms (≈ roundtrip do
  demo da Fase 9). Cai com L (random-walk √t). **Ainda não ligado** —
  `latencyDriftPointsPerMs` precisa entrar no runner/EA + decisão de modelagem.

## Uso

Editar a lista `files` no topo do script (caminhos das capturas `.mkstick`) e:

```
python tools/calibration/spread_stats.py
python tools/calibration/displacement.py
```

Os caminhos hardcoded são exemplos desta máquina; o método é agnóstico de máquina.
A captura precisa estar acessível no disco (repo ou `<terminal>\MQL5\Files\...`).

## Estado (ADR-039)

| Eixo | Estado | Valor medido |
|---|---|---|
| Spread | ✅ medido + ancorado | 240 pts (0.24 USD) |
| Latência→drift | 🟡 medido, não ligado | ~0.25 pts/ms adverso @ ~260ms |
| Slippage puro | 🔴 pendente | precisa dado requested-vs-filled real |
