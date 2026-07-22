---
@document: docs/RETROSPECTIVA-2026-07-22.md
@project: MKS-ULTIMATE
@purpose: Retrospectiva HONESTA da sessão de 2026-07-21/22 — o que foi entregue, mas sobretudo os PONTOS FALHOS do assistente (bugs que passaram, diagnósticos errados, afirmações de certeza que não se sustentaram). Registro para não repetir. Pedido do dono após 2 bugs do CS passarem.
@audience: Próximas sessões (o próprio assistente) + dono.
---

# Retrospectiva — sessão 2026-07-21/22

**Tom:** autocrítico, sem desculpa. O objetivo NÃO é o que deu certo — é o que eu deixei passar, pra a próxima sessão lembrar.

## 1. O que foi entregue (contexto, resumido)

Sessão longa, cruzou 2 dias. E6 fechado; runner de estresse (ADR-038, Fase 9 concluída); calibração spread+latência (ADR-039); circuit breaker corretivo (ADR-040); depois uma caça a bugs do CS (2 achados do dono) e a auditoria completa (17 auditores). Tudo commitado e pushado. Detalhe em `CHECKPOINT-2026-07-22-stress-e-breaker.md` e `AUDITORIA-2026-07-22.md`.

**Mas o valor deste documento é a §2.**

## 2. Os pontos falhos (o que eu errei)

### 2.1 O bug do `showWicks` — o tipo MAIS evitável
`OnBrickForming` ignorava a flag `showWicks` que o gêmeo `OnBrickClose` respeitava → o CS mostrava pavios mesmo com `wicks=false`. **Classe do erro:** uma flag/comportamento tratado num caminho e esquecido no caminho-gêmeo. Passou despercebido inclusive por mim ao revisar o sink. **Por que passou:** a lógica de desenho do CS é IMPURA (chama `CustomRatesUpdate`), não-unit-testável — validada por olhômetro. Os testes cobriam só a parte pura (`ComputeBrickTime`).

### 2.2 A saga da corrupção do CS — diagnóstico errado, em sequência
Ao investigar o "CS congelado com brick pequeno", eu:
- **Cheguei a conclusões antes de ter o dado.** Formulei o "Bug B" (o fill fecharia 0 bricks) como causa — **errado**: o log depois mostrou `bricks:1851`.
- **Abandonei cedo demais a hipótese certa** (recusa do `CustomRatesUpdate`) quando vi "1970" no log, e fui pra hipóteses novas.
- **Afirmei que a guarda `time>0` era "o conserto de raiz"** — **errado**: o Producer seta `nextBarTime = TimeCurrent()` (não 0), então a guarda é INERTE nele. Quem resolveu o caso do dono foi o *delete completo* do símbolo + a auto-recuperação, não a guarda. A guarda é defesa correta pra OUTROS callers, mas eu a vendi como a solução do problema dele.
- Precisei do **"esteja certo do que você vai fazer"** do dono como correção de rumo. Ele estava certo; eu não estava sendo rigoroso.

### 2.3 O padrão comum das falhas 2.1 e 2.2
- **Fix-on-guess:** consertar/afirmar antes de ter o dado que prova a causa.
- **Não distinguir "guarda correta" de "isto resolve o teu caso":** as duas coisas são diferentes e eu as misturei.
- **Confiança excessiva na camada menos testada.** O código impuro do CS/viz é onde eu deveria ter MAIS ceticismo, não menos.

## 3. O que a auditoria confirmou (dado, não opinião)

17 auditores + verificação adversarial. **9 confirmados, 8 deles na camada de DESENHO** (CS + Producer + indicadores). O motor de decisão (builder/brokers/risco/estratégia/runners) saiu quase limpo. **Conclusão factual: os bugs se concentram na camada thin-em-teste — exatamente a suspeita, agora provada.** Ver `AUDITORIA-2026-07-22.md`.

## 4. As lições — mudanças de método (concretas, não promessa vaga)

1. **Dado ANTES do conserto.** Pegar o log / a evidência que PROVA a causa antes de consertar ou afirmar. Nada de fix-on-guess.
2. **Lógica de duplo-caminho → verificar os DOIS.** Toda vez que uma flag/comportamento existe em dois lugares (close↔forming, live↔tester, fill↔live, BUY↔SELL, Send↔Close, preventivo↔corretivo, Producer↔ColorReversal), checar a simetria lado a lado. Foi a classe do `showWicks`.
3. **Extrair o impuro em puro testável.** Tirar a lógica de dentro das chamadas MT5 pra um helper puro que o teste cobre (fiz com `BoxBodyHigh/Low`, `IsRenderableBarTime`). Reduz o "olhômetro" na camada mais frágil.
4. **Distinguir "guarda defensiva correta" de "isto resolve o problema relatado".** Não apresentar a primeira como a segunda sem prova.
5. **Ceticismo MAIOR na camada CS/visualização/indicadores** — é onde os bugs se escondem. O motor é confiável; o desenho não é, até prova em contrário.

## 5. Estado ao fim da sessão

- **Lote A da auditoria aplicado** (5 fixes de correctness, incl. a raiz do desalinhamento do CS: `nextBarTime=0`). 52/0/0. MT5-verde das suítes pendente do dono.
- **Pendente:** Lote B (decisões/ADR), Lote C (verificar adversarialmente os plausíveis de dinheiro/dados — retomar o workflow), Lote D (E7/E8 — a raiz do CS: órfãs de formação / eixo por índice).
- **Fronteira honesta:** o Lote A conserta bugs concretos; NÃO torna o CS "impecável" — isso é o Lote D.

## 6. Regra permanente

Igual ao `V5-POSTMORTEM` fez com o código, este documento faz com o meu método: cada erro futuro deve ser comparado contra a §2 e a §4. A camada CS/viz é o ponto cego declarado — tratar com o rigor que o dono exige, não com o que passou.
