---
@document: docs/PROTOCOLOS.md
@project: MKS-ULTIMATE
@purpose: Checklists executáveis para momentos de risco operacional e decisório
@audience: Dono do projeto, assistentes de IA
---

# MKS-ULTIMATE — Protocolos

Este documento contém **checklists**. Cada protocolo é uma lista de verificação que deve ser percorrida integralmente antes de executar a ação correspondente. Pular itens do checklist é violação do protocolo.

Protocolos existem porque decisões de risco tomadas por memória ou intuição são estatisticamente piores do que decisões tomadas por checklist. Pilotos de avião usam checklist antes de cada decolagem mesmo depois de 10 mil horas de voo. O mesmo se aplica aqui.

**Onde usar:** No dia-a-dia. Antes de cada uma das ações descritas abaixo, **abra este arquivo e percorra o checklist**.

---

## Protocolo 1 — Antes de declarar um módulo do core "pronto"

Aplicável quando um módulo novo (ex: `CMksRenkoBuilder`) está para ter status alterado de "em desenvolvimento" para "pronto" no ROADMAP.

- [ ] Código compila sem warnings no MetaEditor
- [ ] Header do arquivo está no formato padrão (`@file`, `@project`, `@module`, `@responsibility`, `@depends_on`, `@install_path`)
- [ ] Classe tem doc-comment na declaração explicando responsabilidade
- [ ] Métodos públicos têm doc-comment quando não forem auto-evidentes
- [ ] Nenhuma bifurcação `if(MQL5_TESTING)` na lógica do módulo
- [ ] Nenhum `Sleep` bloqueante
- [ ] Nenhuma chamada API global em código de lógica do módulo — ver Protocolo 9 para lista completa (`TimeCurrent`, `SymbolInfo*`, `AccountInfo*`, `OrderSend`, `iATR`, etc.)
- [ ] Unit tests cobrem: caminho feliz, casos de borda, condições de erro
- [ ] Unit tests passam
- [ ] Determinismo verificado por **teste duplo-run automatizado** — um teste roda o caminho determinismo-crítico **2× com a mesma entrada e COMPARA** as saídas campo-a-campo/byte-a-byte, falhando em qualquer divergência. Inspeção visual, raciocínio ou "determinismo assumido" **não fecham** este item. Ex.: `Test_SR_DeterministicDoubleRun`, os testes de paridade pós-recovery do `Test_CMksRenkoBuilder` (E3.1), a paridade de decisão do `verify-parity.ps1` (E2). *Motivação (auditoria 2026-06-02, E3/`[H2]`): o soft-recovery (105) do builder reescrevia a sequência de bricks com determinismo **afirmado e nunca testado** — a regra fecha essa classe de lacuna.*
- [ ] Se o módulo toca paridade (`RenkoBuilder`, `ITickSource`, `IClock`, `IBroker`, estratégia, sink que escreve `.mksbk`), executar `tools/verify-parity.ps1` antes de declarar pronto. O pipeline canônico (ADR-024 §regra 7) é: rodar Producer em chart real + TickRecorder em Service em paralelo por ≥1h → rodar Replayer sobre o `.mkstick` capturado → `verify-parity -LiveMksbk live.mksbk -ReplayMksbk replay.mksbk` deve dar exit code 0. Qualquer divergência byte-a-byte indica não-determinismo no builder ou regressão de dados — bloqueia o "pronto".
- [ ] `ARCHITECTURE.md` atualizado se a conclusão do módulo trouxe decisões arquiteturais novas
- [ ] `CHANGELOG.md` atualizado na seção "Não lançado"
- [ ] Commit na convenção (`feat:` ou `refactor:` conforme o caso)

Se qualquer item está "não" — o módulo não está pronto.

---

## Protocolo 2 — Antes de rodar um EA em backtest pela primeira vez

- [ ] Símbolo, timeframe e janela temporal conferidos
- [ ] Qualidade de dados do MT5 verificada (ideal: "Every tick based on real ticks") — aplicável apenas se rodando via Strategy Tester nativo
- [ ] Se o backtest produzir métricas para release ou comparação oficial: rodado via framework (arquivo de captura + script de replay), não via Strategy Tester. Números oficiais vêm do framework (ADR-015)
- [ ] Histórico baixado e validado (sem gaps suspeitos no período testado)
- [ ] Configuração de custos explícita: spread, comissão, swap
- [ ] Parâmetros do EA revisados (SL, TP, lot size, horários de trading)
- [ ] Logger configurado em nível INFO no mínimo
- [ ] Pasta de logs verificada com espaço em disco
- [ ] `MagicNumber` do EA único e não conflita com outros EAs

