---
@document: docs/ARCHITECTURE.md
@project: MKS-ULTIMATE
@purpose: Registro de decisões arquiteturais e estrutura do sistema
@audience: Dono do projeto, assistentes de IA, contribuidores futuros
---

# MKS-ULTIMATE — Arquitetura

Este documento registra **decisões arquiteturais** do projeto. Não é um documento de "arquitetura final" — arquitetura se desenha conforme o sistema é construído, e congelá-la antes do código é exercício de ficção.

A estrutura abaixo cresce conforme a Fase 1 e seguintes do `ROADMAP.md` avançam.

## 1. Princípios invariantes

Esses princípios foram decididos no `Projeto.md` e não podem ser violados por nenhuma decisão arquitetural posterior:

1. **Paridade backtest/live** — mesmo feed de ticks produz mesmo resultado
2. **Caminho de código único** — nenhuma bifurcação `if(MQL5_TESTING)` na lógica
3. **Abstrações antes de implementações** — interfaces injetadas, não acopladas
4. **Determinismo** — mesma entrada, mesma saída, sempre
5. **Zero dependência de código fechado** para construção de bricks Renko

Qualquer decisão arquitetural registrada neste documento deve ser compatível com esses princípios. Violação exige revisão do `Projeto.md` primeiro.

## 2. Estrutura de diretórios (pretendida)

Esta é a estrutura-alvo. Cresce conforme fases do ROADMAP são implementadas.

MKS-ULTIMATE/
├── docs/                           # Documentação viva
├── MQL5/
│   ├── Include/MKS-ULTIMATE/
│   │   ├── Core/
│   │   │   ├── Version.mqh         # Versão única do framework
│   │   │   ├── Interfaces/         # IBroker, ITickSource, IClock, ILogger, IRenkoSink, IBrickSizer
│   │   │   ├── Types/              # Tick, Brick, OrderRequest, ExecutionResult, Error, RenkoGeometry
│   │   │   ├── RenkoBuilder/       # CMksRenkoBuilder e suas variantes
│   │   │   ├── Broker/             # CMksMt5Broker, CMksSimulatedBroker, CostModel
│   │   │   ├── Trade/              # CMksTradeManager, CMksPositionSizer
│   │   │   ├── Risk/               # CMksRiskManager, camadas de limite
│   │   │   ├── Log/                # CMksLogger (logging estruturado)
│   │   │   └── Testing/            # Framework mínimo de asserções
│   │   └── StressLab/              # Simulação de condições adversas
│   ├── Experts/
│   │   └── MKS-ULTIMATE/           # EAs que usam o framework
│   ├── Scripts/                    # Scripts utilitários
│   └── Services/                   # Coletores de tick em background e workers independentes de gráfico
├── tests/                          # Testes unitários e de integração
├── logs/                           # Logs de backtest e live (gitignored)
│   └── .gitkeep
├── CLAUDE.md
├── README.md
├── CHANGELOG.md
└── .gitignore

## 3. Decisões arquiteturais (ADRs)

Cada decisão importante vira uma entrada aqui, no formato **ADR (Architecture Decision Record)**. Formato padrão:

ADR-NNN: Título curto da decisão
Data: YYYY-MM-DD
Status: Proposta | Aceita | Substituída por ADR-XXX | Revogada
Contexto:
Qual problema estamos resolvendo? Qual a situação que motivou a decisão?
Decisão:
O que decidimos fazer?
Alternativas consideradas:
Quais outras opções foram avaliadas e por que foram rejeitadas?
Consequências:
O que muda no projeto como resultado? Há trade-offs? Dívidas técnicas criadas?

ADRs **não são reescritas** depois de aceitas. Se uma decisão é revertida, a ADR original ganha status "Substituída por ADR-XXX" e uma nova ADR é criada explicando a mudança.

---

### ADR-001: Adoção de versionamento semântico (SemVer)

**Data:** 2026-04-24
**Status:** Aceita

**Contexto:**
Projeto precisa de convenção de versionamento para comunicar compatibilidade e estabilidade entre releases.

**Decisão:**
Adotar Semantic Versioning 2.0 (semver.org). Formato `MAJOR.MINOR.PATCH`. Primeira release-alvo: `6.0.0`.

**Alternativas consideradas:**
- Versão marcada em cada arquivo (ex: "V-6.0" no cabeçalho) — rejeitada por envelhecer mal e duplicar informação entre arquivos.
- Versão apenas no git (tags) — rejeitada porque o framework precisa conseguir se autoidentificar em runtime (log, telemetria).

**Consequências:**
- Um único arquivo `Core/Version.mqh` define `MKS_ULTIMATE_VERSION_MAJOR/MINOR/PATCH/STR`.
- Cabeçalhos de arquivos individuais não carregam número de versão.
- Incrementos seguem regra SemVer: breaking change → MAJOR, feature não-breaking → MINOR, fix não-breaking → PATCH.

---

### ADR-002: Conventional Commits para mensagens de commit

**Data:** 2026-04-24
**Status:** Aceita

**Contexto:**
Histórico Git precisa ser navegável, filtrável e gerar changelog com esforço mínimo.

**Decisão:**
Adotar Conventional Commits (conventionalcommits.org). Tipos usados: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `style`.

**Alternativas consideradas:**
- Mensagens livres — rejeitadas por não permitirem filtragem sistemática.
- Gitmoji (emojis como prefixo) — rejeitado por não ser padrão estabelecido e dificultar busca em terminal.

**Consequências:**
- Toda mensagem de commit começa com tipo + descrição imperativa.
- CHANGELOG pode ser (parcialmente) automatizado a partir do log.
- Primeira linha limitada a 72 caracteres.

---

### ADR-003: Idioma da documentação e do código

**Data:** 2026-04-24
**Status:** Aceita

**Contexto:**
Projeto tem dono nativo de português mas operará em contexto técnico internacional (MQL5, APIs em inglês, corretoras globais).

