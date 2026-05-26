# CLAUDE.md — Contexto persistente para Claude Code neste projeto

## Ordem de leitura em sessões novas

Ao iniciar uma sessão neste projeto, ler nesta ordem:
1. Este arquivo (CLAUDE.md) — panorama
2. docs/Projeto.md — contexto e visão
3. docs/REGRAS.md — regras de conduta
4. docs/ROADMAP.md — fase atual do projeto e próxima a executar
5. docs/ARCHITECTURE.md — decisões arquiteturais (ADRs) aceitas
6. docs/V5-POSTMORTEM.md — análise de causa-raiz do V5 (referência negativa)
7. docs/PROTOCOLOS.md — checklists aplicáveis à tarefa atual
8. CHANGELOG.md — o que mudou recentemente
9. docs/TOM-E-CHATS.md — tom de voz, regras de confronto e modos de chat

Em seguida, invocar `/status` para confirmar o estado atual contra `git log` e ADRs antes da primeira ação.

## Projeto
**MKS-ULTIMATE** — Framework de trading automatizado baseado em Renko para MetaTrader 5.

**Versão atual:** 6.0.0-alpha
**Dono:** Mike Inoue (GitHub: MksMike)

## Princípio norteador
Backtest e live devem produzir resultados idênticos, bit-a-bit, na mesma janela temporal, dado o mesmo feed de ticks. Paridade é requisito do projeto, não objetivo distante.

## Histórico relevante
A versão anterior (V5, repo `MKS-Framework-Renko`) quebrou a conta em 4 horas de operação live após backtests aparentemente excelentes. A divergência entre backtest e live foi o sintoma; a causa-raiz é estrutural, com quatro eixos, e está documentada em `docs/V5-POSTMORTEM.md`. Resumo: a estratégia operava sobre o `close` matemático do brick (não sobre preço observado), backtest e live produziam bricks por caminhos diferentes, o custo de execução não afetava o equity do backtest, e um input bifurcava a lógica entre os dois ambientes. Essa classe de problema não pode se repetir no MKS-ULTIMATE. O `docs/V5-POSTMORTEM.md` é leitura obrigatória antes de qualquer decisão de arquitetura.

Existe também um fork do projeto **Median-and-Turbo-Renko-indicator-bundle** (AzInvest) que foi usado como referência de arquitetura para análise crítica — ele NÃO é base deste projeto. Nenhum nome, namespace, classe, comentário ou identificador do MKS-ULTIMATE deve conter "AzInvest" ou derivados.

## Regras de conduta (críticas)

1. **Análise crítica obrigatória.** Toda ideia do usuário é analisada honestamente, com pontos positivos e negativos. Nunca concordar por concordar.
2. **Zero gambiarras.** Se um erro aparece, a causa-raiz é resolvida. Nunca esconder o sintoma só para o erro "desaparecer".
3. **Nunca gerar código que não compila.** Se há dúvida sobre uma API MQL5, verificar antes (via docs ou pergunta), não chutar.
4. **Arquitetura limpa acima de tudo.** OOP, responsabilidade única por classe, interfaces antes de implementações concretas.
5. **Comentários explicam *por quê*, não *o quê*.** Código autodocumentado nos nomes. Comentários redundantes são poluição.
6. **Headers enxutos em cada arquivo** com: `@file`, `@project`, `@module`, `@responsibility`, `@depends_on`, `@install_path`. Versão e data ficam no git, não em cada arquivo.
7. **Backtest e live compartilham o mesmo caminho de código.** Nada de `if(MQLInfoInteger(MQL5_TESTING))` bifurcando comportamento. Broker e tick source são abstraídos via interfaces.
8. **Testes antes de EA.** Nenhuma estratégia é construída antes do core ter cobertura de testes.

## Convenções de nomenclatura
- Prefixo de classes: `CMks` (ex: `CMksRenkoBuilder`, `CMksTradeManager`)
- Pasta de includes: `MQL5/Include/MKS-ULTIMATE/`
- Header de versão único: `MQL5/Include/MKS-ULTIMATE/Core/Version.mqh`
- Defines de versão: `MKS_ULTIMATE_VERSION_MAJOR`, `MKS_ULTIMATE_VERSION_MINOR`, `MKS_ULTIMATE_VERSION_PATCH`, `MKS_ULTIMATE_VERSION_STR`

## Estrutura de diretórios

A estrutura-alvo do projeto está em `docs/ARCHITECTURE.md` §2, e cresce conforme as fases do `ROADMAP.md` avançam.

## Fluxo operacional

### Skills (invocar quando aplicável)

- `/status` — snapshot do estado atual (fase do ROADMAP, últimos commits, ADRs pendentes, working tree). Invocar no início de cada chat, após bootstrap, antes da primeira ação.
- `/protocolo-1 <Modulo>` — executa o checklist do Protocolo 1 contra um módulo do core (ex.: `CMksRenkoBuilder`). Invocar antes de declarar qualquer módulo do core "pronto" no `ROADMAP.md`.
- `/adr-novo` — template para nova ADR em `docs/ARCHITECTURE.md`.

### Watcher de compile (`tools/watch-compile.ps1`)

Compila headless via `MetaEditor64.exe` os `.mq5` afetados por mudanças em `.mqh`/`.mq5` dentro de `MQL5/Include/MKS-ULTIMATE/` e `MQL5/Scripts/MKS-ULTIMATE/`. Constrói o grafo reverso de `#include` e o rebuilda a cada ciclo com mudanças — pega arquivos novos, includes novos e dependências transitivas.

**Auto-start via VSCode:** `.vscode/tasks.json` declara a task `watch: compile MQL5` com `runOn: folderOpen`. Abrir o repo no VSCode dispara o watcher num terminal dedicado (modo `silent` — não rouba foco). Na primeira vez, o VSCode pergunta "Allow Automatic Tasks in Folder?" — autorizar uma vez. Para forçar manualmente: `Ctrl+Shift+P → Tasks: Run Task → watch: compile MQL5`.

**Rodar fora do VSCode (terminal direto):**
```powershell
powershell -ExecutionPolicy Bypass -File c:\dev\MKS-ULTIMATE\tools\watch-compile.ps1
```

Funciona em Windows PowerShell 5.1 (`powershell`) e PowerShell 7+ (`pwsh`). Path do MetaEditor configurável via `-Editor <path>`. Default: `C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe`. Não rodar concorrente com o MetaEditor GUI compilando o mesmo arquivo.

## Documentos de referência
Todos os documentos abaixo existem em `docs/` e devem ser consultados:

- `docs/Projeto.md` — visão, escopo, glossário, decisões-chave
- `docs/REGRAS.md` — regras de conduta do assistente e do dono
- `docs/ROADMAP.md` — fases de construção em ordem
- `docs/ARCHITECTURE.md` — decisões arquiteturais (ADRs)
- `docs/PROTOCOLOS.md` — checklists para momentos de risco
- `docs/CHEATSHEET.md` — referência rápida de comandos
- `docs/TOM-E-CHATS.md` — tom de voz, regras de confronto e modos de chat estruturados
- `docs/CHECKPOINTS.md` — índice cronológico de checkpoints de sessão (handoffs entre chats; consultar sob demanda histórica, **não está na ordem de leitura**)