Se qualquer item está "não" — não roda o backtest.

---

## Protocolo 3 — Depois de rodar um backtest

- [ ] Número de trades > 30 (amostra mínima estatística)
- [ ] Relatório salvo em `logs/backtest/<data>_<estrategia>.html`
- [ ] Log estruturado salvo
- [ ] Gráfico de equity revisado — procurar por: curva suspeita demais (perfeita), quedas bruscas únicas, padrões de trade em horários específicos
- [ ] Drawdown máximo registrado
- [ ] Trade de maior perda investigado individualmente
- [ ] Resultado comparado contra backtest anterior da mesma estratégia (se houver)
- [ ] Entrada no `CHANGELOG.md` ou diário técnico se for backtest de release

---

## Protocolo 4 — Antes de rodar no StressLab

Aplicável após backtest normal ter passado.

- [ ] Backtest normal passou no Protocolo 3
- [ ] Parâmetros do StressLab definidos por escrito antes de rodar (evita tuning reativo)
- [ ] Níveis de estresse a testar: leve, médio, alto (mínimo 3 passes)
- [ ] Critério de "aprovação" definido antes — ex: "sobrevive a stress alto com drawdown < 2x o drawdown do backtest normal"
- [ ] Resultados de cada nível documentados em tabela comparativa

---

## Protocolo 5 — Antes de rodar em conta demo live

Aplicável após StressLab ter passado.

- [ ] StressLab passou em todos os níveis definidos no Protocolo 4
- [ ] Conta demo configurada com capital realista (não 1M pra "segurança")
- [ ] Broker da demo é o mesmo que será usado em real
- [ ] Horário do servidor conferido
- [ ] Logger configurado para salvar em arquivo persistente
- [ ] Plano de monitoramento definido: quem olha, com que frequência, o que dispara intervenção
- [ ] Condição de parada definida por escrito: "se acontecer X, desligo o EA"
- [ ] Duração mínima da demo definida antes de cogitar live real — recomendado: 30 dias ou 100 trades, o que for maior

---

## Protocolo 6 — Antes de rodar em conta real

**Este é o protocolo mais crítico.** Violação dele foi o que quebrou o V5.

- [ ] Demo passou no Protocolo 5 por pelo menos a duração mínima estabelecida
- [ ] Log-diff entre backtest e demo validado — a divergência máxima por trade é aceitável e documentada
- [ ] Risk manager configurado com limites duros: daily loss, max positions, circuit breaker
- [ ] Capital inicial definido — começar pequeno, escalar depois. Regra sugerida: nunca começar com mais do que o dono estaria confortável em perder 100%.
- [ ] Plano de contingência escrito: "se EA cair, se broker cair, se internet cair — o que eu faço?"
- [ ] Backup do EA e configurações em local seguro
- [ ] Contato de suporte do broker à mão
- [ ] Notificação de emergência configurada (push, SMS, email) para eventos críticos
- [ ] Verificação final: o dono está fisicamente disponível nas primeiras horas de execução?

Se qualquer item está "não" — não vai pra real.

---

## Protocolo 7 — Quando um erro crítico acontece em live

Aplicável em qualquer situação onde comportamento inesperado em live pode afetar capital.

Em ordem, sem pular:

1. **Parar o EA.** Desabilitar AutoTrading no MT5 ou fechar o terminal se necessário.
2. **Fechar posições abertas manualmente** se o estado do EA é suspeito. Preferir perda controlada a exposição descontrolada.
3. **Não reiniciar o EA imediatamente.** A tentação é forte; resistir.
4. **Preservar logs.** Copiar arquivos de log antes que rotação ou reinício sobrescreva.
5. **Escrever um relato por escrito** do que aconteceu, antes de esquecer detalhes. Data, hora, símbolo, último trade, sintoma observado.
6. **Só então investigar.** Com o EA parado e logs preservados.
7. **Identificar causa-raiz** antes de qualquer fix. Se não sabe a causa, não pode saber se o fix resolve.
8. **Reproduzir o problema em backtest/demo** com a mesma causa-raiz.
9. **Consertar no código.** Gambiarras proibidas (ver `REGRAS.md`).
10. **Validar fix** em backtest, StressLab, demo — todos os protocolos novamente.
11. **Entrada no CHANGELOG** com descrição, causa-raiz, fix, lição aprendida.

A ordem importa. Pular etapas é o caminho para a segunda quebra de conta.

---

## Protocolo 9 — Chamadas API globais proibidas em código de lógica

