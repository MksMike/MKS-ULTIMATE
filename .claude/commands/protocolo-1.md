---
description: Executa o Protocolo 1 — valida se um módulo do core está pronto
argument-hint: [caminho-do-arquivo-ou-nome-do-módulo]
allowed-tools: Read, Glob, Grep, Bash(git log:*), Bash(git diff:*)
---

# Protocolo 1 — Validação de módulo pronto

Módulo a validar: $ARGUMENTS

Execute estes passos em ordem, sem pular:

1. Leia `docs/PROTOCOLOS.md`, seção "Protocolo 1 — Antes de declarar um módulo do core 'pronto'".

2. Localize o(s) arquivo(s) do módulo informado. Se não encontrar, pergunte ao usuário o caminho exato antes de prosseguir.

3. Para cada item do checklist do Protocolo 1, verifique no código:
   - Header no formato padrão (`@file`, `@project`, `@module`, `@responsibility`, `@install_path`)
   - Doc-comment na declaração da classe explicando responsabilidade
   - Doc-comments em métodos públicos não-triviais
   - Ausência de bifurcações `if(MQL5_TESTING)` na lógica do módulo
   - Ausência de `Sleep` bloqueante
   - Ausência de acesso direto a `TimeCurrent()` (deve usar `IClock` injetado)
   - Ausência de acesso direto a `OrderSend`/`PositionSelect` fora do `CMksBroker`
   - Existência de unit tests correspondentes em `tests/`
   - Entrada correspondente em `CHANGELOG.md` na seção "Não lançado"

4. Para itens que exigem ação humana (compilação no MetaEditor, execução dos testes, verificação de determinismo), pergunte ao usuário diretamente — não presuma o resultado.

5. Apresente o resultado item a item com `✓` (passou), `✗` (falhou) ou `⚠` (não foi possível verificar automaticamente).

6. Para cada `✗` ou `⚠`, sugira a ação corretiva concreta.

7. Conclusão final: **o módulo está pronto ou não**. Se não está, liste exatamente o que falta pra estar.

**Tom:** técnico, direto, sem suavizar. Itens que violem paridade backtest/live ou ausência de testes são bloqueadores absolutos — destaque isso.
