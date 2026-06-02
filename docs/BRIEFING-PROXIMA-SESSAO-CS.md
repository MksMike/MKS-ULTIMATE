---
@document: docs/BRIEFING-PROXIMA-SESSAO-CS.md
@project: MKS-ULTIMATE
@purpose: Briefing de arranque para uma NOVA sessão. Missão: realinhar a visualização MANTENDO e CORRIGINDO o Custom Symbol (ADR-031 revertida em 2026-06-02: de "aposentar o CS" para "manter+corrigir o CS") e fechar as pontas abertas da auditoria, com qualidade profissional, sem gambiarra e sem ponta solta.
@audience: Assistente (Claude) de uma sessão nova + dono (Mike).
@como_usar: Cole este conteúdo na PRIMEIRA mensagem da sessão nova.
---

# BRIEFING — Realinhar a visualização (MANTER + CORRIGIR o CS, ADR-031) + fechar pontas abertas

> Cole isto numa sessão nova. Ele NÃO substitui a ordem de leitura do projeto — ele aponta pra ela e adiciona a missão.

> ⚠️ **REVERSÃO (2026-06-02) — leia antes de tudo.** A premissa original deste briefing ("aposentar o CS", ADR-031 = abandonar) foi **revertida**. Comparação com o V5 (mesmo `CustomRatesUpdate`, atravessava meia-noites sem morrer) refutou o veredito de "bug de plataforma incorrigível". A morte do CS era **auto-infligida** (CS sem sessões 24/7 [causa-raiz]; specs reaplicadas a cada `OnInit` apagando o histórico; sink sem recovery) e já tem os **4 fixes aplicados** (sessões 24/7; specs só na criação; recovery no sink; marcador em `sink.lastBarTime`), compilando 0/0. **Missão agora = MANTER e CORRIGIR o CS.** Sobrevivência à meia-noite com o build novo segue **pendente de dado** (cruzamento 06-02→06-03 ainda não ocorreu). Onde o texto abaixo disser "aposentar/substituir o CS", leia "manter+corrigir". Detalhe na nota REVERSÃO 2026-06-02 da ADR-023-A (`ARCHITECTURE.md`) e no `CHANGELOG.md`.

## 0. Bootstrap obrigatório (faça antes de qualquer ação)

1. Ler, nesta ordem: `CLAUDE.md` → `docs/Projeto.md` → `docs/REGRAS.md` → `docs/ROADMAP.md` → `docs/ARCHITECTURE.md` (ADRs até a 031; ler com atenção ADR-020, ADR-021, ADR-023, **ADR-023-A** e a nota de correção 2026-05-30) → `docs/V5-POSTMORTEM.md` → `docs/PROTOCOLOS.md` → `docs/CHANGELOG.md` → `docs/TOM-E-CHATS.md`.
2. Ler o checkpoint mais recente: `docs/CHECKPOINT-2026-05-30.md` (estado + diagnóstico do CS + divergência entre branches).
3. Invocar `/status` e conferir contra `git log` e `git branch -a` antes da primeira ação.

## 1. Missão desta sessão

**Deixar a visualização sólida e profissional — sem gambiarra, sem ponta solta.** Concretamente:

- **Executar a ADR-031: MANTER e CORRIGIR o Custom Symbol (CS)** (decisão revertida 2026-06-02 — não mais "aposentar"). Os 4 fixes das causas auto-infligidas já estão aplicados (sessões 24/7; specs só na criação; recovery no sink; marcador em `sink.lastBarTime`); falta **validar empiricamente** a sobrevivência à virada de dia (06-02→06-03 ainda não ocorreu).
- **PRIMEIRO**, antes de desenhar/codar qualquer coisa: **capturar com o dono o que ele espera da visualização** (requisitos). "Alinhar de acordo com o que eu espero" exige elicitar a expectativa, não presumir. Sem isso, qualquer implementação é palpite (e palpite vira gambiarra). Ver §5.
- **Fechar as pontas abertas** da auditoria (§6), cada uma pela causa-raiz.

## 2. Princípios inegociáveis (recolar a disciplina antes de mexer)