**Decisão:**
- **Documentação** (README, docs/*.md, CHANGELOG, comentários de commit de `docs:`) — português do Brasil, com marcadores técnicos em inglês quando forem convenção internacional (Added/Changed/Fixed do Keep a Changelog).
- **Código, nomes de classes/variáveis, mensagens de log estruturado, commit messages técnicos** — inglês.

**Alternativas consideradas:**
- Tudo em inglês — rejeitado por prejudicar fluência de raciocínio do dono em documentos conceituais.
- Tudo em português — rejeitado por atritar com convenções do ecossistema MQL5 e dificultar colaboração futura.

**Consequências:**
- Dono escreve especificações em português, implementação em inglês.
- Documentação fica acessível; código fica portável.

---

### ADR-004: Polimorfismo via classe abstrata com métodos virtuais puros

**Data:** 2026-05-16
**Status:** Aceita

**Contexto:**
MQL5 oferece a keyword `interface`, mas com restrições próprias: uma interface não pode conter membros de dados, nem construtor, nem destrutor, e todos os seus métodos são virtuais puros implicitamente. O projeto precisa de polimorfismo de runtime para abstrair `Broker`, `Clock`, `TickSource`, `Logger` e `RenkoSink` — exigência direta do princípio 3 (abstrações antes de implementações) e do invariante 2 do `V5-POSTMORTEM.md` (um único produtor de bricks, alimentado pela mesma interface em backtest e em live). Antes de escrever qualquer interface do core, é preciso fixar como uma "interface" é expressa em código MQL5, com regras objetivas o suficiente para virar checklist de code review.

**Decisão:**
Toda interface do core do MKS-ULTIMATE é uma **classe abstrata composta exclusivamente por métodos virtuais puros**. A keyword `interface` nativa do MQL5 não é usada.

Sete convenções operacionais — qualquer interface do core respeita todas, e adição ou remoção exige nova ADR:

1. **Prefixo `I`** em toda interface: `IBroker`, `IClock`, `ITickSource`, `ILogger`, `IRenkoSink`.
2. **Zero campos.** A classe `I*` não declara estado. Acrescentar campo a uma interface exige nova ADR justificando a quebra.
3. **Destrutor virtual explícito e vazio:** `virtual ~IBroker() {}`. Garante destruição correta quando o objeto é manipulado via ponteiro base.
4. **Todo método é virtual puro:** `virtual ReturnType method() = 0;`. Nenhum método concreto vive na interface.
5. **`const` quando não modifica estado.** Métodos de leitura são qualificados `const`.
6. **`override` na implementação.** Toda classe concreta marca explicitamente os métodos que sobrescrevem a interface.
7. **Argumentos de tipo objeto** são passados por `const&` (leitura) ou por ponteiro (quando o nulo é possibilidade legítima).

**Alternativas consideradas:**
- **Opção A — `interface` nativa do MQL5:** rejeitada. A keyword proíbe construtor, destrutor e qualquer membro — o que impede tanto um destrutor virtual explícito quanto qualquer helper compartilhado entre implementações. Combinar contrato com comportamento comum exigiria uma camada intermediária de classe, mais verbosa que o equivalente direto em classe abstrata. Não há ganho que compense.
- **Opção C — misturar A e B (algumas interfaces nativas, outras abstratas):** rejeitada por quebrar uniformidade. Leitor e revisor passam a precisar verificar caso a caso o que é cada tipo `I*`. Custo cognitivo permanente para um problema que já tem solução única.
- **Herança múltipla de interfaces:** descartada porque MQL5 não suporta herança múltipla. Limitação da linguagem, não decisão de projeto.
- **Duck typing com `template` + `function pointer`:** rejeitada. Templates resolvem polimorfismo em tempo de compilação; function pointers não oferecem despacho dinâmico estruturado. O composition root precisa **trocar em runtime** `IBroker` real por `IBroker` simulado (e equivalentes), o que exige tabela virtual.

**Consequências:**
- Toda interface do core mora em `MQL5/Include/MKS-ULTIMATE/Core/Interfaces/`, um arquivo por interface (`IBroker.mqh`, `IClock.mqh`, `ITickSource.mqh`, `ILogger.mqh`, `IRenkoSink.mqh`).
- Implementações concretas herdam da interface respectiva e marcam cada método herdado com `override`. Ex.: `class CMksMt5Broker : public IBroker { ... };`.
- Code review da camada de abstração tem checklist objetivo: prefixo `I`, zero campos, destrutor virtual vazio, `= 0` em todo método, `const` onde aplicável, `override` na implementação, argumentos por `const&` ou ponteiro.
- Custo de runtime: o consumo de ticks via ITickSource implica uma chamada virtual por tick. O custo de um despacho virtual é da ordem de nanosegundos e é aceitável mesmo no volume de ticks do XAUUSD. Caso profiling futuro aponte gargalo no loop de ingestão de ticks (risco R2.1 do ROADMAP.md), a mitigação é consumir ticks em lote — uma chamada virtual amortizada sobre N ticks — sem alterar esta decisão.
- Compatibilidade futura: se a keyword `interface` do MQL5 evoluir a ponto de superar essa abordagem, a migração é mecânica e será registrada com uma ADR de substituição.

---

**Nota de esclarecimento — alcance da convenção 7 da ADR-004** (2026-05-17)

A convenção 7 da ADR-004 ("argumentos de tipo objeto por `const&` ou ponteiro") regula argumentos de *entrada*. Parâmetros de *saída* por referência não-const — out-params — não são cobertos por ela e são permitidos. Caso concreto no core: `ITickSource::Next(MksTick &tick)`, em que a referência não-const é o canal de retorno do tick lido. A ADR-004 não é alterada; esta nota apenas registra a interpretação.

---

### ADR-009: Modelo de erro — tipo estruturado retornável com localização automática

**Data:** 2026-05-17
**Status:** Aceita

**Contexto:**
O framework precisa de uma forma única de uma operação falível reportar o que falhou e onde. A Fase 1 entregou o `ILogger` — streaming de eventos —, mas não há um tipo de erro que uma função devolva ao seu chamador. O V5 tinha o `MKSError`, com dois defeitos estruturais: o método `Set()` logava automaticamente, soldando representação de erro e emissão de log num só ato, e a origem do erro era uma string de componente digitada à mão, que não acompanha renomeações. Sem uma convenção fixada, cada módulo inventará a sua. Esta decisão precede a Fase 2: o `CMksRenkoBuilder` deve nascer já usando o modelo de erro, não recebê-lo por retrofit — diagnóstico assado tarde é dívida.

**Decisão:**
O tratamento de erro do MKS-ULTIMATE assenta sobre um tipo de valor estruturado e retornável, separado do logging.

1. **Tipo `MksError`** — struct POD (prefixo `Mks`), em `MQL5/Include/MKS-ULTIMATE/Core/Types/`. Carrega: o código de erro tipado, uma mensagem, a localização de origem (arquivo, função, linha) e um campo de detalhe para valores de runtime.

2. **`MksError` é dado puro — não loga.** Preencher um erro e emitir uma linha de log são atos distintos. O tipo representa; quem decide logar é o chamador, via o `ILogger` injetado. Mantém o caminho de erro testável sem efeito colateral e elimina o defeito do `MKSError` do V5.

3. **Localização capturada no ponto de chamada por macro.** Uma macro de pré-processador (ex.: `MKS_SET_ERROR`) injeta `__FILE__`, `__FUNCTION__` e `__LINE__` no momento em que o erro é preenchido. Os macros expandem no call site — a localização é sempre a real, imune a renomeação.

4. **Operações falíveis usam out-param.** A assinatura padrão é `bool Op(..., MksError &err)`: retorno `bool` para sucesso/falha, erro preenchido por referência. É o mesmo padrão de `ITickSource::Next` da Fase 1.

5. **`MksError::ToString()` formata a linha; o `ILogger` não muda.** Quem quiser logar faz `logger.Log(MKS_LOG_ERROR, err.ToString())`. O `ILogger` permanece a interface mínima decidida na Fase 1.

6. **Severidade não é campo do tipo.** Se uma falha é fatal ou recuperável é interpretação do chamador, expressa na escolha do nível ao logar — não um atributo do erro em si.

7. **Código de erro particionado por faixa de módulo.** O enum `ENUM_MKS_ERROR_CODE` é um registro central único. Os valores são atribuídos em faixas de 100, uma por módulo — o número do código identifica o módulo de origem. Alocação inicial:

| Faixa | Módulo |
|---|---|
| 0 | Reservado — `MKS_ERR_NONE` (ausência de erro) |
| 1–99 | Core (tipos, fundação, infraestrutura) |
| 100–199 | RenkoBuilder |
| 200–299 | Broker |
| 300–399 | Trade |
| 400–499 | Risk |
| 500–599 | StressLab |
| 600–699 | Log / observabilidade |
| 700–799 | Testing |
| 800+ | Reservado para módulos futuros |

Cada módulo novo reivindica uma faixa ao ser criado, registrada por edição desta tabela. As faixas Core e RenkoBuilder são as únicas com conteúdo nesta fase.

8. **Escopo desta ADR.** O tipo, o enum e a macro entram agora. O módulo de logging pesado — saída em arquivo, rotação, filtro — permanece na Fase 8 do ROADMAP. Esta ADR define como um erro é representado e endereçado, não como um log é persistido.

**Alternativas consideradas:**
- **Reaproveitar o `MKSError` do V5 com auto-log no `Set`:** rejeitada. Solda representação e emissão de log, impede testar o caminho de erro sem ruído, e acopla ao logger global estático.
- **Localização por string de componente digitada à mão (jeito V5):** rejeitada. A string não acompanha renomeação de função ou arquivo — mente em silêncio assim que o código evolui.
- **Enum de erro único e plano, sem faixas:** rejeitada. À medida que o framework cresce, o número do código não informa a origem; o erro "endereçado" ficaria só na mensagem, nunca no código.
- **Macro proibida, `__FILE__`/`__FUNCTION__`/`__LINE__` digitados manualmente em cada chamada:** rejeitada. A repetição em todo call site é frágil — esquecimento e copy-paste errado. A macro produz o mesmo efeito sem a repetição. Trade-off aceito: introduz uma indireção de pré-processador no projeto.
- **Result type empacotando sucesso e erro num único retorno:** rejeitada. Inconsistente com o out-param `bool + &` já adotado na Fase 1; MQL5 não tem `optional`/`expected` que tornem o padrão limpo.
- **Exceções (`try`/`catch`):** MQL5 não as oferece. Não é alternativa real.

**Consequências:**
- Toda operação falível do core passa a ter a assinatura `bool Op(..., MksError &err)`. Onde o V5 retornava um `bool` solto ou logava e seguia, passa a existir um erro estruturado e inspecionável.
- O caminho de erro fica testável sem efeito colateral: um teste dispara a falha e assevera sobre o `MksError`, sem produzir linha de log.
- Novo arquivo em `Core/Types/` reúne o enum `ENUM_MKS_ERROR_CODE`, a struct `MksError` e a macro de localização.
- O enum é registro central e cresce por edição da tabela de faixas — cada módulo futuro reivindica a sua.
- Entra uma macro no vocabulário do projeto. Custo assumido: macro não passa por checagem de tipo como uma função e pode surpreender em depuração. A macro é estritamente açúcar de construção de valor — não bifurca lógica de trading nem é compilação condicional, portanto não fere a REGRAS §1.7.
- O `ILogger` da Fase 1 permanece intacto.
- O `CMksRenkoBuilder` (Fase 2) nasce usando este modelo desde a primeira linha de caminho de erro.

---

### ADR-010: Arquitetura de parametrização do RenkoBuilder e escolha do preço-condutor

**Data:** 2026-05-17
**Status:** Aceita

**Contexto:**
O `CMksRenkoBuilder` é o módulo central da Fase 2 — a primeira classe do framework com lógica de trading, não apenas estrutura de dados. O projeto exige suporte a múltiplas formas de Renko: clássico, median, ATR e custom. O desenho ingênuo — uma única classe com um `switch` de modo interno — recriaria, em escala menor, o eixo 2 do colapso do V5: múltiplos comportamentos sob um teto único, sem teste isolado por modo. A leitura do código-fonte do V5 (`MKS-Renko-Core.mqh`) revelou que "median Renko" não é um algoritmo distinto: é o esquema de offset governado por dois percentuais — PO (abertura de continuação) e PRO (abertura de reversão). Clássico, median, turbo, hybrid e scalp são o mesmo algoritmo de formação, com pares `(PO, PRO)` diferentes. O ATR, ao contrário, é genuinamente outra coisa: afeta o tamanho do brick, recalcula ao longo do tempo e depende de dados de mercado. São dois eixos ortogonais. Além disso, o V5 nunca decidiu qual preço do tick alimentava o motor — aceitava um `double` solto e o chamador decidia, brecha pela qual o eixo 2 entrou. Esta ADR fixa como o `CMksRenkoBuilder` é parametrizado e qual preço o dirige, antes de a classe ser escrita.

**Decisão:**
A parametrização do `CMksRenkoBuilder` se organiza em dois eixos ortogonais — geometria e tamanho do brick —, e o motor é dirigido por um preço-condutor único e explícito.

1. **Geometria do brick é um valor, não uma interface.** Um struct POD — `MksRenkoGeometry` — carrega o triplo `(PO, PRO, revSizePct)`: percentual de abertura de continuação, percentual de abertura de reversão e percentual de tamanho do brick de reversão. Não é uma interface: um contrato cujo único papel é devolver constantes viola a convenção 2 da ADR-004 (interface não carrega estado) e é sobre-abstração — o risco R1.1 do `ROADMAP.md`. Os presets nomeados são fábricas que produzem triplos: median = `(0.50, 0.50, 100%)`, clássico = `(0.00, 0.00, 100%)`. O modo custom é um triplo definido livremente pelo usuário.

2. **O tamanho do brick é uma interface — `IBrickSizer`.** O tamanho é o eixo onde o polimorfismo se justifica: tamanho fixo é um número, mas o tamanho por ATR recalcula ao longo do tempo e depende de feed de dados — comportamento e dependências próprios. `CFixedBrickSizer` — tamanho a partir de um valor configurado, com points/pips/price convertidos para pontos na borda — entra na Fase 2. `CAtrBrickSizer` é implementação futura.

3. **`CMksRenkoBuilder` é uma máquina de estado única, agnóstica de modo.** Recebe um `MksRenkoGeometry` e um `IBrickSizer` por injeção, consome `MksTick` via `ITickSource` e emite cada `MksBrick` completo via `IRenkoSink::OnBrickClose`. Não existe ramo condicional de modo dentro da classe — a variação de comportamento vive inteiramente na geometria e no sizer injetados.

4. **O motor é dirigido pelo preço médio — mid `(bid + ask) / 2`** — calculado a partir de cada `MksTick`. O bid carrega um termo de meio-spread que varia no tempo; conduzir o Renko pelo bid embutiria esse offset errante na estrutura. O mid é neutro a spread, mantém a camada de estrutura livre de custo de execução — que pertence à camada de Broker, eixo 3 — e é simétrico entre fills de compra e de venda. O `last` é descartado: não-confiável ou zero para XAUUSD na maioria dos brokers.

5. **Cada brick emitido grava o tick disparador.** `triggerPrice` recebe o mid no tick que disparou o fechamento; `triggerTickId` referencia esse tick, preservando acesso ao bid e ao ask reais. É a resposta ao eixo 1: a estratégia raciocina sobre preço observado, não sobre o `close` matemático.

6. **O brick em formação é estado interno, exposto sob demanda.** Como o `MksBrick` é, por decisão da Fase 1, um tipo exclusivo de brick completo, o brick em formação tem tipo próprio — `MksFormingBrick` —, obtido por um getter do builder. O builder não emite atualização a cada tick e não renderiza nada; renderização é responsabilidade da camada de Custom Symbol, fase posterior.

7. **Escopo da Fase 2.** Entram o `CMksRenkoBuilder`, o `MksRenkoGeometry`, a interface `IBrickSizer`, o `CFixedBrickSizer` e o preset median. Os presets restantes (clássico, turbo, hybrid, scalp, custom) e o `CAtrBrickSizer` são adições futuras — cada uma um triplo ou uma implementação de interface, sem tocar o motor.

A unidade interna de medida é o ponto, conforme decisão herdada do `V5-POSTMORTEM.md`; pip e price são conversões feitas na borda de configuração.

**Alternativas consideradas:**
- **`CMksRenkoBuilder` único com `switch` de modo interno:** rejeitada. Recria o eixo 2 do V5 em escala menor — vários comportamentos num teto só, sem teste isolável por modo; adicionar um modo passaria a exigir edição do motor.
- **Interface `IRenkoMode` para a geometria (median, clássico, etc. como implementações):** rejeitada. Corrige uma proposta anterior do próprio assistente. Clássico, median e turbo não são algoritmos diferentes — são o mesmo algoritmo com números diferentes. Uma interface que apenas devolve constantes é sobre-abstração e fere a convenção 2 da ADR-004.
- **Struct de configuração único e plano, misturando os dois eixos (modelo do V5):** rejeitada. A `MKSRenkoConfig` do V5 reunia treze campos, com geometria e tamanho embaralhados e vários campos inúteis em cada modo.
- **Brick em formação reutilizando `MksBrick` com um campo `isForming`:** rejeitada. A Fase 1 definiu o `MksBrick` como tipo exclusivo de brick completo de forma deliberada; reabrir isso mistura dois conceitos num tipo só.
- **Brick em formação emitido como evento a cada tick:** rejeitada. Custo por tick sem consumidor na Fase 2 — a estratégia reage a bricks fechados, e renderização é fase posterior.
- **Motor dirigido pelo bid:** rejeitada. O bid é `mid − spread/2`, com o meio-spread variando no tempo; conduzir a estrutura pelo bid embute esse offset errante nos bricks e introduz assimetria entre as direções — a estrutura fica alinhada ao fill de venda e desalinhada do fill de compra.
- **Motor dirigido pelo `last`:** rejeitada. Para XAUUSD, o `last` é não-confiável ou zero na maioria dos brokers.

**Consequências:**
- O projeto mantém os quatro modos pretendidos: median, clássico e custom são triplos de geometria; ATR é uma escolha de `IBrickSizer`. Os eixos sendo ortogonais, combinações como "median com tamanho ATR" passam a ser expressáveis.
- Cada variante de Renko fica testável em isolamento: a geometria é um valor, o builder é uma máquina de estado única, e os sizers são classes separadas.
- Adicionar um modo futuro é criar um triplo de preset ou uma implementação de `IBrickSizer` — sem editar uma linha do motor.
- O `CMksRenkoBuilder` consome `MksTick` tipado, não um `double` solto — fecha a brecha de interface pela qual o eixo 2 entrou no V5.
- O `triggerPrice` do `MksBrick` passa a carregar o mid do tick disparador. O comentário desse campo em `Brick.mqh` (Fase 1) — hoje "preço real do tick que disparou o fechamento" — será ajustado para refletir a semântica de preço-condutor (mid) quando o builder for implementado. O `triggerTickId` continua dando acesso ao tick cru, com bid e ask.
- Novos artefatos da Fase 2: os structs `MksRenkoGeometry` e `MksFormingBrick` (em `Core/Types/`), a interface `IBrickSizer` (em `Core/Interfaces/`), e as classes `CFixedBrickSizer` e `CMksRenkoBuilder` (em `Core/RenkoBuilder/`).
- A cadência de recálculo do tamanho por ATR — travado por sessão, por N bricks ou por brick — fica adiada para quando o `CAtrBrickSizer` for construído; é decisão de implementação dele, registrada então.

---

**Nota de esclarecimento — nomenclatura na ADR-010** (2026-05-17)

A ADR-010 nomeia, no texto, as classes concretas de sizer como `CFixedBrickSizer` e `CAtrBrickSizer`. A implementação segue a convenção da §5 — classe concreta com estado leva o prefixo `CMks` — então os nomes reais são `CMksFixedBrickSizer` (já no repositório) e `CMksAtrBrickSizer` (futura). O `CMksRenkoBuilder`, também citado na ADR, já está com o prefixo correto.

A ADR-010 §1 chama o terceiro campo do triplo de geometria de `revSizePct`, descrito como percentual. A struct implementada `MksRenkoGeometry` usa `revSizeRatio` — uma razão, tamanho do brick de reversão dividido pelo normal: o preset median é `revSizeRatio = 1.0`, equivalente aos 100% da ADR. A semântica é a mesma; o nome e o enquadramento como razão refletem a forma final.

A ADR-010 não é alterada; esta nota registra o alinhamento entre o texto da decisão e o código que a implementa.

---

### ADR-011: Tratamento de cruzamento multi-threshold no RenkoBuilder

**Data:** 2026-05-17
**Status:** Aceita

**Contexto:**
O `CMksRenkoBuilder` é dirigido pelo preço médio (mid), conforme a ADR-010. Entre dois ticks consecutivos, o mid pode saltar o suficiente para cruzar mais de um threshold de brick de uma só vez — um spike rápido, um momento de baixa liquidez. O builder precisa de uma regra explícita para esse caso antes de ser escrito; sem ela, a regra fica implícita no código, exatamente o tipo de decisão tácita que o projeto recusa. O desenho ingênuo — emitir N bricks intermediários para preencher o salto — recria o eixo 1 do colapso do V5: a estratégia passa a raciocinar sobre eventos de brick em níveis de preço onde nenhum tick passou. Esses bricks intermediários não têm tick de gatilho próprio; atribuir-lhes identidade (timestamp, `seq`) é fabricá-la, e fabricação fere os invariantes de determinismo (§1) e de auditabilidade (ADR-010 §5, "cada brick emitido grava o tick disparador"). O ROADMAP da Fase 2 lista "Gaps (preço salta mais de um brick)" como caso de tratamento explícito, e a ADR-008 (reabertura de mercado) depende desta decisão. O caso do tick de volume zero — phantom *tick* — é concern distinto, reservado à ADR-006.

**Decisão:**
Um tick que cruza mais de um threshold de brick produz um único `MksBrick` honesto. O builder não cria bricks intermediários ("phantom bricks").

1. **Um brick por movimento.** Um tick que cruza M thresholds (com 1 ≤ M ≤ K) produz exatamente um `MksBrick`. O `open` é o `close` do brick anterior; o `close` é o preço do M-ésimo threshold cruzado; `triggerPrice` recebe o mid do tick disparador e `triggerTickId` o referencia; `Overshoot()` mede a distância do `triggerPrice` ao M-ésimo threshold. O brick é, em todos os campos, um brick normal — exceto pelo tamanho, que abrange M degraus. O invariante de auditabilidade (ADR-010 §5) vale sem exceção: todo brick emitido tem um tick de gatilho real.

2. **Marcação por inteiro.** O `MksBrick` ganha um campo inteiro — `thresholdsCrossed` — com valor 1 para um brick normal e M para um brick formado por cruzamento multi-threshold. É inteiro, não booleano: um booleano responderia apenas "é phantom?", enquanto o inteiro responde "quantos thresholds?", subsume o booleano e carrega a informação que uma estratégia baseada em contagem de bricks precisa. Nenhum consumidor de brick é obrigado a ser phantom-aware — quem assume tamanho uniforme checa o campo, quem não assume o ignora.

3. **A contagem de M respeita a geometria.** M é obtido caminhando a escada de thresholds a partir do `close` do brick anterior. Se o movimento é de reversão, o primeiro degrau está à distância de reversão (`revSizeRatio` da `MksRenkoGeometry`) e os demais à distância de continuação. M não é uma divisão simples do salto pelo tamanho-base do brick.

4. **Limiar K como guarda de corrupção.** Existe um limite configurável K. Um tick com M > K não produz brick: o builder não emite e devolve um `MksError`. Isto é guarda de corrupção, não política de caminho normal — um tick que cruza um número muito grande de thresholds no XAUUSD é quase certamente um tick corrompido, não um movimento real, e emitir bricks a partir dele lavaria dado podre para dentro da estratégia. O valor default de K e a forma de configurá-lo são decisão de implementação do `CMksRenkoBuilder`, registrada quando a classe for escrita; esta ADR fixa que K existe e que a resposta acima do limiar é erro, não emissão.

5. **O builder emite a representação primária.** O brick único é a representação sem perda do movimento. A reconstrução de N sub-bricks de tamanho uniforme — caso uma estratégia ou um renderer futuro precise da vista Renko clássica — é uma transformação derivada e determinística a partir de `open`, `close`, direção, `thresholdsCrossed` e da geometria. Não é responsabilidade do builder. Vistas uniformes derivam do brick honesto, nunca o contrário.

**Alternativas consideradas:**
- **N bricks de tamanho de geometria, sem marca:** rejeitada. Os bricks intermediários não têm tick de gatilho; referenciá-los a um tick fabricado, ou ao mesmo tick do primeiro brick, mente no rastro de auditoria. É o eixo 1 do V5 reembalado — a estratégia decide sobre eventos de brick que correspondem a preços que o mercado nunca imprimiu. E é silencioso: um backtest não distingue uma rajada multi-threshold de uma sequência limpa de bricks.
- **N bricks com os intermediários marcados como anomalia:** rejeitada. Marcar torna a fabricação honesta, não a elimina — ainda é preciso fabricar `timestamp` e `seq` determinísticos para bricks sem tick. É uma vista com perda em relação ao brick único: fabricada a identidade, "isto foi um tick só" deixa de ser recuperável. Empurra complexidade para todo consumidor de brick. E o único ganho aparente — a estratégia "ver" os eventos intermediários — é oco: esses eventos chegam todos no mesmo instante, ao mesmo preço real, e não são acionáveis.
- **Campo booleano de phantom em vez do inteiro `thresholdsCrossed`:** rejeitada. O booleano descarta a contagem; o inteiro a preserva sem custo de espaço relevante e é estritamente mais informativo.
- **Resposta uniforme a qualquer magnitude, sem o limiar K:** rejeitada. Cruzar dois thresholds é movimento rápido normal; interromper nisso inutilizaria o builder. Cruzar centenas é quase certamente corrupção de feed; emitir bricks a partir disso seria gambiarra silenciosa. A resposta tem de ser graduada.

**Consequências:**
- O `MksBrick` ganha o campo `thresholdsCrossed`. O `Brick.mqh` da Fase 1 é alterado — mudança feita após o aceite desta ADR, não antes.
- O tamanho do brick Renko deixa de ser estritamente uniforme: um brick multi-threshold é maior que o nominal. Qualquer indicador ou estratégia que assuma tamanho de brick fixo precisa checar `thresholdsCrossed` e ser magnitude-aware. É um custo real; a mitigação é que a não-uniformidade fica explícita e detectável no campo, nunca silenciosa.
- O invariante de auditabilidade vale sem exceção — todo brick referencia um tick de gatilho real. O problema de identidade sintética para bricks sem tick é eliminado, não resolvido: o builder simplesmente nunca cria um brick desses.
- O enum `ENUM_MKS_ERROR_CODE` (`Error.mqh`) ganha um código novo na faixa RenkoBuilder para o estouro do limiar K, na sequência de `MKS_ERR_RENKO_INVALID_GEOMETRY` (100) e `MKS_ERR_RENKO_INVALID_BRICK_SIZE` (101) — proposto como `MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED`, código 102.
- Um parâmetro K entra na configuração do `CMksRenkoBuilder`; default e forma de configuração ficam para a implementação da classe.
- O estouro do limiar K em live é um `MksError` reportado pelo builder. O que o EA faz com esse erro — continuar, parar, notificar — pertence à camada de EA e ao Protocolo 7, não ao builder. Esta ADR garante apenas que o builder reporta em vez de emitir.
- Fronteira com a ADR-008: esta ADR cobre o cruzamento multi-threshold como mecanismo, independente da causa. A ADR-008 (reabertura de mercado) decide se o gap de fim de semana chega ao builder; se chegar, é este mecanismo que o processa.
- A questão das phantom bars da ADR-006 pendente — tick de volume zero — permanece concern separado. Esta ADR resolve o cruzamento multi-threshold eliminando os phantom bricks: na MKS-ULTIMATE não existe brick sem tick de gatilho.

---

**Nota de esclarecimento — geometria do primeiro brick** (2026-05-18)

A ADR-011 §3 descreve a contagem de M caminhando a escada de thresholds e distingue o primeiro degrau de reversão (à distância `revSizeRatio`) dos degraus de continuação. Essa descrição pressupõe um brick anterior do qual continuar ou reverter. O primeiro brick de uma sessão não tem brick anterior: não há direção prévia, logo não há sentido em "continuação" nem "reversão". A regra fixada é — o primeiro brick tem sua direção definida pelo sinal do primeiro movimento do mid relativo ao mid inicial, e todos os seus degraus (inclusive em cruzamento multi-threshold) usam a geometria de continuação, `(1-PO)*size`. A geometria de reversão só passa a valer a partir do segundo brick, quando existe uma direção anterior. Para o preset median (`PO == PRO`, `revSizeRatio == 1.0`) a regra não altera nenhum valor; ela importa para presets assimétricos futuros, e é fixada agora para que o comportamento do primeiro brick não fique dependente de implementação.

A ADR-011 não é alterada; esta nota registra a regra de borda que a §3 não cobria.

---

### ADR-006: Tratamento de tick inválido no RenkoBuilder

**Data:** 2026-05-18
**Status:** Aceita

**Contexto:**
O `ROADMAP.md` da Fase 2 lista "Volume zero (phantom candidate)" como caso de tratamento explícito do `CMksRenkoBuilder`, e a §4 deste documento reservou a ADR-006 para "phantom bars — ignorar, marcar como suspeito, ou interromper". Encarado o caso, a formulação herdada está errada e a primeira tarefa da ADR é corrigi-la. O termo "phantom bar" do glossário do `Projeto.md` solda três coisas distintas sob um rótulo só: volume de tick igual a zero (um metadado), tick de preço malformado (um perigo real) e gap de feed (concern da ADR-008). A ADR-011, já aceita, eliminou o "phantom *brick*" — brick sem tick de gatilho — e reservou à ADR-006 o "phantom *tick*". Esta ADR resolve o que sobra, e o que sobra não é volume.

Volume não dirige o motor: a ADR-010 fixou o mid `(bid + ask) / 2` como preço-condutor. Um tick com `volume == 0` mas com bid e ask válidos tem um mid válido, move preço e pode fechar brick como qualquer outro. Volume zero também não é sinal confiável de anomalia: para XAUUSD o volume de tick é notoriamente inconsistente entre brokers — há brokers que jamais populam volume. Um critério de anomalia baseado em `volume == 0` classificaria, nesses brokers, todo tick como suspeito; um critério que dispara sempre não informa nada, e ainda deixaria uma propriedade dependente-de-broker decidir a estrutura do Renko — o eixo 2 do colapso do V5.

O perigo real é outro e é ortogonal ao volume: um tick de preço malformado — `bid <= 0`, `ask <= 0` ou `ask < bid` — produz um mid lixo que desloca o motor para um nível de preço irreal. Esse tick pode ter qualquer volume. O tipo `MksTick` da Fase 1 já distingue exatamente esse caso, no método `IsValid()` (`bid > 0 && ask > 0 && ask >= bid`), que deliberadamente não olha volume. Falta a decisão arquitetural de quem aplica essa guarda e o que fazer com o tick reprovado — decisão que, sem ADR, ficaria tácita no código do builder, o tipo de decisão implícita que o projeto recusa.

**Decisão:**
A ADR-006 trata da validade do tick na entrada do `CMksRenkoBuilder`, não de volume. O escopo nominal herdado ("volume zero") é corrigido: volume zero não é anomalia.

1. **Volume zero não é critério de validade.** Um `MksTick` com `volume == 0` e preço válido é um tick legítimo. Flui pelo caminho único — forma e fecha brick — como qualquer outro. O builder não inspeciona `volume` para decidir se processa um tick. O campo `volume` permanece sendo metadado agregado, sem semântica de suspeita.

2. **A guarda de validade vive no builder.** A regra do que é um tick processável pertence a quem processa o tick. Pôr o filtro em cada implementação de `ITickSource` (live, arquivo, mock) faria cada uma reimplementar a regra, e implementações divergem — o eixo 2 do V5 em miniatura. O `CMksRenkoBuilder` aplica a guarda na ingestão de cada tick, num só lugar, no caminho único de backtest e live.

3. **O critério de validade é `MksTick::IsValid()`.** Um tick é inválido quando `bid <= 0`, `ask <= 0` ou `ask < bid` — exatamente o que `IsValid()` já define. A ADR-006 promove esse método a guarda de entrada do builder. Volume não entra no predicado.

4. **Tick inválido é descartado individualmente e reportado.** O builder não processa um tick inválido — não atualiza estado, não forma brick a partir dele — e devolve um `MksError` (modelo da ADR-009), com um código novo na faixa RenkoBuilder: `MKS_ERR_RENKO_INVALID_TICK`, proposto como código 103. Descarta-se o tick, não se interrompe o builder: um tick podre isolado no meio de um feed sadio não deve derrubar a sessão. O descarte é determinístico — mesmo tick inválido, mesmo descarte, mesmo erro reportado.

5. **Guarda de corrupção graduada.** A resposta a um tick inválido é proporcional à magnitude, como o limiar K da ADR-011 é para o cruzamento multi-threshold. Um tick inválido isolado é ruído e é descartado (cláusula 4). Uma sequência de N ticks inválidos consecutivos não é ruído — é sinal de feed quebrado, e continuar seria fingir saúde. Atingido um limiar L de ticks inválidos consecutivos, o builder para de processar e devolve um `MksError` distinto — `MKS_ERR_RENKO_TICK_STREAM_CORRUPT`, proposto como código 104. O valor default de L e a forma de configurá-lo são decisão de implementação do `CMksRenkoBuilder`, registrada quando a classe for escrita; esta ADR fixa que a guarda existe e que a resposta acima do limiar é interrupção reportada, não emissão.

6. **O que o EA faz com o erro não é do builder.** O builder reporta — tick descartado (103) ou feed corrupto (104). Continuar, parar ou notificar o operador pertence à camada de EA e ao Protocolo 7. Esta ADR garante que o builder reporta de forma determinística, nada além.

**Alternativas consideradas:**
- **Tratar `volume == 0` como o critério de phantom (a formulação herdada da §4 e do ROADMAP):** rejeitada. Volume zero é metadado, não anomalia; é comportamento normal do feed para XAUUSD em muitos brokers. Um critério baseado nele classificaria todo tick como suspeito nesses brokers — uma marca que dispara sempre não informa nada — e deixaria uma propriedade não-confiável e dependente-de-broker governar a estrutura do Renko, reintroduzindo o eixo 2 do V5. A pergunta da §4 estava mal formulada; esta ADR a corrige.
- **Ignorar o tick de volume zero (não passá-lo ao motor):** rejeitada. Um tick de volume zero com preço válido carrega movimento de preço real; descartá-lo joga fora estrutura. E como o volume de tick difere entre brokers, o mesmo trecho de mercado gravado por dois brokers produziria sequências de bricks diferentes — a divergência que o eixo 2 do V5-POSTMORTEM proíbe.
- **Marcar o brick formado por ticks de volume zero como suspeito:** rejeitada. A marca herdaria a premissa ruim — num broker sem volume, 100% dos bricks seriam marcados, e a marca vira ruído. Marca só com valor se o critério for preço malformado; e aí não é sobre volume, e o lugar da guarda é o tick na entrada, não o brick na saída.
- **Filtrar o tick inválido no `ITickSource` em vez do builder:** rejeitada. Cada implementação de `ITickSource` reimplementaria a regra e elas divergiriam — múltiplos caminhos para uma mesma decisão, o eixo 2 do V5. A regra de validade pertence a quem consome o tick.
- **Interromper o builder a cada tick inválido:** rejeitada. Desproporcional: um tick corrompido isolado no meio de um feed sadio não justifica derrubar a sessão. A interrupção fica reservada ao sinal de feed genuinamente quebrado — o limiar L da cláusula 5.
- **Descartar ticks inválidos sem nenhuma guarda de corrupção:** rejeitada. Sem o limiar L, um feed inteiramente quebrado seria silenciosamente engolido tick a tick, sem brick e sem alarme — o builder fingiria operar. A resposta tem de ser graduada: descarte para o tick isolado, interrupção para a sequência.

**Consequências:**
- O `CMksRenkoBuilder` (Fase 2) nasce com a guarda `IsValid()` na ingestão de tick. Nenhuma estrutura de dados nova é criada por esta ADR.
- O `enum ENUM_MKS_ERROR_CODE` (`Error.mqh`) ganha dois códigos na faixa RenkoBuilder, na sequência de `MKS_ERR_RENKO_INVALID_GEOMETRY` (100), `MKS_ERR_RENKO_INVALID_BRICK_SIZE` (101) e `MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED` (102, proposto pela ADR-011): `MKS_ERR_RENKO_INVALID_TICK` (103) e `MKS_ERR_RENKO_TICK_STREAM_CORRUPT` (104).
- Um parâmetro L — limiar de ticks inválidos consecutivos — entra na configuração do `CMksRenkoBuilder`; default e forma de configuração ficam para a implementação da classe.
- Os comentários "phantom" da Fase 1 ficam factualmente incorretos com o aceite desta ADR e devem ser corrigidos: em `Brick.mqh`, o campo `volume` ("0 = candidato a phantom (ADR-006)"); em `Tick.mqh`, o campo `volume` ("necessário p/ detecção de phantom (ADR-006)"); no `Projeto.md` §8, a entrada de glossário "Phantom bar". A correção destes arquivos é trabalho à parte, em ciclo próprio, feita após o aceite desta ADR — não antes e não no mesmo commit.
- Fica fora do escopo desta ADR a detecção de outlier de preço — um tick com bid e ask ambos positivos mas com mid implausível (spike de magnitude irreal num tick só). `IsValid()` não cobre esse caso e esta ADR não o resolve. É concern distinto; não recebe número de ADR aqui — registrar ADR no vazio é recusado pela §4 — e será enfrentado se e quando se mostrar necessário.
- A paridade backtest/live desta regra depende de a fonte histórica de ticks e o feed live entregarem ticks crus, sem pré-filtragem. Se o arquivo histórico for gravado já sem ticks inválidos, o builder em backtest nunca exercita a guarda que o builder em live exercita. O descarte é determinístico dado o mesmo input; garantir o mesmo input é responsabilidade da fonte de dados, decisão de Renko engine ainda em aberto, não desta ADR — que aqui apenas registra a dependência.
- O descarte de um tick inválido deixa o `seq` desse tick sem aparecer em nenhum brick. É auditável — o descarte é logado — mas o builder e os consumidores de brick não devem tratar `seq` não-contíguo como erro.

---

### ADR-012: Fonte de dados histórica de ticks e contrato de integridade do feed

**Data:** 2026-05-18
**Status:** Aceita

**Contexto:**
A implementação de backtest da `ITickSource` lê ticks de uma fonte histórica. A `ITickSource` já garante o caminho de código único — em live lê do broker, em backtest lê de arquivo — e essa decisão não é reaberta aqui. O que falta decidir é o que alimenta a implementação de backtest: de onde vêm os ticks, de qual broker, em que formato são gravados, e qual o contrato de integridade entre o que se grava e o que se consome.

A ADR-006, na sua última cláusula de Consequências, registrou esta dívida explicitamente: a paridade da guarda de validade de tick só vale se a fonte histórica e o feed live entregarem ticks crus, sem pré-filtragem; se o arquivo histórico for gravado já sem ticks inválidos, o builder em backtest nunca exercita a guarda que o builder em live exercita. A ADR-006 declarou isso "decisão de Renko engine ainda em aberto, não desta ADR". Esta ADR-012 quita essa dívida.

A decisão tem duas faces que não podem ser colapsadas. **Aquisição** — como os ticks são obtidos e gravados — é engenharia de dados. **Contrato de integridade** — o que a fonte garante sobre o que entrega — é arquitetura, e é o que toca a paridade. Decidir "qual broker" sem decidir o contrato resolve a face fácil e deixa a perigosa implícita. O contrato é fixado primeiro; a aquisição se conforma a ele.

O risco a neutralizar não é múltiplos caminhos de código — a `ITickSource` já o eliminou. É múltiplas fontes de proveniências diferentes alimentando o mesmo caminho: divergência reintroduzida pelos dados em vez de pelo código. Foi por uma porta análoga — `CopyRates(M1)` sintetizando OHLC contra `CopyTicksRange` lendo ticks reais — que o eixo 2 do colapso do V5 entrou.

**Decisão:**
A fonte de dados histórica de ticks do MKS-ULTIMATE assenta sobre um contrato de integridade explícito, e a aquisição se conforma a ele.

1. **O arquivo histórico grava ticks crus.** O arquivo contém os ticks exatamente como o broker os entregou, inclusive os inválidos pelo critério da ADR-006 (`bid <= 0`, `ask <= 0`, `ask < bid`). A gravação não filtra. A limpeza, quando houver, é responsabilidade do consumidor — o `CMksRenkoBuilder` aplica a guarda `IsValid()` da ADR-006 — nunca da gravação. É o que faz o builder em backtest exercitar a mesma guarda que exercita em live: os ticks inválidos chegam ao builder pela mesma porta nos dois modos. Gravar cru é também irreversível-seguro — um tick descartado na captura não se recupera; um tick gravado sempre pode ser filtrado depois.

2. **A fonte é broker-locked, com paridade backtest/live condicional.** O framework permite arquivos históricos de brokers diferentes. A paridade backtest/live, porém, só é garantida quando o broker da captura histórica é o mesmo da conta live: o bid/ask e o volume de tick do XAUUSD divergem entre brokers, e um backtest sobre dados de outro broker produz uma sequência de bricks que não corresponde à realidade da conta de execução. Para que essa condição não seja uma garantia que ninguém verifica — a anatomia do eixo 2 do V5 —, ela é acoplada a um mecanismo de proveniência (cláusula 3).

3. **Todo arquivo histórico carrega um header de proveniência.** O header registra, no mínimo: identificador do broker, símbolo, range temporal coberto e versão do formato binário. Um arquivo sem header de proveniência válido não é consumível — a implementação de backtest da `ITickSource` recusa abri-lo. Quando o backtest roda, a proveniência do arquivo é comparável contra a conta corrente; broker do arquivo diferente do broker da conta não é erro fatal — a cláusula 2 permite a divergência — mas é reportado, não silenciado. A proveniência aparece no rastro de auditoria do backtest, de modo que um resultado possa declarar de qual broker saíram seus dados.

4. **Os flags de tick são preservados.** O MT5 entrega cada tick com flags (`TICK_FLAG_BID`, `TICK_FLAG_ASK`, `TICK_FLAG_LAST`, `TICK_FLAG_VOLUME`, `TICK_FLAG_BUY`, `TICK_FLAG_SELL`) que indicam qual faceta mudou e, em caso de trade, qual lado iniciou. Os seis são gravados no arquivo e preservados no `MksTick` como bitmask `uint`. Descartar qualquer um é destruir dado de auditoria que não se recupera — o builder atual (ADR-010, mid-driven) não consome `BUY`/`SELL`, mas estratégias futuras e a camada de execução podem precisar, e a captura é irreversível. Consequência: o `MksTick` ganha um campo `flags` de tipo `uint` — alteração de tipo do core tratada na seção Consequências.

5. **O formato de armazenamento é binário próprio, com header versionado.** Layout de campos fixo, larguras e ordem de bytes definidas pelo projeto. O determinismo byte-a-byte da leitura — mesmo arquivo produz o mesmo stream de `MksTick`, incluindo `seq` — é uma propriedade do código do próprio framework, não de terceiros. O header inclui um número de versão do formato desde a primeira versão, para que uma futura mudança de layout não quebre arquivos antigos em silêncio. Os detalhes concretos de layout — endianness, magic number, alinhamento, ordem dos campos no header e no registro de tick — são engenharia de dados, não arquitetura, e ficam para o commit do serializador. Esta ADR fixa o contrato (cru, header versionado, flags preservados, broker-locked com proveniência); não fixa o layout.

6. **Captura e consumo são artefatos separados.** A captura de ticks históricos — que toca a rede e o broker — é um script à parte, que escreve o arquivo. O backtest apenas lê o arquivo. São dois artefatos distintos, não dois modos de um mesmo binário. Isso garante a reprodutibilidade offline exigida pela Renko engine: o backtest roda sem conexão ao broker, e o caminho de backtest não tem como tocar a rede.

**Alternativas consideradas:**
- **Limpar os ticks na gravação (arquivo histórico sem ticks inválidos):** rejeitada. O builder em backtest nunca exercitaria a guarda `IsValid()` da ADR-006 que exercita em live — a paridade da guarda viraria ficção. O único ganho seria economia de espaço, irrelevante para o volume de ticks inválidos do XAUUSD. Há ainda o risco de a limpeza confundir tick malformado com tick legitimamente parcial (só `TICK_FLAG_BID` atualizado), descartando dado bom.
- **Broker-locked com paridade incondicional (broker de captura obrigatoriamente igual ao da conta live):** rejeitada como restrição dura. Amarraria o framework a um único broker para sempre — uma troca de broker por razão comercial invalidaria todo o corpus histórico. A cláusula 2 mantém a flexibilidade e move o custo para a disciplina de verificar a condição (cláusula 3), em vez de proibir a divergência.
- **Permitir múltiplos brokers sem mecanismo de proveniência (apenas uma nota declarando a condição):** rejeitada. Uma garantia condicional cuja condição ninguém verifica degrada para nenhuma garantia — foi assim que o eixo 2 do V5 se instalou. O header de proveniência e a comparação em runtime são o que distingue esta opção de uma omissão.
- **Formato CSV:** rejeitada. Ponto flutuante em texto não tem round-trip determinístico garantido sem cuidado de precisão; parsing é lento; arquivo é grande. A única vantagem — legibilidade humana — não compensa o risco ao determinismo byte-a-byte.
- **Formato `.tks` nativo do MT5:** rejeitada. É um formato cuja leitura depende de implementação fechada de terceiro. Se o `.tks` alimenta o builder, código fechado entra no caminho de construção de brick — violação direta do princípio invariante 5 da §1 ("zero dependência de código fechado para construção de bricks Renko").
- **Descartar os flags de tick:** rejeitada. Os flags são informação de auditoria — qual faceta do preço disparou um brick — que não se reconstrói depois. O custo de preservá-los (um campo no `MksTick`) é pequeno e assumido.
- **Captura e consumo no mesmo binário:** rejeitada. Abriria caminho para o backtest tocar a rede, comprometendo a reprodutibilidade offline. A separação física é a garantia.

**Consequências:**
- O contrato de integridade da fonte histórica fica fixado: ticks crus, broker-locked, proveniência rastreável. A `ITickSource` de backtest e o script de captura nascem sob esse contrato.
- **Emenda de tipo do core:** o `MksTick` (`Core/Types/Tick.mqh`, Fase 1) ganha um campo para os flags de tick (bitmask dos `TICK_FLAG_*`). É alteração de um tipo do core já aceito — força recompilação de todo arquivo que o inclui. A alteração do `Tick.mqh` é trabalho à parte, em ciclo próprio, feito após o aceite desta ADR — não antes e não no mesmo commit — seguindo o padrão da ADR-006 (comentários "phantom") e da ADR-011 (campo `thresholdsCrossed`).
- **Dívida de implementação assumida:** o mecanismo de comparação de proveniência em runtime (cláusula 3) toca a implementação da `ITickSource` de backtest e precisa conhecer o broker da conta corrente, o que cruza com a camada de Broker (eixo 3). Esta ADR fixa a obrigação — header obrigatório, comparação reportada, proveniência no rastro de auditoria — mas a implementação do mecanismo é trabalho posterior, registrado aqui como dívida com dono definido: a classe de `ITickSource` de backtest, quando for escrita.
- O `enum ENUM_MKS_ERROR_CODE` (`Error.mqh`) precisará de ao menos um código novo — para arquivo histórico sem header de proveniência válido, e possivelmente para incompatibilidade de versão de formato. A faixa **800–899** fica reservada para o módulo TickSource/Data, dando continuidade ao layout do CHECKPOINT-2026-05-20 §4 (Core 1–99, RenkoBuilder 100–199, Broker 200–299, Trade 300–399, Risk 400–499, StressLab 500–599, Log 600–699, Testing 700–799). Os números exatos dentro da faixa são definidos quando o `ITickSource` de backtest e o serializador forem implementados — esta ADR registra a necessidade sem fixar o número no vazio.
- O serializador/desserializador binário é código novo a manter, e exige teste golden-file próprio: escrever, ler e reescrever produz bytes idênticos.
- Trabalho de aquisição decorrente, fora do escopo desta ADR: definir a origem concreta dos ticks (qual broker para a captura inicial), a estratégia de chunking por volume de dados, e o uso de `CopyTicksRange` com o flag de cópia que preserva todos os ticks. São itens de engenharia de dados, executados sob o contrato que esta ADR fixa.

**Fronteiras:**
- Não é a guarda de validade do tick (ADR-006, aceita) — é a fonte que a ADR-006 pressupõe.
- Não é o desenho do `CMksRenkoBuilder` (ADR-010, ADR-011).
- Não é o módulo de simulação de backtesting — spread, slippage, comissão — que pertence à camada de Broker, eixo 3, decisão futura.

---

### ADR-013: Independência de broker e proveniência no rastro de auditoria

**Data:** 2026-05-20
**Status:** Aceita

**Contexto:**
O MKS-ULTIMATE é, por definição, um framework de trading — não um EA acoplado a um corretor específico. O dono opera atualmente na Exness, mas a expectativa estrutural é que o mesmo motor funcione contra qualquer broker MT5 sem reescrita de código de lógica. Esta expectativa nunca foi enunciada como decisão formal; chega agora ao primeiro ponto em que pode ser violada por omissão.

O Slice 2 do ROADMAP inaugura o consumo de dados reais — `CopyTicksRange` sobre o símbolo do broker conectado. É o primeiro código do projeto que toca infraestrutura de corretor. Sem uma regra fixada, dois padrões erram silenciosamente:

- **Hardcode condicional** — uma cláusula `if (broker == "Exness") {...}` em qualquer ponto de lógica recriaria, em escala menor, o eixo 2 do colapso do V5: múltiplos caminhos de execução sob o mesmo teto, escolhidos por uma propriedade do ambiente em vez da decisão arquitetural. Adicionar um broker novo passaria a exigir edição da lógica.
- **Artefatos sem proveniência** — relatórios, logs, arquivos e outputs gerados pelo framework sem registro de qual broker os produziu. A ADR-012 (proposta) já resolve esse caso para o arquivo binário histórico de ticks; o resto do framework — relatórios do painel Experts, futuros logs estruturados (ADR-007 pendente), saídas de validação de Slice — carece da mesma disciplina.

O ponto de cuidado é distinguir duas perguntas que parecem uma só. *"Como o framework opera contra qualquer broker?"* é a pergunta de arquitetura de runtime — detecção de ambiente, perfil por broker, símbolo canônico, sessões, precisão de pontos. Essa pergunta exige evidência empírica do que de fato varia entre brokers, e a evidência só começa a aparecer depois do Slice 3 (Custom Symbol). Decidir essa estrutura agora é fazer arquitetura no vazio — recusado pela §4 deste documento.

*"Como o framework registra de qual broker vieram seus dados?"* é uma pergunta menor, é resolvível agora, e é a única que o Slice 2 efetivamente atravessa. Esta ADR resolve essa, e somente essa. A pergunta maior fica como dívida explícita com dono e momento definidos.

**Decisão:**
O MKS-ULTIMATE é broker-agnóstico por construção, e todo artefato persistido ou comunicado pelo framework carrega proveniência de execução.

1. **Sem hardcode de broker.** Nenhuma string com identificador de broker — `"Exness"`, `"ICMarkets"`, `"XM"`, ou qualquer outro — aparece em código de lógica do framework: builder, sizer, sink, interfaces do core, classes de trade, risk, ou estratégia. Nenhuma cláusula condicional bifurca comportamento por nome de broker. Variação entre brokers é absorvida exclusivamente por parâmetros injetados — geometria, sizer, símbolo, configuração — nunca por ramo de código.

2. **Símbolo é parâmetro, não constante.** Toda função, classe ou script que opera sobre um instrumento recebe o símbolo como entrada explícita. Default sensato em ponto de borda — por exemplo, `_Symbol` no `OnStart` de um script — é aceito; constante literal `"XAUUSD"` (ou variante) em qualquer ponto de código é vedada.

3. **Todo artefato carrega proveniência.** Saídas do framework — relatórios em painel Experts, logs (formato a ser fixado na ADR-007), arquivos binários (estrutura definida pela ADR-012), CSVs de validação, e qualquer artefato persistido ou comunicado — registram, no mínimo, o tripleto `(broker, account, symbol)`. A proveniência é capturada em runtime, no momento da geração do artefato, não congelada em código.

4. **Aquisição de proveniência em runtime.** O identificador do broker é obtido via `AccountInfoString(ACCOUNT_COMPANY)`. O número da conta via `AccountInfoInteger(ACCOUNT_LOGIN)`. Estes são pontos de borda — usados em logging, headers, relatórios. Não são consultados dentro de lógica de trading, de construção de brick ou de execução de ordem.

5. **Detecção de broker e auto-configuração ficam fora do escopo.** A pergunta arquitetural maior — uma camada que detecta o broker em runtime e expõe perfil estruturado (símbolo canônico, precisão de pontos, sessões válidas, spread esperado, regras de margem e de execução) — não é decidida nesta ADR. É registrada como dívida explícita, a ser enfrentada por nova ADR após o Slice 3 (Custom Symbol), quando o framework tiver evidência empírica do que de fato varia entre brokers. Decidir essa estrutura agora — antes de operar em pelo menos um broker e idealmente comparar contra um segundo — é fazer arquitetura no vazio.

6. **Escopo desta ADR.** Esta decisão fixa a disciplina de não-hardcode e o requisito de proveniência. Não cria tipos, interfaces ou classes novas. Não altera tipos existentes. É uma diretriz que vincula todo código futuro do framework — incluindo o script do Slice 2, que nasce sob ela.

**Alternativas consideradas:**
- **ADR larga definindo `IBrokerEnvironment` e perfis de broker agora:** rejeitada. Decide a estrutura — interface, campos do perfil, ponto de detecção, contrato de auto-configuração — antes de o framework ter rodado em qualquer broker. É arquitetura no vazio, padrão recusado pela §4 deste documento. Sob evidência zero do que varia entre brokers, a decisão tende a fixar exatamente os campos errados.
- **Postergar a questão até o Custom Symbol:** rejeitada. O Slice 2 começa a gerar artefatos imediatamente — relatórios em painel Experts, e logo CSVs e arquivos. Sem a disciplina de proveniência fixada agora, esses artefatos nascem rastreáveis apenas pelo timestamp do commit, e a regra "todo artefato carrega proveniência" entra tarde demais para corrigir o passivo já gerado. A ADR-012, em paralelo, já exige proveniência no arquivo binário de ticks; manter a regra restrita à ADR-012 deixaria os outros artefatos sob disciplina diferente — eixo 2 em outra dimensão.
- **Hardcode tolerado para "o broker atual" com nota de TODO:** rejeitada. Hardcode com TODO é apenas hardcode com prazo indefinido. A primeira vez que a string `"Exness"` entrar em qualquer arquivo do framework, a expectativa de portabilidade já é mentira retroativa.
- **Proveniência opcional ("registrar quando conveniente"):** rejeitada. Garantia condicional cuja condição depende da disciplina momentânea de quem escreve o código degrada para nenhuma garantia — foi assim que o eixo 2 do V5 se instalou. Proveniência obrigatória em todo artefato persistido fecha a porta.

**Consequências:**
- O `ValidateBuilderOnRealTicks.mq5` (Slice 2) nasce sob esta ADR: recebe símbolo via input com default `_Symbol`, e imprime no relatório do painel Experts a tripleta `(broker, account, symbol)` obtida em runtime. Zero strings de broker no código.
- A ADR-012, quando aceita, já registra proveniência no header do arquivo binário — alinhada por construção a esta ADR. A ADR-007 (formato de log estruturado, pendente) herda o requisito de proveniência como campo canônico do log.
- Dívida arquitetural registrada com dono e momento: nova ADR para detecção de broker e perfil estruturado, a ser proposta após o Slice 3 (Custom Symbol), com evidência empírica do que varia entre brokers já em mão.
- Nenhuma alteração em tipos do core. Nenhum código existente precisa ser tocado para retroativamente aderir — o builder, o sizer e os tipos da Fase 1 já não mencionam broker em lugar nenhum.
- Esta ADR é diretriz vinculante para code review: qualquer cláusula condicional que ramifique comportamento por identificador de broker, ou qualquer literal de nome de broker em código de lógica, é defeito a corrigir.

**Fronteiras:**
- Não é a estrutura de detecção e perfil de broker — essa é a dívida registrada na cláusula 5 e na lista de Consequências.
- Não é o contrato de integridade do arquivo histórico — essa é a ADR-012.
- Não é o formato do log estruturado — essa é a ADR-007.

---

### ADR-014: Política de rotação e nomenclatura do arquivo .mksbk

**Data:** 2026-05-21
**Status:** Aceita

**Contexto:**
O Slice 3b inaugura o EA produtor (`Producer.mq5`) — primeiro código do framework que escreve `.mksbk` em runtime, fora de teste. Cada `OnInit` precisa decidir qual arquivo abrir antes de uma linha de motor rodar. Sem regra fixada, três armadilhas se instalam:

1. **Append entre sessões** recria o eixo do `SyncWithExisting` do V5 (`V5-POSTMORTEM` §5 invariante 5): o estado do builder em memória é zerado a cada `OnInit`; reconciliar com o arquivo exigiria reprocessar ticks da janela coberta ou alterar o formato `.mksbk` (v2 com estado serializado). Custo alto, ganho ilusório.

2. **Sobrescrita silenciosa por colisão de timestamp**: dois `OnInit` dentro do mesmo segundo (recompile rápido, restart do terminal) geram o mesmo nome de arquivo. Sem proteção, `FileOpen` em escrita destrói o conteúdo anterior sem aviso.

3. **Duplicação inútil de proveniência**: o header do `.mksbk` já carrega broker, accountLogin, symbol, geometry e brickSizePoints (ADR-012 §3, ADR-013 §3). Carregar a mesma informação no nome do arquivo é redundância; ordenação por timestamp lexicográfico continua trivial sem ela.

A decisão sobre o naming e a política de rotação não pode ficar implícita no código do Producer; precisa ser fixada antes que um segundo EA (ou ferramenta de pós-análise) tenha que decidir o mesmo de novo. O `Producer.mq5` da Slice 3b parte 1 (commit `468206c`) já nasceu sob a forma desta política — esta ADR a formaliza retroativamente, capturando o desenho em vigor.

**Decisão:**
A política de rotação do `.mksbk` no MKS-ULTIMATE assenta sobre três regras: arquivo novo por sessão, naming mínimo com proveniência no header, e guarda explícita contra colisão de nome.

1. **Arquivo novo a cada `OnInit` do produtor.** Cada sessão do EA cria um `.mksbk` próprio. Nenhum modo de append entre sessões. O estado do builder começa zerado em cada `OnInit` — coerente com o invariante 5 do `V5-POSTMORTEM` ("reconstrução de estado é completa ou não acontece"); reconciliação parcial não existe por design.

2. **Naming mínimo: `<symbol>_<YYYYMMDDTHHMMSS>.mksbk`.** Apenas o símbolo e o timestamp da sessão (segundo de `TimeCurrent` no `OnInit`, formato ISO compacto). A proveniência completa (broker, accountLogin, geometry, brickSizePoints) mora no header por ADR-012 §3 / ADR-013 §3 e não é duplicada no nome. Justificativas: (a) o timestamp em largura fixa ordena lexicograficamente por tempo; (b) o nome curto cabe folgado nos limites de path (Windows 260, MQL5 256); (c) ler broker/conta requer abrir o arquivo de qualquer forma — ferramentas de análise consultam o header, não o nome.

3. **Sub-pasta única: `MKS-ULTIMATE\Bricks\`.** Todos os arquivos do produtor moram nessa pasta, sem segmentação por símbolo. Razão: o símbolo já é prefixo do nome de cada arquivo; ordenação por nome agrupa automaticamente. Sub-pasta por símbolo introduziria nível de diretório sem ganho. `FolderCreate("MKS-ULTIMATE")` + `FolderCreate("MKS-ULTIMATE\\Bricks")` antes do primeiro `FileOpen` — MQL5 não cria recursivamente.

4. **Guarda contra colisão de nome.** Dois `OnInit` no mesmo segundo produziriam o mesmo nome. O `CMksBrickFileWriter::Open` recusa abrir se o arquivo já existe (via `FileIsExist`) e devolve o código novo `MKS_ERR_DATA_FILE_EXISTS = 806` (faixa Data, na sequência de 800-805). O Producer, ao receber 806, tenta novamente com sufixo numérico — `<base>_2.mksbk`, `<base>_3.mksbk`, … — até encontrar nome livre ou esgotar tentativas razoáveis (limite de implementação a fixar no Producer). Granularidade de segundos no timestamp é mantida; o sufixo cobre o resto.

5. **Sem limpeza automática de arquivos antigos.** Retenção é política operacional, não do framework. Arquivos antigos ficam no disco até que o operador remova manualmente. Fora do escopo desta ADR.

**Alternativas consideradas:**

- **Append entre sessões (continuação do `.mksbk` anterior):** rejeitada. Reconciliação parcial recria o eixo do `SyncWithExisting` do V5. O builder em memória começa em estado zero a cada `OnInit`; reconstruir a partir do arquivo exigiria reprocessar a janela de ticks coberta ou estender o formato (v2) para carregar estado interno do builder (formingHigh, formingLow, lastDirection, lastClose). Custo alto, ganho ilusório — restart é evento raro e o histórico fica preservado em arquivo próprio.

- **Naming completo com brokerSlug + accountLogin no nome (`<symbol>__<broker>_<account>__<TS>.mksbk`):** rejeitada. Duplica informação que o header já carrega (ADR-012 §3, ADR-013 §3). Toda ferramenta que precisa de proveniência tem de abrir o arquivo de qualquer modo — o ganho de "ver no nome" não compensa o custo de nome longo, com riscos de normalização (caracteres inválidos no `ACCOUNT_COMPANY`, truncamento, slug instável entre sessões). Nome curto e header completo é o desenho cumulativamente menos frágil.

- **Granularidade de milissegundos no timestamp:** rejeitada. Ruído visual sem ganho real; a colisão de segundo é resolvida com mais segurança pela guarda explícita (regra 4) que pelo aumento de precisão — que apenas torna a colisão mais rara sem eliminá-la.

- **Sub-pasta por símbolo (`MKS-ULTIMATE\<symbol>\`):** rejeitada. O símbolo já é prefixo do nome do arquivo; sub-pasta replica segmentação que o naming já oferece. Mais um nível de diretório para criar e navegar, sem benefício prático.

- **Permitir sobrescrita silenciosa (`FileOpen` em modo write puro):** rejeitada. Destruir dado de sessão anterior sem aviso é o tipo de comportamento implícito que o projeto recusa. O check `FileIsExist` + erro 806 + retry com sufixo torna a guarda explícita e a recuperação automática.

- **Limpeza automática de arquivos antigos (idade ou contagem):** rejeitada como escopo desta ADR. Política de retenção é decisão operacional, não arquitetural — uma sessão pode ser preciosa (validação de paridade, análise post-mortem) e outra pode ser lixo. O framework não decide isso.

**Consequências:**

- **Producer.mq5 nasce simples:** cada sessão é autocontida. Sem recuperação de estado entre sessões. Sem leitura de arquivo anterior no `OnInit`.

- **Continuidade visual entre sessões** (chart do Custom Symbol) fica como questão aberta. Quando o usuário reinicia o EA, o Custom Symbol da sessão atual usa apenas os bricks da sessão atual. Plotar histórico mais longo exige (a) replay de `.mksbk` anteriores via ferramenta separada, ou (b) acionar `InpHistoricalFillDays` para o Producer reconstruir N dias de bricks no `OnInit`. Trade-off aceito.

- **Novo código de erro `MKS_ERR_DATA_FILE_EXISTS = 806`** no enum `ENUM_MKS_ERROR_CODE` (`Error.mqh`), faixa Data (ADR-012 reservou 800-899).

- **`CMksBrickFileWriter::Open`** ganha guarda `FileIsExist` antes do `FileOpen` — alteração de código já aceito (ADR-012), feita em trabalho à parte após o aceite desta ADR, no padrão das ADRs anteriores (ADR-006 sobre comentários "phantom", ADR-011 sobre `thresholdsCrossed`, ADR-012 sobre `Tick.flags`).

- **`Producer.mq5`** implementa o retry com sufixo numérico ao receber 806. Limite de tentativas (ex.: 99) registrado como detalhe de implementação, não-arquitetural.

- **Recuperação de estado em restart do EA** fica registrada como dívida arquitetural conhecida — esta ADR a empurra deliberadamente para o futuro. Quando virar problema concreto (operação contínua com restarts frequentes), nova ADR enfrenta a questão; até lá, a política de "arquivo novo, builder zerado" é a regra.

**Fronteiras:**

- Não é o formato binário do `.mksbk` — ADR-012 §5 fixou o contrato; layout concreto vive em `Core/Data/BrickFileFormat.mqh`.
- Não é o contrato de integridade do arquivo histórico — ADR-012.
- Não é o naming do Custom Symbol — decisão de implementação do Producer, sem ADR. Variação no naming do Custom Symbol não fere esta ADR.

---

### ADR-015: Strategy Tester nativo como ferramenta, não fonte de verdade

**Data:** 2026-05-21
**Status:** Aceita

**Contexto:**
O Strategy Tester nativo do MT5 é feature central da plataforma: oferece três modos de geração de ticks (every tick, every tick based on real ticks, 1 minute OHLC), otimização genética, walk-forward, visualização do backtest com trades sobre o gráfico, integração com MQL5 Cloud Network para paralelização, e o handler `OnTester` para devolver métrica customizada. O ecossistema MQL5 trata o tester como o caminho padrão de backtest e otimização — qualquer EA novo, a expectativa default é "rode no tester".

O MKS-ULTIMATE escolheu, na ADR-012, gravar ticks crus em arquivo `.mksbk` (e, na nomenclatura desta sessão, em arquivo de captura de ticks separado a ser definido) e ler de volta via `ITickSource` para backtest. Essa decisão implica que **o tester nativo não é a fonte de verdade do backtest deste projeto**. Mas essa implicação nunca foi enunciada como decisão formal — vive escondida na ADR-012 (que fala de fonte de dados, não do papel do tester) e no princípio norteador do `Projeto.md` (paridade backtest/live bit-a-bit). A primeira estratégia que for construída vai disparar a pergunta inevitável: "se o tester roda com real ticks, qual o problema de usá-lo?". A resposta precisa estar pronta, registrada, defensável — não improvisada.

Esta ADR resolve a pergunta antes dela ser feita.

**Decisão:**
O Strategy Tester nativo do MT5 é usado no MKS-ULTIMATE **como ferramenta de desenvolvimento e visualização**, nunca como fonte de verdade para mérito de estratégia.

1. **Backtest oficial roda fora do tester.** A execução canônica do backtest é um Script ou Service (`MQL5/Scripts/` ou `MQL5/Services/`) que instancia o composition root do framework com `ITickSource` apontando para arquivo de captura. Nenhum resultado de tester é citado em commit message, em CHANGELOG, em entrega de release ou em comparação de fitness entre estratégias.

2. **Tester aceito para uso instrumental.** É permitido — e às vezes útil — rodar um EA no tester para:
   - **Visualização** do comportamento da estratégia sobre o gráfico (debug visual rápido).
   - **Smoke test** antes de capturar um arquivo de ticks longo.
   - **Apresentação** ao dono ou stakeholders.

   Em todos esses casos, o output do tester é **descartável** — não vira métrica de release.

3. **Sem bifurcação de lógica via `MQLInfoInteger(MQL5_TESTING)`.** A REGRAS §1.7 já proíbe isso e o Protocolo 9 reforça. Esta ADR fixa o complemento positivo: o EA nem sabe se está rodando no tester ou em live; o caminho de código é único. Eventualmente, configuração de logger pode ser ajustada via input para reduzir verbosidade em backtest longo — mas isso é configuração de output, não bifurcação de lógica de trading.

4. **Métricas vêm do framework, não do report do tester.** Sharpe ratio, drawdown, profit factor, trade count e equivalentes são computados por código próprio sobre o stream de `MksExecutionResult` produzido pelo backtest. O HTML report do tester é tolerado para inspeção rápida; nunca é a fonte autoritativa.

5. **Otimização de parâmetros é trabalho futuro, fora do escopo das Fases 0–4.** Quando virar problema real (provavelmente Fase 10 ou depois), será implementada pelo framework próprio — não delegada ao optimizer do tester. Isso porque o optimizer do tester usa o engine de backtest do tester, que esta ADR rejeitou como fonte de verdade.

**Alternativas consideradas:**

- **Usar Strategy Tester como fonte de verdade do backtest:** rejeitada. Três razões empilhadas — (a) o tester depende do modo de geração de ticks escolhido, e cada modo produz resultado diferente para o mesmo período; (b) o `.tks` que alimenta o tester é arquivo da MetaQuotes, formato fechado, sujeito a evolução não-documentada entre builds do terminal; (c) o V5 usou o tester como fonte de verdade e o eixo 2 do colapso entrou exatamente por essa porta — múltiplos produtores de bricks (tester com OHLC vs. live com ticks) gerando sequências diferentes para o mesmo intervalo.

- **Híbrido — tester para alguns cenários, framework para outros:** rejeitada. Mistura de métricas vira soup intratável: cada comparação fica dependente de "qual engine produziu este número". Disciplina binária — tester como ferramenta, framework como fonte de verdade — é mais simples de defender e de auditar. Erro de classificação é tipo "olhei o número do tester como se fosse oficial" — fácil de detectar e corrigir; erro de mistura é tipo "metade do relatório veio de A e metade de B" — invisível até dar problema.

- **Adiar a decisão para Fase 9 (validação end-to-end):** rejeitada. A primeira estratégia que rodar — provavelmente bem antes da Fase 9 — vai disparar a pergunta. Decidir sob pressão de timeline ou de resultado é decidir mal. Decidir agora, no calmo, com o post-mortem do V5 fresco e os custos do tester já mapeados, é mais barato.

**Consequências:**

- **Framework reconstrói capabilities que o tester oferece.** Engine de backtest (parcialmente pronto: `ITickSource` + builder + sinks), reporter de métricas (pendente — Sharpe, drawdown, profit factor, equity curve), visualização (pendente). Cada um vira slice próprio do roadmap.

- **Custo aceito de não ter otimização barata.** O tester com MQL5 Cloud Network paraleliza otimização gratuitamente; o framework não. Quando otimização for necessária, será implementação própria — provavelmente fora do MT5, como pipeline em outra linguagem que consome arquivo de captura e itera sobre o framework. Trabalho substancial, registrado como dívida explícita.

- **ADR-018 (cálculo do ATR) herda restrição.** A alternativa (c) da ADR-018 — usar `iATR` nativo — fica vetada por esta ADR: `iATR` em backtest depende das séries que o tester injeta, e o framework rejeita o tester como fonte de verdade. ADR-018, quando for decidida, escolhe entre (a) cálculo próprio sobre ticks ou (b) cálculo próprio sobre bricks fechados.

- **Documentação operacional ajusta.** `docs/PROTOCOLOS.md` Protocolo 2 ("Antes de rodar um EA em backtest pela primeira vez") tem o item "Qualidade de dados do MT5 verificada (ideal: 'Every tick based on real ticks')" — refere ao tester. Não fere esta ADR (uso instrumental é aceito), mas o protocolo ganha item adicional: "se o backtest é para release, foi rodado também via framework (arquivo de captura + script de replay), e os números do release vieram do framework, não do tester". Atualização do PROTOCOLOS é trabalho à parte, após o aceite desta ADR.

- **Tom do projeto preservado.** O MKS-ULTIMATE não é hostil ao tester — usa quando faz sentido. É hostil a tratar o tester como gold standard.

**Fronteiras:**

- Não é a arquitetura do engine de backtest próprio — trabalho de slices futuros (4, 5 ou Fase 7).
- Não é o formato dos relatórios de release — decisão futura, possivelmente acoplada à ADR-007 (logger).
- Não é o contrato de integridade dos arquivos de dados — esse é a ADR-012 (ticks) e a ADR-014 (bricks `.mksbk`).
- Não é sobre como capturar ticks crus em produção — esse é trabalho de Service futuro em `MQL5/Services/`.

---

## 4. Decisões pendentes

Pontos que precisam virar ADR assim que forem enfrentados:

- **ADR-005 (pendente):** Estrutura e execução dos testes unitários. Framework próprio mínimo ou adaptação de algo existente?
- **ADR-007 (pendente):** Formato do log estruturado. JSON-line ou key=value? Volume de log esperado em live vs custo de parsing.
- **ADR-008 (pendente):** Como tratar reabertura de mercado (segunda-feira) no RenkoBuilder. Gap vira brick? Vira múltiplos bricks? Vira nada? Evidência parcial já registrada em `CHECKPOINT-2026-05-20-slice2.md` §6.
- **ADR-016 (pendente):** Interfaces `ISymbol` e `IAccount` + checklist de chamadas API globais proibidas em código de lógica (ver Protocolo 9 em `PROTOCOLOS.md`). Hoje a porta está fechada por convenção — ADR-013 §2 só permite chamadas globais na borda (composition root em `OnInit`/`OnTick`/`OnDeinit`). Precisa virar contrato testável antes de `CMksTradeManager`/`CMksRiskManager`/estratégias serem escritas.
- **ADR-017 (pendente):** Modelo de confirmação de execução do `CMksMt5Broker`. Síncrono via retcode do `OrderSend` ou assíncrono via `OnTradeTransaction::TRADE_TRANSACTION_DEAL_ADD`? Decide latência vs. fidelidade de `fillPrice`/`slippage`. Inclui também política de filling mode (FOK/IOC/RETURN via `SymbolInfoInteger(SYMBOL_FILLING_MODE)`), uso de `OrderCheck`, e diferença netting vs. hedging. Bloqueia Fase 4 (Broker abstractions).
- **ADR-018 (pendente):** Cálculo do ATR no `CMksAtrBrickSizer`. Três alternativas: (a) ATR sobre ticks brutos, cálculo próprio; (b) ATR sobre bricks fechados (coerente com filosofia "decisão pós-brick é sobre bricks"); (c) `iATR` nativo (reintroduz dependência do tester, contra ADR-015 quando aceita). ADR-010 §Consequências adiou explicitamente.

Essas decisões são registradas formalmente quando forem enfrentadas, não antes. Decidir arquitetura no vazio produz decisões erradas.

## 5. Convenções de nomenclatura

Sistema de prefixos do framework, vinculante para todo código em `MQL5/Include/MKS-ULTIMATE/`:

| Prefixo | Aplica-se a | Exemplos |
|---|---|---|
| `I` | Interfaces (classe abstrata com virtuais puros — ADR-004) | `IBroker`, `IClock`, `ITickSource`, `ILogger`, `IRenkoSink` |
| `CMks` | Classes concretas com estado e ciclo de vida | `CMksRenkoBuilder`, `CMksTradeManager`, `CMksMt5Broker` |
| `Mks` | Structs e tipos primitivos sem ciclo de vida (POD) | `MksTick`, `MksBrick`, `MksOrderRequest`, `MksExecutionResult` |

O prefixo identifica de relance, no ponto de uso, **qual contrato cada identificador representa**: contrato puro (`I*`), unidade com estado (`CMks*`), ou valor passável por cópia/referência (`Mks*`). A distinção entre `CMks*` e `Mks*` está alinhada à divisão entre classes e structs do MQL5 — classes têm identidade, structs têm valor.

Enums internos do framework usam o prefixo `ENUM_MKS_` (ex.: `ENUM_MKS_BRICK_DIR`, `ENUM_MKS_ORDER_SIDE`), seguindo a convenção do próprio MQL5 para enums (`ENUM_TIMEFRAMES`, etc.). Constantes de enum têm o prefixo `MKS_` sem o `ENUM_` (ex.: `MKS_BRICK_BULL`, `MKS_ORDER_BUY`).

## 6. Como este documento evolui

- Nova ADR é adicionada ao final da seção 3, com número sequencial.
- ADRs antigas **não são editadas** após aceitas — apenas recebem status novo se substituídas.
- A estrutura de diretórios (seção 2) é atualizada quando a realidade do projeto muda.
- Seção de decisões pendentes (seção 4) serve de fila de trabalho arquitetural.
- Mudanças significativas geram entrada no `CHANGELOG.md` com categoria apropriada.

Arquitetura é um livro-razão, não um manifesto.