Aplicável durante code review e antes de declarar pronto qualquer módulo de lógica do core (`CMksTradeManager`, `CMksRiskManager`, estratégias futuras) ou auxiliar (`CMksLogger`, sizers, sinks). Fronteira clara: **bordas** (composition root em `OnInit`/`OnTick`/`OnDeinit` de EAs/scripts; implementações concretas de interfaces como `CMksMt5Broker`, `CMksLogger`) **podem** chamar a API global; **código de lógica** não pode.

A regra está enunciada na ADR-013 §2 ("borda aceita default sensato como `_Symbol`"). Este protocolo lista as funções concretas que ficam fora da lógica, com o substituto correto.

### Tempo

| Função MQL5 | Substituto em código de lógica |
|---|---|
| `TimeCurrent`, `TimeLocal`, `TimeGMT`, `TimeTradeServer` | `IClock.NowMsc()` |

### Mercado (símbolo)

| Função MQL5 | Substituto |
|---|---|
| `Symbol()`, `_Symbol` | parâmetro injetado pela borda |
| `Period()`, `_Period` | proibido em lógica (Renko não tem timeframe) |
| `SymbolInfoDouble`, `SymbolInfoInteger`, `SymbolInfoString` | `ISymbol.*` (ADR-016, `Core/Symbol/CMksMt5Symbol`) |
| `SymbolInfoTick(symbol, mt)` | `ITickSource.Next(tick)` |
| `SymbolInfoSessionTrade`, `SymbolInfoSessionQuote` | `ISymbol.*` — não no escopo do v1 da ADR-016; adicionar quando necessário |

### Conta

| Função MQL5 | Substituto |
|---|---|
| `AccountInfoDouble`, `AccountInfoInteger`, `AccountInfoString` | `IAccount.*` (ADR-016, `Core/Account/CMksMt5Account`) |

### Identidade do programa

| Função MQL5 | Substituto |
|---|---|
| `MQLInfoInteger(MQL5_TESTING)` | proibido — caminho único de código (REGRAS §1.7) |
| `MQLInfoInteger(MQL5_PROGRAM_TYPE)` | proibido em lógica |

### Séries e indicadores

| Função MQL5 | Substituto |
|---|---|
| `iOpen`, `iHigh`, `iLow`, `iClose`, `iTime` | proibido — estratégia opera sobre `MksBrick.triggerPrice`, não sobre velas |
| `iATR`, `iMA`, `iRSI`, `i*` família | proibido em lógica — cálculo próprio sobre `MksTick`/`MksBrick` (ADR-018 pendente) |
| `CopyTicks`, `CopyRates`, `CopyBuffer` | `ITickSource.Next(tick)` para ticks; sizers calculam internamente sobre o que recebem |

### Execução de ordem

| Função MQL5 | Substituto |
|---|---|
| `OrderSend`, `OrderSendAsync` | `IBroker.Send(request, result, err)` |
| `OrderCheck` | interno ao `CMksMt5Broker` |
| `PositionSelect*`, `OrderSelect*`, `HistorySelect*` | `IBroker.*` (estado das ordens vive no broker) |

### Custom Symbol

| Função MQL5 | Substituto |
|---|---|
| `CustomSymbolCreate`, `CustomSymbolSet*`, `CustomRatesUpdate`, `CustomRatesDelete` | aceitável apenas em sinks de renderização (ex.: `CCustomSymbolSink` no Producer) — nunca como fonte de preço para lógica de trading (Eixo 1 do V5) |

### Como aplicar

- Code review bloqueia merge se qualquer função desta lista aparecer fora de uma implementação concreta de interface (pasta `Core/Broker/`, `Core/Log/`, sinks de renderização) ou da camada de borda (`OnInit`/`OnTick`/`OnDeinit` de EAs/scripts em `MQL5/Experts/`, `MQL5/Scripts/`, `MQL5/Services/`).
- Quando uma função substituta ainda não existe (ADR-017 pendente para `IBroker` completo), a chamada direta na borda é tolerada com nota de TODO citando a ADR que vai fechar a porta.
- Lista evolui — ADRs novas reorientam o substituto canônico.

---

## Protocolo 8 — Atualização destes protocolos

Protocolos evoluem conforme o projeto amadurece. Mudanças aqui exigem:

- [ ] Razão da mudança descrita no commit
- [ ] Se a mudança remove um checklist item — justificativa explícita do porquê
- [ ] Se a mudança adiciona um checklist item — exemplo concreto do que motivou
- [ ] Commit: `docs(protocols): <descrição curta>`

Protocolos só ficam mais rigorosos com o tempo, não menos. Remoção de etapa é exceção, não regra.
