---
@document: docs/CHECKPOINT-2026-05-25-audit.md
@project: MKS-ULTIMATE
@purpose: Adendo da sessão 2026-05-25 (tarde/noite) — auditoria profunda do projeto, Lote A (sincronização documental) e Lote B parcial (B2+B3) executados; B1 suspenso por padrão de erro analítico identificado pelo dono.
@audience: Próxima sessão (humano + IA)
---

# CHECKPOINT — 2026-05-25 (auditoria profunda + sincronização documental)

Adendo a [`CHECKPOINT-2026-05-25.md`](CHECKPOINT-2026-05-25.md). A sessão anterior cobriu auditoria preliminar P0-P3 + Blocos 1/2/3 (trincos defensivos + pipeline ADR-024 completo em código + pacote pré-empírico). Esta sessão pegou a auditoria entregue, executou parcialmente as correções documentais, e terminou com confronto do dono sobre padrão de erro analítico do assistente — reordenando o plano de trabalho para o próximo ciclo.

**Regra:** CHECKPOINT é guia, código é verdade.

---

## 1. Escopo

Dono pediu **auditoria completa do projeto, ao máximo crítica, com relatório didático para leitor não-técnico**. Após auditoria, escolheu sequência de fechamento de arestas em três lotes:

- **Lote A (mecânico/documental):** sincronizar docs com realidade do disco.
- **Lote B (ADRs novas/amendas):** decisões arquiteturais pendentes.
- **Lote C (correções de código):** os 3 críticos da auditoria.

Sessão executou: **Lote A inteiro + Lote B parcial (B2, B3) + tentativa frustrada de B1**. Lote C não tocado. Zero código MQL5 modificado — todas as mudanças são em `docs/` + `CHANGELOG.md` + `CLAUDE.md`.

---

## 2. Auditoria entregue (resumo)

Cobertura: 67 arquivos `.mqh`, 38 arquivos `.mq5`, 3 PowerShell, 12 docs. Organizada em 10 pilares (disciplina anti-V5, documentação, núcleo Renko, execução, simulação, dados, saída, indicadores, testes/ferramentas, ecossistema).

**Três pontos 🔴 críticos identificados:**

1. **`CMksSimulatedBroker` não dispara SL/TP automaticamente.** Backtest estruturalmente otimista — recriação sutil do eixo 3 do V5-POSTMORTEM.
2. **`CMksStressLabBroker` não aplica latência ao fill price.** `latencyMeanMs`/`latencyStdevMs` declarados como "informativos em v1" — stress testing teatral para estratégias sensíveis a latência.
3. **Validação empírica E2E (Protocolo 1) nunca rodou.** Paridade do projeto é teorema, não fato.

**Descobertas materiais adicionais:**
- ROADMAP dessincronizado (Fases 5/6/7 marcadas como "Não iniciada" mas implementadas no disco).
- `CMksTradeManager` + conta netting é bug (`positionId` em netting não identifica posição individual).
- `CMksRiskManager.CheckOrder` não chama `snapshot.Update()` — depende do EA chamar manualmente.
- `CMksStressLabBroker.spreadMultiplier` mal composto com `CMksCostModel` (adiciona pontos extras em vez de multiplicar half-spread).
- Indicadores violam ADR-020 §1 pela letra (mas o caminho de paridade está fechado pela REGRAS §1.9 — descoberto durante a aplicação do B2).
- Dívida ADR-013 §5 sem ação tomada, mas critério de vencimento substantivo não foi satisfeito.

---

## 3. Lote A — Sincronização documental (concluído, 5 itens)

### A1. ROADMAP Fases 5, 6, 7, 8 → Concluída

