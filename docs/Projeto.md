---
@document: docs/Projeto.md
@project: MKS-ULTIMATE
@purpose: Visão, contexto, escopo, glossário e decisões-chave do projeto
@audience: Dono do projeto, assistentes de IA (Claude), contribuidores futuros
---

# MKS-ULTIMATE — Projeto

## 1. Identificação

- **Nome:** MKS-ULTIMATE
- **Dono:** Mike Inoue (GitHub: MksMike)
- **Versão-alvo inicial:** 6.0.0
- **Status:** Em desenvolvimento inicial (alpha)
- **Plataforma-alvo:** MetaTrader 5 — exclusivamente
- **Linguagem:** MQL5
- **Licença:** Proprietária, privada

## 2. Contexto e motivação

O MKS-ULTIMATE é a sucessão do projeto MKS-FRAMEWORK-RENKO (doravante "V5"), abandonado em abril de 2026 após um incidente crítico: uma estratégia que apresentou backtests excepcionais quebrou a conta do operador em aproximadamente 4 horas de operação em ambiente real.

A causa-raiz identificada foi **divergência silenciosa entre backtest e live**. A arquitetura do V5 não garantia paridade — backtest e live seguiam caminhos de código diferentes em pontos críticos do fluxo de execução, modelagem de custos e construção de bricks Renko. O backtest, portanto, não era um preditor confiável do comportamento real.

O MKS-ULTIMATE nasce com a missão explícita de eliminar essa classe de problema pela raiz, não pela mitigação.

## 3. Princípio norteador

**Backtest e live devem produzir resultados bit-a-bit idênticos, dado o mesmo feed de ticks, na mesma janela temporal.**

Este é um requisito do projeto, não um objetivo distante. Toda decisão de arquitetura é avaliada contra este princípio.

Consequências práticas:

- **Caminho de código único** entre backtest e live. Nenhum `if(MQLInfoInteger(MQL5_TESTING))` bifurcando comportamento na lógica de trading.
- **Abstrações obrigatórias:** `IBroker`, `ITickSource`, `IClock` — injetadas via dependência. Em backtest, implementações sintéticas; em live, implementações reais. A estratégia não sabe em qual modo está rodando.
- **Modelagem explícita de custos:** spread, comissão, swap, slippage, latência, rejeições e requotes são modelados no backtest — não assumidos como zero.
- **Logging estruturado em ambos os ambientes:** live e backtest emitem logs no mesmo formato, permitindo comparação trade-a-trade pós-execução.

## 4. Visão

Construir um framework de trading automatizado em MQL5 com as seguintes propriedades:

1. **Paridade de execução** — backtest e live determinísticos e equivalentes
2. **Core orientado a objetos** — com separação estrita de responsabilidades
3. **Renko reproduzível** — geração de bricks a partir de ticks, determinística e auditável (não dependente de indicador externo de caixa-preta)
4. **Risk management em camadas** — por trade, por estratégia, por conta, com circuit breakers
5. **StressLab** — ambiente de simulação adversa com dados reais de broker, onde a estratégia é testada contra cenários progressivamente piores (spread inflado, latência alta, rejeições, requotes frequentes) antes de ir para live
6. **Testabilidade** — unit tests cobrindo o core. Nenhuma estratégia construída antes do core ter cobertura.

## 5. Escopo

### Dentro do escopo (V6)

- Framework em MQL5 para MetaTrader 5
- Renko como tipo primário de barras (range, tick, volume, tempo podem ser adicionados depois)
- Integração Git para versionamento
- Documentação viva no próprio repositório
- StressLab como módulo integrado
- EAs de exemplo usando o framework (construídos APÓS o core estar validado)

### Fora do escopo (V6)

- Outras plataformas (cTrader, NinjaTrader, TradeStation, etc.)
- Portabilidade para linguagens fora do ecossistema MQL5
- Engine de backtest fora do MetaTrader (idealizado, mas não nesta versão)
- Interface gráfica customizada além do que MT5 oferece nativamente
- Distribuição pública, marketplace, comercialização

### Explicitamente não fazer

- **Não** depender de indicador de código fechado para construção dos bricks Renko
- **Não** copiar código do AzInvest (Median-and-Turbo-Renko-indicator-bundle). O projeto é referência de estudo apenas; nenhuma linha é reutilizada.
- **Não** construir estratégias antes do core estar testado

## 6. Referências externas

### AzInvest / Median-and-Turbo-Renko-indicator-bundle

Repositório originalmente analisado como possível base. Após análise crítica, foi descartado como base por:

