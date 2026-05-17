---
@document: docs/V5-POSTMORTEM.md
@project: MKS-ULTIMATE
@purpose: Análise de causa-raiz do colapso do MKS-FRAMEWORK-RENKO (V5)
@audience: Dono do projeto, assistentes de IA, contribuidores futuros
---

# MKS-ULTIMATE — Post-mortem do V5

Este documento é a análise de causa-raiz do incidente que encerrou o projeto **MKS-FRAMEWORK-RENKO** ("V5"): uma estratégia com backtests excelentes quebrou a conta do operador em aproximadamente 4 horas de operação real, em abril de 2026.

Diferente de versões anteriores desta narrativa — escritas de memória, antes de qualquer revisão de código — este documento é baseado na **leitura direta do código-fonte do V5**. Onde uma afirmação depende de um arquivo, o arquivo e a linha são citados.

Este post-mortem **corrige** afirmações erradas que haviam sido propagadas para `Projeto.md` e `ROADMAP.md`. As correções estão registradas na seção 6.

---

## 1. O que se acreditava antes da revisão de código

Antes da leitura do código, três afirmações circulavam nos documentos do projeto:

1. "A causa-raiz foi divergência silenciosa entre backtest e live."
2. "O V5 dependia de um indicador de caixa-preta para construir os bricks Renko."
3. "O V5 não tinha simulação de condições adversas (StressLab)."

A revisão do código mostrou que **as três estão erradas ou incompletas**:

1. "Divergência silenciosa" é o **sintoma observável**, não a causa. A causa é estrutural e está detalhada na seção 3.
2. **Falso.** O V5 tinha engine Renko própria, escrita em casa (`MKS-Renko-Core.mqh`, 741 linhas). A dependência de indicador de caixa-preta é uma característica do **AzInvest**, projeto de referência externa — nunca foi do V5. Esta afirmação confundiu os dois.
3. **Parcialmente falso.** O V5 tinha simulação de spread, comissão, latência e rejeição — porém embutida dentro de cada EA como bloco de código ativável por input, não como módulo. E, como a seção 3 mostra, essa simulação **não afetava o resultado do backtest** — apenas alimentava um relatório.

---

## 2. Arquivos analisados

| Arquivo | Papel no V5 |
|--|--|
| `MKS-Renko-Types.mqh` | Tipos, enums, structs, parsing de Custom Symbol |
| `MKS-Renko-Core.mqh` | Motor matemático Renko PO/PRO (state machine) |
| `MKS-Renko-Generator.mq5` | Script: gera histórico Renko a partir de ticks reais |
| `MKS-Renko-LiveEngine.mq5` | Indicador: atualiza o Renko em tempo real |
| `MKS-EA-CE-PRO.mq5` | EA de produção — o que rodou em live |

Os demais arquivos do V5 (`EA-SANDBOX`, `MKS-EA-CE-TEST`, `MKS-Dashboard`, painéis e bridge) não foram necessários para fechar a causa-raiz e não foram auditados em profundidade.

---

## 3. Causa-raiz

O V5 não quebrou por um bug pontual. Quebrou porque **backtest e live mediam coisas diferentes**, em quatro eixos simultâneos e independentes. Cada eixo, isolado, já comprometeria a confiabilidade do backtest. Combinados, tornaram o backtest uma ficção sem relação causal com o resultado real.

### 3.1 Eixo 1 — A estratégia nunca operou sobre preço de mercado

A função `ProcessMain()` do EA (`MKS-EA-CE-PRO.mq5`, linhas 514-532) é a origem de toda decisão de trading. O que ela lê é:

```
iOpen(g_csName, PERIOD_M1, 1)
iClose(g_csName, PERIOD_M1, 1)
```

`g_csName` é o **Custom Symbol** — o feed Renko sintético gerado pelo framework. O valor de `iClose` aqui é o `close` do brick, e esse `close` é definido matematicamente pelo Core:

> `MKS-Renko-Core.mqh`, linhas 484-550: todo brick novo recebe `close = open ± m_sz`.

