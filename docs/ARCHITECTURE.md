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
│   └── Scripts/                    # Scripts utilitários
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

## 4. Decisões pendentes

Pontos que precisam virar ADR assim que forem enfrentados:

- **ADR-005 (pendente):** Estrutura e execução dos testes unitários. Framework próprio mínimo ou adaptação de algo existente?
- **ADR-006 (pendente):** Tratamento de phantom bars no `RenkoBuilder`. Ignorar, marcar como suspeito, ou interromper?
- **ADR-007 (pendente):** Formato do log estruturado. JSON-line ou key=value? Volume de log esperado em live vs custo de parsing.
- **ADR-008 (pendente):** Como tratar reabertura de mercado (segunda-feira) no RenkoBuilder. Gap vira brick? Vira múltiplos bricks? Vira nada?

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
