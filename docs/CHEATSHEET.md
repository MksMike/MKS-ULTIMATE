---
@document: docs/CHEATSHEET.md
@project: MKS-ULTIMATE
@purpose: Referência rápida de comandos para Git, GitHub CLI, Claude Code e VS Code
@audience: Dono do projeto (principalmente) e qualquer contribuidor futuro
---

# MKS-ULTIMATE — Cheatsheet

Referência rápida de comandos mais usados no projeto. Organizado por tarefa.

**Como usar:** encontre o que quer fazer, copie o comando. Não precisa decorar.

---

## 1. Fluxos do dia-a-dia

### 1.1 Começar uma sessão de trabalho

```powershell
# Abrir o terminal dentro do projeto
cd C:\dev\MKS-ULTIMATE

# Abrir o VS Code nesta pasta
code .

# Puxar mudanças do GitHub (caso tenha trabalhado em outra máquina)
git pull
```

### 1.2 Commit e push (ritual completo)

```powershell
git status                      # o que mudou?
git add .                       # marca tudo para commit
git status                      # confirma que foi marcado
git commit -m "tipo: descrição" # registra no histórico local
git push                        # envia pro GitHub
```

**Tipos de commit** (Conventional Commits):
- `feat:` — nova funcionalidade
- `fix:` — correção de bug
- `refactor:` — muda código sem mudar comportamento
- `docs:` — só documentação
- `test:` — adiciona ou corrige testes
- `chore:` — manutenção (build, config, deps)
- `perf:` — melhoria de performance

### 1.3 Ver o que mudou antes de commitar

```powershell
git diff             # mostra mudanças em arquivos não-staged
git diff --staged    # mostra mudanças já adicionadas com git add
```

### 1.4 Ver histórico de commits

```powershell
git log --oneline                # formato curto, uma linha por commit
git log --oneline -10            # últimos 10 commits
git log --all --decorate --oneline --graph   # visual com branches
```

Atalho útil: configure um alias uma vez:
```powershell
git config --global alias.lg "log --all --decorate --oneline --graph"
```
Depois é só `git lg`.

### 1.5 Abrir o repositório no navegador

```powershell
gh repo view --web
```

### 1.6 Desfazer mudanças

```powershell
# Descartar mudanças em arquivo não-commitado
git restore NomeDoArquivo.md

# Descartar TODAS as mudanças não-commitadas (cuidado)
git restore .

# Tirar arquivo do staging (sem descartar as mudanças)
git restore --staged NomeDoArquivo.md

# Desfazer o último commit MANTENDO as mudanças nos arquivos
git reset --soft HEAD~1

# Desfazer o último commit DESCARTANDO as mudanças (muito cuidado)
git reset --hard HEAD~1
```

**Regra:** nunca use `--hard` se está em dúvida. É irreversível.

---

## 2. Git — referência essencial

### 2.1 Verificar estado

```powershell
git status                  # mostra arquivos modificados e branch
git branch                  # lista branches locais
git branch -a               # lista branches locais e remotos
git remote -v               # mostra remotes configurados
```

### 2.2 Configuração

```powershell
git config --global --list                      # vê todas configs
git config --global user.name "Seu Nome"
git config --global user.email "seu@email.com"
```

### 2.3 Ignorar arquivos

Editar `.gitignore` na raiz. Padrões comuns:
*.log                # ignora todos os .log
logs/                # ignora pasta inteira
!logs/.gitkeep       # exceção: mantém o .gitkeep

### 2.4 Arquivo já foi commitado mas deveria estar no .gitignore

```powershell
# Remove do Git mas mantém no disco
git rm --cached NomeDoArquivo.log
git commit -m "chore: stop tracking log files"
git push
```

---

## 3. GitHub CLI (`gh`)

### 3.1 Autenticação

```powershell
gh auth status              # vê se está logado
gh auth login               # logar
gh auth logout              # deslogar
```

### 3.2 Repositórios

