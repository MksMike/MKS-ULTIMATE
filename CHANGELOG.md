# Changelog

Todas as mudanças relevantes neste projeto serão documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e este projeto adere a [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Added
- `docs/V5-POSTMORTEM.md` — análise de causa-raiz do colapso do V5, baseada na leitura direta do código-fonte. Identifica quatro eixos de falha estrutural.
- `docs/ARCHITECTURE.md` §3 — ADR-004 aceita: polimorfismo em MQL5 via classe abstrata com métodos virtuais puros (em vez da keyword `interface` nativa), com sete convenções operacionais para toda interface do core (`I*`).
- `MQL5/Include/MKS-ULTIMATE/Core/Types/` — quatro tipos primitivos do core, autocontidos: `MksTick` (com `seq` como fonte de verdade do determinismo), `MksBrick` (com `triggerPrice`, `triggerTickId` e `Overshoot()` — resposta direta ao eixo 1 do V5-POSTMORTEM), `MksOrderRequest` e `MksExecutionResult` (preço real de preenchimento, não fictício).
- `docs/ARCHITECTURE.md` §5 — Convenções de nomenclatura registradas: sistema de prefixos `I` (interfaces), `CMks` (classes com estado), `Mks` (structs/tipos primitivos POD) e `ENUM_MKS_` (enums internos).
- `MQL5/Include/MKS-ULTIMATE/Core/Version.mqh` — versão única do framework em defines SemVer (`MAJOR`/`MINOR`/`PATCH`/`STR`), conforme ADR-001.
- `MQL5/Include/MKS-ULTIMATE/Core/Interfaces/` — cinco interfaces do core (`IBroker`, `ITickSource`, `IClock`, `ILogger`, `IRenkoSink`), classes abstratas com métodos virtuais puros conforme ADR-004.
- `docs/ARCHITECTURE.md` §3 — nota de esclarecimento da convenção 7 da ADR-004: out-params por referência não-const são permitidos.
- `docs/ARCHITECTURE.md` §3 — ADR-009 aceita: modelo de erro — tipo estruturado retornável, separado do logging, com localização automática via macro e códigos de erro particionados por faixa de módulo.
- `docs/ARCHITECTURE.md` §3 — ADR-010 aceita: arquitetura de parametrização do RenkoBuilder (geometria como valor via `MksRenkoGeometry`, tamanho via interface `IBrickSizer`) e escolha do mid como preço-condutor do motor.
- `MQL5/Include/MKS-ULTIMATE/Core/Types/Error.mqh` — tipo de erro `MksError` (estruturado, retornável, separado do logging), enum `ENUM_MKS_ERROR_CODE` particionado por faixa de módulo, e a macro `MKS_SET_ERROR` de captura automática de localização. Implementa a ADR-009.
- `MQL5/Include/MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh` — struct `MksRenkoGeometry`, o triplo `(PO, PRO, revSizeRatio)` da geometria do brick, com `Validate` via `MksError` e as fábricas de preset `MksGeometryMedian`, `MksGeometryClassic` e `MksGeometryCustom`. Implementa a ADR-010. O enum `ENUM_MKS_ERROR_CODE` (`Error.mqh`) ganha `MKS_ERR_RENKO_INVALID_GEOMETRY` (código 100), primeiro da faixa RenkoBuilder.
- `MQL5/Include/MKS-ULTIMATE/Core/Interfaces/IBrickSizer.mqh` — interface `IBrickSizer` (6ª interface do core): contrato de fornecimento do tamanho-base do brick Renko em pontos, com `SizePoints`, `IsReady` (prontidão de sizers derivados de dados, ex. ATR) e `Validate` via `MksError`. Implementa o eixo de tamanho da ADR-010. O método de alimentação de dados foi deliberadamente omitido — sua forma depende da cadência de recálculo do ATR, adiada para o `CAtrBrickSizer`; o raciocínio está no doc-comment da interface.
- `MQL5/Include/MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh` — primeira implementação concreta de `IBrickSizer`: tamanho de brick fixo em pontos, definido na construção e constante durante toda a sessão (`IsReady()` sempre verdadeiro, sem warm-up); `Validate()` rejeita tamanho menor ou igual a zero. Pasta `Core/RenkoBuilder/` criada. Acompanha o código de erro `MKS_ERR_RENKO_INVALID_BRICK_SIZE = 101` em `Error.mqh`, faixa RenkoBuilder.
- `docs/ARCHITECTURE.md` §3 — nota de esclarecimento da ADR-010: as classes concretas de sizer seguem o prefixo `CMks` da §5 (`CMksFixedBrickSizer`, `CMksAtrBrickSizer`) e o campo de geometria implementado é `revSizeRatio` (razão), não `revSizePct`.

### Changed
- `docs/Projeto.md` §2 — causa-raiz do V5 reescrita: de "divergência silenciosa entre backtest e live" (sintoma) para a causa estrutural de quatro eixos.
- `docs/Projeto.md` §6 — referência ao V5 corrigida: V5 tinha engine Renko própria e não dependia de indicador de caixa-preta (essa é característica do AzInvest).
- `docs/ROADMAP.md` — removida afirmação incorreta de que o V5 dependia de indicador de caixa-preta; seção "Lições aprendidas do V5" reescrita com base nos quatro eixos do post-mortem.
- `docs/REGRAS.md` §1.7 — regra de paridade backtest/live ampliada: de proibição de `if(MQL5_TESTING)` para proibição de qualquer condicional de ambiente na lógica de trading.
- `docs/ARCHITECTURE.md` §4 — entrada "ADR-004 (pendente)" removida da fila de decisões pendentes (decisão registrada na seção 3).
- Documentação sincronizada com o estado real do projeto: status das fases no `ROADMAP.md` (Fases 0 e 1 concluídas, Fase 2 em andamento), seção de estrutura do `CLAUDE.md` apontando para `ARCHITECTURE.md` §2, lista de documentos do `README.md` completada, campo `@depends_on` adicionado ao formato de header em `CLAUDE.md` e `PROTOCOLOS.md`, e comentários da árvore de diretórios em `ARCHITECTURE.md` §2.

## [6.0.0-alpha] - 2026-04-24

### Added
- Estrutura inicial do projeto MKS-ULTIMATE
- README.md com visão geral e princípio norteador
- .gitignore específico para projetos MQL5
- CLAUDE.md com contexto persistente para Claude Code
- Pasta docs/ para documentação viva
- CHANGELOG.md seguindo Keep a Changelog