- **Fase 5 (Trade Management):** marcada Concluída com entregáveis reais (`CMksFixedLotSizer`, `CMksPercentRiskSizer`, `CMksTradeManager`, `CMksTradeJournal`). Escopo reduzido documentado: ATR-adjusted e Kelly sizers não implementados — eixo de tamanho dinâmico já coberto pelo `CMksAtrBrickSizer`; Kelly espera dados de retorno realizados. Limitações conhecidas: netting + partial close, auto-detach em SL hit.
- **Fase 6 (Risk Management):** Concluída com as 3 camadas (6.1/6.2/6.3) + `CMksRiskGatedBroker` decorator. Limitação: `snapshot.Update()` não chamado em `CheckOrder` (fix pendente).
- **Fase 7 (StressLab):** Concluída com **3 limitações materiais** marcadas como pré-requisito da Fase 9 (latência informativa, `spreadMultiplier` mal composto, SL/TP não disparados). Engine separado não materializado — arquitetura final é composição (broker simulado → wrapper StressLab).
- **Fase 8 (Logging):** Concluída — `verify-parity.ps1` quita a ferramenta de log-diff prevista no critério de saída. Limitações: timestamp em segundos, `FileFlush` por linha.

### A2. ARCHITECTURE §2 — árvore de diretórios

Sincronizada com o disco: pastas adicionadas (`Core/Output/`, `Core/Trade/`, `Core/Risk/`, `Core/Position/`, `Core/Account/CMksAccountSnapshot`, `Core/Testing/Mocks/`, `MQL5/Indicators/MKS-ULTIMATE/`, `tools/`, `reference/`). Removida referência a `tests/` na raiz — testes reais vivem em `MQL5/Scripts/MKS-ULTIMATE/Tests/`. Convenções de slice (5a/5b/6.1/6.2/6.3) referenciadas nos comentários.

### A3. ADR-012 — nota de esclarecimento (dívida quitada)

Dívida "mecanismo de comparação de proveniência em runtime" da ADR-012 §Consequências foi quitada pelos slices 24b (`CMksFileTickSource.BrokerMismatch()`/`AccountMismatch()`) e 24d-parte-2 (`CMksMultiFileTickSource` com erros 807, 810, 811). Nota registra a quitação sem alterar a ADR.

### A4. CHANGELOG — entrada consolidando

Entrada `### Changed` no `[Não lançado]` referenciando todas as mudanças do Lote A.

### A5. `docs/CHECKPOINTS.md` (novo)

Índice cronológico dos 11 checkpoints acumulados (anteriores a este). **Decidiu-se indexar in-place em vez de mover para `docs/checkpoints/`** — análise dos links mostrou 10 links cruzados entre checkpoints + 1 link externo a `MQL5/Experts/` + 4 arquivos externos (ARCHITECTURE, ROADMAP, CHANGELOG, reference/V5/README) referenciando checkpoints. Mover quebraria tudo isso; indexar resolve o problema real (achar o relevante) sem refator. `CLAUDE.md` atualizado com entrada na lista de Documentos de referência marcando "**não está na ordem de leitura**".

---

## 4. Lote B2 — Nota de esclarecimento ADR-020 (indicadores)

**Problema reportado pela auditoria:** indicadores `.mq5` em `MQL5/Indicators/MKS-ULTIMATE/` leem o CS via API global do MQL5 (`iOpen`/`iClose`/`high[]`/`low[]`); a ADR-020 §1 lista "indicador customizado" entre os agentes proibidos de fazer isso. Aparente violação silenciosa que poderia recriar o eixo 2 do V5 caso uma estratégia consumisse indicador via `iCustom`.

**Descoberta ao aplicar:** **REGRAS.md §1.9** (tabela de APIs proibidas em código de estratégia) lista `iCustom` como **proibido**. O caminho perigoso `Strategy → iCustom(indicator) → CS` já está fechado pela REGRAS §1.9 — pelo *lado da estratégia*, não pelo *lado do indicador*. Logo, indicadores rodando no chart do CS para visualização humana não criam o risco que a regra 1 da ADR-020 quer impedir.

**Conclusão:** **conflito textual, não arquitetural**. Adicionada nota de esclarecimento na ADR-020 restringindo o alcance da regra 1 ao caminho `Strategy → iCustom(indicator) → CS`; `INDICATORS.md` ganhou §1.1 documentando isso com referência cruzada. ADR-020 não é alterada. Zero código tocado.

---

## 5. Lote B3 — Nota de esclarecimento ADR-013 §5 (dívida vencida)

**Problema reportado pela auditoria:** ADR-013 §5 declara dívida "nova ADR para detecção de broker, a ser proposta após o Slice 3 (Custom Symbol), com evidência empírica do que de fato varia entre brokers". Slice 3 e todos os subsequentes (4, 4.5, 5a, 5b, 6.1-6.3, 7, 8) foram fechados sem a dívida ser acionada.