Ou seja: o `close` do brick **não é o preço do tick que disparou o fechamento**. É um valor calculado a partir do tamanho do brick. Quando um tick a 2050 dispara o fechamento de um brick cujo `close` matemático é 2000, o brick é gravado com `close = 2000` — e o preço real (2050) é descartado. O brick não armazena o preço observado, o overshoot, nem qualquer referência ao tick disparador.

**Consequência:** a estratégia inteira do V5 — CE1, CE2, Combo, BOX, Pyramid — raciocina dentro de um espaço de preços fictício. Em backtest isso é invisível, porque o backtest também roda sobre o Custom Symbol. Em live, a estratégia decide em preço fictício e envia ordem a mercado em preço real.

Evidência adicional de que o próprio V5 sabia disso, sem tratar: `MKS-EA-CE-PRO.mq5`, linha 369 — `trade.SetDeviationInPoints(50)`. O EA aceitava em silêncio até 50 pontos de desvio entre o preço esperado e o preço executado. Isso não é tratamento do problema; é tolerância ao sintoma.

### 3.2 Eixo 2 — Bricks produzidos por caminhos diferentes em backtest e em live

O Core (`CMKSRenkoCore::ProcessPrice`) é um motor único e determinístico. Mas ele é alimentado por **cinco produtores diferentes**, e os cinco veem dados diferentes:

| Caminho | Origem dos dados | Granularidade |
|--|--|--|
| A — Generator: `ProcessTicks` | `CopyTicksRange`, dia a dia | Todos os ticks reais |
| B — Generator: `ProcessM1` | `CopyRates(M1)` | OHLC sintetizado, 4 pontos por minuto |
| C — LiveEngine: `GenerateQuickHistory` | `CopyRates(M1)` | OHLC sintetizado, 4 pontos por minuto |
| D — LiveEngine: `FillGap` | `CopyRates(M1)` quando detecta gap | OHLC sintetizado, 4 pontos por minuto |
| E — LiveEngine: `OnTimer` | `SymbolInfoTick`, a cada 250 ms | 1 tick a cada 250 ms |

(`MKS-Renko-Generator.mq5`: `ProcessTicks` linhas 151-252, `ProcessM1` linhas 255-308, `LoadAndProcess` linhas 312-349; `MKS-Renko-LiveEngine.mq5` linhas 204-286, 372-439, 868-916.)

O Generator não é um produtor de caminho único. `LoadAndProcess` despacha entre os dois caminhos: com `InpDataSource = MKS_SOURCE_TICKS` (o padrão) roda `ProcessTicks`; mas se os ticks do broker cobrem menos da metade dos dias pedidos, executa `core.Reset()` e reconstrói o Custom Symbol inteiro pelo caminho B (M1 OHLC). O fallback é silencioso — só uma linha `Warn` no log o registra. Logo, **não se pode afirmar com certeza** que o backtest rodou sobre ticks reais: o Custom Symbol pode ter saído do caminho A ou do B conforme a cobertura de tick history do broker no momento da geração, não uma decisão registrada.

Em live, o histórico inicial era reconstruído pelo caminho C (M1 OHLC, 4 pontos/minuto) e a operação corrente rodava pelo caminho E (1 tick a cada 250 ms — todos os ticks entre duas execuções do timer são ignorados).

**Consequência:** dado o mesmo símbolo, o mesmo intervalo e a mesma configuração, os cinco caminhos produzem **cinco sequências de bricks diferentes**. Não há paridade nem entre os caminhos internos do LiveEngine, muito menos entre LiveEngine e Generator. A estratégia foi calibrada sobre uma sequência de bricks e operada sobre outra — e a própria origem do lado da calibração não era garantida.

### 3.3 Eixo 3 — O custo de execução era contabilizado, não aplicado

O V5 tinha um conjunto de parâmetros chamado "StressLab" dentro do EA (`MKS-EA-CE-PRO.mq5`, linhas 42-63): spread, slippage, comissão, latência, taxa de rejeição, taxa de requote, com presets prontos (`ECN_BEST` até `NIGHTMARE`, linhas 399-404).

