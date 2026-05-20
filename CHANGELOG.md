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
- `docs/ARCHITECTURE.md` §3 — ADR-011 aceita: tratamento de cruzamento multi-threshold no RenkoBuilder — um tick que cruza vários thresholds produz um único `MksBrick` honesto (sem phantom bricks), marcado pelo campo inteiro `thresholdsCrossed`; limiar configurável K acima do qual o builder devolve `MksError` em vez de emitir.
- `MQL5/Include/MKS-ULTIMATE/Core/Types/Brick.mqh` — campo `int thresholdsCrossed` no `MksBrick` (1 = brick normal, >1 = brick multi-threshold; default 1, pois um brick cruza no mínimo um threshold). Implementa o eixo de marcação da ADR-011.
- `MQL5/Include/MKS-ULTIMATE/Core/Types/Error.mqh` — código de erro `MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED = 102` (faixa RenkoBuilder), para o estouro do limiar K do RenkoBuilder. Implementa o eixo de guarda de corrupção da ADR-011.
- `docs/ARCHITECTURE.md` §3 — ADR-006 aceita: tratamento de tick inválido no RenkoBuilder. Volume zero não é anomalia; o critério é `MksTick::IsValid()` (preço malformado) como guarda de entrada do builder. Tick inválido é descartado e reportado; sequência de inválidos consecutivos interrompe o builder. Dois códigos novos na faixa RenkoBuilder de `Error.mqh`: `MKS_ERR_RENKO_INVALID_TICK` e `MKS_ERR_RENKO_TICK_STREAM_CORRUPT`.
- `docs/ARCHITECTURE.md` §3 — nota de esclarecimento da ADR-011: geometria do primeiro brick. Sem brick anterior não há "continuação" nem "reversão"; o primeiro brick tem direção fixada pelo sinal do movimento inicial e todos os seus degraus usam `(1-PO)*size` (continuação). Para median a regra não altera valores; importa para presets assimétricos futuros. Comentário-âncora correspondente em `CMksRenkoBuilder.mqh` no caminho `!m_hasFirstBrick`.
- `docs/ARCHITECTURE.md` §3 — ADR-013 aceita: independência de broker e proveniência no rastro de auditoria. Framework é broker-agnóstico por construção — sem hardcode de identificador de broker em código de lógica, sem cláusula condicional ramificando por nome de broker. Símbolo é parâmetro (não constante literal). Todo artefato persistido ou comunicado carrega proveniência `(broker, account, symbol)` capturada em runtime via `AccountInfoString(ACCOUNT_COMPANY)` e `AccountInfoInteger(ACCOUNT_LOGIN)`. Detecção e perfil estruturado de broker ficam como dívida explícita pós-Slice 3, quando houver evidência empírica do que de fato varia entre brokers.
- `MQL5/Include/MKS-ULTIMATE/Core/Types/Tick.mqh` — campo `uint flags` no `MksTick`, bitmask dos `TICK_FLAG_*` do MT5. Implementa a consequência de tipo da ADR-012 §4: os flags são informação de auditoria irreversível — o builder atual (mid-driven, ADR-010) não consome, mas estratégias e camada de execução futuras podem precisar, e a captura é one-shot. `ValidateBuilderOnRealTicks.mq5` atualizado para propagar `mt.flags` em `ToMksTick`.

### Changed
- `docs/Projeto.md` §2 — causa-raiz do V5 reescrita: de "divergência silenciosa entre backtest e live" (sintoma) para a causa estrutural de quatro eixos.
- `docs/Projeto.md` §6 — referência ao V5 corrigida: V5 tinha engine Renko própria e não dependia de indicador de caixa-preta (essa é característica do AzInvest).
- `docs/ROADMAP.md` — removida afirmação incorreta de que o V5 dependia de indicador de caixa-preta; seção "Lições aprendidas do V5" reescrita com base nos quatro eixos do post-mortem.
- `docs/REGRAS.md` §1.7 — regra de paridade backtest/live ampliada: de proibição de `if(MQL5_TESTING)` para proibição de qualquer condicional de ambiente na lógica de trading.
- `docs/ARCHITECTURE.md` §4 — entrada "ADR-004 (pendente)" removida da fila de decisões pendentes (decisão registrada na seção 3).
- Documentação sincronizada com o estado real do projeto: status das fases no `ROADMAP.md` (Fases 0 e 1 concluídas, Fase 2 em andamento), seção de estrutura do `CLAUDE.md` apontando para `ARCHITECTURE.md` §2, lista de documentos do `README.md` completada, campo `@depends_on` adicionado ao formato de header em `CLAUDE.md` e `PROTOCOLOS.md`, e comentários da árvore de diretórios em `ARCHITECTURE.md` §2.
- `docs/V5-POSTMORTEM.md` §3.2 — tabela do Eixo 2 corrigida: o Generator do V5 tem dois caminhos produtores (`ProcessTicks` e `ProcessM1`, com fallback silencioso para M1 OHLC), totalizando cinco produtores, não quatro. Revisão registrada na §7.

## [6.0.0-alpha] - 2026-04-24

### Added
- Estrutura inicial do projeto MKS-ULTIMATE
- README.md com visão geral e princípio norteador
- .gitignore específico para projetos MQL5
- CLAUDE.md com contexto persistente para Claude Code
- Pasta docs/ para documentação viva
- CHANGELOG.md seguindo Keep a Changelog