**Descoberta ao aplicar:** o critério da §5 **não é "passar do Slice 3"** — é "**ter evidência empírica do que varia entre brokers**". Esse critério substantivo nunca foi satisfeito porque o framework só rodou contra um broker (Exness demo). Variação entre brokers já está absorvida pelo `ISymbol`/`IAccount` (ADR-016) e pelo `CMksMt5Broker` (ADR-017) sem precisar de "perfil estruturado".

**Conclusão:** dívida **permanece em aberto sem ação requerida**. ADR-013 ganhou nota de esclarecimento documentando o status e fixando **3 gatilhos explícitos de reabertura**:
1. Framework operar contra segundo broker com divergência de comportamento observada e documentada.
2. Caso de uso concreto exigir conhecimento prévio de propriedades do broker (estratégia decidir `OrderSendAsync` vs síncrono por broker, política de horário de sessão, regras de margem específicas).
3. Adição da camada virar pré-requisito de outra ADR aceita.

Zero código tocado.

---

## 6. Lote B1 — SUSPENSO antes da execução

**Problema reportado pela auditoria (Pilar 11.1):** Producer + TickRecorder consomem ticks do MT5 por canais paralelos diferentes (`SymbolInfoTick` no `OnTick` do Producer vs `CopyTicks` no loop do TickRecorder). Os dois canais podem divergir por dedup retroativo, ordem de chegada, janela de polling do Service, retransmissões. Pipeline canônico da ADR-024 (verify-parity comparando `live.mksbk` vs `replay.mksbk`) pode falhar **não por bug no builder, mas por input divergente** entre Producer e Replayer.

