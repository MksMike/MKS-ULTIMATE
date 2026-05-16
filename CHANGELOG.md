# Changelog

Todas as mudanças relevantes neste projeto serão documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e este projeto adere a [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Added
- `docs/V5-POSTMORTEM.md` — análise de causa-raiz do colapso do V5, baseada na leitura direta do código-fonte. Identifica quatro eixos de falha estrutural.
- `docs/ARCHITECTURE.md` §3 — ADR-004 aceita: polimorfismo em MQL5 via classe abstrata com métodos virtuais puros (em vez da keyword `interface` nativa), com sete convenções operacionais para toda interface do core (`I*`).

### Changed
- `docs/Projeto.md` §2 — causa-raiz do V5 reescrita: de "divergência silenciosa entre backtest e live" (sintoma) para a causa estrutural de quatro eixos.
- `docs/Projeto.md` §6 — referência ao V5 corrigida: V5 tinha engine Renko própria e não dependia de indicador de caixa-preta (essa é característica do AzInvest).
- `docs/ROADMAP.md` — removida afirmação incorreta de que o V5 dependia de indicador de caixa-preta; seção "Lições aprendidas do V5" reescrita com base nos quatro eixos do post-mortem.
- `docs/REGRAS.md` §1.7 — regra de paridade backtest/live ampliada: de proibição de `if(MQL5_TESTING)` para proibição de qualquer condicional de ambiente na lógica de trading.
- `docs/ARCHITECTURE.md` §4 — entrada "ADR-004 (pendente)" removida da fila de decisões pendentes (decisão registrada na seção 3).

## [6.0.0-alpha] - 2026-04-24

### Added
- Estrutura inicial do projeto MKS-ULTIMATE
- README.md com visão geral e princípio norteador
- .gitignore específico para projetos MQL5
- CLAUDE.md com contexto persistente para Claude Code
- Pasta docs/ para documentação viva
- CHANGELOG.md seguindo Keep a Changelog