- **Anti-V5 (V5-POSTMORTEM):** 4 eixos. Paridade backtest/live bit-a-bit. Caminho de código único. Custo de execução aplicado ao equity, nunca ao lado.
- **ADR-020 §1 — a estratégia NUNCA lê o visual.** Isso é o que mantém qualquer problema do CS confinado à UX. A ADR-031 (manter+corrigir) **não** remove o Custom Symbol; a regra de isolamento vale por si.
- **Zero gambiarra (REGRAS §1.2):** resolver a causa-raiz, nunca esconder o sintoma. (A causa-raiz da morte do CS NÃO era "renko num eixo de tempo" — era falta de sessões 24/7 + reaplicação de specs apagando o histórico + ausência de recovery, tudo auto-infligido e já corrigido. O cap de drift da ADR-023-A foi band-aid sobre uma não-causa; mantido só como higiene.)
- **Não fazer arquitetura no vazio (ARCHITECTURE §4) + ponte empírica:** observação → hipótese → **dado** → ADR. Não propor refator sobre risco teórico; validar empiricamente.
- **Propor antes de executar** mudança arquitetural; **toda decisão estrutural vira ADR** (a ADR-031 ainda NÃO é ADR escrita/aceita — só referenciada; seu sentido mudou para "manter+corrigir o CS" e deve ser redigida com o conteúdo correto após a validação empírica).
- **Nunca gerar código que não compila (REGRAS §1.3):** compilar headless (MetaEditor64 / watcher) e validar os testes no MT5 antes de declarar pronto (Protocolo 1).
- **Git:** não commitar nem pushar sem o dono pedir. Conventional Commits, mensagem técnica em inglês para `feat/fix`, pt-BR para `docs:`. **NUNCA usar o trailer `Co-Authored-By`** (o dono mantém o histórico limpo).

## 3. Estado atual (verdade do git + produção — 2026-05-30)

- **Branch de produção:** `feat/phase9-trade-visualization` (== `origin`, HEAD `7621507`). É o que está rodando no terminal.
- **Já validado no MT5 e pushado** (NÃO reabrir): **ADR-029** (hedging-only — broker recusa netting/exchange, `Test_CMksMt5Broker` 11/11) e **ADR-030** (StressLab credível p2 — saídas estressadas + requote interno + report sobre pipeline real; `Test_CMksStressLabBroker` 112/112 + `Test_CMksStressLabReport` 32/32).
- **EA `ColorReversal` rodando LIVE** (demo Exness, XAUUSDm). **Trading OK; o CS é que está quebrado visualmente.**
- **Branches divergentes (a reconciliar):** `feat/sensors-foundation` e `feat/indicators-bundle-1` (trabalho paralelo, **não auditado** nesta linha, **não mergeado** na produção) + **`main` defasada** (nada da Fase 9/viz/ADR-029/030 está em main).

## 4. O problema do CS — causa-raiz (para a ADR-031 atacar a raiz certa)

**REVISADO 2026-06-02.** A morte do CS na virada de dia tinha **causas auto-infligidas** (não um bug incorrigível de plataforma — o V5 usava o mesmo `CustomRatesUpdate` e atravessava a meia-noite sem morrer):

1. **CS criado SEM sessões 24/7 (CAUSA-RAIZ).** O MT5 recusa `CustomRatesUpdate` na **virada de dia do server** quando faltam sessões nos 7 dias (`-1` com `GetLastError()=0`). O V5 setava `CustomSymbolSetSessionQuote/Trade` 24/7 em todos os dias — por isso sobrevivia.
2. **Spec-setters reaplicados a cada `OnInit`** (`SYMBOL_DIGITS/POINT/CHART_MODE/TICK_SIZE`) apagavam o histórico do CS a cada re-anexação do EA.
3. **Sink sem recovery** na falha do `CustomRatesUpdate`.

Os achados anteriores ("bug de plataforma incondicional", "independente de barra-no-futuro", "`CustomRatesReplace`/`CustomTicksAdd` compartilham o container bugado") estão **refutados/eram conjectura sem fonte**. A corrupção de virada de dia que existe no fórum é **condicional a múltiplos custom symbols** (sem reprodução com CS único — nossa config). A mecânica da timeline híbrida (gaps/colisões em rajada) afeta **aparência**, não era a causa da morte, e **não** torna o CS "o veículo errado".

**Conclusão REVISADA:** o CS **é mantido e corrigido**. ADR-020/021/023/023-A **não** são superseded (o cap da ADR-023-A fica como higiene). Os 4 fixes (sessões 24/7; specs só na criação; recovery no sink; marcador em `sink.lastBarTime`) estão aplicados (0/0); **sobrevivência à meia-noite pendente de dado** (06-02→06-03). Segue verdade que **não é problema de trading** — a estratégia não lê o CS; o `.mksbk` + audit TSV são a verdade e estão íntegros.

## 5. PRIMEIRO PASSO da sessão — elicitar a expectativa do dono (não pular)

Antes de escolher a solução, perguntar ao dono (e registrar as respostas na ADR-031):

