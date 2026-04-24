---
description: Resume o estado atual do projeto MKS-ULTIMATE
allowed-tools: Read, Bash(git log:*), Bash(git status), Glob
---

# Status do projeto MKS-ULTIMATE

Execute:

1. Leia `docs/ROADMAP.md` e identifique:
   - A fase atual (status "Em andamento")
   - A próxima fase não iniciada

2. Execute `git log --oneline -10` e mostre os últimos 10 commits.

3. Execute `git status` e identifique se há arquivos modificados não commitados.

4. Leia `docs/ARCHITECTURE.md`, seção "Decisões pendentes", e liste as ADRs pendentes (ADR-004 em diante, conforme o caso).

5. Apresente o resumo em formato conciso:
   - **Fase atual:** (nome + breve descrição)
   - **Próxima fase:** (nome)
   - **Últimos commits:** (lista de hash + mensagem, máximo 5)
   - **ADRs pendentes:** (lista curta)
   - **Working tree:** limpo / N arquivos modificados (listar quais)

**Tom:** objetivo. Sem frases introdutórias decorativas. Relatório de estado, não narrativa.
