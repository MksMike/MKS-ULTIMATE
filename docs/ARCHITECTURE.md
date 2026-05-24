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
│   │   │   ├── Interfaces/         # IBroker, ITickSource, IClock, ILogger, IRenkoSink, IBrickSizer, IPositionBook
│   │   │   ├── Types/              # Tick, Brick, OrderRequest, ExecutionResult, Error, RenkoGeometry
│   │   │   ├── RenkoBuilder/       # CMksRenkoBuilder, sizers (Fixed, Atr)
│   │   │   ├── Data/               # BrickFileFormat, TickFileFormat, CMksBrickFile/TickFile Writer/Reader, CMksFileTickSource
│   │   │   ├── Clock/              # CMksMt5Clock (live), CMksReplayClock (replay)
│   │   │   ├── Symbol/             # CMksMt5Symbol (impl de ISymbol)
│   │   │   ├── Account/            # CMksMt5Account (impl de IAccount), CMksAccountSnapshot
│   │   │   ├── Position/           # CMksMt5PositionBook (impl de IPositionBook)
│   │   │   ├── Broker/             # CMksMt5Broker, CMksSimulatedBroker, CMksCostModel
│   │   │   ├── Trade/              # CMksPositionSizer (Fixed/PercentRisk), CMksTradeManager (BE+Trail+Partial), CMksTradeJournal (diário de trades + agregados)
│   │   │   ├── Risk/               # CMksRiskManager (Por Trade + Estratégia + Conta), CMksRiskGatedBroker
│   │   │   ├── Log/                # CMksLogger (logging estruturado)
│   │   │   └── Testing/            # Framework mínimo de asserções
│   │   └── StressLab/              # CMksRandom (RNG seedável), CMksStressParams (presets None/Light/Medium/High/Nightmare), CMksStressLabBroker (wrapper IBroker injetando slippage/rejection/requote), CMksStressLabReport (snapshot agregado + PrintComparison)
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

### ADR-018: Cálculo do ATR no CMksAtrBrickSizer

**Data:** 2026-05-21
**Status:** Aceita

**Contexto:**
A ADR-010 desenhou o eixo de tamanho do brick como interface `IBrickSizer` e listou `CMksAtrBrickSizer` como implementação futura, com "a cadência de recálculo do tamanho por ATR — travado por sessão, por N bricks ou por brick — fica adiada para quando o `CAtrBrickSizer` for construído".

A auditoria MQL5 (Risco 6, integrada em `4756e8e`) reabriu a discussão e identificou três alternativas técnicas para o cálculo:

- **(a)** ATR sobre ticks brutos, cálculo próprio.
- **(b)** ATR sobre bricks fechados, cálculo próprio.
- **(c)** `iATR` nativo do MQL5, com fallback para arquivo histórico em backtest.

A ADR-015 vetou (c) — `iATR` em backtest depende das séries que o Strategy Tester injeta, e o framework rejeita o tester como fonte de verdade. Resta decidir entre (a) e (b), e também a forma da interface `IBrickSizer` (que hoje não permite ao sizer receber feedback do builder).

**Decisão:**
O ATR no MKS-ULTIMATE é calculado sobre **bricks fechados**, com a interface `IBrickSizer` estendida para receber notificação do builder a cada brick emitido.

