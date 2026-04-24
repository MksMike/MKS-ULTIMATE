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
│   │   │   ├── Interfaces/         # IBroker, ITickSource, IClock, ILogger, IRenkoSink
│   │   │   ├── Types/              # Tick, Brick, OrderRequest, ExecutionResult
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

## 4. Decisões pendentes

Pontos que precisam virar ADR assim que forem enfrentados:

- **ADR-004 (pendente):** Como abstrair polimorfismo em MQL5 dado que a linguagem não tem `interface` keyword. Candidato: classes abstratas com métodos virtuais puros.
- **ADR-005 (pendente):** Estrutura e execução dos testes unitários. Framework próprio mínimo ou adaptação de algo existente?
- **ADR-006 (pendente):** Tratamento de phantom bars no `RenkoBuilder`. Ignorar, marcar como suspeito, ou interromper?
- **ADR-007 (pendente):** Formato do log estruturado. JSON-line ou key=value? Volume de log esperado em live vs custo de parsing.
- **ADR-008 (pendente):** Como tratar reabertura de mercado (segunda-feira) no RenkoBuilder. Gap vira brick? Vira múltiplos bricks? Vira nada?

Essas decisões são registradas formalmente quando forem enfrentadas, não antes. Decidir arquitetura no vazio produz decisões erradas.

## 5. Como este documento evolui

- Nova ADR é adicionada ao final da seção 3, com número sequencial.
- ADRs antigas **não são editadas** após aceitas — apenas recebem status novo se substituídas.
- A estrutura de diretórios (seção 2) é atualizada quando a realidade do projeto muda.
- Seção de decisões pendentes (seção 4) serve de fila de trabalho arquitetural.
- Mudanças significativas geram entrada no `CHANGELOG.md` com categoria apropriada.

Arquitetura é um livro-razão, não um manifesto.
