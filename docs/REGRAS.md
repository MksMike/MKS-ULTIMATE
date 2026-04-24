---
@document: docs/REGRAS.md
@project: MKS-ULTIMATE
@purpose: Regras de desenvolvimento, conduta e colaboração entre dono e assistente
@audience: Dono do projeto, assistentes de IA (Claude), contribuidores futuros
---

# MKS-ULTIMATE — Regras

Este documento define as regras de trabalho no projeto. É vinculante para todas as partes envolvidas (dono, assistentes de IA, contribuidores). Violações devem ser apontadas imediatamente pela parte que percebê-las.

## 1. Regras de conduta do assistente

### 1.1 Análise crítica obrigatória

Toda ideia, proposta ou decisão trazida pelo dono do projeto deve ser analisada honestamente, com **pontos positivos e negativos** explicitados. Concordar por concordar é proibido.

Se a ideia é boa, diga que é boa e por quê.
Se a ideia tem falhas, aponte as falhas com clareza, sem disfarçar.
Se a ideia é ruim, diga que é ruim e proponha alternativa.

Esta regra existe porque concordância cega foi um dos fatores do fracasso do V5.

### 1.2 Zero gambiarras

Quando um erro aparece, a **causa-raiz** deve ser investigada e corrigida. Nunca esconder o sintoma apenas para o erro "desaparecer". Se a solução correta exige mais trabalho, o trabalho maior é feito — não o atalho.

Exemplos de gambiarra proibida:
- Envolver código em try/catch vazio só pra silenciar exceção
- Adicionar `Sleep(500)` em vez de entender por que a race condition existe
- Hardcodar valor pra um teste passar
- Comentar código quebrado em vez de remover ou consertar
- Duplicar lógica em vez de abstrair

### 1.3 Nunca gerar código que não compila

Se há dúvida sobre uma API MQL5, um comportamento do MT5, ou qualquer coisa que possa estar errada, **pergunte ou pesquise antes** de escrever. Código que não compila queima tempo do dono e erode confiança.

Quando for legítimamente incerto sobre algo, declare: *"Não tenho certeza se X funciona assim. Vou verificar."* — e aí verifica.

### 1.4 Arquitetura limpa acima de tudo

- Orientação a objetos onde faz sentido
- Responsabilidade única por classe
- Interfaces antes de implementações concretas
- Dependências injetadas, não acopladas
- Nomes expressivos — código se lê como prosa técnica

### 1.5 Comentários explicam *por quê*, não *o quê*

Código autodocumentado nos nomes. Comentários redundantes (`i++; // incrementa i`) são poluição e envelhecem mal.

Use comentários para:
- Decisões não-óbvias de arquitetura
- Invariantes que o código assume
- Workarounds com justificativa e referência (bug do broker, limitação do MT5)
- Contexto histórico relevante ("mudado em X porque Y")

Não use comentários para:
- Traduzir a linha de código em linguagem natural
- Marcar autor/data de cada mudança (isso é trabalho do git)
- Desabilitar código (remover ou criar branch)

### 1.6 Headers enxutos em cada arquivo

Todo arquivo `.mq5` e `.mqh` do projeto começa com header no formato:

//+------------------------------------------------------------------+
//| @file           : NomeDoArquivo.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Categoria / Submódulo (ex: Core / RenkoBuilder)
//| @responsibility : Descrição de 1-2 linhas do que o arquivo faz
//| @depends_on     : Interfaces e classes principais usadas
//| @install_path   : MQL5/Include/MKS-ULTIMATE/...
//+------------------------------------------------------------------+

Versão e data de modificação **não entram no header** — o git cuida disso. O projeto inteiro usa uma versão única, definida em `Core/Version.mqh`.

### 1.7 Paridade backtest/live não é negociável

Código não pode bifurcar comportamento lógico entre backtest e live. Especificamente:

- Proibido `if(MQLInfoInteger((int)MQL5_TESTING))` dentro da lógica de estratégia, risk management, ou execução de ordens.
- Permitido apenas em pontos de composição (onde decidimos qual `IBroker` instanciar, qual `ITickSource` usar). Esse ponto fica isolado na fábrica/composition root.

Quando em dúvida se um `if(MQL5_TESTING)` é legítimo, traga a questão à tona — não pressuponha.

### 1.8 Testes antes de EA

Nenhuma estratégia é construída antes do core ter cobertura de testes:

- `CMksRenkoBuilder` precisa ter unit tests cobrindo casos: brick simples, reversão, gap, volume zero, ticks fora de ordem, boundary conditions.
- `CMksTradeManager` precisa ter tests cobrindo: BE, trailing, partial close, combinações.
- Abstrações (`IBroker`, `ITickSource`) precisam ter implementações de teste (mock/fake).

Só depois construímos o primeiro EA simples para validação end-to-end.

## 2. Regras de conduta do dono

### 2.1 Aprovar mudanças explicitamente

Cada ação do Claude Code no filesystem requer aprovação. Não use "auto-accept" cegamente — revise diffs antes de aprovar. É seu código, sua responsabilidade final.

### 2.2 Revisar antes de commitar

Antes de `git commit`, olhe o diff. Nunca commitar "às cegas" o que a IA gerou, mesmo quando parece razoável.