- Depender de indicador proprietário de código fechado
- Bifurcar comportamento entre backtest e live
- Ter estratégias de entrada triviais (simples reversão de cor)
- Tratamento recursivo de phantom bars sem limite de profundidade
- Conter `Sleep(500)` bloqueante após ordens
- Partial close em conta netting implementado via ordem oposta (gera custos duplos)

Permanece como **referência de análise** — útil para aprender o que funciona e, principalmente, o que não funciona. Nada dele é copiado.

### MKS-FRAMEWORK-RENKO (V5)

Versão anterior, abandonada. Fica no repositório `MksMike/MKS-Framework-Renko` como **referência negativa** — exemplo concreto do que não repetir. Lições aprendidas devem ser capturadas no `ROADMAP.md` ou em documento dedicado de post-mortem.

## 7. Atores e responsabilidades

| Ator | Responsabilidade |
|------|------------------|
| Mike Inoue | Dono do projeto. Define visão, aprova decisões arquiteturais, valida resultados de testes, executa operação em live. |
| Claude (assistente) | Parceiro técnico. Analisa criticamente propostas, sugere arquitetura, redige código, mantém documentação viva. Segue as regras do `REGRAS.md`. |
| MetaEditor (MT5) | Compilador MQL5 — única ferramenta que compila `.mq5` e `.mqh` para `.ex5`. |
| VS Code | Editor primário para escrita e versionamento. |
| Claude Code (CLI) | Ponte entre o assistente e o filesystem do projeto. |
| GitHub | Hospedagem do repositório privado. Fonte da verdade. |

## 8. Glossário

- **Renko** — tipo de gráfico em que novas barras (bricks) são formadas apenas quando o preço se move uma distância pré-definida, ignorando o tempo.
- **Brick** — cada barra do gráfico Renko. Tem cor (alta ou baixa) e tamanho fixo.
- **Tick** — unidade atômica de movimento de preço recebida do broker. Renko se constrói a partir de ticks.
- **Phantom bar** — brick com volume zero, geralmente resultante de gap ou dado faltante. Precisa ser identificado e tratado explicitamente.
- **StressLab** — módulo do framework que simula condições adversas de mercado (spread, slippage, latência, rejeições) usando dados reais de broker, para testar robustez da estratégia antes da execução em live.
- **Paridade backtest/live** — garantia de que o mesmo feed de ticks em backtest e em live produz o mesmo output bit-a-bit.
- **Tick source** — abstração que fornece ticks à estratégia. Em live, lê do broker; em backtest, lê de arquivo histórico.
- **Circuit breaker** — mecanismo de proteção que pausa automaticamente o EA quando uma condição crítica é atingida (perda diária máxima, drawdown, número de trades).
- **Determinístico** — mesma entrada produz sempre a mesma saída, sem variação por tempo, thread ou ambiente.

## 9. Decisões-chave já tomadas

Esta seção captura decisões fundamentais já discutidas e aprovadas. Novas decisões arquiteturais devem ser registradas no `ARCHITECTURE.md`; esta seção serve apenas para as decisões que guiam o projeto inteiro.

- **Plataforma-alvo é exclusivamente MT5.** Não há multi-plataforma no escopo V6.
- **Linguagem é MQL5.** Core e EAs são escritos em MQL5.
- **Renko é construído em casa** — nenhum indicador de caixa-preta entra no caminho crítico.
- **Nomenclatura:** classes prefixadas com `CMks` (ex: `CMksRenkoBuilder`). Pasta de includes: `MQL5/Include/MKS-ULTIMATE/`. Versão única em `Core/Version.mqh`.
- **SemVer** para versionamento do framework. Primeira release-alvo: `6.0.0`.
- **Conventional Commits** para mensagens de commit (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).
- **Core antes de estratégias.** Nenhum EA é desenvolvido antes do core estar testado.
- **Testes obrigatórios** para componentes do core antes de serem considerados prontos.

## 10. Como este documento evolui

O `Projeto.md` é um documento vivo, mas estável. Mudanças aqui indicam mudanças fundamentais de rumo — não flutuações de desenvolvimento diário.

Para cada mudança:

1. A decisão que motivou a mudança deve estar registrada no `ARCHITECTURE.md` ou no `CHANGELOG.md`
2. O commit deve usar prefixo `docs:` e descrever brevemente a mudança
3. Mudanças que quebram princípios anteriores (ex: abandonar paridade backtest/live) exigem discussão explícita e aprovação do dono do projeto

Desenvolvimento do dia-a-dia (novas features, refactors, módulos novos) é registrado em `ROADMAP.md`, `CHANGELOG.md`, `ARCHITECTURE.md` e no git log — não aqui.