1. **ATR sobre bricks fechados (alternativa b).** O `CMksAtrBrickSizer` acumula uma janela rolante dos últimos N bricks fechados e calcula o ATR clássico (Wilder's smoothing) sobre essa janela. `SizePoints()` retorna `ATR_derived * multiplier`, com clamp opcional em `[minSizePoints, maxSizePoints]`.

2. **`IBrickSizer` ganha método `OnBrick`.** Adição na interface, em respeito à ADR-004 (pure virtual):

   ```
   virtual void OnBrick(const MksBrick &brick) = 0;
   ```

   - `CMksFixedBrickSizer` implementa como no-op (corpo vazio) — size é constante, sem feedback necessário.
   - `CMksAtrBrickSizer` implementa como recálculo da janela e do ATR.

   Builder chama `m_sizer.OnBrick(brick)` imediatamente após cada `EmitBrick`. Mudança no `CMksRenkoBuilder` é pequena (1 linha).

3. **Cadência de recálculo: por brick.** A cada brick emitido, o sizer atualiza o ATR. Custo de CPU é trivial (janela de N bricks com smoothing constante). Sem rate-limiting nem otimização prematura.

4. **Warm-up: `SizePoints` retorna `defaultSizePoints` até acumular N bricks.** O `CMksAtrBrickSizer` recebe `defaultSizePoints` no construtor (ex.: 3.0). `IsReady()` retorna `true` **desde o início**. Antes de acumular N bricks, `SizePoints` retorna o default. A partir do N-ésimo brick, retorna `ATR_derived * multiplier`.

   Razão para `IsReady=true` desde o primeiro tick: o builder atual NÃO emite bricks enquanto `sizer.IsReady()==false` (`Core/RenkoBuilder/CMksRenkoBuilder.mqh`, linha 150). Se ATR sizer retornasse `false` durante warm-up, deadlock — não emite brick → sizer nunca recebe brick → nunca fica pronto.

5. **Fórmula: Wilder's smoothing.** `ATR_n = (ATR_{n-1} * (N-1) + TR_n) / N`, onde `TR_n = max(high - low, |high - prev_close|, |low - prev_close|)` sobre o brick atual. Wilder é o ATR clássico (formulação de J. Welles Wilder em "New Concepts in Technical Trading Systems", 1978). Simple MA do TR é alternativa rejeitada — Wilder é mais responsivo a movimentos recentes sem o efeito de "drop-off" da SMA quando uma observação grande sai da janela.

6. **Parâmetros do construtor:**
   - `atrPeriod`: N (default sugerido 14 bricks — convenção).
   - `multiplier`: fator sobre o ATR (default sugerido 0.5 — brick size = metade do ATR; valores típicos 0.3 a 1.0).
   - `defaultSizePoints`: fallback durante warm-up.
   - `minSizePoints`, `maxSizePoints`: clamps opcionais (defaults 0 e infinito).

**Alternativas consideradas:**

- **(a) ATR sobre ticks brutos:** rejeitada. Conceitualmente forçada — "high" e "low" são pontuais em ticks, sem analogia direta com ATR clássico. Implementação requer `IBrickSizer.OnTick(MksTick&)` — interface mais larga, custo de CPU por tick (vs. por brick), e a resultante "ATR de ticks" não é grandeza padrão da literatura. Sobre bricks, ATR é coerente com Renko: "toda decisão pós-brick é sobre bricks".

- **(c) `iATR` nativo:** vetada pela ADR-015. `iATR` em backtest depende das séries injetadas pelo Strategy Tester, e o framework rejeita o tester como fonte de verdade. Implementação ficaria sujeita a dependência oculta do tester.

- **Cadência por sessão (travado no `OnInit`):** rejeitada. Mata a adaptabilidade do ATR — perde o ponto de ter sizer dinâmico. Útil apenas se o objetivo for "ATR como inicialização one-shot", o que não é o caso aqui.

- **Cadência por janela (recalcula a cada M bricks, M > 1):** rejeitada. Otimização prematura — CPU de recalcular ATR a cada brick é desprezível. Adiciona complexidade sem ganho mensurável.

- **Simple MA do TR (vs. Wilder's):** rejeitada. SMA é mais lenta a reagir e tem efeito de "drop-off" quando uma observação grande sai da janela. Wilder é o padrão da literatura para ATR.

- **Sizer também implementa `IRenkoSink` (recebe bricks como sink):** rejeitada. Acoplamento confuso — sizer ficaria conectado a duas cadeias (builder via `SizePoints`; multiSink via `OnBrickClose`). E MQL5 não suporta herança múltipla. Método `OnBrick` direto em `IBrickSizer` é mais limpo.

- **`IsReady=false` durante warm-up, builder espera:** rejeitada. Causaria deadlock — sem bricks emitidos, sizer nunca acumula janela, nunca fica pronto. `defaultSizePoints` + `IsReady=true` quebra o ciclo determinismticamente.

**Consequências:**

- **`IBrickSizer` ganha `OnBrick(const MksBrick&)` como pure virtual.** Alteração de interface do core já aceita (ADR-010). `CMksFixedBrickSizer` (já existente) ganha implementação no-op. Recompilação obrigatória de arquivos que incluem `IBrickSizer.mqh`. Alteração feita em ciclo próprio após este aceite, padrão das ADRs anteriores.

- **`CMksRenkoBuilder.mqh` chama `m_sizer.OnBrick(brick)`** após cada `EmitBrick`. Alteração pequena (1 linha em `EmitBrick` ou no caller, dependendo da abordagem).

- **`CMksAtrBrickSizer` em `Core/RenkoBuilder/CMksAtrBrickSizer.mqh`** — nova classe. Implementação pendente, em slice próprio. Inclui janela rolante de N bricks, cálculo de TR e ATR Wilder, `SizePoints` com fallback warm-up, `Validate` checando parâmetros.

- **Teste de regressão do `CMksFixedBrickSizer`:** adição do `OnBrick` no-op não muda comportamento. `Test_CMksRenkoBuilder.mq5` (428 assertions) deve continuar verde após a alteração da interface.

- **Determinismo preservado.** ATR sobre bricks é função pura da sequência de bricks. Sequência de bricks é função pura da sequência de ticks (ADRs 010/011/006). Logo, ATR é função pura dos ticks — paridade backtest/live mantida.

- **Path dependence aceita.** ATR drift muda size que muda formação do próximo brick. Sistema é path-dependent, mas determinístico: mesma sequência de ticks gera a mesma sequência completa (bricks + ATR + sizes), sempre.

- **Warm-up determinístico.** Os primeiros N bricks usam `defaultSizePoints` fixo, depois o sizer transita para `ATR_derived`. Transição é por contagem de bricks, não por tempo — reprodutível.

**Fronteiras:**

- Não é a implementação concreta do `CMksAtrBrickSizer` — slice próprio.
- Não é a escolha de defaults numéricos (`atrPeriod=14`, `multiplier=0.5`) como vinculantes — são sugestões; cada estratégia escolhe os seus.
- Não é o conceito de "sizer dinâmico" em geral — esta ADR cobre só ATR. Outros sizers dinâmicos (baseados em volume, sessão, volatilidade realizada) ficam para ADRs futuras se forem necessários.

---

### ADR-017: Modelo de confirmação de execução do broker

**Data:** 2026-05-22
**Status:** Aceita

**Contexto:**
A interface `IBroker` foi definida na Fase 1 com três métodos síncronos — `Send`, `Close`, `Modify` — retornando `MksExecutionResult`. O tipo já carrega `status`, `fillPrice`, `requestedPrice`, `filledLots`, `commission`, `execTimeMsc`, `brokerRetcode`. O que falta decidir, antes de escrever `CMksMt5Broker` e `CMksSimulatedBroker`, é o **modelo de confirmação** — o conjunto de regras de comportamento que faz a interface síncrona funcionar contra uma API MQL5 que tem confirmação parcialmente assíncrona, contra fillings que variam entre brokers, e contra contas que podem ser netting ou hedging.

A API MQL5 expõe duas vias de confirmação para uma ordem (`docs.mql5.com/en/docs/trading/ordersend`, `docs.mql5.com/en/docs/event_handlers/ontradetransaction`):

- **Síncrona via `OrderSend`** — retorna `bool` + `MqlTradeResult`. `result.retcode` reflete o status no momento do retorno. `TRADE_RETCODE_DONE` em ordem a mercado geralmente significa "preenchida", mas não universalmente.
- **Assíncrona via `OnTradeTransaction`** — evento `TRADE_TRANSACTION_DEAL_ADD` é o único momento canônico em que sabemos que o deal foi executado, com `deal_ticket` recuperável e `DEAL_PRICE`/`DEAL_VOLUME`/`DEAL_COMMISSION`/`DEAL_SWAP` legíveis via `HistoryDealGetDouble`.

Sem fixar como o broker do framework reconcilia essas duas vias, o `CMksMt5Broker` nasce com comportamento ambíguo: a estratégia chama `Send` e recebe um `MksExecutionResult` — esse resultado vem do retcode imediato (rápido, mas pode mentir sobre preenchimento de fato) ou da espera por `DEAL_ADD` (mais lento mas correto)? Adicionalmente, três outros eixos têm armadilhas conhecidas e precisam de política fixada:

- **Filling mode** (`SYMBOL_FILLING_MODE`) varia por broker. `INVALID_FILL` (retcode 10030) é rejeição garantida se o tipo solicitado não está no bitmask do símbolo.
- **Margin mode** (`ACCOUNT_MARGIN_MODE`): netting fecha por ordem oposta; hedging exige `MqlTradeRequest.position = ticket`. Tratar errado faz "posições sumirem" do ponto de vista do EA.
- **Retcodes retryable** (REQUOTE 10004, PRICE_CHANGED 10020, PRICE_OFF 10021) merecem nova tentativa; outros (NO_MONEY, TRADE_DISABLED, INVALID_VOLUME) são fatais.

Esta ADR fixa o modelo antes do código nascer com convenções tácitas. Não escreve o `CMksMt5Broker` — fixa as regras dele.

**Decisão:**
O `CMksMt5Broker` (real) e o `CMksSimulatedBroker` (futuro) compartilham um modelo de confirmação único, organizado em sete regras.

1. **`Send`/`Close` são síncronos lógicos.** A interface `IBroker` permanece síncrona: a estratégia chama `Send(request)`, espera o resultado, segue. Internamente, o `CMksMt5Broker` chama `OrderSend` e então **bloqueia até `OnTradeTransaction` reportar `TRADE_TRANSACTION_DEAL_ADD` para o deal correspondente, ou até atingir o timeout**. O resultado retornado carrega o preço executado real lido via `HistoryDealGetDouble(deal_ticket, DEAL_PRICE)`, não o `result.price` do `OrderSend` síncrono (que pode ser estimativa).

   Razões: (a) `IBroker` é o mesmo contrato em backtest, onde a confirmação é trivialmente síncrona — manter síncrono em live preserva paridade; (b) preço real só é confiável após `DEAL_ADD` (a race entre `OrderSend` e o evento é documentada); (c) estratégia que aciona `Send` e segue agindo antes de saber o resultado introduz não-determinismo que mata paridade backtest/live.

2. **Broker é per-símbolo.** `CMksMt5Broker` recebe `ISymbol*` e `IAccount*` no construtor; opera **um único símbolo**. EA chart-bound (caso de uso atual e previsto) instancia um broker por símbolo no composition root. Broker multi-símbolo é trabalho futuro, fora desta ADR.

3. **Timeout configurável, default 5 segundos.** Se `DEAL_ADD` não chega dentro do timeout, `Send` retorna `MksExecutionResult` com `status = MKS_EXEC_ERROR` e `brokerRetcode = MKS_ERR_BROKER_TIMEOUT` (novo código na faixa Broker 200–299). O builder de ordens **não retenta automaticamente em timeout** — é fatal para a chamada corrente. Estratégia decide se chama novamente.

4. **Filling mode pré-detectado + fallback no primeiro `INVALID_FILL`.** No `Init()`, o broker lê `m_symbol.FillingMode()` (bitmask) e escolhe o tipo preferido por ordem de preferência configurável (default `IOC → FOK → RETURN`). Cache do filling efetivo no broker. Se o broker do corretor mente sobre o bitmask e devolve `INVALID_FILL` (retcode 10030) na primeira ordem, o broker **regrida na escala** (próximo filling do bitmask) e retenta uma vez. Após esse fallback bem-sucedido, o filling efetivo é cacheado e usado dali em diante.

5. **Margin mode handling dual.** No `Init()`, o broker lê `m_account.MarginMode()`. `Close(positionId, lots)`:
   - **Netting** (`ACCOUNT_MARGIN_MODE_RETAIL_NETTING` ou `EXCHANGE`): envia ordem oposta de `lots` no mesmo símbolo. Campo `MqlTradeRequest.position` ignorado.
   - **Hedging** (`ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`): envia ordem oposta de `lots` com `MqlTradeRequest.position = positionId`. Necessário para fechar a posição específica.

   `Send` (abertura) é idêntico nos dois modos.

6. **Retry interno para retcodes retryable.** Lista: `TRADE_RETCODE_REQUOTE` (10004), `TRADE_RETCODE_PRICE_CHANGED` (10020), `TRADE_RETCODE_PRICE_OFF` (10021). Política default: **3 tentativas, backoff de 100ms entre elas**. Configurável no construtor. Camada superior (`CMksTradeManager`, estratégia) recebe apenas o resultado final — sucesso ou último erro. Retcodes não-retryable (NO_MONEY, TRADE_DISABLED, MARKET_CLOSED, INVALID_*) retornam imediatamente.

7. **`deviation` default = 10 points, configurável.** Nunca enviar `deviation=0` (pode ser rejeitado em alguns brokers; janela zero é hostil em mercados voláteis). O valor é definido por símbolo no construtor; estratégia não toca esse parâmetro diretamente — é configuração do broker.

8. **`CostModel` como classe separada.** Em `Core/Broker/CMksCostModel.mqh`. Para o broker real, é **passthrough** — comissão e swap vêm de `HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION/DEAL_SWAP)`. Para o broker simulado, é um modelo gerador: spread em points (fixed ou floating distribution), commission_per_lot, slippage como distribuição (uniform ou normal), swap_long/swap_short por noite. `MksExecutionResult` carrega o resultado de qualquer um dos dois — broker upstream não distingue.

**Alternativas consideradas:**

- **`IBroker` assíncrono — `Send` retorna imediato; estratégia consome eventos de fill via callback ou polling:** rejeitada. Assincronicidade quebra paridade backtest/live (backtest não tem race) e empurra complexidade para a estratégia. O custo síncrono (alguns ms aguardando `DEAL_ADD`) é aceitável para o caso de uso atual — uma estratégia faz poucas ordens por sessão, não é HFT.

- **`OrderSend` síncrono puro — confiar em `result.retcode` e `result.price` sem aguardar `OnTradeTransaction`:** rejeitada. Documentação MQL5 e prática consolidada do ecossistema indicam que `DEAL_ADD` é o evento canônico de fill. Confiar em `result.price` cru produz `MksExecutionResult.fillPrice` que pode divergir do `DEAL_PRICE` real, especialmente em condições de spread variável ou Market execution.

- **`OrderSendAsync` exclusivamente:** rejeitada. Faz sentido para HFT/multi-símbolo, não para o caso de uso atual. Mantém a complexidade alta sem retorno.

- **Broker multi-símbolo (`Send(request, symbol)`):** rejeitada para v1. Adiciona parâmetro a cada chamada e complica a injeção de `ISymbol*`. Single-symbol broker cobre 100% dos casos previstos até a Fase 9 (EA de validação).

- **Retry global sem política configurável (hardcoded 3 tentativas):** rejeitada. Diferentes estratégias têm tolerâncias diferentes — uma estratégia de breakout pode tolerar 0 retries (preço se moveu, oportunidade passou), uma estratégia de mean reversion pode tolerar 5. Política no construtor permite ajuste por estratégia.

- **`MksExecutionResult` separado por tipo (FillReport vs RejectReport):** rejeitada. O tipo atual já tem `status` que discrimina FILLED/PARTIAL/REJECTED/ERROR. Tipos separados duplicariam código sem ganho.

- **Filling mode tentando ordem real em vez de pré-detectar:** rejeitada. Pré-detecção (via `SYMBOL_FILLING_MODE` no `Init`) tem custo zero e evita uma rejeição garantida no caminho feliz. Fallback fica para o caso em que o broker mente sobre o bitmask — minoritário.

**Consequências:**

- **Novos códigos de erro na faixa Broker (200–299, reservada por ADR-009):**
  - `MKS_ERR_BROKER_TIMEOUT = 200` — `DEAL_ADD` não chegou no tempo configurado.
  - `MKS_ERR_BROKER_INVALID_FILL = 201` — todos os filling modes do bitmask falharam (caso patológico).
  - `MKS_ERR_BROKER_RETRY_EXHAUSTED = 202` — tentativas de retry esgotadas em retcode retryable.
  - `MKS_ERR_BROKER_NOT_INITIALIZED = 203` — `Send`/`Close` chamado antes de `Init`.
  - Outros códigos surgem conforme implementação (REJECTED genérico, etc.).

- **`MksExecutionResult` ganha campos.** Trabalho à parte em ciclo próprio após este aceite:
  - `swap` (double) — captura de carry overnight (`DEAL_SWAP`).
  - `dealId` (ulong) — ticket do deal MT5 que originou o fill, para auditoria.
  - `attempts` (int) — quantas tentativas o broker fez (1 = sucesso na primeira; >1 = retries).

- **`MksOrderRequest`** não muda em v1. Símbolo vem do broker (per-symbol). Magic number, expiration de pendente, type não-mercado ficam para futuro.

- **`IBroker.Send/Close/Modify`** mantêm assinatura atual. A semântica síncrona já é compatível.

- **Pasta nova `Core/Broker/`** — `CMksMt5Broker.mqh`, `CMksSimulatedBroker.mqh`, `CMksCostModel.mqh`. Atualizar `ARCHITECTURE.md` §2 quando implementada.

- **`CMksMt5Broker` precisa receber `OnTradeTransaction` do EA.** Composition root expõe um método público (ex.: `g_broker.OnTradeTransactionEvent(transaction, request, result)`) chamado pelo `OnTradeTransaction` do EA. O broker mantém estado interno (deals esperados, deals chegados) para a sincronização síncrona-via-evento.

- **Teste de paridade.** Quando ambos os brokers estiverem implementados, replicar o padrão do `Test_CMksRenkoBuilder`: duas instâncias (`CMksMt5Broker` mock + `CMksSimulatedBroker`) alimentadas com a mesma sequência de `MksOrderRequest` produzem `MksExecutionResult` idênticos campo-a-campo, dada uma simulação de slippage e custo idênticos. Esse é o gold standard de prova de paridade backtest/live para a camada de execução.

- **ADR-016 prepara terreno aqui.** `CMksMt5Broker` consome `ISymbol` (FillingMode, TickSize, Point, VolumeStep, StopsLevel) e `IAccount` (MarginMode, FreeMargin). A interface estabelecida pela ADR-016 é a base direta.

- **ARCHITECTURE.md §4** perde a entrada ADR-017 pendente quando esta for aceita.

**Fronteiras:**

- Não cobre **ordens pendentes** (`BUY_LIMIT`, `SELL_STOP`, etc.) — v1 do broker é apenas a mercado. Pendentes ficam para evolução futura.
- Não cobre **multi-símbolo** no mesmo broker — cada símbolo tem seu broker.
- Não cobre **otimização de latência** (`OrderSendAsync`, threading). Estratégia atual opera em escala de minutos por brick; latência síncrona é irrelevante.
- Não cobre **broker para spread betting / CFD com regras especiais** — assumimos Market/Exchange execution padrão.
- Não cobre a **implementação concreta** do `CMksMt5Broker` ou `CMksSimulatedBroker` — slice próprio após este aceite.
- Não cobre `CostModel` em detalhe matemático — esta ADR fixa que ele existe como classe separada com responsabilidades duais (passthrough/gerador). Os parâmetros e fórmulas concretas do gerador são decisão do slice de implementação do `CMksSimulatedBroker`.

---

**Nota de esclarecimento — mecânica de confirmação síncrona** (2026-05-22)

A ADR-017 §1 fixou que `Send`/`Close` são "síncronos lógicos — bloqueiam até `OnTradeTransaction` reportar `TRADE_TRANSACTION_DEAL_ADD`, ou até o timeout". Essa formulação descrevia a **semântica externa** (interface síncrona com `fillPrice` real lido após o deal existir), mas a **mecânica interna** sugerida (Sleep loop aguardando o evento setar uma flag) tem um problema descoberto na validação empírica do `CMksMt5Broker` em demo Exness no dia 2026-05-22: **MQL5 é single-threaded cooperativo**. `OnTradeTransaction` **não é processado durante uma execução de `OnTick`** — fica enfileirado até o `OnTick` retornar. Logo, um Sleep loop dentro de `Send` (chamado por `OnTick`) deadlocka logicamente: espera evento que só vem depois que `Send` retornar. Empiricamente, ordem real foi executada em 129ms no servidor, mas o EA acusou `TIMEOUT` após 5s — esperando um evento que estava em fila.

**A mecânica correta**, aplicada na implementação (`CMksMt5Broker.mqh` commit `88947cd`): após `OrderSend(req, res)` retornar `TRADE_RETCODE_DONE` em Market execution, `res.deal` já está populado pelo servidor. Lê-se imediatamente via `HistoryDealSelect(res.deal)` + `HistoryDealGetDouble(deal, DEAL_PRICE/VOLUME/COMMISSION/SWAP)`, **sem depender de `OnTradeTransaction`**. A semântica externa da ADR-017 §1 é preservada (`Send` retorna com preço executado real); a mecânica interna troca "Sleep + flag por evento" por "leitura direta do histórico do deal". O roteamento de `OnTradeTransaction` para `OnTradeTransactionEvent` permanece como **fallback** para casos edge (`res.deal == 0` imediato — ordens pendentes, execução postergada).

A ADR-017 não é alterada; esta nota registra o refinamento da mecânica encontrado em validação.

---

### ADR-016: Interfaces ISymbol e IAccount

**Data:** 2026-05-21
**Status:** Aceita

**Contexto:**
A ADR-013 §2 estabeleceu que código de lógica não pode chamar a API global do MQL5 — borda (composition root em `OnInit`/`OnTick`/`OnDeinit` e implementações concretas de interfaces) pode; lógica não. O Protocolo 9 (criado na integração da auditoria MQL5, commit `4756e8e`) materializou essa fronteira como tabela: cada função global proibida em código de lógica tem um substituto canônico. Para tempo o substituto é `IClock`; para tick é `ITickSource`; para execução é `IBroker`; para mercado e conta o substituto canônico é `ISymbol.*` e `IAccount.*` — mas essas duas interfaces **ainda não existem**.

A consequência é que código futuro (`CMksTradeManager`, `CMksRiskManager`, estratégias) ou nasce violando o Protocolo 9 (chamando `SymbolInfoDouble`, `AccountInfoInteger` etc. diretamente) ou recria essas chamadas espalhadas pelo framework. O `Producer.mq5` atual usa as funções globais na borda do `OnInit` — permitido por ADR-013 §2 mas exceção, e o padrão se perde sem interfaces formais.

Esta ADR fixa o contrato de `ISymbol` e `IAccount` antes que qualquer módulo de lógica dependa delas. Sem isto, o Protocolo 9 é regra cosmética.

**Decisão:**
Duas interfaces puras seguindo ADR-004, com escopo focado no que o framework realmente vai consumir — não cobertura completa da API MQL5.

1. **`ISymbol`** — propriedades estáticas/semi-estáticas do instrumento (ficha técnica). Não inclui dados de tick ao vivo.

   ```
   class ISymbol
   {
   public:
      virtual ~ISymbol() {}
      virtual string Name()              const = 0;
      virtual int    Digits()            const = 0;
      virtual double Point()             const = 0;
      virtual double TickSize()          const = 0;
      virtual double TickValue()         const = 0;
      virtual double ContractSize()      const = 0;
      virtual double VolumeMin()         const = 0;
      virtual double VolumeMax()         const = 0;
      virtual double VolumeStep()        const = 0;
      virtual int    StopsLevel()        const = 0;
      virtual int    FreezeLevel()       const = 0;
      virtual int    FillingMode()       const = 0; // bitmask de ENUM_SYMBOL_FILLING_MODE
      virtual string BaseCurrency()      const = 0;
      virtual string ProfitCurrency()    const = 0;
      virtual string MarginCurrency()    const = 0;
   };
   ```

   **Bid/Ask/Spread/Last NÃO entram em ISymbol.** Preço ao vivo vem do `MksTick` via `ITickSource`. Misturar canal de tick com ficha técnica viola single-responsibility e duplica a fonte do tick.

2. **`IAccount`** — estado da conta corrente.

   ```
   class IAccount
   {
   public:
      virtual ~IAccount() {}
      virtual long   Login()      const = 0;
      virtual string Company()    const = 0;
      virtual string Currency()   const = 0;
      virtual double Balance()    const = 0;
      virtual double Equity()     const = 0;
      virtual double Margin()     const = 0;
      virtual double FreeMargin() const = 0;
      virtual int    Leverage()   const = 0;
      virtual ENUM_ACCOUNT_MARGIN_MODE MarginMode() const = 0;
      virtual ENUM_ACCOUNT_TRADE_MODE  TradeMode()  const = 0;
   };
   ```

3. **Enums nativos do MQL5.** Os métodos `FillingMode`, `MarginMode`, `TradeMode` retornam diretamente os enums da plataforma (`ENUM_SYMBOL_FILLING_MODE` como bitmask `int`, `ENUM_ACCOUNT_MARGIN_MODE`, `ENUM_ACCOUNT_TRADE_MODE`). Framework é MQL5-only (ADR-004 fixou a plataforma) — não há razão para mapear esses enums em enums próprios. Mocks de teste retornam valores dos enums diretamente.

4. **Implementações concretas:**
   - `Core/Symbol/CMksMt5Symbol.mqh` — construtor `(string symbolName)`, cada método delega para `SymbolInfoString`/`SymbolInfoInteger`/`SymbolInfoDouble`.
   - `Core/Account/CMksMt5Account.mqh` — sem construtor especial, cada método delega para `AccountInfoString`/`AccountInfoInteger`/`AccountInfoDouble`.

5. **Composition root injeta as instâncias.** EAs e scripts instanciam `CMksMt5Symbol(_Symbol)` e `CMksMt5Account()` no `OnInit`. Módulos de lógica recebem `ISymbol*` e `IAccount*` via construtor — nunca consultam a API global.

6. **Get-on-demand, não snapshot.** Cada chamada faz uma consulta. Razão: Equity, Balance e Margin mudam continuamente; cachear no construtor produz dados defasados. Custo: uma chamada de API por leitura — desprezível (microssegundos) e não está em hot path.

**Alternativas consideradas:**

- **Interface única (`IBrokerEnv` ou `IMarketContext`) cobrindo símbolo + conta + execução:** rejeitada. Viola single-responsibility — broker é executor de ordem (`IBroker.Send/Close/Modify`), não fonte de info. Misturar consultas estáticas com execução assíncrona produz interface enorme e difícil de mockar.

- **Funções livres como helpers (`MksSymbolDigits(name)` etc.):** rejeitada. Não permite injeção em testes — mock ficaria via `#define`, mecanismo frágil em MQL5. Interfaces + injeção é o padrão estabelecido (ADR-004).

- **Pular ISymbol/IAccount e usar API global em todo lugar (ADR-013 §2 só na borda):** rejeitada. O V5 fez exatamente isso e a impossibilidade de mockar levou a "testes" que rodavam contra dados reais, expondo a estratégia a feed do broker durante desenvolvimento.

- **Snapshot no construtor em vez de get-on-demand:** rejeitada para campos dinâmicos (Equity, Margin, FreeMargin). Pode fazer sentido para campos estáticos (Digits, Point) — mas a uniformidade de "tudo via API on demand" simplifica o contrato. Profiling futuro pode justificar cache local; v1 não precisa.

- **Incluir Bid()/Ask()/Spread() em ISymbol:** rejeitada. Duplica fonte com `ITickSource` (canal canônico de tick), e o builder é mid-driven (ADR-010 §4) sobre `MksTick.bid`/`MksTick.ask` — não sobre snapshots de ISymbol. Toda decisão pós-brick é sobre brick; toda decisão pós-tick é sobre tick; ficha técnica do símbolo é coisa diferente.

- **Cobrir 100% da API SymbolInfo/AccountInfo:** rejeitada. A API MQL5 expõe dezenas de campos por símbolo; ISymbol expõe apenas os que o framework consome ou consumirá em breve. Adicionar mais é fácil quando necessário; pré-mapear tudo é trabalho a fundo perdido.

**Consequências:**

- **Duas interfaces novas** em `Core/Interfaces/ISymbol.mqh` e `Core/Interfaces/IAccount.mqh`.

- **Duas classes concretas** em `Core/Symbol/CMksMt5Symbol.mqh` e `Core/Account/CMksMt5Account.mqh`. Pastas novas `Core/Symbol/` e `Core/Account/` na árvore (atualizar `ARCHITECTURE.md` §2 quando implementadas).

- **Producer.mq5 refactor.** Substituir as ~6 chamadas a `SymbolInfo*` e ~2 a `AccountInfo*` (todas em `OnInit`) por chamadas via `g_iSymbol.*` e `g_iAccount.*`. Comportamento idêntico; apenas indireção. Pavimentação para futuros EAs.

- **Protocolo 9 ganha referências concretas.** A tabela "Mercado" e "Conta" hoje referenciam `ISymbol.*`/`IAccount.*` como pendentes (ADR-016). Quando esta ADR for aceita, o protocolo aponta para as interfaces reais.

- **Mocks de teste** (`CMksFakeSymbol`, `CMksFakeAccount`) **não entram nesta ADR.** Serão construídos quando os primeiros testes de Trade Manager / Risk Manager precisarem deles. Slice próprio, possivelmente relacionado à ADR-005 (framework de testes formal).

- **ADR-017 (broker) prepara terreno.** O futuro `CMksMt5Broker` vai consumir `ISymbol` (`FillingMode`, `TickSize`, `ContractSize`, `StopsLevel`) e `IAccount` (`MarginMode`, `Leverage`). Esta ADR é pré-requisito direto.

- **ARCHITECTURE.md §4** perde a entrada ADR-016 pendente quando esta for aceita.

**Fronteiras:**

- Não cobre múltiplos símbolos operando simultaneamente — composition root instancia múltiplos `CMksMt5Symbol(name)` se necessário. EA cross-symbol é tema futuro, fora desta ADR.
- Não cobre mudança dinâmica de símbolo do chart (caso raro; EAs típicos são chart-bound).
- Não inclui mocks/fakes — esses são trabalho de slice de testes futuro.
- Não é fonte de tick ou de bricks — `ITickSource` e `IRenkoSink` continuam canais canônicos para esses.

---

### ADR-007: Formato e destino do log estruturado

**Data:** 2026-05-21
**Status:** Aceita

**Contexto:**
A interface `ILogger` foi definida na Fase 1 (`Core/Interfaces/ILogger.mqh`), mas o formato concreto da linha de log nunca foi decidido. EAs e scripts atuais — `Producer.mq5`, `ValidateBuilderOnRealTicks.mq5`, `ValidateProducerOutput.mq5`, `Test_*.mq5` — usam `Print`/`PrintFormat` direto, com formato livre. Volume vai crescer rapidamente: `CMksLogger` (pendente) será dependência transversal de todos os módulos futuros (`CMksTradeManager`, `CMksRiskManager`, `CMksMt5Broker`, estratégias).

Sem formato fixado, três problemas se materializam:

1. **Paridade backtest/live (princípio norteador) não tem ferramenta de auditoria.** Log-diff entre uma execução em backtest e uma em live é a forma direta de detectar divergência (eixo 4 do V5-POSTMORTEM). Sem schema estruturado, log-diff é impossível ou degenera em regex-fest.

2. **Hot path não pode logar de qualquer forma.** `Print` é síncrono no MT5 e pode atrasar `OnTick` quando chamado em volume (~1000 ticks/min em XAUUSD). Sem política explícita, código novo loga em qualquer lugar — vira gargalo.

3. **Volume e custo de armazenamento.** Backtest de 7 dias com Producer já gerou 1.7M ticks e ~10k bricks. Um log de 1 linha por brick = ~10k linhas (~1MB). Um log de 1 linha por tick = 1.7M linhas (~170MB). Decisão precoce ou ausência leva a desperdício ou perda de auditoria.

Esta ADR fixa formato, destino e política antes de o `CMksLogger` ser escrito.

**Decisão:**
O log estruturado do MKS-ULTIMATE assenta sobre cinco regras: JSON-line, destino dual, hot path mudo, arquivo por sessão, e política de níveis decidida na borda.

1. **Formato: JSON-line.** Cada mensagem é uma linha contendo um objeto JSON válido, terminado por `\n`. Schema mínimo obrigatório:

   ```json
   {"ts": "2026-05-21T15:30:42.123Z", "level": "INFO", "module": "RenkoBuilder", "msg": "brick emitted", "brickIdx": 9883, "direction": "BULL"}
   ```

   Campos obrigatórios:
   - `ts` — ISO 8601 UTC com precisão de milissegundo.
   - `level` — `TRACE` / `DEBUG` / `INFO` / `WARN` / `ERROR`.
   - `module` — nome curto do módulo de origem (`RenkoBuilder`, `Broker`, `TradeManager`, etc.).
   - `msg` — mensagem em inglês, curta, sem template interpolation com runtime values (esses vão em campos próprios).

   Campos contextuais opcionais (key/value), sem schema fixo — cada chamada do logger adiciona o que faz sentido. Exemplos comuns: `seq` (tick), `brickIdx`, `orderId`, `errorCode`, `lastErr`.

2. **Destino dual: `Print` + `FileWrite`.** Cada chamada de log escreve em DOIS lugares simultaneamente:
   - `Print(jsonLine)` — para o Experts panel do MT5 (inspeção em tempo real).
   - `FileWrite(handle, jsonLine + "\n")` — para arquivo persistente em `MKS-ULTIMATE\Logs\<symbol>_<YYYYMMDDTHHMMSS>.log`.

   Custo dobrado de I/O é aceito — vale a inspeção em tempo real combinada com auditoria persistente. Para casos onde apenas um destino faz sentido (cenário de teste interno sem persistência), o `CMksLogger` recebe flags no construtor (`bool toPrint`, `bool toFile`).

3. **Hot path mudo.** `OnTick`, `IngestTick`, `OnBookEvent` e qualquer função chamada por tick **não logam**. Logger é usado em:
   - Decisões pós-brick (`OnBrickClose` e callbacks downstream).
   - Eventos de ordem (entrada/saída em `IBroker.Send`/`Close`/`Modify`).
   - Erros estruturados (`MksError` reportado por qualquer módulo).
   - Inicialização e finalização (`OnInit`, `OnDeinit`).

   Logging granular por tick é proibido em produção. Para diagnóstico de tick-level em desenvolvimento, o EA pode ter um flag input (ex.: `InpPrintBricks` já existente no Producer) que ativa logging detalhado — mas a saída vai para `Print` apenas, não para arquivo, e o flag é descritivo do que é logado (não "log de tudo").

4. **Arquivo por sessão.** Cada `OnInit` cria um arquivo novo de log, simétrico com a política da ADR-014 para `.mksbk`. Nome: `MKS-ULTIMATE\Logs\<symbol>_<YYYYMMDDTHHMMSS>.log`. Sub-pasta `Logs/` na árvore. Sem append entre sessões. Sem rotação interna do logger — sessão = arquivo. Disco lotado é problema operacional, não do framework. Guard contra colisão de nome (análoga à ADR-014 §4) fica para a implementação do `CMksLogger`.

5. **Política de níveis decidida na borda.** O `CMksLogger` recebe o nível mínimo no construtor — não consulta `MQLInfoInteger(MQL5_TESTING)` internamente, respeitando o Protocolo 9. A decisão de nível default fica no `OnInit` do EA, que pode optar por:
   - `INFO+` em live (recomendado para produção).
   - `WARN+` em backtest (reduz volume — `MQLInfoInteger(MQL5_TESTING)` consultado na borda do `OnInit` é uso permitido por ADR-015 §3 para ajustar verbosidade de output, não para bifurcar lógica de trading).
   - Input do EA (`InpLogLevel`) tem precedência sobre defaults — desenvolvimento ativa `TRACE`/`DEBUG`.

6. **Header do arquivo (primeira linha).** A primeira linha do arquivo é um JSON-line especial com `level: "META"` contendo proveniência cached do `OnInit`: `broker`, `accountLogin`, `symbol`, `digits`, `frameworkVersion` (de `Core/Version.mqh`), `eaName`, `sessionStartMsc`. Linhas subsequentes não repetem essa informação — economiza bytes e facilita header-vs-body parsing.

**Alternativas consideradas:**

- **Key=value (logfmt do Heroku/structlog):** rejeitada. Mais legível no MT5 Experts panel sem ferramenta externa, mas escaping de quotes/espaços em valores é frágil. JSON-line tem parsing trivial em qualquer linguagem (`jq`, Python, Go), e o overhead de `{"":""}` extra é irrelevante para o volume previsto.

- **Texto livre estruturado (`[INFO] msg key=value`):** rejeitada. Máxima legibilidade humana, parsing por regex. Mata auditoria sistemática — log-diff entre backtest/live precisa de schema, não de regex.

- **Só `Print`, sem arquivo:** rejeitada. O Experts panel é limpo no restart do terminal; auditoria de paridade exige persistência além da sessão. E o panel tem limite de scroll-back que esconde mensagens antigas em sessões longas.

- **Só `FileWrite`, sem `Print`:** rejeitada. Perde inspeção em tempo real durante operação. Operador olhando o MT5 não vê nada — precisa abrir tail do arquivo numa janela paralela. UX ruim.

- **Logging assíncrono via buffer + flush periódico:** rejeitada. Complexidade alta (gerenciamento de buffer, flush em `OnDeinit`, risco de perder mensagens no crash) para ganho marginal — a regra de "hot path mudo" já elimina o problema de atraso síncrono.

- **Logger sem schema fixo (campo livre):** rejeitada. Sem schema, log-diff é impossível, e cada módulo inventa o seu — recriação do eixo 2 do V5 em outra dimensão.

**Consequências:**

- **`CMksLogger` em `Core/Log/CMksLogger.mqh`** — implementação de `ILogger`. Construtor recebe path do arquivo e flags (`bool toPrint`, `bool toFile`, nível mínimo). Métodos: `Trace`/`Debug`/`Info`/`Warn`/`Error` como helpers + um `Log(level, module, msg, ctx)` interno. Forma exata da assinatura fica para a implementação, desde que respeite o JSON-line schema desta ADR.

- **`ILogger` da Fase 1 pode precisar de revisão.** O método atual `Log(level, message)` é genérico mas não força o schema (`module`, contextos). Quando `CMksLogger` for implementado, vai propor uma assinatura mais estruturada — possivelmente aceitando um `MksLogContext` (struct POD com pares chave-valor). Se a interface mudar, é alteração de tipo do core (ciclo próprio após este aceite, padrão das ADRs anteriores).

- **Sub-pasta `MKS-ULTIMATE\Logs\`** aparece. `FolderCreate("MKS-ULTIMATE")` + `FolderCreate("MKS-ULTIMATE\\Logs")` antes do `FileOpen` no `OnInit` do EA, mesmo padrão do `Bricks/`. Estrutura-alvo em §2 deve refletir isso quando o `CMksLogger` for implementado.

- **`Producer.mq5` (já existente) ganha `CMksLogger` no composition root** — substituição de `PrintFormat` por `logger.Info`/`Warn`/`Error` em ciclo de refactor pós-aceite. EA atual continua funcional até esse refactor.

- **Faixa de erros Log: 600–699** (ADR-009 já reservou). `MKS_ERR_LOG_FILE_IO`, `MKS_ERR_LOG_INVALID_LEVEL`, etc., serão alocados quando `CMksLogger` for escrito.

- **Ferramenta de log-diff vira possível.** Dois arquivos `.log` de runs diferentes podem ser comparados linha-a-linha após normalização de `ts`/`seq`. Implementação futura (Fase 8 ou utilitário Python externo), não bloqueada por esta ADR.

- **Custo de I/O do destino dual aceitável.** Para ~10k linhas por sessão de Producer, ~1MB de log. Imperceptível. Em estratégia futura com mais eventos (~100k linhas/dia), ~10MB/dia — ainda gerenciável. Mitigação se virar problema: desligar `toPrint` em runs longos ou aumentar nível mínimo.

**Fronteiras:**

- Não é a implementação de `CMksLogger` — vem depois.
- Não é a ferramenta de log-diff — trabalho futuro.
- Não é o formato do report de release (Sharpe, drawdown) — esse é tema da ADR-015 §Consequências, decidido quando o reporter for implementado.
- Não é a estrutura do `MksError` — esse é ADR-009. O log de erro estruturado consome `MksError` e serializa seus campos no JSON-line.

---

**Nota de esclarecimento — WARN/ERROR rate-limited em hot path** (2026-05-24)

A ADR-007 §3 fixou "hot path mudo" — `OnTick`, `IngestTick`, `OnBookEvent` e qualquer função chamada por tick **não logam**. Auditoria forense de 2026-05-24 identificou que o `Producer.mq5` (linhas 241–263, `IngestOne` chamado a partir de `OnTick`) emite `g_logger.Warn`/`g_logger.Error` para reportar erros do builder: `MKS_ERR_RENKO_INVALID_TICK` (103), `MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED` (102) e `MKS_ERR_RENKO_TICK_STREAM_CORRUPT` (104). Pela letra da §3, isso é violação.

A regra é refinada — não revogada — para reconhecer a categoria de uso que o Producer já implementa: **`WARN` e `ERROR` são aceitos em hot path desde que rate-limited**. A configuração `InpInvalidLogEvery=100` do Producer ilustra o padrão — uma linha de log a cada N ocorrências do mesmo erro, com contador agregado no `OnDeinit` para o total real. `Error` 104 (stream corrupt) é não-rate-limited porque dispara uma única vez por sessão.

Razões para a exceção:
- Eventos de erro são **eventos**, não tráfego de rotina — `TRACE`/`DEBUG`/`INFO` continuam proibidos em hot path porque o volume é por tick. `WARN`/`ERROR` aparecem proporcionais à frequência de **anomalias**, não de ticks.
- Sem logar erros do builder no momento em que ocorrem, o operador perde a janela onde o feed estava degradado — a auditoria post-mortem fica cega sobre exatamente o tipo de problema que matou o V5.
- O rate-limit (1 a cada N) garante que mesmo um feed 100% inválido em pico não trava o terminal — N=100 em XAUUSD a 100tps = 1 log/segundo no pior caso.

Restrições que **continuam vigentes**:
- `TRACE`, `DEBUG`, `INFO` permanecem proibidos em hot path, sem exceção. O log de inicialização, de fim de sessão e o `META` do header vivem na borda (`OnInit`, `OnDeinit`).
- `WARN`/`ERROR` em hot path **devem ser rate-limited explicitamente**. Caller é responsável pelo rate-limit (não o logger) — o logger continua emitindo cada chamada sem amortecimento próprio.
- O `OnDeinit` deve incluir contadores agregados (`seen`, `logged`) para que a contagem real apareça mesmo com o rate-limit suprimindo a maior parte.

A ADR-007 não é alterada; esta nota registra a categoria refinada que o código de produção já segue. Code review: WARN/ERROR no hot path sem rate-limit explícito é defeito a corrigir.

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

### ADR-005: Framework próprio mínimo para testes unitários do core

**Data:** 2026-05-21
**Status:** Aceita

**Contexto:**
A Fase 3 do `ROADMAP.md` exige um "framework mínimo de asserções (`ASSERT_EQ`, `ASSERT_TRUE`, etc.) em `Core/Testing/`" como critério de saída. Quatro suítes de teste já existem e passam — `Test_CMksRenkoBuilder` (428 assertions), `Test_CMksBrickFile` (97), `Test_CMksAtrBrickSizer` (72) e `Test_CMksSimulatedBroker` (51) —, mas usam asserções inline copiadas e coladas entre os arquivos. Auditoria desses 4 arquivos antes desta ADR revelou divergências estruturais: a tolerância de `AssertEqualDouble` é hardcoded por arquivo (1e-9 em três, 1e-12 em um), `AssertNearDouble` (tolerância explícita) só existe em dois deles, a mensagem de falha varia em formatação numérica entre arquivos, e o comportamento de fim diverge (um dispara `Alert`, os outros só `Print`). Helpers de domínio — `CCapturingSink`, `CFakeSymbol`, `MakeTick`, `MakeBrick`, `BuildSampleBricks` — são reescritos inline em cada arquivo. O registro de testes é manual: cada função é chamada em `OnStart()`; esquecer de adicionar a chamada deixa o teste fora da execução sem aviso. Sem uma decisão fixada, cada novo módulo do core (Trade Manager, Risk Manager, StressLab) replicará o padrão divergente e a dívida cresce. A ADR-005 estava reservada na §4 desde a abertura do documento; esta entrada a quita antes da Fase 5 abrir.

**Decisão:**
O MKS-ULTIMATE adota um framework próprio mínimo de testes em `MQL5/Include/MKS-ULTIMATE/Core/Testing/`, sem dependência externa.

1. **Três artefatos compõem o framework.** `Core/Testing/Asserts.mqh` carrega o vocabulário uniforme de asserção. `Core/Testing/TestRunner.mqh` carrega o singleton runner e a macro `MKS_RUN`. `Core/Testing/Mocks/` é a pasta de mocks reutilizáveis — um arquivo por mock, nomeado por convenção (`CMksFakeSymbol.mqh`, `CMksFakeAccount.mqh`, `CMksCapturingSink.mqh`).

2. **Vocabulário de asserção uniforme.** Um único include — `Asserts.mqh` — define todas as sobrecargas necessárias: `MKS_ASSERT_TRUE`, `MKS_ASSERT_FALSE`, `MKS_ASSERT_EQ_INT`, `MKS_ASSERT_EQ_LONG`, `MKS_ASSERT_EQ_ULONG`, `MKS_ASSERT_EQ_STRING`, `MKS_ASSERT_EQ_DOUBLE`, `MKS_ASSERT_NEAR_DOUBLE`. A tolerância de `MKS_ASSERT_EQ_DOUBLE` é parâmetro com default explícito `1e-9`; `MKS_ASSERT_NEAR_DOUBLE` exige tolerância obrigatória. A mensagem de falha é única, sempre no formato `FAIL [<test_name>] <what>: expected=<x> actual=<y>`. As macros — não funções diretas — capturam `__FILE__`/`__LINE__` no call site para diagnóstico, no mesmo padrão da ADR-009.

3. **Registro de teste manual via `MKS_RUN(funcName)`.** O `OnStart()` lista os testes via uma macro `MKS_RUN(Test_BullContinuation)` que expande para `g_mksTestRunner.Begin("Test_BullContinuation"); Test_BullContinuation(); g_mksTestRunner.End();`. O nome do teste passa a ser o nome da função (via stringification `#funcName`), eliminando o `g_currentTest = "string livre"` que hoje pode divergir do nome da função. A lista no `OnStart()` continua sendo o manifesto explícito do que roda — adicionar um teste novo exige uma linha nesse manifesto, e a omissão é visível em code review.

4. **State global encapsulado no runner singleton.** O `g_mksTestRunner` (instância global declarada no `TestRunner.mqh`) carrega `passedAssertions`, `failedAssertions`, `passedTests`, `failedTests`, `currentTest`. As macros de asserção chamam `g_mksTestRunner.Pass()` ou `g_mksTestRunner.Fail(...)`. MQL5 não tem exceções nem RAII; passar um `MksTestContext&` em cada chamada de asserção seria peso sem ganho proporcional. O singleton é deliberado e o escopo é o programa do script de teste.

5. **Mocks moram em `Core/Testing/Mocks/`.** A justificativa é a árvore do `ARCHITECTURE.md §2`, que reservou `Core/Testing/` para o framework de teste desde a abertura do documento. Mocks são biblioteca do framework — quem precisa do framework, precisa dos mocks. Como nenhum código de produção faz `#include` de mock, a separação física entre teste e produção continua clara (`Scripts/Tests/` vs `Experts/` vs `Include/` de produção).

6. **Saída padronizada do runner.** Ao final, o runner imprime `=== <passedAssertions>/<totalAssertions> assertions in <numTests> tests (<failedTests> failed) ===`. Falha gera `Alert` único no fim, não `Alert` por arquivo. A diferença atual entre o `Alert` do `Test_CMksRenkoBuilder` e o silêncio dos outros desaparece.

7. **Escopo desta ADR.** Esta ADR fixa a estrutura do framework. A migração dos 4 testes existentes para o framework é trabalho separado, em slice próprio após o aceite. A Fase 3 só passa a "Concluída" quando o framework existir **e** os 4 testes existentes tiverem sido migrados sem perda de cobertura — esse é o critério de saída efetivo, gravado aqui.

**Alternativas consideradas:**
- **Adaptar projeto open-source (MQL5-Unit ou similar):** rejeitada. Introduz dependência externa num caminho crítico — toda validação do core passa pelo framework de teste. Convenções não batem com as do projeto (prefixos `Mks`, `ENUM_MKS_*`, `__FILE__`/`__FUNCTION__`/`__LINE__` no padrão da ADR-009). Se o projeto upstream morrer ou divergir, herdamos código órfão de qualquer jeito — e o custo de manter 400 linhas próprias é menor que o de auditar e patchear código de terceiros que não respeita as convenções do MKS-ULTIMATE. O espírito do princípio invariante 5 da §1 (controle do caminho crítico) sustenta a recusa, mesmo a regra literal não se aplicando a testes.
- **Manter asserções inline, apenas extrair helpers de domínio:** rejeitada. Resolve copy-paste de mocks (`CCapturingSink`, `CFakeSymbol`) mas deixa intactos os bugs latentes — tolerâncias divergentes, mensagens inconsistentes, comportamento de fim divergente, registro manual sem ligação ao nome da função. É meia-solução que perpetua exatamente o estado que motivou esta ADR.
- **Auto-registro de testes via function pointer global e macro com bloco estático:** rejeitada. MQL5 não tem inicialização estática garantida para tabelas de function pointers, e a manipulação seria frágil (sem `__attribute__`, sem `static_assert`, sem RTTI). O ganho — "esqueci de adicionar a chamada em `OnStart`" — é pequeno comparado ao custo de manter mágica de macro que pode quebrar entre versões do MetaEditor. A lista manual no `OnStart()` é o manifesto explícito do que roda; omissão é visível em code review.
- **Contexto isolado por teste (`MksTestContext& ctx` passado em cada asserção):** rejeitada. Forçaria a assinatura `ctx.AssertEqual(...)` em toda chamada, com `ctx` passado para cada função de teste. Em MQL5 (single-threaded, sem RAII, sem exceções), o ganho de isolamento real é zero — o runner singleton já encapsula o estado, e nada além de um teste roda em paralelo. O peso de propagar `ctx` por todas as assinaturas não compensa.
- **Mocks em `Scripts/Tests/Helpers/` (fora do `Core/`):** rejeitada. O `ARCHITECTURE.md §2` já reservou `Core/Testing/` como o lugar do framework de teste; criar pasta nova fora do plano por receio de "misturar teste com produção" ignora que a separação física entre `Scripts/Tests/*.mq5` (consumidor) e `Include/.../Core/Testing/` (biblioteca) já é nítida. Manter no `Core/Testing/` honra a árvore já decidida.

**Consequências:**
- Nova pasta `MQL5/Include/MKS-ULTIMATE/Core/Testing/` materializa o que o `ARCHITECTURE.md §2` já reservou. A árvore do §2 ganha a sub-pasta `Mocks/` quando o framework for implementado.
- O framework tem ~400 linhas estimadas (Asserts.mqh ~150, TestRunner.mqh ~80, Mocks/ ~200 distribuídas). Tamanho coerente com "mínimo".
- A faixa de erro Testing (700–799) reservada na ADR-009 continua disponível; será usada se o framework precisar reportar erros estruturados (ex.: setup de mock falhou). Esta ADR não cunha código de erro novo.
- **Critério de saída efetivo da Fase 3** redefinido: framework existe + 4 testes migrados sem perda de cobertura. O `ROADMAP.md` carrega hoje "Parcialmente concluída"; passa a "Concluída" apenas depois da migração.
- Próximos módulos do core (Trade Manager, Risk Manager, StressLab) nascem usando o framework — fecha a porta para o padrão divergente se replicar.
- Dívida de migração assumida: o slice de implementação reescreve os 4 arquivos atuais (`Test_CMksRenkoBuilder`, `Test_CMksBrickFile`, `Test_CMksAtrBrickSizer`, `Test_CMksSimulatedBroker`). Trabalho mecânico, baixo risco, mas exige rodar empiricamente cada suíte pós-migração para confirmar a paridade de cobertura (648 assertions preservadas).
- Compatibilidade futura: se o MQL5 evoluir a ponto de oferecer reflexão ou um framework de teste nativo, migração é mecânica e fica registrada em ADR de substituição.

**Fronteiras:**
- Não é a especificação dos mocks individuais — `CMksFakeSymbol`, `CMksFakeAccount`, `CMksCapturingSink` são criados conforme a demanda dos testes que os consomem; cada um é detalhe de implementação registrado no commit que o introduz, não nova ADR.
- Não é a política de naming de teste — adotamos por convenção `Test_<ClasseTestada>` para o arquivo e `Test_<Cenário>` para a função, herdado dos 4 testes existentes. Convenção, não cláusula.
- Não cobre testes de integração ao broker real (`Test_MksMt5BrokerLive.mq5` em `Experts/`) — esses são EAs por necessidade da API MT5 e ficam fora do framework. O critério para a Fase 4 não exigiu cobertura formal desses; permanece assim.

---

### ADR-019: Ordem de construção `PositionSizer → RiskManager → TradeManager`

**Data:** 2026-05-22
**Status:** Aceita

**Contexto:**
O `ROADMAP.md` na sua forma original lista as fases pendentes do core na ordem **Fase 5 (Trade Management) → Fase 6 (Risk Management) → Fase 7 (StressLab)**. A Fase 5 agrega dois componentes em um pacote único: `CMksTradeManager` (BE, trailing, partial close, state machine) e `CMksPositionSizer` (4 modos de sizing). A "regra de ouro" no topo do `ROADMAP.md` é explícita: "nenhuma fase começa antes da anterior ter todos os critérios de saída cumpridos. Pular fases foi um erro do V5 e não se repete aqui".

Esta ADR é provocada por duas observações que apareceram ao planejar o próximo slice:

1. **Risco moral.** O `ROADMAP.md` §Fase 6 documenta literalmente: "Foi a ausência disso que permitiu o V5 quebrar conta em 4 horas." O `V5-POSTMORTEM.md` lista "Risk manager como middleware, não como lembrete" como lição permanente. Construir o `TradeManager` antes de existir um `RiskManager` cria uma janela em que o ciclo `OrderRequest → IBroker` está sem rede de segurança — mesmo que essa janela seja apenas em ambiente de teste, ela documenta uma prioridade invertida que conflita com o objetivo declarado do framework (proteger a conta primeiro).

2. **Dependência técnica interna.** `RiskManager` precisa validar "tamanho máximo por trade" (ROADMAP §Fase 6.Camadas.Por_trade) — checagem que consome o `PositionSizer` resolvido. `TradeManager`, em contraste, consome `PositionSizer` apenas indiretamente: a estratégia chama `Sizer.Compute()`, monta `OrderRequest`, e o `TradeManager` gerencia o trade que nasceu daquele request. Logo, o `PositionSizer` é dependência do `RiskManager`, mas não o `TradeManager`.

A pergunta arquitetural: seguir a ordem ordinal do ROADMAP (Fase 5 inteira antes de Fase 6) ou re-sequenciar a construção interna para `Sizer → Risk → TradeManager`?

**Decisão:**
A ordem real de construção será **`CMksPositionSizer` → `CMksRiskManager` → `CMksTradeManager`**, com a Fase 5 do `ROADMAP.md` reinterpretada como dois sub-slices independentes (5a Sizer, 5b TradeManager) intercalados pela Fase 6.

1. **`CMksPositionSizer` primeiro.** Implementação isolada de uma classe próxima de função pura — entrada: `(IAccount*, ISymbol*, riskParams, slDistancePoints)`, saída: `lots`. Quatro modos (fixed/percent risk/ATR-adjusted/Kelly fracionado). Sem ciclo de vida, sem state machine. Testável com `CMksFakeAccount` + `CMksFakeSymbol` já existentes.

2. **`CMksRiskManager` em seguida.** Middleware entre `OrderRequest` (vinda da estratégia) e `IBroker`. Consome o `PositionSizer` no caminho "validar tamanho máximo". Três camadas (trade/strategy/account) com `IAccount` injetado para limites baseados em equity/drawdown. Testável com `CMksFakeAccount` controlando o estado da conta.

3. **`CMksTradeManager` por último.** Construído num ambiente onde toda `OrderRequest` que ele dispara passa primeiro pelo `RiskManager`. State machine + BE + trailing + partial close, lendo preço observado via `ITickSource` (não calculando do brick — lição V5 #1).

4. **A "regra de ouro" do ROADMAP é refinada, não violada.** Re-sequenciar componentes dentro de duas fases adjacentes do core não é o mesmo erro que o V5 cometeu (saltar da Fase 1 direto pra Fase 9 — escrever estratégia antes do core). Aqui, todas as três peças são pré-requisito da Fase 9 (EA end-to-end); a sequência interna entre elas não muda quando elas estão prontas. O `ROADMAP.md` ganha nota dizendo que a Fase 5 está dividida em 5a e 5b, executadas em volta da Fase 6.

**Alternativas consideradas:**

- **(a) Ordem estrita do ROADMAP (Fase 5 inteira → Fase 6).** Rejeitada. `TradeManager` nasceria sem `RiskManager` montado. A janela é apenas em teste, mas a ordem documentada conflita com a prioridade do projeto. O argumento "regra de ouro" não se aplica aqui — a regra existe para impedir saltar fases (Fase 1 → Fase 9), não para forçar ordem ordinal entre componentes de duas fases adjacentes.

- **(b) Inverter Fase 5 e Fase 6 inteiras (Risk inteira primeiro, depois Trade inteira).** Rejeitada. `RiskManager.checkPositionSize` precisa do `PositionSizer`. Construir Risk inteira sem Sizer obriga ou stub interno (gambiarra futura) ou validação parcial até Sizer existir.

- **(c) Fundir Fase 5 e Fase 6 em um pacote único.** Rejeitada. Cada componente tem testes próprios e ciclo de vida próprio. Fundir as fases obscurece o critério de saída de cada peça. A sub-divisão 5a/5b com Fase 6 no meio é mais limpa que uma "Fase 5-6" agregada.

- **(d) Construir `PositionSizer` como detalhe interno do `RiskManager` (sem classe própria).** Rejeitada. `PositionSizer` é consumido também pela estratégia diretamente — ela calcula `lots` antes de montar `OrderRequest` para passar pela rede de Risk. Esconder dentro do Risk obriga a estratégia a chamar Risk só pra obter sizing, acoplando demais. Manter como classe própria em `Core/Trade/CMksPositionSizer.mqh` preserva a separação Trade/Risk.

**Consequências:**

- **Cláusula anti-precedente.** Sub-dividir uma fase do `ROADMAP.md` em sub-slices fora da ordem original é permitido **apenas via ADR própria**, nunca como prática informal ou nota de commit. Sem isso, a "regra de ouro" perde força com cada exceção bem-intencionada. Esta ADR-019 cria o primeiro precedente; futuras sub-divisões reaproveitam a forma (ADR justificando + sub-letras na fase) ou não acontecem.

- **`ROADMAP.md` ganha nota na Fase 5** dizendo que ela está sub-dividida (5a/Sizer, 5b/TradeManager) e que 5a vem antes da Fase 6, 5b depois. Não altera entregáveis, só a sequência interna.

- **Slice próximo: implementação do `CMksPositionSizer`**. Localização decidida: `Core/Trade/CMksPositionSizer.mqh` (não `Core/Risk/`) — pertence ao domínio Trade conceitualmente, mesmo sendo consumido por Risk. Tests em `Test_CMksPositionSizer.mq5` usando `CMksFakeAccount` e `CMksFakeSymbol`.

- **Slice seguinte: `CMksRiskManager`**. Em `Core/Risk/CMksRiskManager.mqh`. Composition root passará a injetar `RiskManager` entre estratégia e `IBroker` — ainda não há estratégia para acoplar, mas o broker precisa expor pontos de injeção limpos. Decisão sobre wrapper (`CMksRiskGatedBroker`?) ou inline-check fica para a própria ADR da Fase 6.

- **Slice final desta sequência: `CMksTradeManager`**. Após Risk estar testado, o TradeManager nasce sabendo que toda ordem que ele dispara passa pelo Risk. Não muda o código dele — muda o ambiente em que ele opera.

- **Sem regressão no core existente.** Nenhuma das 3 peças exige mudança em código já testado (`CMksRenkoBuilder`, `CMksAtrBrickSizer`, `CMksSimulatedBroker`, `CMksMt5Broker`, `CMksLogger`, `Producer`). São adições.

**Fronteiras:**

- Não é a especificação dos 4 modos de sizing (fixed/percent/ATR/Kelly) — detalhe do slice 5a.
- Não é a especificação das 3 camadas do Risk Manager — detalhe da ADR da Fase 6.
- Não cobre a relação entre `TradeManager` e tick observado (lição V5 #1) — será explicitada quando o slice 5b abrir.
- Não fecha a Fase 5 do ROADMAP em si — a fase só é Concluída quando Sizer **e** TradeManager existem testados.

---

### ADR-020: Custom Symbol — semântica, contrato visual e fronteiras de uso

**Data:** 2026-05-22
**Status:** Aceita

**Contexto:**
O Slice 3b inaugurou o Custom Symbol no MKS-ULTIMATE via `CCustomSymbolSink` e `EnsureCustomSymbolReady` em `Producer.mq5`. A ADR-014 §Fronteiras delegou explicitamente o naming e os detalhes do Custom Symbol a "decisão de implementação do Producer, sem ADR". Auditoria de 2026-05-22 (registrada em `CHECKPOINT-2026-05-22.md` §A da seção de auditoria) levantou que várias decisões implícitas no código são arquiteturais e merecem contrato formal:

1. Visual no chart do MT5 aparece como "candles M1 normais", não como bricks renko. Reportado empiricamente — usuário não consegue distinguir do M1 do mercado real.
2. O builder atual rastreia excursão intra-brick via `m_formingHigh`/`m_formingLow`, e o brick fechado carrega esses valores. Como `CCustomSymbolSink` propaga `brick.high` e `brick.low` cruamente, cada candle do CS tem sombras (wicks) — quebrando o visual renko.
3. `CustomRatesUpdate` foi escolhido em vez de `CustomTicksAdd` sem ADR. Implicações: CS é série OHLC pura, sem tick stream — indicadores baseados em tick não funcionam nele.
4. Timestamp das bars é fictício monotônico (`nextBarTime += 60s`), pois `CustomRatesUpdate` sobrescreve bars com mesmo `time`. Risco: qualquer código que consuma `iTime()` do CS vê tempo desconectado da realidade.
5. Não há regra impedindo uso do CS como **fonte de leitura por código de lógica** (estratégias, indicadores, EAs consumer). Risco direto: eixo 2 do `V5-POSTMORTEM` ("múltiplos caminhos de produção de bricks"). Strategy Tester operando no CS injeta série OHLC sintética que diverge do `.mksbk`.
6. Política de wipe entre sessões existe (`InpResetCustomSymbolBars`) mas seu efeito quando `false` não está documentado — `nextBarTime` começa em "agora" no OnInit, criando gap no eixo de tempo se houver bars antigas.
7. CSs criados não são deletados — acumulam no Market Watch a cada experimentação com `brickSize` diferente.
8. Sem definição clara de chart timeframe correto para visualização (M1 obrigatório, M5+ agregaria múltiplos bricks numa candle só).

Esta ADR consolida o desenho do CS, separando o que é **visualização humana** (CS) do que é **fonte de verdade** (`.mksbk` + builder ao vivo), e fixa as decisões implícitas como contrato.

**Decisão:**
O Custom Symbol no MKS-ULTIMATE é exclusivamente **camada de visualização humana**. As nove regras abaixo formalizam seu contrato.

1. **CS é só visualização.** Nenhum código de lógica do MKS-ULTIMATE (estratégia, indicador customizado, EA consumer) lê dados do CS via `iOpen/iClose/iHigh/iLow/iTime/CopyRates`. Fontes de verdade para bricks: `.mksbk` (histórico) e `IRenkoSink` (live). Esta regra protege contra o eixo 2 do V5 (múltiplos caminhos de produção de bricks).

2. **`CustomRatesUpdate`, não `CustomTicksAdd`.** Empurra 1 bar OHLC por brick fechado. CS não tem tick stream populado. Indicadores baseados em tick (volume real, BBO spread) não funcionam no CS — e isso é intencional, dado a regra 1.

3. **Bricks no CS são SEM WICKS.** `CCustomSymbolSink.OnBrickClose` substitui:

   ```
   rates[0].high = MathMax(brick.open, brick.close);
   rates[0].low  = MathMin(brick.open, brick.close);
   ```

   Cada bar vira uma caixinha sólida no chart de candlestick — visual coerente com renko clássico. O `.mksbk` permanece com `brick.high`/`brick.low` cruamente (info de excursão preservada para análise quant). Os dois sinks DIVERGEM DELIBERADAMENTE.

4. **Timestamp fictício M1 monotônico.** Cada brick fechado = 1 bar a cada 60 segundos no eixo X do CS. Tempo das bars do CS NÃO reflete tempo real do mercado. Quem precisa de timing real consulta `.mksbk` (`closeTimeMsc`). Decorrência: o eixo X do CS é "índice ordenador de brick", não "tempo de mercado".

5. **Chart type recomendado: Candlestick.** Bars chart é aceitável mas inferior visualmente. Line chart é inútil (perde direção da barra). O chart deve abrir **em timeframe M1** — qualquer outro timeframe agrega múltiplos bricks numa candle só, destruindo o visual renko.

6. **Naming fixo: `<symbol>.MKS_RKN<size>`.** Prefixo do símbolo base + sufixo `MKS_RKN` (MKS Renko) + `size` em pontos. Inteiros não levam decimal (`MKS_RKN3`); decimais usam 2 casas (`MKS_RKN3.50`). Sem broker no nome — proveniência completa fica no header do `.mksbk` correspondente da sessão (consistente com ADR-014 §2).

7. **Política de wipe entre sessões: opt-in com default `true`.** `InpResetCustomSymbolBars=true` chama `CustomRatesDelete(cs, 0, LONG_MAX)` no OnInit, limpando histórico do CS. Quando `false`, `nextBarTime` começa em `AlignDownToM1(TimeCurrent())` e bars antigas permanecem — **cria gap deliberado no eixo de tempo** entre bars antigas (passado) e bars novas (a partir de agora). Esse comportamento é documentado como decisão consciente, não bug.

8. **CS não é deletado pelo framework, mas script de cleanup é entregável obrigatório.** `CustomSymbolDelete` não é chamado em OnDeinit (cada sessão deve poder sobreviver a um restart sem perder histórico do chart). Acúmulo de CSs órfãos por experimentação é problema operacional real, então o framework provê um utility executável: `MQL5/Scripts/MKS-ULTIMATE/MksCleanupCustomSymbols.mq5`, que lista todos os CSs com sufixo `.MKS_RKN*` e permite ao operador deletar os selecionados. Faz parte do slice de implementação desta ADR — não é opcional nem futuro.

9. **Template `.tpl` opcional para o chart.** Slice de implementação fornece `MQL5/Profiles/Templates/MKS-ULTIMATE_Renko.tpl` com candlestick + cores body sólidas (bull verde, bear vermelho) + bordas contrastantes. Usuário aplica via Charts → Template no MT5. Sem .tpl, o usuário configura manualmente conforme nota no Producer.

**Alternativas consideradas:**

- **(a) CS como segunda fonte de bricks (leitura por código de lógica):** rejeitada. Strategy Tester operando no CS injeta série OHLC sintética que diverge do `.mksbk` (cache do tester != cache do terminal real). Recria diretamente o eixo 2 do V5-POSTMORTEM. Regra 1 é o antídoto explícito.

- **(b) Wicks no CS idênticos ao `.mksbk`:** rejeitada. Defeito visual reportado e replicável — candle do CS fica indistinguível de M1 normal. Visual de caixinha sólida é o que o usuário consome, e supressão de wicks no CS preserva info de excursão no arquivo.

- **(c) Bricks sem wicks também no `.mksbk` (renko clássico puro):** rejeitada. Wicks de excursão são informação quant útil para análise post-mortem (overshoot, volatilidade intra-brick). Perder isso para sempre por causa de visual é destruir dado. `.mksbk` preserva tudo; CS é render seletivo.

- **(d) `CustomTicksAdd` com ticks reais:** rejeitada. Custo de I/O por tick (ordens de magnitude maior que por brick). Bricks são a unidade canônica do framework; ticks no CS seriam ruído sem propósito útil dada regra 1.

- **(e) Timestamp real (`brick.closeTimeMsc`) no CS:** rejeitada. `CustomRatesUpdate` sobrescreve bars com mesmo `time`. Bricks fechando mais rápido que 1 por segundo (movimento forte) destruiriam-se mutuamente. Timestamp fictício monotônico é solução estrutural ao limite da API.

- **(f) Indicador renko próprio (canvas / `OBJECT_RECTANGLE`):** adiada (não rejeitada). Cobre 100% do visual sem depender do chart type do MT5. Mas é trabalho significativo (~slice próprio) e candlestick puro sem wicks resolve 90% do caso. Fica como Nível 3 opcional para slice futuro se a regra 3 + template (regra 9) não satisfizer empiricamente.

- **(g) Sub-pasta ou prefixo broker no naming:** rejeitada. Custom Symbols vivem no namespace global do terminal MT5, sem hierarquia. Adicionar `<broker>` ao nome introduz fragilidade (normalização de caracteres, slug instável) sem ganho — proveniência completa está no `.mksbk` header.

- **(h) CS por símbolo + size por brick fixo (sem `MKS_RKN<size>` no nome):** rejeitada. Usuário experimentaria múltiplos tamanhos sobrescrevendo o mesmo CS, sem rastro de qual size cada bar representa. Naming com size separa namespaces explicitamente.

**Consequências:**

- **`CCustomSymbolSink.OnBrickClose` muda** (slice próprio): `rates[0].high = MathMax(brick.open, brick.close)` e `rates[0].low = MathMin(brick.open, brick.close)`. Wicks suprimidos no CS, preservados no `.mksbk`.

- **`CCustomSymbolSink` deve ser extraído** de `Producer.mq5` para `Core/Output/CMksCustomSymbolSink.mqh` (criar nova pasta `Core/Output/` para futuros sinks de visualização/destination). Mesma extração para `CBrickWriterSink` (vai para `Core/Data/`) e `CMultiSink` (para `Core/Output/`). Cobertura: torna sinks reusáveis por EAs futuros (Consumer, replay tools). Slice próprio.

- **Template `.tpl`** em `MQL5/Profiles/Templates/MKS-ULTIMATE_Renko.tpl`. Slice próprio.

- **Producer.mq5** ganha nota no header explicando que o CS é visual + recomendação de M1 + apontador para esta ADR.

- **CHANGELOG.md** registra ADR-020 aceita e suas consequências.

- **README.md** ganha seção "Visualizando bricks no chart" apontando para o template e para esta ADR.

- **Sem mudança no `.mksbk`**, no builder, nem em testes existentes. Apenas o renderer no sink e a documentação.

- **Cobertura de teste:** `CMksCustomSymbolSink` extraído ganha unit test mínimo sobre a transformação OHLC (sem invocar a API global do MT5, apenas a lógica de wipe-wick e timestamp monotônico). Slice próprio.

- **Auditoria CHECKPOINT-2026-05-22 §A**: pontos A1, A2, A3, A6, A7 (parcial) endereçados por esta ADR. A4, A5, A8, A9 ficam como itens menores no roadmap operacional (ver Fronteiras).

**Fronteiras:**

- **Não cobre o indicador renko canvas (Nível 3).** Adiado para slice futuro caso candlestick + template não satisfaçam visualmente.

- **Não cobre o builder.** `m_formingHigh`/`m_formingLow` e o cálculo de `brick.high`/`brick.low` em `CMksRenkoBuilder.mqh:77-78` permanecem intactos. Esta ADR só decide o que o renderer faz com a info.

- **Não cobre o `.mksbk`.** Formato e conteúdo já fixados por ADR-012/013/014.

- **Não cobre o ponto A4 (gap entre sessões com wipe=false)** além do que a regra 7 fixa — é comportamento documentado.

- **Não cobre limpeza automática de CSs órfãos.** Regra 8 fica como dívida operacional; script utility fica para slice opcional.

- **Não cobre multi-símbolo no mesmo Producer.** EA atual é per-símbolo (consistente com ADR-017 §2 sobre broker per-símbolo).

- **Não cobre uso do CS por EAs do usuário fora do MKS-ULTIMATE.** Eles podem ler do CS — regra 1 vincula apenas código DENTRO do framework. Mas o usuário que fizer isso opera sob seu próprio risco de paridade.

- **Armadilha conhecida — backtest do EA do usuário no Strategy Tester apontado para o CS.** O Strategy Tester do MT5 mantém seu próprio cache de séries históricas isolado do terminal real. Um EA backtestado no Strategy Tester apontando para o Custom Symbol `<symbol>.MKS_RKN<size>` **não vê os mesmos bricks** que o `.mksbk` da sessão real produziu — o tester pode regenerar a série OHLC sinteticamente a partir de ticks aproximados, ou simplesmente não ter dado. Esta ADR não impede esse uso, mas registra como **armadilha**: bricks como fonte de verdade para backtest são consumidos exclusivamente do `.mksbk` via leitor próprio (futuro), nunca do CS via Strategy Tester. Lição V5 #2 ("um único produtor de bricks") aplicada literalmente.

---

### ADR-021: Bar parcial do brick em formação no Custom Symbol

**Data:** 2026-05-22
**Status:** Aceita
**Relação com ADR-020:** Substitui parcialmente as regras 2 e 4. ADR-020 permanece Aceita; ADR-021 estende.

**Contexto:**
ADR-020 fixou que o Custom Symbol recebe 1 bar OHLC por brick fechado (regra 2 + 4), via `CustomRatesUpdate`, sem tick stream populado. Após validação visual empírica (chart M1 do CS com bars sem wicks, em 2026-05-22), o usuário reportou:

> O brick atual deveria ter uma linha ask ou bid igual ao M1 normal, mostrando o brick em formação.

O efeito observado: no chart do CS, enquanto um brick está se formando (preço se movendo dentro dos limites do brick atual), **nada aparece**. A última bar visível é o último brick fechado. Em comparação, no chart M1 normal o último candle "cresce" tick a tick — comportamento esperado em qualquer plataforma de trading.

O builder atual já rastreia o brick em formação internamente (`m_formingHigh`/`m_formingLow`, getter `GetFormingBrick()` retornando `MksFormingBrick`). Não há nenhum mecanismo que propague esse estado para sinks — apenas bricks FECHADOS disparam `IRenkoSink::OnBrickClose`.

Três caminhos foram considerados:

- **(α) Template `.tpl` com linha bid do CS visível.** Inútil porque o "bid do CS" é o close do último brick fechado — fica imóvel entre bricks. Rejeitada.
- **(β) Indicador customizado lendo `SymbolInfoTick(símbolo_base)`.** Preserva ADR-020 intacta; desenha o preço real do mercado sobreposto ao chart do CS. Defendível, mas perde o "feel" do candle se formando.
- **(γ) Push de bar parcial no CS via `CustomRatesUpdate` a cada tick.** Visualmente fica igual ao M1 normal. Substitui parcialmente regras 2 e 4 da ADR-020. **Caminho escolhido.**

**Decisão:**
O Custom Symbol passa a receber a **bar do brick em formação** a cada tick processado pelo builder. As regras 2 e 4 da ADR-020 são substituídas parcialmente; o resto da ADR-020 (regra 1, 3, 5, 6, 7, 8, 9) permanece intacto.

1. **Regra 2 (substituída):** `CustomRatesUpdate` continua sendo o canal de atualização do CS — `CustomTicksAdd` segue rejeitado. Mas o CS agora recebe atualizações em dois momentos:
   - **A cada brick fechado:** bar definitiva no slot `nextBarTime`, SEM wicks (ADR-020 regra 3 preservada), incrementa `nextBarTime += 60s`.
   - **A cada tick processado:** bar PARCIAL do brick em formação no slot `nextBarTime` (o próximo livre, ainda não ocupado por brick fechado). COM wicks (excursão intra-brick visível). É a "última bar" do chart, que cresce/encolhe a cada tick.

2. **Regra 4 (substituída parcialmente):** Timestamp fictício M1 monotônico permanece. Cada brick fechado ocupa um slot M1. O brick em formação ocupa o slot SEGUINTE (`nextBarTime` já avançado) e é atualizado a cada tick. Quando o brick em formação fecha, sua bar parcial vira a bar definitiva (regra 3 — sem wicks), e o próximo brick em formação começa a ocupar o próximo slot.

3. **`IRenkoSink` ganha método `OnBrickForming(const MksFormingBrick &fb)`** como `virtual` com corpo default vazio (NÃO pure virtual). Sinks que não precisam (writer, capturing-sink dos testes existentes) seguem ignorando silenciosamente. Apenas `CMksCustomSymbolSink` implementa.

4. **`CMksRenkoBuilder.IngestTick`** ao final de toda chamada bem-sucedida (inclusive em ticks que fecharam brick e dispararam `OnBrickClose`) chama `m_sink.OnBrickForming(GetFormingBrick())` — **mas apenas quando a flag interna `m_emitForming` está em `true`**. A ordem é: primeiro `OnBrickClose` (se brick fechou nesse tick, dispara dentro do `IngestTick` como hoje), depois `OnBrickForming` ao fim do `IngestTick`. Nunca há race — sequência síncrona dentro de uma única chamada.

   **Flag `m_emitForming` default `true`.** O builder expõe `SetEmitForming(bool)` para o composition root controlar. Uso esperado: o EA (Producer) chama `builder.SetEmitForming(false)` antes de `RunHistoricalFill` (que processa centenas de milhares ou milhões de ticks), e `builder.SetEmitForming(true)` depois — assim o fill histórico não dispara `CustomRatesUpdate` por tick (que travaria o terminal por minutos). Em live, OnBrickForming é emitido normalmente.

5. **`MksFormingBrick` ganha campo `currentMid` (double).** Carrega o último `mid` observado pelo builder. Permite ao sink desenhar `close` da bar parcial igual ao preço atual. Antes do primeiro tick, `currentMid == 0.0` e `hasData == false` (sink ignora).

6. **`CMksCustomSymbolSink.OnBrickForming`** empurra `MqlRates` no slot `nextBarTime` com:
   - `open` = `fb.open` (close do último brick fechado).
   - `high` = `fb.high` (extremo observado durante a formação — COM wick).
   - `low` = `fb.low` (extremo observado durante a formação — COM wick).
   - `close` = `fb.currentMid` (preço corrente).
   - `tick_volume` = 0 (sem agregação ainda — brick não fechou).
   - Demais campos = 0.

   `CustomRatesUpdate` no mesmo slot a cada tick. Quando o brick fecha, `OnBrickClose` sobrescreve esse slot com a bar definitiva sem wicks (regra 3), e `nextBarTime += 60s` no próprio sink (igual hoje).

7. **Performance esperada:** `CustomRatesUpdate` por tick. Em XAUUSDm Exness ativo (~100 ticks/min em horário de Londres), ~6000 calls/hora. Sem benchmark prévio, mas a estrutura `MqlRates[1]` é leve e a chamada é local (não rede). Em testes empíricos posteriores, se virar gargalo, decisão futura sobre rate-limiting (ex.: atualizar a cada N ms ou a cada N ticks).

**Alternativas consideradas:**

- **(α) Template com linha bid do CS:** rejeitada (ver Contexto). Bid do CS fica congelado.
- **(β) Indicador customizado lendo símbolo base:** rejeitada como solução exclusiva, mas **mantida como possibilidade aditiva** num slice futuro caso o usuário queira ver explicitamente os thresholds do próximo brick acima/abaixo, ou alguma outra informação rica que não couber numa bar OHLC.
- **`OnBrickForming` como pure virtual:** rejeitada. Quebraria todos os sinks existentes (`CMksBrickWriterSink`, `CMksCapturingSink`, `CMksMultiSink`, mocks de teste) que teriam que implementar no-op explicitamente. Default vazio mantém compatibilidade.
- **Passar `currentMid` como argumento separado** em `OnBrickForming(fb, currentMid)`: rejeitada. Estender `MksFormingBrick` é mais coerente — `currentMid` é uma propriedade do estado em formação. Argumento extra polui a assinatura.
- **`OnBrickForming` em `IBroker`/`ITickSource` em vez de `IRenkoSink`:** sem sentido — o estado em formação é do **builder**, e os sinks são os consumidores naturais.
- **Bar parcial SEM wicks (igual aos bricks fechados):** rejeitada. Wicks na bar em formação são informação real (preço excursionou e voltou); ao fechar, o brick vira caixinha sólida (regra 3). A "perda de wicks" no momento do fechamento é coerente com o renko clássico — brick fechado é discreto, formação é contínua.
- **Empurrar a cada N ticks ou a cada N ms (throttling):** rejeitada como decisão inicial. Sem evidência de gargalo, throttle prematuro. Decisão futura se virar necessário.

**Consequências:**

- **`MksFormingBrick` ganha `currentMid`** (`Core/Types/FormingBrick.mqh`). Compatível com uso atual — quem só lê `open/high/low/direction/hasData` segue funcionando.

- **`CMksRenkoBuilder` armazena `m_lastMid`** (`double`), atualizado a cada `IngestTick` válido. `GetFormingBrick().currentMid = m_lastMid`.

- **`CMksRenkoBuilder` ganha membro `m_emitForming` (`bool`, default `true`)** + método público `SetEmitForming(bool v)`. Permite ao composition root suprimir o broadcast de forming sem mexer em sink.

- **`CMksRenkoBuilder.IngestTick`** ganha 1 linha ao final: `if(m_emitForming && m_sink != NULL) m_sink.OnBrickForming(GetFormingBrick());`. Chamado SEMPRE — em ticks válidos que fecharam brick, em ticks válidos que não fecharam, e em ticks inválidos? Decisão: **apenas em ticks válidos** (após a guarda de invalidação retornar OK). Tick inválido não atualiza estado interno do builder, não faz sentido emitir forming sobre estado obsoleto.

- **`Producer.mq5` integra o ciclo de fill histórico**: chama `g_builder.SetEmitForming(false)` antes de `RunHistoricalFill(InpHistoricalFillDays)` e `SetEmitForming(true)` depois. Apenas o último `OnBrickForming` (após o último tick processado em live) reflete o estado final — o fill histórico não toca o CS para bar parcial.

- **`IRenkoSink.OnBrickForming`** novo método virtual default vazio. Sinks existentes (`CMksBrickWriterSink`, `CMksCapturingSink`, `CMksFakeSymbol`, etc.) **não precisam mudar**.

- **`CMksCustomSymbolSink.OnBrickForming`** novo método. Empurra bar parcial conforme regra 6.

- **`Test_CMksRenkoBuilder.mq5` ganha cobertura** de `OnBrickForming`. `CMksCapturingSink` (mock de teste) ganha override de `OnBrickForming` que captura chamadas em array — permite afirmar quantas vezes foi chamado, com qual `MksFormingBrick`. Cobertura mínima: brick formando-se gera ticks com `OnBrickForming` capturado; `currentMid` reflete último tick.

- **`.mksbk` permanece com bricks FECHADOS apenas.** Bar parcial é só visual no CS; nenhum brick parcial é gravado em arquivo. Mantém integridade do `.mksbk` (ADR-012, ADR-014).

- **Validação empírica obrigatória:** Mike roda Producer no MT5 em mercado aberto e confirma que a última bar do chart cresce/encolhe a cada tick, e que ao fechar o brick, o slot vira caixinha sólida e a próxima bar começa a se formar no slot seguinte.

- **CHANGELOG e CHECKPOINT atualizados** registrando ADR-021.

**Fronteiras:**

- **Não cria backpressure para tick storms.** Cada tick = um `CustomRatesUpdate`. Se a thread de tick ficar atrás do mercado, é problema de plataforma, não desta ADR.

- **Não muda o builder em essência.** A semântica de "quando um brick fecha" segue idêntica (ADRs 010, 011). Apenas adiciona um evento de propagação de estado em formação.

- **Não muda o `.mksbk`.** ADR-012/013/014 intactas. Arquivo continua tendo só bricks fechados.

- **Não cobre indicador customizado** (caminho β). Fica disponível como extensão futura caso o usuário queira marcação rica de thresholds próximos ou outra info que não cabe numa bar OHLC.

- **Não cobre testes de performance.** Benchmark de `CustomRatesUpdate` por tick em XAUUSDm é decisão operacional pós-implementação. Se virar gargalo, throttling fica como ADR futura.

---

### ADR-022: Producer dinâmico — tipo, geometria, wicks toggle, naming estendido, auto-open

**Data:** 2026-05-22
**Status:** Aceita
**Relação com ADR-020:** Substitui parcialmente as regras 3 e 6. ADR-020 permanece Aceita; ADR-022 estende.

**Contexto:**
Após ADR-020 (Custom Symbol básico) e ADR-021 (bar parcial), o Producer ainda tem hardcodings que limitam o uso real: `MksGeometryMedian()` fixo (sem Classic ou Custom), `InpHistoricalFillDays=0` default (usuário precisa lembrar de setar 30 dias), naming `<symbol>.MKS_RKN<size>` que não distingue Median de Classic (mesma combinação `size=3` sobrescreve a mesma série, perdendo histórico do tipo anterior), e nenhuma abertura automática do chart do CS — usuário precisa abrir manualmente em M1 toda vez. Comparado ao V5 (Code-Review confirma `<symbol>_MKS_<size>_<mode>_<preset>` com Validate abrangente), o Producer atual é cru.

Pedido empírico de 2026-05-22:
> "atualmente o producer deve fazer o papel do generator e liveengine e ter as mesmas configurações básicas do V5 e ser aberto automaticamente e mostrar o renko de acordo com as configurações... quando inserir o producer no gráfico M1, quero que abra a caixa de configuração igual a do V5, após confirmar deve abrir automaticamente o CS no M1"

Tensões com ADR-020:
- **Regra 3** ("bricks no CS sem wicks") fixou ausência de wicks. Usuário quer toggle (default false continua).
- **Regra 6** ("naming `<symbol>.MKS_RKN<size>`") não comporta variação de tipo/preset. Configurações diferentes precisam de namespaces diferentes para não sobrescrever histórico anterior.

**Decisão:**
O Producer ganha configurabilidade rica via inputs nativos do MQL5 (popup ao arrastar EA no chart), naming carrega tipo+pro+po, wicks no CS são opcionais, e o chart do CS abre automaticamente em M1 após init. Sete regras:

1. **Tipo de geometria selecionável via `InpGeometryType`** — enum com três opções: `Median` (default, equivale a `MksGeometryMedian` = pro/po 0.50/0.50), `Classic` (pro/po 0.00/0.00, brick clássico simétrico), `Custom` (pro/po livres via `InpPro`/`InpPo`). Demais geometrias (ATR-based) ficam fora deste slice.

2. **`InpPro` e `InpPo` configuráveis** — defaults `0.50` e `0.50`. **Usados apenas quando `InpGeometryType == Custom`**. Em Median/Classic, ignorados (valores derivam do preset).

3. **`InpShowWicksInCS` default `false`** — quando `true`, `CMksCustomSymbolSink` empurra `brick.high`/`brick.low` cruamente (com wicks de excursão); quando `false`, empurra `max/min(open, close)` (caixinhas sem wicks, comportamento atual). Substitui a parte fixa da ADR-020 regra 3 — wicks viram preferência do operador.

4. **`InpHistoricalFillDays` default vira `30`** — alinhado com V5. Operador que quer apenas live seta `0`. Trade-off aceito: cold start passa a carregar 30 dias por padrão, mais lento mas com história visível imediatamente.

5. **Naming estendido — substitui ADR-020 regra 6.** Formato: `<symbol>.MKS_<typeCode>_<sizeStr>` para Median/Classic; `<symbol>.MKS_X_<sizeStr>_<proInt>_<poInt>` para Custom. Códigos: `M` = Median, `C` = Classic, `X` = Custom. `sizeStr` é inteiro quando size é inteiro (ex.: `3`), com 2 decimais quando fracionário (ex.: `3.50`). `proInt`/`poInt` = `round(pro*100)`/`round(po*100)` (ex.: `0.65` vira `65`). Exemplos: `XAUUSDm.MKS_M_3`, `XAUUSDm.MKS_C_3`, `XAUUSDm.MKS_X_3_30_70`. Limite de 32 chars do MT5 verificado em runtime via comprimento total — se ultrapassar, Producer aborta com `INIT_PARAMETERS_INCORRECT` e log explicativo.

6. **`ChartOpen(csName, PERIOD_M1)` ao final do `OnInit`** — após geometry, writer, sinks e builder estarem prontos e `RunHistoricalFill` ter rodado, o Producer abre o chart do CS em M1 automaticamente. Se o chart já estiver aberto (mesmo CS), `ChartOpen` retorna o handle existente — comportamento desejado. Se falhar, Producer apenas loga warning (não aborta) — chart é cosmético.

7. **Inputs organizados em grupos via `input group`** (recurso MQL5 build 3000+): "Brick", "Risco/Volatilidade", "Histórico/Live", "Logging", "Custom Symbol". Tooltips em cada input. Popup nativo do MT5 ao arrastar EA já é a "caixa de configuração" do V5 — não há janela customizada (decisão pragmática registrada).

8. **CS renderiza bricks com tamanho visual FULL** (= `InpBrickSizePts`), independentemente do `PO`/`PRO` da geometria. Especificamente, o `CMksCustomSymbolSink.OnBrickClose` desenha bar com `open = brick.open`, `close = brick.open ± InpBrickSizePts` (sinal pela direção). Isso reproduz o visual Median Renko tradicional do V5 — bricks de tamanho cheio com sobreposição igual a `PO*size` no eixo de preço. O `.mksbk` continua gravando `brick.close = open + (1-PO)*size` (close matemático, ADR-010). Divergência deliberada entre CS (visual) e `.mksbk` (matemática) — coerente com ADR-020 regra 1 (CS é só visualização humana, código de lógica consome `.mksbk` ou direto do builder, não o CS). Para Classic (`PO=0`), visual = matemático (sem diferença). Para Median (`PO=0.5`) e Custom (`PO>0`), visual estende além do matemático.

**Alternativas consideradas:**

- **Janela customizada com `ChartObjectCreate`/`EditCreate`** (popup próprio): rejeitada. ~500 linhas de UI code MQL5, frágil entre versões do MT5, e o popup nativo já cobre o caso. Investimento alto, retorno baixo.
- **Naming completo com `<symbol>_MKS_<size>_<mode>_<preset>` (igual V5):** próximo do escolhido, mas formatação ligeiramente diferente. Decisão: usar `.` como separador entre símbolo e namespace (consistente com convenção atual) e `_` dentro do namespace. `MKS_M_3` em vez de `_MKS_3_M`. Limite 32 chars respeitado.
- **Adicionar tipo ATR neste slice:** rejeitada por escopo. ATR exige `CMksAtrBrickSizer` + período + warm-up — slice próprio. ADR-022 cobre só os 3 tipos imediatos.
- **`InpShowWicksInCS` default `true`:** rejeitada. ADR-020 fechou em "sem wicks" pra visual renko clean. Mudar default reabre confusão visual já resolvida. Quem quer wicks ativa explicitamente.
- **Deletar+recriar CS quando configs diferem:** rejeitada. Naming estendido (regra 5) já resolve — configs diferentes geram CSs diferentes, sem sobrescrever. `CustomSymbolDelete` automático fica fora; cleanup utility (ADR-020 regra 8) cuida disso quando o operador quiser.
- **Naming sem `_` interno (collapsed):** ex.: `XAUUSDm.MKSM3` ou `XAUUSDm.MKSX36570`. Rejeitada — ilegível. O custo de 1-2 chars extras compensa legibilidade.

**Consequências:**

- **`Producer.mq5` ganha inputs novos**: `InpGeometryType` (enum), `InpPro` (double), `InpPo` (double), `InpShowWicksInCS` (bool), reorganização em grupos. `InpHistoricalFillDays` default muda 0→30.

- **`Producer.OnInit` faz build dinâmico da `MksRenkoGeometry`**: switch no `InpGeometryType` → escolhe Median/Classic/Custom; valida via `geometry.Validate(err)`.

- **`Producer.BuildCustomSymbolName`** é estendida: passa a aceitar `type/pro/po` além de symbol/size. Formato conforme regra 5.

- **`CMksCustomSymbolSink` ganha campo público `showWicks` (default `false`)**: `OnBrickClose` lê `showWicks` para decidir se empurra `brick.high`/`brick.low` cruamente ou `max/min(open, close)`. Mesma flag controla `OnBrickForming` (consistente).

- **`Producer.OnInit` chama `ChartOpen(csName, PERIOD_M1)` ao final**, após `RunHistoricalFill`. Resultado loga via `g_logger.Info` com chartId.

- **Sem mudança nos testes existentes** — `Test_CMksRenkoBuilder` etc. não são afetados (mudança é no Producer, que é EA, não tem testes unitários hoje).

- **ADR-020 regra 3** passa a ser interpretada como "default sem wicks; configurável via `InpShowWicksInCS` (ADR-022)".

- **ADR-020 regra 6** passa a ser superseded por ADR-022 regra 5.

- **CHANGELOG.md** registra ADR-022 + reorganização de inputs + auto-open.

**Fronteiras:**

- **Não cobre ATR como tipo de geometria.** Hoje temos `CMksAtrBrickSizer` pronto, mas ADR-018 fixou que ele lê bricks fechados — então o sizer alimenta o builder, mas a "geometria" continua sendo Median/Classic/Custom. Adicionar `InpGeometryType=ATR` seria uma simplificação tendenciosa porque mistura o eixo "preço dos thresholds" (pro/po) com o eixo "tamanho do brick" (sizer). Fica fora.

- **Não cobre delete automático de CS antigos.** Operador limpa Market Watch manualmente ou via script utility (ADR-020 regra 8, ainda dívida pendente).

- **Não cobre validação de path de inputs interdependentes** (ex.: usuário escolhe Median mas seta `InpPro=0.7`). Producer ignora `InpPro/InpPo` quando type≠Custom; é decisão de implementação, não erro.

- **Não cobre persistência das configs entre sessões** além do que o MT5 já faz nativamente (last-used inputs).

- **Não cobre multi-símbolo.** Producer continua per-símbolo (ADR-017 §2).

- **Não cobre input para `revSizeRatio` da geometry.** Continua fixo em `1.0` (default da `MksRenkoGeometry`). Se virar necessidade, ADR posterior.

---

### ADR-023: Timeline híbrida no Custom Symbol (real + bump)

**Data:** 2026-05-22
**Status:** Proposta (implementação adiada para fase de produto — ver §Implementação)
**Relação com ADR-020:** Substituirá parcialmente regra 4 quando implementada. ADR-020 permanece Aceita; ADR-023 estende.

**Contexto:**
ADR-020 regra 4 fixou que o timestamp das bars do Custom Symbol é **fictício M1 monotônico** (`nextBarTime += 60s` por brick, independente do tempo real). Essa decisão resolve estruturalmente o problema de `CustomRatesUpdate` sobrescrever bars com mesmo `time` — cada brick precisa de slot único, então +60s garante separação visual em chart M1.

Auditoria de 2026-05-22 (discussão com o dono em chat) identificou que o tempo fake gera dor real para visão de produto, mesmo sem quebrar nada técnico do core:

- Análise temporal visual empobrecida (não dá pra ver se um rally durou 5min ou 5h olhando o chart)
- Sessões (Sydney/Tokyo/London/NY) invisíveis no eixo X
- Gaps de fim de semana somem (sexta 23h e segunda 00:01 ficam encostados visualmente)
- Múltiplos CSs com `size` diferentes não dá pra comparar visualmente
- Timestamps no futuro (após 9430 bricks em fill histórico, chart mostra bricks até 6.5 dias adiante em tempo fake) — fricção imediata em onboarding de cliente
- Integração com news feed / calendar API fica inutilizada (eixo X não bate com tempo real)

Investigação do projeto `Renko-MQL5` (auditado em paralelo, [`Renko-MQL5/mql5/Include/RenkoCharts.mqh:172-177`](Renko-MQL5/mql5/Include/RenkoCharts.mqh#L172-L177)) revelou padrão **híbrido real + bump** que resolve 80% do problema sem mudar visual:

```cpp
if(time <= renko_buffer[index-1].time)
   renko_buffer[index].time = renko_buffer[index-1].time + 60;
else 
   renko_buffer[index].time = time;
```

Em mercado calmo (1 brick a cada vários minutos): time real é maior que `último+60s` → usa real, **granularidade de segundos aparece naturalmente**. Em mercado frenético (vários bricks por minuto): bump +60s garante visual separado. Catch-up automático quando mercado fica parado por longos períodos.

Alternativa "+1s entre bricks rápidos" foi considerada e rejeitada: chart M1 do MT5 **agrega** bricks do mesmo minuto numa única candle composta, destruindo o visual renko exatamente em momentos de alta volatilidade (notícias, NFP, FOMC) — quando mais se quer ver os bricks individualmente. MT5 não tem timeframes sub-minuto nativos.

Alternativa "CustomTicksAdd em vez de CustomRatesUpdate" também foi considerada e rejeitada: ganho de timeline perfeita, mas perda do visual renko com sobreposição (ADR-022 regra 8), perda da bar parcial em formação (ADR-021), perda do controle de wicks por brick. CS viraria "candle M1 normal filtrada por bricks", indistinguível de outras séries.

**Decisão:**
O CS adota timeline **híbrida real + bump** quando esta ADR for implementada. Quatro regras substituem parcialmente a ADR-020 regra 4:

1. **Inicialização do `nextBarTime` em `0`** (epoch) em vez de `AlignDownToM1(TimeCurrent())`. O primeiro brick decide o slot de partida.

2. **Por brick fechado:**
   ```cpp
   datetime realTime = (datetime)(brick.closeTimeMsc / 1000);
   datetime brickTime = (realTime > nextBarTime) ? realTime : nextBarTime;
   rates[0].time = brickTime;
   // ... grava brick
   nextBarTime = brickTime + 60; // próximo slot mínimo
   ```
   Logic: se o tempo real do tick que disparou o brick é maior que o último slot+60s, usa real. Senão, usa último+60s (bump).

3. **Bar parcial (`OnBrickForming`) usa `nextBarTime` atual** (igual hoje). Em mercado calmo, isso pode resultar em "bar parcial presa em um slot do passado" enquanto preço se move agora — aceitável, é o que `Renko-MQL5` faz. Alternativa (atualizar slot da parcial por tick) destruiria visual.

4. **Fill histórico opera idêntico ao live** — `closeTimeMsc` do tick histórico já é o tempo real do passado. Resultado: 9430 bricks de 30 dias ficam **distribuídos nos 30 dias reais** (não em 6.5 dias futuros como hoje).

**Alternativas consideradas (todas rejeitadas):**

- **`+1s` literal entre bricks consecutivos:** quebra visual em mercado frenético (60 bricks/min agregam em 1 candle M1 composta). Pior em momentos críticos.
- **`CustomTicksAdd` (ticks reais no CS):** timeline perfeita mas destrói visual renko, bar parcial, controle de wicks. Sacrifício alto demais.
- **Dois CSs paralelos (rates + ticks):** dobra complexidade. CS rates pra visual, CS ticks pra timeline. Usuário escolheria qual abrir. Adiado.
- **Manter timeline fake permanentemente:** posição padrão do framework atualmente. Aceitável para uso interno / lab pessoal, inaceitável para produto.

**Consequências:**

- **`CMksCustomSymbolSink.OnBrickClose`** muda ~5 linhas — usa `brick.closeTimeMsc` para decidir slot.
- **`CMksCustomSymbolSink.OnBrickForming`** sem mudança — continua usando `nextBarTime` como slot.
- **`Producer.OnInit`** inicializa `g_nextBarTime = 0` em vez de `AlignDownToM1(TimeCurrent())`.
- **ADR-020 regra 4** fica explicitamente substituída por esta ADR-023 quando implementada. Documentação cruzada.
- **ADR-020 regra 5** ("chart timeframe M1") permanece intacta — granularidade ≥ 60s entre bricks consecutivos é mantida pelo bump.
- **`.mksbk` intacto** — `closeTimeMsc` real já é gravado.
- **Sem regressão em testes existentes** — `Test_CMksRenkoBuilder` etc. não dependem do sink timing.
- **Possível teste novo:** `Test_CMksCustomSymbolSink_Timeline` validando os 3 cenários (calmo / frenético / catch-up) com mocks de tempo. Slice da implementação.

**Implementação:**

**Adiada deliberadamente.** Esta ADR fica como Proposta até a fase de produto do framework. Razão: nenhum impacto técnico funcional do core; impacto é puramente de UX/percepção. Outras frentes (Slice 5b TradeManager, Slice 6.2/6.3 Risk camadas restantes, painel UX, log-diff tool) têm prioridade. Quando o framework for empacotado como produto comercial ou abrir para usuários externos, esta ADR é uma das primeiras a executar — custo trivial (~20 linhas de código + testes), benefício grande de UX.

Critério para promover de Proposta para Aceita + executar: qualquer um dos eventos abaixo:
- Decisão de produtizar o framework (alpha externo, beta fechado, lançamento comercial)
- Primeira demo para terceiro (cliente, contratante, parceiro) — timestamps fake são deal-breaker visual
- Integração com calendar API / news feed (não há sentido em overlay de eventos sobre eixo X fake)
- Suporte requerido a múltiplos CSs comparativos (size 3 vs size 5 lado a lado)

**Fronteiras:**

- Não cobre granularidade sub-segundo. `MqlRates.time` é `datetime` (segundo). Bricks que fecham no mesmo segundo bumpam +60s — colisões de segundo são raras mas tratadas.
- Não cobre múltiplos CSs comparativos (cada Producer roda independente). Comparação visual entre CSs depende de cada um adotar esta ADR.
- Não cobre `CustomTicksAdd` (decisão de não usar ticks, ADR-020 regra 2).
- Não cobre Strategy Tester. O tester continua usando série OHLC do CS — com timeline real do passado quando esta ADR estiver ativa, o backtest sintético do tester reflete melhor o tempo real, mas continua armadilha (ADR-020 regra: bricks como fonte de verdade vêm de `.mksbk`, não do CS via tester).
- Não cobre indicador customizado com bid/ask em tempo real (item separado, futuro).

---

### ADR-024: Captura e replay de ticks crus — formato `.mkstick`, Service de gravação, EA de replay

**Data:** 2026-05-23
**Status:** Aceita
**Relação:** Materializa o trabalho pendente da ADR-012 (§5 layout binário e §Consequências captura/consumo) e fecha a porta arquitetural prevista na ADR-015 (§Consequências engine de backtest fora do tester). Não cria arquitetura nova; quita duas dívidas explícitas.

**Contexto:**
ADR-012 fixou o contrato de integridade da fonte histórica de ticks — cru, broker-locked, proveniência, flags preservados, formato binário versionado próprio — e ADR-015 fixou que o backtest oficial roda fora do Strategy Tester nativo, via composition root do framework. Ambas referenciam um "arquivo de captura de ticks a ser definido" e um "engine de backtest próprio" como trabalho posterior, dívidas explicitamente assumidas. Esta ADR quita as duas em conjunto.

O `.mksbk` (ADR-014) cobre persistência de bricks fechados. Mas dois bricks com OHLC matemático idêntico podem ter sido produzidos por sequências diferentes de ticks — `triggerTickId` é seq local ao run do Producer. Sem o stream de ticks que gerou os bricks, não é possível reproduzir bit-a-bit o que aconteceu em live: `CopyTicksRange` lido a posteriori pode divergir dos ticks que chegaram em tempo real (dedup retroativo, agregação, ticks perdidos). O eixo 2 do V5 ressurge por essa porta, mais sutil — não pela bifurcação de código (já vetada), mas pela divergência de dados.

A solução simétrica é gravar `MksTick` no momento da chegada e replayar pelo mesmo `CMksRenkoBuilder`. Como o builder é determinístico por construção (mesmo stream → mesmos bricks, mesmos `triggerPrice`/`triggerTickId`/M), paridade do feed e da decisão da estratégia fica garantida bit-a-bit. Paridade da execução (preço de fill, latência, rejeição) permanece modelada — não é dado capturável na maioria dos brokers e é trabalho do `CMksSimulatedBroker` + StressLab.

**Decisão:**
Materializa-se o caminho `tick → Builder → brick` como infraestrutura de captura e replay simétrica ao `.mksbk`. Sete regras:

1. **Formato binário `.mkstick` v1 — layout fixado.** Espelha o `.mksbk` em estrutura: HEADER de 256 bytes (magic `"MKSTK01"` + versão `1` + record_size `64` + headerSize `256` + broker/account/symbol/digits trancados + tickCount/timeMscFirst/timeMscLast/createdAtMsc/closedAtMsc patcheados no Close + tickSize/point/contractSize do símbolo no momento da abertura + reserved zero-fill) seguido de RECORDS de 64 bytes por tick (seq uint64, timeMsc int64, bid double, ask double, last double, volume int64, flags uint32, 12 bytes reservados para alinhamento e futuras extensões). Little-endian, sem padding entre campos do record. Tamanho total = 256 + 64 × tickCount. Constantes em `Core/Data/TickFileFormat.mqh`, espelhando `BrickFileFormat.mqh`.

2. **Captura é Service, não EA.** O artefato `MQL5/Services/MKS-ULTIMATE/TickRecorder.mq5` roda em background (sem chart), alinhado à seção 2 do ARCHITECTURE.md (`MQL5/Services/ — Coletores de tick em background e workers independentes de gráfico`). Assina ticks via `OnTick` do Service ou agendamento `OnTimer` chamando `SymbolInfoTick`. Append-only ao arquivo, flush a cada N=100 ticks ou T=1s (o que vier primeiro). Header patcheado no `OnDeinit`. Tolerância a reopen no mesmo dia: detecta header existente, valida proveniência exata (broker/account/symbol/digits), continua append em posição correta. Reopen com proveniência incompatível aborta com erro 802.

3. **Granularidade: 1 arquivo por dia UTC.** Nome `<symbol>_YYYYMMDD.mkstick` (ex.: `XAUUSDm_20260523.mkstick`). Roll-over à 00:00 UTC, equivalente ao roll-over do `.mksbk` em ADR-014. Operador rodando 5 dias = 5 arquivos sequenciais. Replayer aceita lista de arquivos ou diretório, replaya em ordem cronológica garantida pela ordem natural do filename.

4. **Consumo via `CMksFileTickSource` — implementa `ITickSource` (ADR-004).** Open valida magic + version + record_size + headerSize. Compara proveniência do arquivo contra conta corrente: broker/account diferentes geram WARN no logger (não fatal, conforme ADR-012 §2 e ADR-013 §3); symbol diferente é fatal (erro 803). `Next(MksTick&)` lê record-a-record na ordem natural do arquivo (cronológica por construção da captura). Encerra com `false` no EOF. Multi-arquivo: o source mantém estado interno, transitiona transparentemente do EOF do arquivo N para o arquivo N+1, validando que o último seq do N é estritamente menor que o primeiro seq do N+1 (continuidade da seq cross-file).

5. **Replay via `Replayer.mq5` — EA em chart qualquer, fora do Tester.** O EA monta o composition root completo no `OnInit`:
   - `ITickSource` = `CMksFileTickSource(InpTickFilePath)` ou `(InpTickFolder)` para multi-arquivo
   - `IClock` = `CMksReplayClock(tickSource)` — `Now()` retorna `currentTick.timeMsc / 1000`
   - `IBroker` = `CMksSimulatedBroker` (configurado via `CMksCostModel` por inputs do EA)
   - `Builder`, `Sizer` (Fixed ou ATR), `RiskManager`, `Logger`, `BrickFileWriter`, `CustomSymbolSink` — instâncias idênticas às da live
   - Estratégia futura — mesma classe da live, sem `if(MQL_TESTER)` em nenhum ponto

   `OnInit` abre source e writer, dispara `EventSetMillisecondTimer(InpTickIntervalMs)` (default `0` = throughput máximo; valor positivo = sleep entre ticks para debug visual). `OnTimer` faz loop apertado: `source.Next() → builder.IngestTick() → sink/strategy reagem → simulatedBroker fecha trades`. EOF do source dispara `EventKillTimer`, fecha writer, imprime sumário e desliga via `ExpertRemove`. Roda em chart de qualquer símbolo — o chart é só hospedeiro, nenhum dado vem dele.

6. **Regras vinculantes para a estratégia ser replay-safe.** A `REGRAS.md` ganha cláusula §1.9: proibido na estratégia o uso direto de `TimeCurrent`, `TimeLocal`, `MathRand` sem seed injetada, `_Symbol`, `_Period`, `SymbolInfoTick`/`SymbolInfoDouble`/`SymbolInfoInteger` em decisão de runtime, `AccountInfo*` em decisão de runtime, `iCustom`/`iHigh`/`iLow`/leitura de bars do CS. Tudo via interfaces injetadas — `IClock`, `ISymbol`, `IAccount`, `IBroker`, `ITickSource`, e o feed Renko apenas via callbacks de `IRenkoSink`. Violação é bug de paridade, bloqueia merge. Auditoria via grep no Protocolo 1.

7. **Validação canônica — a "prova" da ADR.** Pipeline obrigatório no Protocolo 1 quando módulos que tocam paridade são declarados prontos:
   - **(a)** Rodar Producer em live por janela ≥ 1h — gera `live.mkstick` + `live.mksbk` + `live.log`.
   - **(b)** Rodar Replayer sobre `live.mkstick` — gera `replay.mksbk` + `replay.log`.
   - **(c)** `fc /b live.mksbk replay.mksbk` byte-idêntico. Diferiu = não-determinismo no builder ou regressão de dados.
   - **(d)** `diff` filtrando linhas com chave `decision=*` do log byte-idêntico. Diferiu = estratégia tem dependência não-injetada.
   - **(e)** Equity de execução pode diferir entre live e replay — delta de modelagem do `CMksSimulatedBroker`/StressLab, documentado e fora do escopo desta paridade.

   Esses passos viram `tools/verify-parity.ps1`, materializando a "log-diff tool" pendente da Fase 8.

**Alternativas consideradas:**

- **Usar `.tks` nativo do MT5 + `CustomTicksAdd` para injetar ticks no Tester:** rejeitada por ADR-015 (Tester não é fonte de verdade) e por ADR-012 §Alternativas (`.tks` é formato fechado de terceiros, viola invariante 5 do §1).

- **Replay dentro do Strategy Tester via Custom Symbol alimentado com `CustomTicksAdd`:** rejeitada. O Tester reagrupa/sintetiza os ticks pelo seu próprio modo (every-tick ou 1-min OHLC), reabrindo o eixo 2 do V5 com roupa nova — o feed que a estratégia vê dentro do Tester não bate com o `.mkstick` original. Já vetado pela combinação ADR-015 §1 + ADR-020 regra 1.

- **Recorder como EA em chart em vez de Service:** rejeitada. EA depende de `OnTick` do símbolo do chart hospedeiro — se o chart é fechado por engano, a captura para silenciosamente. Service em background é desacoplado de chart, sobrevive a fechamento de gráficos e está alinhado à seção 2 do ARCHITECTURE.md (pasta `MQL5/Services/` foi reservada precisamente para isso). Custo: Services no MT5 não têm UI; operador inspeciona via journal e via tamanho do arquivo crescendo.

- **Recorder gravando direto no `.mksbk` (sem `.mkstick` separado):** rejeitada. Quebra a separação ADR-012 §6 (captura e consumo são artefatos distintos) e impede o replay de redescobrir bricks a partir dos ticks — bricks ficariam acoplados ao run específico do recorder, sem reprodutibilidade do builder. Manter `.mkstick` como fonte primária e deixar `.mksbk` ser sempre derivado é o que permite a regra 7c (fc/b byte-idêntico).

- **Formato CSV ou JSON em vez de binário:** rejeitada por ADR-012 §Alternativas — precisão float em texto sem round-trip determinístico, parsing lento, arquivo grande, drift de formatação entre versões do MT5.

- **Granularidade por sessão de mercado (overlap real) em vez de dia UTC:** rejeitada. Dia UTC é boundary natural sem ambiguidade, consistente com `.mksbk` (ADR-014). Sessões variam por broker e introduzem ambiguidade no naming e na ordenação cronológica de arquivos.

- **Replayer como Script em `MQL5/Scripts/` em vez de EA:** rejeitada. Script roda síncrono em `OnStart` único, sem `OnTimer`, sem possibilidade de modo `RealTime` com sleep entre ticks para debug visual, sem parada limpa por `ExpertRemove`. EA com Timer cobre throughput máximo e RealTime no mesmo código.

- **`IClock` no replay derivar de wall-clock multiplicado por fator de aceleração:** rejeitada. Reintroduz dependência de tempo externo no caminho determinístico. `IClock.Now()` retornando `currentTick.timeMsc/1000` é função pura do feed — determinismo preservado, e o relógio "avança" naturalmente em sincronia com os ticks consumidos.

- **Captura multi-símbolo no mesmo arquivo:** rejeitada por esta ADR (ver §Fronteiras). Operador rodando N símbolos = N Services em paralelo, N arquivos/dia. Multi-símbolo é ADR futura quando estratégias multi-asset surgirem.

- **Capturar L2 book (`MarketBookGet`) ao lado de cada tick desde já:** rejeitada por escopo. O `flags bit0=hasBook` do header está reservado, mas a captura de book é trabalho posterior — `CMksCostModel` modela slippage sem book hoje. Quando broker expõe e estratégia exige modelagem mais honesta, ADR posterior amplia o record sem quebrar v1 (versão do header sobe para 2 ou bit0 acende e adiciona-se record paralelo `.mkstickbk`).

**Consequências:**

- **Arquivos novos no core de Data:**
  - `Core/Data/TickFileFormat.mqh` — constantes do layout binário, espelhando `BrickFileFormat.mqh`
  - `Core/Data/CMksTickFileWriter.mqh` — writer espelhando `CMksBrickFileWriter`
  - `Core/Data/CMksTickFileReader.mqh` — reader espelhando `CMksBrickFileReader`
  - `Core/Data/CMksFileTickSource.mqh` — implementa `ITickSource`, encapsula o reader

- **Nova pasta `Core/Clock/`** com:
  - `CMksMt5Clock.mqh` — implementa `IClock`, retorna `TimeCurrent()` (uso live; consolida lógica que hoje vive implícita no Producer)
  - `CMksReplayClock.mqh` — implementa `IClock`, retorna `currentTick.timeMsc/1000` do `ITickSource` corrente

- **Novo Service `MQL5/Services/MKS-ULTIMATE/TickRecorder.mq5`** — captura dedicada, single-symbol por instance.

- **Novo EA `MQL5/Experts/MKS-ULTIMATE/Replayer.mq5`** — consumidor do `.mkstick`, monta composition root completo.

- **Novos códigos de erro na faixa 800–899** (reservada por ADR-012 §Consequências):
  - `MKS_ERR_TICKFILE_INVALID_HEADER` = 800 — magic ou versão inválidos
  - `MKS_ERR_TICKFILE_PROVENANCE_MISMATCH` = 801 — proveniência divergente da conta corrente (WARN, não fatal)
  - `MKS_ERR_TICKFILE_REOPEN_INCOMPATIBLE` = 802 — reopen com header diferente (fatal)
  - `MKS_ERR_TICKFILE_SYMBOL_MISMATCH` = 803 — símbolo do arquivo ≠ símbolo de consumo (fatal)
  - `MKS_ERR_TICKFILE_SEQ_DISCONTINUITY` = 804 — multi-arquivo com seq descontínua cross-file
  - `MKS_ERR_TICKFILE_IO` = 810 — falha de I/O genérica do writer/reader

   Observação: a faixa 800–899 já está ocupada pelos códigos de `Data` materializados na ADR-012 (`MKS_ERR_DATA_FILE_IO=800` … `MKS_ERR_DATA_FILE_EXISTS=806`). A renumeração concreta dos códigos do TickFile dentro da mesma faixa fica para o slice 24c, que reconciliará os dois conjuntos sem reabrir esta ADR (a faixa é a fronteira arquitetural; o número exato dentro da faixa é detalhe do serializador, conforme ADR-012 §Consequências).

- **`REGRAS.md` ganha §1.9** — proibições da regra 6 acima. Lint check no Protocolo 1: `grep -rE "(TimeCurrent|TimeLocal|MathRand|_Symbol|_Period|SymbolInfo|AccountInfo)" MQL5/Experts/` na pasta de estratégias deve dar zero hits (exceto em comentários explícitos de "uso intencional documentado").

- **`docs/PROTOCOLOS.md` Protocolo 1 ganha item:** "se o módulo toca paridade (RenkoBuilder, ITickSource, IClock, IBroker, estratégia), executar `tools/verify-parity.ps1` antes de declarar pronto. `fc /b` dos `.mksbk` e `diff` das linhas `decision=*` do log têm que dar zero divergência."

- **`tools/verify-parity.ps1`** — script novo, materializa a regra 7 e fecha a dívida da Fase 8 (log-diff tool). Recebe dois pares (live.mksbk/log + replay.mksbk/log) e reporta diff com exit code não-zero em qualquer divergência.

- **`docs/ROADMAP.md` ganha Fase 4.5 — "Tick Recorder + Replayer"**, posicionada entre Fase 4 (Broker abstractions, concluída) e Fase 5a (PositionSizer, concluída) historicamente — mas, como Fase 5a já foi executada antes, esta fase é declarada concluída ao final da implementação desta ADR. Critério de saída: regra 7 (validação canônica) passa em janela ≥ 1h com zero divergência em (c) e (d).

- **Tamanho de arquivo gerenciável.** XAUUSDm com ~10 tps de média 24h × 64 bytes = ~55 MB/dia/símbolo. Janela de 30 dias ≈ 1.6 GB/símbolo. Compressível com zstd offline em ~3x (não é responsabilidade do framework — housekeeping do operador).

- **Sequência de implementação estimada (6 commits, ~1.5k linhas + testes):**
  1. `TickFileFormat.mqh` + `CMksTickFileWriter.mqh` + `CMksTickFileReader.mqh` + `Test_CMksTickFile` (golden-file round-trip: escreve 10k ticks sintéticos, lê de volta, byte-idêntico)
  2. `CMksMt5Clock.mqh` + `CMksReplayClock.mqh` + `CMksFileTickSource.mqh` + `Test_CMksFileTickSource`
  3. Novos códigos de erro 800–810 em `Error.mqh` (reconciliação com códigos `MKS_ERR_DATA_*` pré-existentes da ADR-012)
  4. `TickRecorder.mq5` Service + execução empírica de 1h para gerar primeiro `.mkstick` real
  5. `Replayer.mq5` EA + execução empírica sobre o `.mkstick` do passo 4 → gera `replay.mksbk`
  6. `tools/verify-parity.ps1` + atualização do Protocolo 1 + atualização do REGRAS.md §1.9 + atualização do ROADMAP.md (Fase 4.5 declarada concluída)

**Fronteiras:**

- **Não cobre captura multi-símbolo no mesmo arquivo.** 1 arquivo = 1 símbolo. Operador rodando N símbolos = N Services em paralelo. Multi-símbolo unificado é ADR futura quando surgirem estratégias multi-asset; o overhead arquitetural disso (sincronização de seqs entre símbolos) não vale antes de existir consumidor real.

- **Não cobre captura de book L2.** `flags bit0=hasBook` reservado no header para versão 2. Hoje slippage é estimativa do `CMksCostModel`; quando broker expõe book e estratégia exige modelagem mais honesta, ADR posterior amplia o record sem quebrar a v1.

- **Não cobre paridade de execução** (preço de fill, latência real, rejeições). Esses ficam modelados por `CMksSimulatedBroker` + `CMksCostModel` + StressLab (Fase 7). Esta ADR fixa paridade do FEED + DECISÃO; execução é trabalho de modelagem, com erro residual aceito e documentado.

- **Não cobre compressão do arquivo.** Operador comprime offline (zstd, gzip, 7z) se quiser; framework lê apenas o binário cru, sem dependência de biblioteca de compressão.

- **Não cobre captura de wall-clock do recorder** (timestamp de recebimento local) separado do timestamp do broker. `MksTick.timeMsc` é suficiente para determinismo do builder. Auditoria de latência live exigiria clock próprio do recorder e fica fora desta ADR.

- **Não cobre purga automática de arquivos antigos.** Operador gerencia retenção; framework não deleta `.mkstick` antigos. Quando virar problema, script utility análogo ao `MksCleanupCustomSymbols.mq5` (ADR-020 regra 8).

- **Não cobre paridade entre brokers diferentes.** Por ADR-012 §2, paridade é condicional ao broker da captura coincidir com o broker da conta de execução. Replay de `.mkstick` da corretora A num backtest cuja conta é corretora B funciona tecnicamente (com WARN), mas a paridade arquitetural não se aplica — é experimento de calibração cross-broker, não release.

---

**Nota de esclarecimento — timestamps wall-clock no header do `.mksbk`** (2026-05-24)

A ADR-024 §regra 7c diz: "`fc /b live.mksbk replay.mksbk` byte-idêntico. Diferiu = não-determinismo no builder ou regressão de dados". Auditoria pré-validação empírica em 2026-05-24 identificou que essa formulação é literalmente incorreta — o `.mksbk` tem um campo de timestamp wall-clock no header que diverge inerentemente entre live e replay:

```
offset 184  size 8  int64  createdAtMsc  (TimeCurrent na hora do Close)
```

- Em **live**: `createdAtMsc` = `TimeCurrent` no momento de `Producer.OnDeinit` (quando o operador desanexa o EA).
- Em **replay**: `createdAtMsc` = `TimeCurrent` no momento de `Replayer.OnDeinit` (quando o EA atinge EOF — pode ser horas ou dias depois).

Esses 8 bytes (offset 184-191) divergem sempre, mesmo com builder 100% determinístico. `fc /b` puro daria falso negativo garantido.

**A regra 7c é refinada — não revogada — para excluir esse range específico**:

> "**Comparação byte-a-byte do `.mksbk` ignorando o range 184-191 do header** (`createdAtMsc`, wall-clock). Divergência em qualquer outro byte = não-determinismo no builder ou regressão de dados."

O `tools/verify-parity.ps1` implementa exatamente essa exclusão. O range ignorado é mínimo (8 bytes em ~700KB típicos = 0.001% do arquivo) e bem-delimitado. Todos os outros campos do header (proveniência, geometria, `brickSizePoints`, `brickCount`, `timeMscFirst`, `timeMscLast` — esses últimos vêm dos ticks, não wall-clock) e os 72 bytes × N de cada brick continuam sob escrutínio total.

**Para diagnosticar uma divergência futura**: o script reporta o offset exato + identifica o campo (`header.<field>` ou `brick[N].<field>`), e exibe os bytes em hex ao redor do ponto de divergência. Divergência em campo do header indica problema de metadata (proveniência, geometry, brickSize); divergência em campo de brick indica não-determinismo do `CMksRenkoBuilder` ou feed divergente (o `.mkstick` consumido pelo Replayer não corresponde aos ticks que o Producer viu em live).

Esta nota também identifica que o `.mkstick` tem **dois** timestamps wall-clock no header (`createdAtMsc` em 184-191 e `closedAtMsc` em 192-199). O `.mkstick` não é comparado pelo `verify-parity.ps1` — apenas o `.mksbk`. Se um pipeline de comparação de `.mkstick` for criado no futuro, deve excluir o range 184-199 (16 bytes).

A ADR-024 não é alterada; esta nota registra o caveat técnico descoberto na auditoria pré-empírica.

---

### ADR-008: Tratamento de reabertura de mercado (gap de fim-de-semana) no RenkoBuilder

**Data:** 2026-05-23
**Status:** Aceita
**Relação:** Quita a única dívida formal pendente na §4 desta ARCHITECTURE.md. Apoia-se em evidência empírica de produção (`CHECKPOINT-2026-05-20-slice2.md` §6 — run de 7 dias incluindo um gap de 49h em XAUUSDm/Exness). Não cria mecanismo novo: formaliza, como decisão deliberada, o comportamento que a combinação ADR-010 (mid-driven) + ADR-011 (multi-threshold) já produz.

**Contexto:**
Mercados de FX e metais fecham na sexta à noite e reabrem na segunda — tipicamente 48-49 horas sem ticks. Quando o primeiro tick de segunda chega, o preço pode estar significativamente longe do último tick de sexta. O `CMksRenkoBuilder` recebe esse tick como qualquer outro: o mecanismo de cruzamento multi-threshold (ADR-011) processa o salto.

A pergunta arquitetural é: esse processamento implícito é a decisão certa? Quatro alternativas existem, e o `ROADMAP.md §Fase 2 R2.3` registrou explicitamente a pendência. Esta ADR escolhe entre elas, com fundamentação.

A evidência empírica disponível, registrada em `CHECKPOINT-2026-05-20-slice2.md §6`:
- XAUUSDm/Exness, janela 2026-05-13 → 2026-05-20 (7 dias corridos).
- 1.676.426 ticks → 9.672 bricks com `S=3.0`, preset median, `K=20`.
- **1 gap de 49h** (fim de semana 15→17 mai).
- **Zero erros** 102 (threshold limit), 103 (invalid tick), 104 (corrupt stream).
- O gap foi absorvido como um brick multi-threshold modesto (M=2 ou similar), com movimento de preço observado entre 5 e 10 USD durante o weekend.
- O produto `K · (1−PO) · S = 20 · 0.5 · 3.0 = 30 USD` ficou confortavelmente acima do movimento real.

O gap de fim-de-semana, neste instrumento e broker, **já está sendo tratado corretamente** pela arquitetura aceita (ADR-010 + ADR-011). Esta ADR formaliza essa observação como decisão deliberada e fecha a fronteira para futuras mudanças sem ADR de substituição.

**Decisão:**
O `CMksRenkoBuilder` trata o primeiro tick pós-gap como **qualquer outro tick do stream**, sem mecanismo especial para detectar ou rotular gaps temporais. O mecanismo de cruzamento multi-threshold (ADR-011) é o caminho único de absorção; o limiar `K` atua como guarda contra gaps patológicos. Quatro cláusulas vinculantes:

1. **Sem detecção temporal de gap.** O builder não consulta relógio, não compara `timeMsc` entre ticks consecutivos, não tem threshold de "X minutos entre ticks → reset". Detecção baseada em tempo viola o princípio de determinismo da §1: o "agora" do builder é função pura do stream de ticks, nunca de wall-clock. O caminho de live e o caminho de replay sobre `.mkstick` consomem o mesmo tick na mesma ordem; tratar o tick pós-gap diferentemente exigiria estado externo (relógio) que não está no tick — quebra paridade bit-a-bit.

2. **Sem brick de fechamento parcial no fim da semana.** Se houver um brick em formação no último tick de sexta-feira (wickHigh/wickLow não-vazios), seu estado é preservado intacto até o primeiro tick de segunda. Não emitimos "brick de gap" ou "brick parcial" para fechar a sessão — porque tais bricks seriam phantom (sem tick de gatilho próprio), violação direta da ADR-011 §regra 1.

3. **Sem flag de gap no `MksBrick`.** O contrato do brick (ADR-010, ADR-014) não ganha campo `wasAfterGap` ou equivalente. Estratégia que queira distinguir bricks pós-gap consulta `closeTimeMsc` do brick atual contra o do anterior — gap = delta grande em segundos. É derivado, não primário. Adicionar campo seria mudar o contrato do tipo central do core (cascateando para `.mksbk`, writer, reader, sinks, snapshot etc.) por um caso que estratégias raramente precisam tratar explicitamente.

4. **`K` (limiar multi-threshold, ADR-011) é a guarda contra gap patológico.** Quando o gap excede `K · (1−PO) · S` pontos, o builder emite erro 102 (`MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED`) e interrompe o stream — comportamento já especificado pela ADR-011 §regra 4. Operador escolhe `K` por instrumento e broker; default `K=20` está validado empiricamente para XAU/Exness e tem margem ampla (~3x o pior gap observado). Para instrumentos voláteis (criptos, instrumentos exóticos), o operador pode subir `K` ou ajustar `S`/preset.

**Alternativas consideradas:**

- **Detectar gap por delta de tempo e descartar.** Definir `gapThresholdSec` (ex.: 1800s = 30 min); ticks após gap maior reset wickHigh/wickLow e iniciam novo brick "limpo". **Rejeitada** por três razões empilhadas: (a) viola o princípio de determinismo da §1 — o motor consulta tempo absoluto; (b) cria comportamento dependente de broker (rollover diário de Exness ~62 min seria detectado como gap, mas é evento técnico, não pausa de mercado); (c) descartar bricks em formação introduz perda de informação que não se reconstrói — wickHigh/wickLow contém movimento real entre o último brick fechado e o gap, descartá-lo é gerar bricks pós-gap com base parcial.

- **Detectar gap e emitir brick especial / flag em `MksBrick`.** Adicionar campo `wasAfterGap` (bool) ou `secondsSinceLastTick` (long) no `MksBrick`, populado pelo builder quando detecta delta acima de threshold. **Rejeitada** por dois motivos: (a) o consumidor primário deste sinal (estratégia) não existe ainda; criar contrato antes do consumidor é arquitetura no vazio, vetada pela §4 desta ARCHITECTURE.md; (b) o sinal é derivado — qualquer consumidor que precise dele computa via `closeTimeMsc` consecutivos. Adicionar redundância no tipo central por conveniência futura não compensa o custo de manter o campo coerente em writer/reader/sinks (cinco arquivos a atualizar).

- **Detectar gap e emitir brick de fechamento sintético no último tick de sexta.** Estratégia "fecha sessão antes do gap". **Rejeitada**: o brick sintético não tem tick de gatilho — é phantom por construção. Viola ADR-011 §regra 1 ("cada brick emitido grava o tick disparador"). O efeito desejado (estratégia evitar carry-over de risco no weekend) é responsabilidade da estratégia + Risk Manager (Fase 6), não do builder.

- **Manter o status quo informal sem ADR.** Continuar tratando gap "tacitamente" via ADR-011 sem registrar a decisão. **Rejeitada** porque deixa a porta aberta para alguém, em algum ciclo futuro, propor um dos mecanismos rejeitados acima sem ter o histórico do porquê. ADR-008 fecha essa porta com argumentação registrada.

**Consequências:**

- **Nenhum código alterado.** O comportamento atual do `CMksRenkoBuilder` já implementa esta decisão. Esta ADR é puramente formalizadora — converte status quo empiricamente validado em decisão arquitetural deliberada.

- **Calibração de `K` por instrumento entra no manual operacional.** Operador escolhe `K` levando em conta o pior gap esperado para o instrumento × broker. Para XAU/Exness com preset median e S=3.0, K=20 tem margem confortável (cobre gap até 30 USD, observado ~5-10 USD na pior semana auditada). Documentação operacional desta calibração entra em `docs/CHEATSHEET.md` em ciclo posterior.

- **Estratégias que querem guardar-se contra entradas pós-gap consultam timestamps.** O padrão recomendado é: na entrada, comparar `currentBrick.closeTimeMsc` com `previousBrick.closeTimeMsc`; se delta > threshold escolhido pela estratégia, skip a entrada por uma ou mais barras. Esta lógica vive na estratégia, não no builder.

- **Determinismo total preservado.** O fato de o builder não consultar relógio entre ticks é o que mantém a paridade bit-a-bit (ADR-024) automaticamente válida em qualquer caminho com gap. Replay sobre `.mkstick` que cobre uma janela com gap produz exatamente os mesmos bricks que o live produziu.

- **Fronteira com ADR-024 fechada.** O `.mkstick` capturado em live preserva o gap como exatamente o que ele é no broker: ausência de ticks por N horas. O Replayer EA sobre esse `.mkstick` consome o último tick de sexta, depois o primeiro de segunda — sem nenhum tratamento intermediário. A combinação produz reprodutibilidade total.

- **Não introduz código de erro novo.** A faixa RenkoBuilder 100–199 do `Error.mqh` já tem `MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED=102`, que é exatamente o erro disparado por gap patológico além de `K`. Cobertura completa do caso pelo erro existente.

**Fronteiras:**

- **Não cobre interrupção de feed durante o pregão.** Falha de conexão broker→cliente que cause perda de ticks intra-sessão não é gap de mercado; é falha de infraestrutura, e o framework propaga o stream que recebeu (ADR-012 §1: arquivo histórico grava ticks crus, sem preencher buracos). Estratégia robusta a esse caso é responsabilidade do operador (monitoramento de healthcheck, não do builder).

- **Não cobre weekend trading em criptomoedas.** Cripto não tem gap de fim-de-semana — a discussão é inaplicável. Quando o framework operar cripto, esta ADR continua válida (sem detecção temporal de qualquer espécie), simplesmente o caso não dispara.

- **Não cobre eventos extraordinários** (decisões de banco central fora-do-horário, suspensão de pregão por falha de bolsa, etc.). Esses casos exigem decisão operacional do dono, não regra do framework. Se gerarem gap superior a `K · (1−PO) · S`, o erro 102 dispara — e essa é a defesa estrutural.

- **Não cobre rollover diário do broker** (ex.: ~22h GMT na Exness, pausa de 1-3 minutos para reset de swap). Tecnicamente é um micro-gap, mas o `K=20` cobre confortavelmente. Trate-se como tick normal pós-pausa, mesmo mecanismo desta ADR.

---

### ADR-026: Producer classic-only — remoção de geometria selecionável

**Data:** 2026-05-24
**Status:** Aceita
**Relação com ADR-010:** Não revoga. ADR-010 permanece — eixos ortogonais geometria/sizer continuam no core. Esta ADR só restringe a superfície exposta pelo Producer.
**Relação com ADR-022:** Substitui parcialmente as regras 1, 5 e 7. ADR-022 permanece Aceita; ADR-026 estreita o conjunto de geometrias selecionáveis via Producer para `{classic}`.

**Contexto:**

A ADR-022 fixou o Producer como dinâmico em geometria (`MKS_GEOM_MEDIAN`, `MKS_GEOM_CLASSIC`, `MKS_GEOM_CUSTOM`), com naming do CS carregando `typeCode` para evitar colisão entre presets. Inspeção do pipeline `MksBrick → MqlRates → CustomRatesUpdate` em sessão de 2026-05-24 revelou três distorções estruturais quando o preset é `median` (ou qualquer geometria com `PO > 0`):

1. **`brick.close` matemático ≠ preço real do tick disparador.** Em median (PO=0.5, S=3.0), o brick fecha quando o mid atinge `open + 1.5`, mas o `close` registrado é `open + 1.5` enquanto o tick disparador real (com overshoot) tipicamente está em `open + 1.5 + ε`. Estratégia que ler `brick.close` cru opera em espaço de preços fictício — o eixo 1 do `V5-POSTMORTEM`. Mitigado no core pelo `triggerPrice`, mas a possibilidade de erro de leitura existe.

2. **`visualClose` no CS ≠ `brick.close` matemático.** [CMksCustomSymbolSink.mqh:63-65](MQL5/Include/MKS-ULTIMATE/Core/Output/CMksCustomSymbolSink.mqh#L63-L65) recalcula `visualClose = open ± brickSizePts` (ADR-022 §8 — "tamanho VISUAL full"). Em median, isso é `open ± S`, enquanto o `brick.close` matemático é `open ± (1−PO)·S = open ± 0.5·S`. O CS mostra um nível de preço a `0.5·S` (1.5 USD em XAU) **além do threshold matemático real**, e a `(1−PO)·S + overshoot` além do preço de mercado de fato impresso pelo broker. Indicadores nativos do MT5 arrastados sobre o chart do CS (RSI, Donchian, MACD, SuperTrend, Chandelier) leem `iClose(CS) = visualClose` — calculam sobre números fictícios.

3. **Equivalência matemática descoberta no caminho.** Os thresholds do builder dependem só de `(1−PO)·S`. Logo, **`median S=X` é matematicamente equivalente a `classic S=(1−PO)·X` em termos de quando e onde os bricks fecham** — mesmos `triggerPrice`, mesmos `triggerTickId`, mesma sequência. Para `PO=0.5`, `median S=3 ≡ classic S=1.5`. Mantida a cadência, classic oferece tudo o que median oferece *exceto* a sobreposição visual de 50% entre bricks consecutivos. Em classic, `brick.close = visualClose = threshold real cruzado` — as três distorções acima desaparecem.

A escolha histórica por median no Producer veio de costume visual do V5, não de análise de fidelidade. Esta ADR fecha a porta para o operador cair em median por inércia, sem remover a capability do core (testes, decoder de `.mksbk` antigos, experimentos futuros).

**Decisão:**

O Producer do MKS-ULTIMATE opera **exclusivamente em geometria classic** (PO=PRO=0, revSizeRatio=1.0). Seis cláusulas:

1. **`MksGeometryClassic()` hardcoded no Producer.** O EA `Producer.mq5` constrói a geometria via `MksGeometryClassic()` no `OnInit`, sem input. Sem `ENUM_MKS_GEOMETRY_TYPE`, sem `InpGeometryType`, sem `InpPro`, sem `InpPo`, sem `BuildGeometry()`. O grupo de inputs `=== Brick ===` reduz a um único campo: `InpBrickSizePts`.

2. **Default do construtor `MksRenkoGeometry()` muda para classic.** O construtor sem argumentos (`MksRenkoGeometry g;`) passa a inicializar com `(po=0, pro=0, revSizeRatio=1.0)` — antes era `(0.5, 0.5, 1.0)`, ou seja, median silencioso. Fecha a porta no core também: nenhum código que esqueça de chamar fábrica recebe median por acidente.

3. **Naming do CS simplifica para `<symbol>.MKS_<sizeStr>`.** O `typeCode` da ADR-022 §5 (`M`/`C`/`X`) some — não há mais tipo a distinguir. `BuildCustomSymbolName(symbol, sizePts)` recebe dois argumentos em vez de cinco.

4. **Core intocado — fábricas e suporte completo a presets preservados.** `MksGeometryMedian()`, `MksGeometryClassic()`, `MksGeometryCustom()` continuam definidas em [RenkoGeometry.mqh](MQL5/Include/MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh). O `CMksRenkoBuilder` continua recebendo `MksRenkoGeometry` por injeção e processando qualquer triplo válido. Razões para não remover:
   - **Testes existentes.** `Test_CMksRenkoBuilder.mq5` (428 assertions) cobre median e custom; remover reduziria cobertura matemática do builder.
   - **Leitura de `.mksbk` antigos.** Header `.mksbk` carrega geometria como 3 doubles; reler arquivos gerados em median exige as fábricas no core.
   - **Experimentos comparativos.** Validar empiricamente esta decisão (ou outras presets para instrumentos diferentes) exige o suporte intacto.
   - **Custo de manter é trivial** — ~10 linhas de fábricas.

5. **Naming do `.mksbk` não muda.** ADR-014 §2 já fixou `<symbol>_<YYYYMMDDTHHMMSS>.mksbk` com proveniência completa (incluindo `po`, `pro`, `revSizeRatio`) no header binário. Como o nome não carregava typeCode, esta ADR não toca em `.mksbk` naming. Arquivos novos serão lidos pelo decoder normalmente; arquivos antigos em median permanecem decodificáveis pela mesma rota.

6. **Equivalência registrada como invariante.** O fato matemático `median S=X ≡ classic S=(1−PO)·X` fica registrado nesta ADR como contrato. Operador que queira reproduzir o comportamento de cadência do "median S=3" antigo configura `InpBrickSizePts=1.5` em classic. Operador que queira reproduzir "median S=5" usa `classic S=2.5`. A conversão é mecânica.

**Alternativas consideradas:**

- **(a) Manter ADR-022 intacta — Producer dinâmico com default classic + tooltip forte em median.** Rejeitada. Default + tooltip resolve "operador escolheu median por engano", mas não fecha a porta — alguém futuro, sem o contexto desta análise, pode ainda selecionar median por curiosidade e cair na armadilha sem perceber as três distorções. Tornar a opção inacessível pelo Producer é proteção estrutural, não cosmética.

- **(b) Remover `MksGeometryMedian()` do core completamente.** Rejeitada. Quebra `Test_CMksRenkoBuilder.mq5`, invalida o argumento de eixos ortogonais da ADR-010, e impede a leitura de `.mksbk` antigos em median (decoder precisa do struct correspondente). Custo alto, ganho zero — a cláusula 1 já garante "impossível selecionar pela GUI", que é o objetivo real.

- **(c) Manter median via flag de compilação `MKS_ALLOW_MEDIAN`.** Rejeitada. Adiciona condicional de compilação ao Producer — polui o caminho de produção por algo que se resolve simplesmente removendo a opção da GUI. Quem quiser experimentar median escreve um script de teste próprio que instancie o builder direto com `MksGeometryMedian()`.

- **(d) Estender o escopo: remover também o `CMksAtrBrickSizer`.** Rejeitada. O sizer ATR é eixo ortogonal à geometria (ADR-010 §1), não compartilha as distorções do median, e o ADR-018 cobre a sua corretude. "Não usar agora" não é razão para remover — está pronto, testado (72 assertions), e é compatível com classic (`classic geometry + ATR sizer = bricks de tamanho variável com close fiel`).

- **(e) Mudar o default do construtor `MksRenkoGeometry()` para classic, mas manter Producer dinâmico.** Rejeitada como cobertura única. A mudança do construtor (cláusula 2 desta ADR) é necessária mas não suficiente — o Producer ainda exporia inputs que permitem chegar em median explicitamente. Esta ADR aplica as duas mudanças em conjunto.

**Consequências:**

- **Producer.mq5 reduz ~90 linhas.** Removidos: enum `ENUM_MKS_GEOMETRY_TYPE`, inputs `InpGeometryType`/`InpPro`/`InpPo`, funções `BuildGeometry()` e `GeometryTypeName()`, lógica de switch no `BuildCustomSymbolName`. Hardcoded: `MksGeometryClassic()` no OnInit, `"Classic"` literal no `g_panel.LiveMode`, `"preset":"classic"` no log de starting.

- **`RenkoGeometry.mqh` muda 1 linha.** Construtor default passa de `(0.5, 0.5, 1.0)` para `(0.0, 0.0, 1.0)`. Comentário-âncora atualizado.

- **Naming do CS muda para `<symbol>.MKS_<sizeStr>`** (sem `_C_`/`_M_`/`_X_`). CSs gerados por sessões anteriores em median ou classic permanecem visíveis no Market Watch com naming antigo — sem migração automática. Operador limpa via `MksCleanupCustomSymbols.mq5` quando quiser (regra 8 da ADR-020).

- **`Test_CMksRenkoBuilder.mq5` continua passando sem mudança** — instancia geometrias via fábricas diretamente, não toca em código do Producer.

- **`.mksbk` produzidos pós-ADR-026 carregam `po=0, pro=0, revSizeRatio=1.0` no header.** `.mksbk` antigos em median continuam legíveis pelo `CMksBrickFileReader` sem mudança.

- **ADR-022 ganha nota de substituição parcial:** regras 1 (tipo dinâmico), 5 (naming com typeCode), 7 (input group "Geometria" com 4 inputs) substituídas. Regras 2 (defaults sensatos), 3 (`InpShowWicksInCS`), 4 (auto-open chart), 6 (`InpResetCustomSymbolBars`), 8 (`brickSizePts` no sink — visual full), 9 (inputs em grupos) permanecem intactas.

- **ADR-008 argumento simplifica.** O produto `K · (1−PO) · S` do raciocínio sobre gap de fim-de-semana vira `K · S` em classic. Conclusões idênticas, fronteira ainda mais clara. Sem nota de esclarecimento necessária — texto da ADR-008 continua válido (PO=0 é caso particular).

- **Estratégias futuras nascem em classic.** Toda estratégia construída a partir desta ADR opera sobre bricks onde `brick.close` é o threshold real. A guarda de "use `triggerPrice` em vez de `brick.close`" continua válida (overshoot do tick disparador pode adicionar fração de ponto), mas o risco de raciocínio em espaço fictício é estruturalmente menor.

- **Sem mudança em ADRs aceitas adjacentes:** ADR-010 (eixos ortogonais), ADR-011 (multi-threshold), ADR-018 (ATR sizer), ADR-020 (CS contrato visual), ADR-021 (bar parcial), ADR-024 (tick recorder/replay) ficam intactas. Esta ADR estreita a superfície exposta, não revoga capability.

**Fronteiras:**

- Não cobre presets futuros (asymmetric reversal, breakout-tuned, etc). Se algum dia surgir necessidade real e validada empiricamente, nova ADR pode reabrir a porta no Producer — provavelmente com nome e racional próprios.

- Não cobre o `CMksAtrBrickSizer`. O sizer ATR continua existindo e testado, compatível com classic. Não está em uso pelo Producer hoje (usa `CMksFixedBrickSizer`), mas a opção está disponível quando/se for necessária.

- Não cobre a remoção do CS como categoria. ADR-020 segue válida — CS continua como camada de visualização humana exclusiva.

- Não cobre migração retroativa de `.mksbk` ou CSs antigos. Arquivos e CSs gerados em median permanecem no disco/Market Watch com naming antigo, sem renomeação automática. Operador limpa o que não precisa mais via scripts utility.

- Não cobre estratégias externas ao framework (EAs do usuário fora de `MQL5/Experts/MKS-ULTIMATE/`). Esta ADR vincula apenas o `Producer.mq5` do framework. EAs externos que leiam `.mksbk` podem operar em qualquer geometria — sob responsabilidade do operador.

---

## 4. Decisões pendentes

Nenhuma decisão arquitetural formal pendente neste momento. Decisões novas são registradas formalmente quando forem enfrentadas, não antes — decidir arquitetura no vazio produz decisões erradas.

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
