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

## 9. Fluxos do framework MKS-ULTIMATE

### 9.1 Validar que tudo compila (sanity check)

Compila headless todos os `.mq5` do projeto (Experts, Services, Scripts, Indicators) via MetaEditor64. Útil antes de cada commit grande ou após refactor amplo.

```powershell
powershell -ExecutionPolicy Bypass -File tools\compile-all.ps1
```

Modos:
- Default: imprime cada arquivo + summary.
- `-Quiet`: só summary final.
- `-Editor <path>`: usa outro MetaEditor (default = Exness).

Exit codes: `0` tudo limpo, `1` erros, `2` warnings, `3` setup inválido.

### 9.2 Watcher de compile incremental (durante desenvolvimento)

Já roda automaticamente quando você abre o VSCode (task `watch: compile MQL5`). Para rodar manualmente:

```powershell
powershell -ExecutionPolicy Bypass -File tools\watch-compile.ps1
```

Recompila apenas os `.mq5` afetados por mudanças em `.mqh` ou `.mq5` em `MQL5/Include/MKS-ULTIMATE/` e `MQL5/Scripts/MKS-ULTIMATE/`.

### 9.3 Pipeline de paridade canônica (ADR-024)

Provar que backtest e live produzem o mesmo `.mksbk` byte-a-byte. **Esta é a prova mecânica que valida o framework antes de qualquer estratégia entrar.**

**Fase A — Captura (mercado aberto, ≥ 1h):**

1. MetaTrader → arrastar `Producer.mq5` num chart XAUUSDm
   - Inputs: `InpBrickSizePts=3.0`, `InpHistoricalFillDays=0` (sem fill histórico — paridade vale só para o trecho live)
   - Saída: `MQL5\Files\MKS-ULTIMATE\Bricks\XAUUSDm_<YYYYMMDD>T<HHMMSS>.mksbk` + `MQL5\Files\MKS-ULTIMATE\Logs\XAUUSDm_<TS>.log`
2. Navigator → Services → `TickRecorder` → instalar → input `InpSymbol=XAUUSDm`
   - Saída: `MQL5\Files\MKS-ULTIMATE\Ticks\XAUUSDm_<YYYYMMDD>.mkstick`
3. Deixar ambos rodando por ≥ 1h (idealmente atravessando momento de movimento — abertura de Londres, news).
4. Parar Producer (desanexar do chart) e TickRecorder (Stop no Services).

**Fase B — Replay (qualquer hora, qualquer chart):**

5. Arrastar `Replayer.mq5` em qualquer chart (mesmo símbolo ou não — Replayer é símbolo-agnóstico).
   - Input: `InpTickFilePath=MKS-ULTIMATE\Ticks\XAUUSDm_<YYYYMMDD>.mkstick` (mesmo arquivo da captura)
   - `InpBrickSizePts=3.0` (mesmo do Producer)
   - Saída: `MQL5\Files\MKS-ULTIMATE\Bricks\replay_XAUUSDm_<YYYYMMDD>_<TS>.mksbk` + log
6. EA encerra automaticamente ao atingir EOF (`ExpertRemove()`).

**Fase C — Verificação:**

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-parity.ps1 `
  -LiveMksbk "C:\Users\<você>\AppData\Roaming\MetaQuotes\Terminal\<hash>\MQL5\Files\MKS-ULTIMATE\Bricks\XAUUSDm_<live>.mksbk" `
  -ReplayMksbk "C:\Users\<você>\AppData\Roaming\MetaQuotes\Terminal\<hash>\MQL5\Files\MKS-ULTIMATE\Bricks\replay_XAUUSDm_<TS>.mksbk"