O padrão de uso aparece mais de 20 vezes no arquivo. Exemplo (linha 843):

```
bool canExec = !InpUseStressLab || SimulateExecution("CE1_BUY", InpCE1Lot, cost);
```

A função `SimulateExecution` (linhas 411-424) faz o seguinte:

- Sorteia uma rejeição via `MathRand()` e, se rejeitar, retorna `false`.
- Soma um custo fictício a contadores globais: `g_costSpread`, `g_costSlippage`, `g_costCommission`.
- Retorna `true`.

O que ela **não faz**: não envia ordem, não altera o preço de entrada, não desconta nada do equity da conta de teste. O custo somado nos contadores só aparece em um único lugar — o relatório final impresso no `OnDeinit` (linha 1948).

Quando `SimulateExecution` retorna `true`, o `trade.Buy()` real é chamado logo abaixo — e essa ordem é executada no preço fictício do Custom Symbol, **sem nenhum dos custos que acabaram de ser somados**. Os contadores e o trade são dois universos paralelos que nunca se tocam.

**Consequência:** o "backtest com StressLab" do V5 não era um teste de estresse. Era um backtest comum — perfeito por baixo, operando sobre preço fictício — com uma planilha de custos rodando ao lado. O operador via a linha "Custos: Total = $X" no relatório e presumia que o equity tinha sentido aquele valor. Não tinha. O equity do backtest nunca foi tocado por um centavo de custo de execução.

### 3.4 Eixo 4 — Backtest e live eram programas funcionalmente diferentes

O bloco StressLab era ativado pelo input `InpUseStressLab` (`MKS-EA-CE-PRO.mq5`, linha 43). No backtest, ligado. Em live, desligado.

Com `InpUseStressLab = false`, a expressão `!InpUseStressLab || SimulateExecution(...)` sofre curto-circuito no `||`: `SimulateExecution` **nunca é chamada**. Não há sorteio de rejeição, não há contagem de custo. `canExec` é sempre `true`.

Tecnicamente, isso **não viola** a regra que o V5 (e o MKS-ULTIMATE) herdaram — a proibição de `if(MQLInfoInteger(MQL5_TESTING))`. `InpUseStressLab` é um input, não auto-detecção da engine de teste. O V5 cumpria a letra da regra. E quebrou do mesmo jeito.

A lição: o gatilho da bifurcação (flag de ambiente, input, compilação condicional) é irrelevante. A doença é **existir um caminho de código de lógica de trading que só roda em um dos ambientes**. O V5 passou pela brecha exata da regra.

### 3.5 Síntese da causa-raiz

> O V5 nunca teve um modelo de execução. Tinha um modelo de desenho de bricks, e confundiu desenhar com executar.

O backtest era estruturalmente otimista — não por um parâmetro mal calibrado, mas porque (a) operava em preço fictício, (b) sobre uma sequência de bricks que o live não reproduzia, (c) sem custo de execução nenhum afetando o equity, (d) com um caminho de código que o live não rodava.

Quando o V5 foi para live, todos os custos que o backtest fingira aplicar — e na verdade só somara num relatório — apareceram de uma vez, agora alterando trades de verdade. As 4 horas até a quebra de conta foram o tempo que levou para esse acúmulo consumir o capital.

---

## 4. O que estava correto no V5

Para que este documento sirva como referência honesta e não apenas como lista de culpas:

- A engine Renko (`MKS-Renko-Core.mqh`) é uma state machine PO/PRO bem estruturada, determinística, sem dependência externa. O problema nunca foi a matemática do Renko.
- O `MKSError` com contexto e log automático é um padrão de tratamento de erro razoável.
- A validação de configuração (`MKSRenkoConfig::Validate`) é defensiva e cobre os casos esperados.
- O Generator processa ticks em chunks de 1 dia para proteger RAM — decisão correta para o volume de dados do XAUUSD.

O V5 não falhou por incompetência de implementação pontual. Falhou por uma decisão de arquitetura: tratar o feed Renko desenhado como se fosse o ambiente de execução.

---

## 5. Invariantes que este post-mortem torna obrigatórios no MKS-ULTIMATE