```powershell
gh repo list                # lista seus repositórios
gh repo view                # mostra info do repo atual
gh repo view --web          # abre no navegador
gh repo clone nome-do-repo  # clona repo
```

### 3.3 Criar novo repositório a partir de pasta local

```powershell
cd C:\dev\meu-projeto
git init
git add .
git commit -m "chore: initial commit"
gh repo create NOME --private --source=. --remote=origin
git push -u origin main
```

### 3.4 Issues e PRs (para uso futuro)

```powershell
gh issue list               # lista issues abertas
gh issue create             # cria issue interativo
gh pr list                  # lista pull requests
gh pr create                # cria PR interativo
```

---

## 4. Claude Code

### 4.1 Iniciar sessão

```powershell
cd C:\dev\MKS-ULTIMATE       # entrar na pasta do projeto
claude                       # abrir Claude Code (lê CLAUDE.md automaticamente)
```

Alternativa: abrir via extensão VS Code no painel lateral (ícone da estrelinha do Claude).

### 4.2 Comandos internos dentro do Claude Code

Dentro da sessão, estes são comandos do Claude Code (começam com `/`):
/help          # lista comandos
/init          # gera um CLAUDE.md novo (já temos, não precisa rodar)
/exit          # sair
/clear         # limpar contexto da conversa atual
/theme         # trocar tema de cores

### 4.3 Boas práticas ao pedir coisas ao Claude Code

- **Dar contexto** antes da tarefa ("estamos na Fase 2 do ROADMAP, preciso que...").
- **Deixar claro o nível de autonomia** ("só me explique", "me dê opções", "execute direto").
- **Revisar diffs antes de aprovar** — o botão Allow existe por uma razão.
- **Apontar erros imediatamente** — se Claude Code sugerir algo ruim, dizer o que está errado em vez de deixar passar.
- **Não confiar cegamente em código gerado** — ler, entender, testar.

---

## 5. VS Code

### 5.1 Atalhos de teclado essenciais

| Ação | Atalho |
|------|--------|
| Abrir terminal integrado | `Ctrl + '` (apóstrofo) |
| Abrir painel de arquivos | `Ctrl + Shift + E` |
| Abrir busca global | `Ctrl + Shift + F` |
| Abrir painel Git | `Ctrl + Shift + G` |
| Abrir extensões | `Ctrl + Shift + X` |
| Abrir paleta de comandos | `Ctrl + Shift + P` |
| Abrir arquivo rápido | `Ctrl + P` |
| Salvar | `Ctrl + S` |
| Salvar todos | `Ctrl + K, S` |
| Fechar aba | `Ctrl + W` |
| Zoom in / out | `Ctrl + =` / `Ctrl + -` |

### 5.2 Paleta de comandos

`Ctrl + Shift + P` abre uma caixa onde você digita o que quer fazer. Úteis:
- `Git: Clone`
- `Git: Commit`
- `Terminal: Toggle Terminal`
- `Markdown: Open Preview`
- `View: Toggle Word Wrap`

### 5.3 Preview de arquivos Markdown

Com um arquivo `.md` aberto, `Ctrl + Shift + V` abre uma preview renderizada do lado.
Atalho alternativo: `Ctrl + K, V` abre preview lado-a-lado.

### 5.4 Extensões instaladas no projeto

- **MQL Tools** (L-I-V) — syntax highlighting para `.mq5` e `.mqh`
- **Claude Code** (oficial Anthropic) — integração com o assistente

---

## 6. PowerShell — o básico que você vai usar

| Comando | O que faz |
|---------|-----------|
| `cd caminho` | Entra em uma pasta |
| `cd ..` | Sobe um nível |
| `pwd` | Mostra a pasta atual |
| `ls` | Lista arquivos da pasta |
| `ls -Force` | Lista incluindo arquivos ocultos (começam com `.`) |
| `cat arquivo` | Mostra o conteúdo de um arquivo no terminal |
| `mkdir nome` | Cria uma pasta |
| `rm arquivo` | Remove arquivo (cuidado — não vai pra lixeira) |
| `rm -r pasta` | Remove pasta recursivamente |
| `Clear` | Limpa a tela do terminal |
| `code .` | Abre o VS Code na pasta atual |