**Descoberta forte ao analisar:** **Producer não usa `ITickSource`** — lê `SymbolInfoTick` direto em [`Producer.mq5:610`](MQL5/Experts/MKS-ULTIMATE/Producer.mq5#L610). Replayer usa `ITickSource` (`CMksFileTickSource`). Logo, Producer e Replayer atravessam **o mesmo builder** mas consomem **fontes diferentes do MT5**. Falha arquitetural sutil identificada.

**Análise de 3 opções apresentada ao dono:**
- **Opção G (Producer emite o próprio `.mkstick` via sink novo):** single-source garantido — `.mkstick` reflete exatamente o stream que o builder viu; Replayer reproduz garantidamente o mesmo `.mksbk`. Custo: ~80 linhas. Recomendada.
- **Opção D (pipeline serial — TickRecorder captura, dois Replayers comparam):** zero código, mas só valida determinismo do builder (já garantido por construção). **Não valida o Producer.**
- **Opção C (aceitar divergência + ferramenta de diagnóstico):** zero código no caminho crítico, mas degrada o princípio norteador para "geralmente bate, aqui está o porquê".

### 6.1 Confronto do dono e reconhecimento de padrão

Dono interrompeu antes do `OK Opção G`:

> "já é a terceira vez que você supostamente identifica um problema, e na real é outro. Como posso ter certeza de que esse problema atual que você me disse é o problema real?"

**Reconhecimento do padrão pelo assistente.** Os três casos (B2, B3, B1) seguem o mesmo padrão de erro:

| Caso | Estrutura que identifiquei | Conclusão que apresentei | Onde estava o erro |
|---|---|---|---|
| **B2** | Indicadores leem CS via `iClose`/`iHigh` | "Viola ADR-020 §1" | Não cruzei com REGRAS §1.9 que cobre o caminho de paridade pelo outro lado. Conflito era **textual**, não arquitetural. |
| **B3** | Slice 3 passou; dívida não foi acionada | "Dívida vencida" | Não verifiquei o **gatilho substantivo** (evidência empírica entre brokers). O calendário passou; o critério substantivo, não. |
| **B1** | Producer usa `SymbolInfoTick`; TickRecorder usa `CopyTicks` | "Vai divergir; precisa de ADR-025" | **Nunca observei a divergência empiricamente.** Estava prevendo baseado em documentação MQL5 + raciocínio. Estaria propondo ADR-025 sobre risco teórico. |

**Padrão único dos três:** salto da estrutura observada no código direto para conclusão arquitetural, **sem passar pela ponte empírica**. Violação direta da `ARCHITECTURE.md` §4 ("recusa arquitetura no vazio") — regra que o próprio assistente citou duas vezes na sessão.

**Conclusão:** B1 suspenso. **ADR-025 não redigida.** O próximo passo correto é validação empírica E2E (Lote C item 11 da auditoria) **antes** de qualquer decisão sobre concorrência Producer/TickRecorder.

---

## 7. O que fazer na próxima sessão

A próxima sessão DEVE executar nesta ordem:

### 7.1 PRIMEIRO: Validação empírica E2E (Lote C item 11)

Antes de qualquer ADR-025 ou modificação de código:

**1. Pipeline canônico em demo** (Mike executa no MT5):
   - Atachar `Producer.mq5` em chart real (XAUUSDm em Exness demo) — geração de bricks live.
   - Atachar `TickRecorder.mq5` como Service paralelo — captura de `.mkstick` independente.
   - Deixar rodando por **≥1 hora** durante horário ativo de mercado (Londres ou NY).
   - Inputs idênticos: `InpBrickSizePts=3.0`, `InpInvalidTickLimit=10`, `InpThresholdLimit=20`.

**2. Replayer sobre o `.mkstick` capturado** (após finalizar Producer/TickRecorder):
   - Atachar `Replayer.mq5` apontando para o `.mkstick` gerado pelo TickRecorder via `InpTickFilePath`.
   - Inputs: `InpBrickSizePts`, `InpInvalidTickLimit`, `InpThresholdLimit` **idênticos** aos do Producer.
   - Gera `replay_*.mksbk` + `Replayer_*.log`.

**3. Comparação canônica via tool:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File c:\dev\MKS-ULTIMATE\tools\verify-parity.ps1 `
     -LiveMksbk   "<path>\MKS-ULTIMATE\Bricks\XAUUSDm_<TS>.mksbk" `
     -ReplayMksbk "<path>\MKS-ULTIMATE\Bricks\replay_<sourceStem>_<TS>.mksbk" `
     -LiveLog     "<path>\MKS-ULTIMATE\Logs\XAUUSDm_<TS>.log" `
     -ReplayLog   "<path>\MKS-ULTIMATE\Logs\Replayer_<sourceSymbol>_<TS>.log"
   ```

**4. Trazer para a próxima sessão**: os 4 arquivos gerados + a saída do `verify-parity.ps1` (texto integral com offset/campo identificado em caso de divergência).

### 7.2 SEGUNDO: Decidir B1 com base nos bytes

Três desfechos possíveis, ações correspondentes:

| Desfecho `verify-parity` | Ação no B1 |
|---|---|
| **Exit 0 (byte-a-byte idêntico após exclusão do range wall-clock 184-191)** | Cancelar ADR-025. Documentar como "investigado, não-problema". B1 vira nota em algum lugar. |
| **Divergência pequena** (1-N ticks isolados, 0 ou poucos bricks afetados) | ADR-025 fica embasada com **dados**: N=X, offset=Y, broker=Z. Escolha entre Opção G (sink direto) ou Opção C (tool de diagnóstico) depende da magnitude. |
| **Divergência grande ou estrutural** | ADR-025 (Opção G) + provavelmente correções adicionais. Causa concreta em mão para decidir. |

### 7.3 TERCEIRO: Lote C itens 1, 2 (decisões arquiteturais críticas — independente do B1)

Os outros 2 críticos da auditoria precisam ser endereçados antes da Fase 9:

- **SL/TP-hit detection no `CMksSimulatedBroker`.** ADR explícita declarando como v1 fica (auto-close interno baseado em `tick.bid`/`tick.ask` cruzando `sl`/`tp` armazenado), ou implementação imediata. Sem isso, backtest **mente** sobre stops e a Fase 9 valida ficção.
- **Latência aplicada ao fill no `CMksStressLabBroker`.** ADR explícita ou implementação imediata: a latência sortear**d**a deve gerar deslocamento no mid usado no fill (`fillPrice` reflete mid em `t + lat`, não em `t`).

### 7.4 QUARTO (opcional): Refinamentos médios

Lista da auditoria §12.2 — 9 itens 🟠 a endereçar caso a caso, com prioridade:
- TradeManager auto-Detach em fechamento externo (consulta a `IPositionBook`).
- RiskManager chama `snapshot.Update()` em `CheckOrder` (1 linha).
- Logger aceita `tickMsc` no contexto para precisão de ms quando o caller tem tick à mão.
- Producer chunking por dia no fill histórico (em vez de `CopyTicksRange` único de 30 dias).
- Bug netting + partial close documentado/protegido por `Validate()` que recusa configuração inválida.

---

## 8. Lição operacional descoberta nesta sessão

**Princípio:** observação → hipótese → **dado** → ADR, nessa ordem. Não pular a ponte empírica.

A `ARCHITECTURE.md` §4 já proíbe "arquitetura no vazio". Esta sessão concretizou 3 casos onde a regra teria sido violada:
- B2 violaria por declarar conflito que não existe (REGRAS §1.9 já cobria).
- B3 violaria por declarar dívida vencida sem checar critério substantivo.
- B1 violaria por redigir ADR-025 sobre risco teórico sem dado empírico de divergência.

**Memória de longo prazo a salvar (com aprovação explícita do dono):** *"Não pular ponte empírica — antes de propor ADR ou refator arquitetural baseado em risco identificado por raciocínio, verificar empiricamente que o risco é material. ARCHITECTURE.md §4 é o princípio existente; esta lição operacionaliza-o em padrão de processo."*

Status: ainda **não salva**. Pendente confirmação do dono.

---

## 9. Estado atual do repositório

Arquivos modificados nesta sessão (**não commitados** — dono não solicitou):

```
M CHANGELOG.md         (+14 linhas — Added + Changed)
M CLAUDE.md            (+1 linha — entrada para CHECKPOINTS.md)
M docs/ARCHITECTURE.md (~+150 linhas líquido — árvore §2 + notas ADR-012/013/020)
M docs/INDICATORS.md   (+6 linhas — §1.1)
M docs/ROADMAP.md      (~+110 linhas líquido — Fases 5/6/7/8)
?? docs/CHECKPOINTS.md (novo — índice cronológico)
?? docs/CHECKPOINT-2026-05-25-audit.md (este arquivo)
```

Branch: `feat/producer-classic-only`. Base: HEAD `e712c13` (`docs: CHECKPOINT 2026-05-25 (sessao atravessando 24-25/05)`).

**Nenhum commit feito.** Quando dono solicitar, commit sugerido:

```
docs: auditoria 2026-05-25 + sync ROADMAP/ARCHITECTURE + Lote A/B2/B3

- Lote A (sync documental): ROADMAP Fases 5/6/7/8 marcadas como Concluídas
  com entregáveis reais e limitações conhecidas; ARCHITECTURE §2 árvore
  sincronizada com disco; ADR-012 nota de dívida quitada; CHECKPOINTS.md
  como índice cronológico.
- Lote B2: nota de esclarecimento ADR-020 sobre alcance da regra 1
  (indicadores como visualização — paridade via REGRAS §1.9).
- Lote B3: nota de esclarecimento ADR-013 §5 sobre status da dívida de
  detecção de broker (permanece em aberto sem ação requerida; 3 gatilhos
  de reabertura fixados).
- B1 (concorrência Producer/TickRecorder) suspenso até validação empírica
  E2E confirmar divergência material.
```

---

## 10. Convenções operacionais re-confirmadas

- **CHECKPOINT é guia, código é verdade.**
- **REGRAS §1.7:** caminho de código único entre live e backtest — a única diferença é qual implementação de interface é injetada.
- **REGRAS §1.9:** APIs proibidas em código de estratégia (incluindo `iCustom`, `iOpen`, `iClose`, etc.) — paridade da estratégia é protegida pelo lado dela.
- **ARCHITECTURE.md §4:** arquitetura não é decidida no vazio — exige evidência empírica.
- **ADR-019 §cláusula anti-precedente:** sub-divisão de fase do ROADMAP só por ADR própria.
- **ADRs aceitas não são reescritas** — notas de esclarecimento são o canal correto.
- **Conventional commits** padrão de mensagens.

---

Sessão termina sem código MQL5 tocado. Próxima sessão começa pela **validação empírica E2E em demo** — é isso que vai destravar B1 e Fase 9.