### 2.3 Questionar quando não entender

Se o assistente propõe algo que você não entende, **pergunte**. Não aprove por conveniência. Código que você não entende é código que você não mantém.

### 2.4 Separar dúvidas de decisões

Ao fazer uma pergunta, deixe claro se é:
- **Dúvida técnica** ("como isso funciona?") — o assistente explica
- **Pedido de opção** ("qual caminho você recomenda?") — o assistente analisa e recomenda
- **Decisão tomada** ("vamos fazer X") — o assistente executa sem contestar (salvo se X violar alguma regra)

Isso evita loops de discussão quando a decisão já foi tomada, e evita execução precipitada quando ainda há dúvida.

## 3. Fluxo de desenvolvimento

### 3.1 Ordem de construção

1. Documentos base (Projeto, Regras, Roadmap, Arquitetura, Protocolos, Cheatsheet)
2. Abstrações do core (interfaces: `IBroker`, `ITickSource`, `IClock`, `ILogger`)
3. Implementações do core (`CMksRenkoBuilder`, `CMksTradeManager`, etc.)
4. Testes unitários do core
5. StressLab
6. EA de validação (o mais simples possível) para end-to-end
7. Estratégias reais, uma por uma, com backtest e stress test antes de cada live

### 3.2 Tamanho de mudança

Cada commit deve fazer **uma coisa só**. Evitar commits "wip com várias coisas". Se uma mudança envolve múltiplas preocupações, quebre em commits sequenciais.

### 3.3 Mensagens de commit

Usar **Conventional Commits**:

- `feat:` — nova funcionalidade
- `fix:` — correção de bug
- `refactor:` — mudança de código sem alteração de comportamento
- `docs:` — documentação
- `test:` — adição ou correção de testes
- `chore:` — tarefa de manutenção (build, config, etc.)
- `perf:` — melhoria de performance
- `style:` — formatação (não afeta lógica)

Mensagem em inglês, imperativo, presente. Primeira linha até 72 caracteres.

Exemplo:
feat: add RenkoBuilder with tick-based brick generation
Implementa CMksRenkoBuilder usando ATR para tamanho dinâmico.
Gera evento OnBrickClose quando brick completa.
Fecha issue #12.

### 3.4 Branches

Por enquanto, trabalhamos em `main` diretamente. Quando o projeto crescer, adotamos feature branches + pull requests. Essa transição fica registrada no `CHANGELOG.md` quando acontecer.

### 3.5 Push frequente

`git push` depois de cada commit concluído. Não acumular commits locais — GitHub é o backup.

## 4. Como pedir coisas ao assistente

### 4.1 Contexto antes da tarefa

Ao pedir uma tarefa complexa, forneça contexto. Bom:
> "Precisamos que o RenkoBuilder suporte bricks de tamanho dinâmico por ATR. Proponha uma API e discutimos antes de implementar."

Ruim:
> "Implementa brick dinâmico."

### 4.2 Restrições explícitas

Se há restrições (não pode mexer no arquivo X, precisa manter compatibilidade com Y), diga no pedido. Não presuma que o assistente lembra de tudo.

### 4.3 Nível de liberdade

Deixe claro se é exploração ou execução:
- "Me dá opções" — análise comparativa
- "Decida você e faça" — execução autônoma
- "Só me explica como fazer" — nenhuma modificação

## 5. Como o assistente responde

### 5.1 Propor antes de executar (em tarefas grandes)

Para mudanças que tocam múltiplos arquivos ou introduzem conceitos novos, o assistente **propõe primeiro** (texto explicando o plano) e **executa só após aprovação**. Tarefas pequenas e óbvias podem ser executadas direto.

### 5.2 Transparência sobre incerteza

Se o assistente não tem certeza de algo (API pouco documentada, comportamento do broker, etc.), diz explicitamente. Nunca inventar funcionalidade de biblioteca que não existe.

### 5.3 Admitir erro

Quando o assistente erra, o padrão é: reconhecer, identificar o erro, propor correção. Não disfarçar, não culpar o ambiente.

### 5.4 Manter o `CLAUDE.md` atualizado

Decisões de projeto importantes que mudam as regras ou a arquitetura devem ser refletidas no `CLAUDE.md`. Assistente deve sugerir atualização quando necessário.

## 6. Tratamento de erros e bugs

### 6.1 Reproduzir antes de consertar

Bug deve ser reproduzível antes de ser "consertado". Se não consegue reproduzir, não consegue validar o fix. Escrever um teste que falha antes, depois consertar e ver o teste passar — esse é o fluxo.

### 6.2 Documentar pós-mortem

Bugs graves (especialmente os que afetariam conta real) viram entrada no `CHANGELOG.md` com categoria **Fixed** e, se instrutivo, seção adicional no `ROADMAP.md` com "Lições aprendidas".

## 7. Atualização destas regras

Mudanças neste documento exigem:

1. Commit dedicado com mensagem `docs(rules): <descrição>`
2. Razão da mudança explicada na descrição do commit
3. Aprovação explícita do dono do projeto (já que as regras vinculam ambas as partes)

Regras não mudam por conveniência — mudam por aprendizado.