### 6.1 Histórico de comandos

- **Setas ↑ / ↓** — navegar por comandos anteriores
- `Ctrl + R` — buscar em comandos anteriores

---

## 7. Fluxos comuns em situações específicas

### 7.1 Commitei algo errado e ainda não fiz push

```powershell
# Opção A: só muda a mensagem
git commit --amend -m "nova mensagem"

# Opção B: descarta o commit mas mantém as mudanças
git reset --soft HEAD~1

# Opção C: descarta tudo (atenção)
git reset --hard HEAD~1
```

### 7.2 Commitei algo errado e JÁ fiz push

```powershell
# Reverter criando um commit novo que desfaz o anterior
git revert HASH_DO_COMMIT
git push
```

`git revert` é seguro — ele adiciona um commit. Não reescreve história do remoto.

### 7.3 Adicionei arquivo secreto por engano (chave, senha)

1. **Considerar a senha vazada** e revogá-la/trocá-la imediatamente.
2. Remover do histórico é complicado; para arquivos grandes use `git filter-repo` ou BFG Repo-Cleaner.
3. Adicionar o arquivo ao `.gitignore` imediatamente.
4. Se o repo é privado e o incidente é recente, pode ser mais simples recriar o repo.

### 7.4 Quero ver quando/por que uma linha específica foi adicionada

```powershell
git blame NomeDoArquivo.md
```

Mostra commit, autor e data de cada linha.

### 7.5 Quero voltar meu código ao que estava há 3 commits atrás (só olhar)

```powershell
git log --oneline                    # pegar o hash do commit
git checkout HASH_DO_COMMIT          # ir até esse ponto
git checkout main                    # voltar pro atual
```

`checkout` com hash te coloca em modo "detached HEAD" — apenas leitura. Seguro.

---

## 8. Problemas comuns e soluções

### 8.1 "fatal: not a git repository"

Você está em uma pasta que não tem `.git/`. Provavelmente `cd` errado.
```powershell
pwd       # onde estou?
cd C:\dev\MKS-ULTIMATE    # vai pra pasta certa
```

### 8.2 "Your branch is ahead of 'origin/main' by N commits"

Você commitou localmente mas não pushou.
```powershell
git push
```

### 8.3 "Your branch is behind 'origin/main' by N commits"

Alguém (ou você em outra máquina) pushou algo que você ainda não baixou.
```powershell
git pull
```

### 8.4 "rejected - non-fast-forward"

Conflito: você e o remoto divergiram.
```powershell
git pull --rebase    # puxa e rebaseia seus commits por cima
git push             # agora deve funcionar
```

Se der conflito de merge, abrir os arquivos marcados (`<<<<<<<` aparece neles), resolver manualmente, e:
```powershell
git add .
git rebase --continue
git push
```

### 8.5 "npm : O termo 'npm' não é reconhecido..."

Path do PowerShell não foi atualizado. Fechar e abrir o terminal resolve.

### 8.6 "...execução de scripts foi desabilitada neste sistema"

Resolver com (terminal como admin, uma vez só):
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

---

## 9. Links rápidos

- **Repo:** https://github.com/MksMike/MKS-ULTIMATE
- **Conventional Commits:** https://www.conventionalcommits.org
- **Keep a Changelog:** https://keepachangelog.com
- **SemVer:** https://semver.org
- **MQL5 Reference:** https://www.mql5.com/en/docs
- **Git Book (grátis, excelente):** https://git-scm.com/book/pt-br/v2

---

## 10. Como este documento evolui

Toda vez que um comando novo virar parte do fluxo de trabalho, adicionar aqui na seção apropriada. Não deixar conhecimento solto "na cabeça" — se é usado mais de uma vez, entra no cheatsheet.

Commit: `docs(cheatsheet): add <descrição>`.