Cada item abaixo responde diretamente a um eixo da causa-raiz. Estes invariantes alimentam correções em `Projeto.md`, `REGRAS.md` e `ARCHITECTURE.md`.

1. **O brick carrega o preço observado.** Responde ao Eixo 1. O tipo `Brick` deve incluir, além do OHLC matemático, o preço real do tick que disparou seu fechamento (`triggerPrice`), o `overshoot` em relação ao threshold, e uma referência ao tick disparador (`triggerTickId`). Estratégia que decide por preço usa `triggerPrice`, nunca `close`.

2. **Um único produtor de bricks.** Responde ao Eixo 2. Não pode existir mais de um caminho de geração de bricks. Backtest e live consomem ticks da mesma interface `ITickSource`, processados pelo mesmo código. M1-OHLC-sintetizado como fonte de bricks é proibido.

3. **Custo de execução é aplicado ao trade, nunca contabilizado ao lado.** Responde ao Eixo 3. O `CMksSimulatedBroker` deve retornar um `ExecutionResult` cujo preço de preenchimento já incorpora spread, slippage e o efeito da latência. O equity do backtest sente o custo no mesmo instante do trade. Contador paralelo de custo, desacoplado do resultado, é proibido por design.

4. **Lógica de trading não tem condicional de ambiente.** Responde ao Eixo 4. Não basta proibir `if(MQL5_TESTING)`. É proibido qualquer caminho de código de lógica de trading que exista condicionalmente — seja o condicional uma flag de ambiente, um input, ou compilação condicional. A diferença entre backtest e live vive exclusivamente na escolha de qual implementação de interface (`IBroker`, `ITickSource`, `IClock`) é injetada no composition root.

5. **Reconstrução de estado é completa ou não acontece.** Observação adicional do Eixo 2: o `SyncWithExisting` do V5 (`MKS-Renko-LiveEngine.mq5`, linha 293) restaurava apenas `prevClose` e `prevDir`, descartando `wickHigh`, `wickLow` e o brick em formação. Todo restart era uma reset parcial silenciosa. No MKS-ULTIMATE, retomar o estado de um RenkoBuilder reconstrói o estado inteiro a partir do feed de ticks, ou não retoma.

---

## 6. Correções feitas nos documentos de base

Este post-mortem motivou as seguintes correções, registradas no `CHANGELOG.md` e feitas em commits `docs:` próprios:

- **`Projeto.md` §2 e §3** — a causa-raiz do V5 foi reescrita: de "divergência silenciosa entre backtest e live" (sintoma) para a causa estrutural de quatro eixos descrita aqui.
- **`Projeto.md` §6** — a referência ao V5 deixou de sugerir dependência de indicador de caixa-preta. Essa característica pertence ao AzInvest e foi mantida apenas lá.
- **`ROADMAP.md`** — removida a afirmação "o ponto mais grave do V5 — dependia de indicador de caixa-preta". A seção "Lições aprendidas do V5" foi reescrita com base nos quatro eixos.
- **`REGRAS.md` §1.7** — a regra de paridade backtest/live foi ampliada: de "proibido `if(MQL5_TESTING)`" para a proibição de qualquer condicional de ambiente na lógica de trading.

---

## 7. Status

Post-mortem **fechado**. A causa-raiz foi determinada a partir de evidência de código, não de memória. Não há análise pendente.

Se, no futuro, surgir acesso a outros artefatos do V5 (logs do dia da quebra, EAs não auditados), eles podem ser anexados como evidência adicional — mas não é esperado que mudem a conclusão.

**Revisão 2026-05-17.** A tabela do Eixo 2 (§3.2) foi corrigida. A leitura completa de `MKS-Renko-Generator.mq5` mostrou que o Generator tem dois caminhos produtores — `ProcessTicks` (ticks reais) e `ProcessM1` (M1 OHLC), este último acionado também como fallback silencioso por `LoadAndProcess` —, totalizando cinco produtores, não quatro. A conclusão do post-mortem não muda: o Eixo 2 sai reforçado, porque nem a origem do Custom Symbol do backtest é garantida.