```

Exit code:
- `0` = paridade verificada (byte-a-byte idênticos exceto pelo range 184-191 do header, que é wall-clock por design).
- `1` = divergência detectada. O script reporta offset exato + qual campo (`header.broker`, `brick[42].close`, etc.) + bytes em hex.
- `3` = arquivo não encontrado.

**Diagnosticando divergência (exit 1):**
- Divergência em `header.*` (offset < 256) = problema de metadata (proveniência, geometria, contagem).
- Divergência em `brick[N].*` (offset ≥ 256) = não-determinismo do builder OU feed divergente (o `.mkstick` consumido pelo Replayer não corresponde aos ticks que o Producer viu em live).

**Opcional — comparar logs também:**

```powershell
powershell ... -LiveLog <live>.log -ReplayLog <replay>.log
```

Filtra linhas com eventos do builder (brick emitido, erros 102/103/104), normaliza `ts` e `sessionStartMsc` (que divergem inerentemente), compara linha-a-linha.

### 9.4 Onde estão os arquivos do framework

O terminal MT5 e o repo estão sincronizados via junctions. Path do terminal:
```
%APPDATA%\MetaQuotes\Terminal\<HASH>\MQL5\
```

Junctions ativas:
- `MQL5\Include\MKS-ULTIMATE` → `C:\dev\MKS-ULTIMATE\MQL5\Include\MKS-ULTIMATE`
- `MQL5\Experts\MKS-ULTIMATE` → `C:\dev\MKS-ULTIMATE\MQL5\Experts\MKS-ULTIMATE`
- `MQL5\Services\MKS-ULTIMATE` → `C:\dev\MKS-ULTIMATE\MQL5\Services\MKS-ULTIMATE`
- `MQL5\Scripts\MKS-ULTIMATE` → `C:\dev\MKS-ULTIMATE\MQL5\Scripts\MKS-ULTIMATE`
- `MQL5\Indicators\MKS-ULTIMATE` → `C:\dev\MKS-ULTIMATE\MQL5\Indicators\MKS-ULTIMATE`

Outputs ficam em `MQL5\Files\MKS-ULTIMATE\` (NÃO sincronizado com repo, gitignorado):
- `Bricks\` — `.mksbk` do Producer e do Replayer
- `Ticks\` — `.mkstick` do TickRecorder
- `Logs\` — `.log` JSON-line de qualquer EA/Service

### 9.5 Criar junction quando faltar (após clonar repo em máquina nova)

```powershell
cd "%APPDATA%\MetaQuotes\Terminal\<HASH>\MQL5\Include"
mklink /J MKS-ULTIMATE C:\dev\MKS-ULTIMATE\MQL5\Include\MKS-ULTIMATE
# Repetir para Experts, Services, Scripts, Indicators
```

### 9.6 Desinstalar/atualizar o MT5 com SEGURANÇA (⚠️ incidente 2026-07-19)

**PERIGO:** desinstalar o MT5 (ou deixar o uninstaller/Explorer apagar a pasta `MQL5\`) **com as junctions vivas ATRAVESSA as junctions e apaga os arquivos-alvo no repo** — foi o que aconteceu em 2026-07-19 (recuperado via `git checkout HEAD -- MQL5/`; só o git salvou). **Sempre remova as 5 junctions ANTES de desinstalar.** Remover a junction (`rmdir`) NÃO apaga os arquivos do repo — só corta o atalho.

```powershell
# 1. ANTES de desinstalar: remover as 5 junctions do lado do terminal.
$mql5 = "$env:APPDATA\MetaQuotes\Terminal\<HASH>\MQL5"
foreach ($t in 'Include','Experts','Services','Scripts','Indicators') {
  $link = Join-Path $mql5 "$t\MKS-ULTIMATE"
  if (Test-Path $link) { cmd /c rmdir "$link" }   # rmdir remove a junction, não o alvo
}
# 2. Confirmar que o repo segue intacto:  git -C C:\dev\MKS-ULTIMATE status
# 3. Agora sim desinstalar/atualizar o MT5.
# 4. Após reinstalar: recriar as junctions (§9.5) — se o path de instalação
#    for o mesmo, o HASH do Terminal é o MESMO.
```

Regra geral: **commit + push antes de qualquer mexida no terminal** — trabalho não commitado morre junto.

### 9.7 Backup dos dados de captura (insubstituíveis)

Os `.mkstick`/`.mksbk`/`.log` vivem só em `MQL5\Files\MKS-ULTIMATE\` (fora do repo, gitignorado) — o tick feed não se recaptura. Backup para fora da árvore do terminal:

```powershell
powershell -ExecutionPolicy Bypass -File C:\dev\MKS-ULTIMATE\tools\backup-captures.ps1
# Default: copia para C:\dev\MKS-DATA. Ajuste com -Dest <path> (ex.: uma pasta OneDrive/nuvem).
# Para agendar diário: Task Scheduler → nova tarefa → aponta para o comando acima.
```

### 9.8 Runbook de primeira execução — operar o ColorReversal (E6.4)

O caminho único para pôr o EA de trading pra rodar. **Um EA por função — não confunda:**

| Artefato | Tipo | Para quê | Anexar em |
|---|---|---|---|
| **`ColorReversal`** | Expert | **É o que OPERA** (live e tester) | chart do símbolo **REAL** (ex.: XAUUSDm) |
| `Producer` | Expert | Só desenha o Custom Symbol (visualização do renko) — **não opera** | chart do símbolo real |
| `TickRecorder` | Service | Captura `.mkstick` do feed (para replay/paridade) | Navigator → Services |
| `Replayer` / `DecisionReplayer` | Expert | Replay de `.mkstick` (paridade de bricks / de decisão) | qualquer chart |
| `Test_*` | Script | Testes do core — arrastar como Script (rodam sem recompilar) | qualquer chart |

**Pré-requisitos (uma vez):**
1. Conta **HEDGING** (o EA recusa netting/exchange com popup — invariante v1, ADR-029).
2. Junctions ativas (§9.5) e `compile-all` **0/0** (§9.1).
3. Símbolo **REAL** do broker no Market Watch (o EA recusa anexar num Custom Symbol `.MKS*`).

**Passo a passo (live):**
1. Abrir um chart do **símbolo real** (ex.: `XAUUSDm`). **Não** o CS de visualização.
2. Arrastar `ColorReversal` no chart. Ajustar os inputs **básicos**:
   - `InpBrickSize` (tamanho do brick em USD; XAU ≈ 3.0)
   - `InpSlBricks` (SL em **bricks**, broker-agnóstico — ADR-032; default 10)
   - `InpLotMode` + `InpFixedLots` **ou** `InpRiskPct`
   - Limites de risco: `InpMaxDailyLossPct`, `InpMaxDrawdownPct`, `InpMinEquityAbs`
   - (`InpMagicNumber` só se rodar mais de uma estratégia no mesmo símbolo)
3. **Enter.** O EA: valida conta/símbolo/piso de SL, cria+abre o chart do Custom Symbol de visualização, opcionalmente popula `InpHistoricalFillDays` dias de bricks (warm-up, **não opera** no passado), e passa a abrir/fechar posição a cada flip de cor.
4. Acompanhar em `MQL5\Files\MKS-ULTIMATE\Logs\ColorReversal_<symbol>_<TS>.log` (JSON-line) e nas setas de trade no chart do CS (ADR-028).

**Se o EA recusar anexar (popup/`INIT_FAILED`), a causa está na mensagem:**
- *"é um Custom Symbol"* → anexe no símbolo real, não no `.MKS*`.
- *"conta NETTING/EXCHANGE"* → troque para conta/corretora hedging.
- *"piso de SL / InpSlBricks abaixo do piso"* → suba `InpSlBricks` (ou `InpMinSlBricks`).
- *"N posições abertas… gerencia no máximo 1"* → feche/ajuste manualmente e reanexe.

**Backtest (Strategy Tester):** mesmo EA, mesmos inputs; o CS é pulado (proibido no tester — os bricks vão direto à estratégia). Para stress (níveis None→Nightmare) ainda **não** há runner pronto — fatia futura.

---

## 10. Links rápidos

- **Repo:** https://github.com/MksMike/MKS-ULTIMATE
- **Conventional Commits:** https://www.conventionalcommits.org
- **Keep a Changelog:** https://keepachangelog.com
- **SemVer:** https://semver.org
- **MQL5 Reference:** https://www.mql5.com/en/docs
- **Git Book (grátis, excelente):** https://git-scm.com/book/pt-br/v2

---

## 11. Como este documento evolui

Toda vez que um comando novo virar parte do fluxo de trabalho, adicionar aqui na seção apropriada. Não deixar conhecimento solto "na cabeça" — se é usado mais de uma vez, entra no cheatsheet.

Commit: `docs(cheatsheet): add <descrição>`.
