---
description: Cria uma nova ADR (Architecture Decision Record) em docs/ARCHITECTURE.md
argument-hint: [título curto da decisão]
allowed-tools: Read, Edit
---

# Nova ADR

Título proposto: $ARGUMENTS

Execute estes passos:

1. Leia `docs/ARCHITECTURE.md` por completo. Identifique:
   - O próximo número ADR disponível (última ADR existente + 1)
   - A lista de princípios invariantes (seção 1)

2. Pergunte ao usuário, em uma única mensagem bem estruturada:
   - **Contexto:** qual problema motiva esta decisão? Qual situação apareceu que exige decidir isso agora?
   - **Decisão:** o que propomos fazer?
   - **Alternativas consideradas:** quais outras opções foram avaliadas e por que foram rejeitadas? (mínimo 1 alternativa — decisão sem alternativa avaliada é palpite)
   - **Consequências:** o que muda no projeto como resultado? Há trade-offs? Dívidas técnicas criadas?

3. **Valide contra os princípios invariantes.** Se a ADR proposta violar algum princípio (paridade backtest/live, caminho de código único, abstrações antes de implementações, determinismo, zero dependência de código fechado), PAUSE e confronte o usuário antes de escrever nada:
   - Aponte qual princípio é violado e por quê
   - Pergunte se ele quer reconsiderar, ou se quer seguir adiante (o que exige atualizar `docs/Projeto.md` primeiro, pois princípios vêm de lá)

4. Se passar na validação, monte a nova ADR no formato padrão (use ADR-003 como template de estilo), com:
   - Data: data de hoje (formato YYYY-MM-DD)
   - Status: **Proposta** (usuário aceita explicitamente depois)

5. Mostre o diff proposto antes de aplicar ao arquivo.

6. Depois de aprovado, adicione também uma entrada no `CHANGELOG.md` na seção "Não lançado":


Added

ADR-NNN proposta: [título]


**Tom:** modo sério técnico (conforme `docs/TOM-E-CHATS.md`, seção 1.2) — decisão arquitetural é contexto de risco. Sem humor, cirúrgico.