- **O que ele quer VER:** só os bricks renko limpos? bricks + marcadores de trade (setas/linha P&L da ADR-028)? indicadores (Donchian/RSI/etc.) por cima? eixo de tempo real ou índice de brick?
- **Onde:** no chart do símbolo real (`XAUUSDm`)? num indicador em subjanela? objetos sobre os candles M1? um indicador `DRAW_COLOR_CANDLES`?
- **Fidelidade:** caixinhas sólidas (sem wick) como renko clássico, ou com wick de excursão? tamanho fixo visual?
- **Live e backtest:** a visualização precisa funcionar no Strategy Tester também (lembrar: tester proíbe `CustomSymbolCreate`)? E para revisar um backtest a partir do `.mksbk`?
- **Producer:** o `Producer.mq5` também usa o `CMksCustomSymbolSink` — ele migra junto ou continua no CS? (decisão de escopo).

Só depois disso: **redigir a ADR-031** (contexto, decisão, alternativas, consequências, fronteiras), aceitar com o dono, e então implementar.

## 6. Pontas abertas a fechar (priorizadas) — todas sem gambiarra

1. **[FOCO] ADR-031 — manter e CORRIGIR o CS** (não mais "substituir"). Validar empiricamente os 4 fixes aplicados (sessões 24/7; specs só na criação; recovery no sink; marcador em `sink.lastBarTime`) — a virada de meia-noite 06-02→06-03 é o teste pendente. A família `IRenkoIndicator` (nota ADR-020-A) e os marcadores (ADR-028) seguem como tópicos válidos, agora sobre o CS corrigido. Visualizador de backtest do `.mksbk` (CS gerado fora do tester) continua válido.
2. **`Test_CMksCustomSymbolSink_Timeline.mq5`** — rodar a suíte no MT5 e confirmar verde. (A ADR-031 mantém o CS e o sink — a suíte NÃO será aposentada; ao contrário, deve cobrir os 4 fixes.) Compila 0/0 com os fixes aplicados.
3. **Alinhamento de branches** (decisão do dono + execução cuidadosa): ordem de merge de `phase9-trade-visualization`, `sensors-foundation`, `indicators-bundle-1`; o que e quando vai pra `main`. Auditar `sensors`/`indicators` antes de mergear (não foram revisados). Deletar `feat/hedging-only-guard` (já mergeada).
4. **Dívidas menores da auditoria** (não-bloqueantes, fechar quando tocar a área):
   - Logger ignora `IClock` — no replay o `ts` é wall-clock, não tempo do feed (não afeta paridade; corrigir aceitando `tickMsc`).
   - `watch-compile.ps1` com pontos cegos: ignora `#include "..."` (quote-style → editar `TestRunner.mqh` não recompila testes) e não observa `Experts/`/`Services/`.
   - `CMksSimulatedBroker` swap=0 (carry overnight não modelado; ok p/ intraday, mas nada força intraday).
   - Drift de comentários/códigos de erro (ADR-024 nomeia `MKS_ERR_TICKFILE_*` que não existem; comentários velhos em `CMksFileTickSource`).
   - `DumpMksTick.mq5` divide por zero com `InpPrintLastN=0`.

## 7. Decisões que o dono precisa tomar (perguntar cedo)
- A **visão da visualização** (§5) — bloqueia a ADR-031.
- **Ordem de merge das branches** e o que vai pra `main`.
- Se o **Producer** migra do CS junto com a estratégia.

## 8. Operacional (compilar/testar)
- **Compilar headless:** o watcher (`tools/watch-compile.ps1`) roda no save via VSCode; para forçar, `tools/compile-all.ps1` (ou MetaEditor64 `/compile:<arquivo> /log:<log>` direto). Terminal data path: `...\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06\` (junctions repo↔terminal). Log do compile é UTF-16; procurar a linha `Result: N errors, N warnings`.
- **Testar:** rodar os `Test_*.mq5` como Script no MT5; verde = `=== N/N assertions in M tests (0 failed) ===`.
- **Paridade:** `tools/verify-parity.ps1` quando tocar RenkoBuilder/ITickSource/IClock/sink de `.mksbk`.

---

**Resumo em 3 linhas:** (1) Missão = MANTER e CORRIGIR o CS (ADR-031 revertida 2026-06-02: de "aposentar" para "manter+corrigir") e fechar as pontas abertas, sem gambiarra. (2) Os 4 fixes (sessões 24/7; specs só na criação; recovery no sink; marcador em `sink.lastBarTime`) estão aplicados e compilam 0/0; falta validar a virada de meia-noite (06-02→06-03). (3) Trading sólido e validado (ADR-029/030 no MT5); o CS quebrado era só visual e tinha causas auto-infligidas. NB separado: o INVALID_STOPS (retcode 10016) de 06-02 veio de `InpSlPoints=30` (vs 3000 que funcionava), SL abaixo do stops level do broker — não é problema do CS.
