---
@document: docs/PROTOCOLOS.md
@project: MKS-ULTIMATE
@purpose: Checklists executáveis para momentos de risco operacional e decisório
@audience: Dono do projeto, assistentes de IA
---

# MKS-ULTIMATE — Protocolos

Este documento contém **checklists**. Cada protocolo é uma lista de verificação que deve ser percorrida integralmente antes de executar a ação correspondente. Pular itens do checklist é violação do protocolo.

Protocolos existem porque decisões de risco tomadas por memória ou intuição são estatisticamente piores do que decisões tomadas por checklist. Pilotos de avião usam checklist antes de cada decolagem mesmo depois de 10 mil horas de voo. O mesmo se aplica aqui.

**Onde usar:** No dia-a-dia. Antes de cada uma das ações descritas abaixo, **abra este arquivo e percorra o checklist**.

---

## Protocolo 1 — Antes de declarar um módulo do core "pronto"

Aplicável quando um módulo novo (ex: `CMksRenkoBuilder`) está para ter status alterado de "em desenvolvimento" para "pronto" no ROADMAP.

- [ ] Código compila sem warnings no MetaEditor
- [ ] Header do arquivo está no formato padrão (`@file`, `@project`, `@module`, `@responsibility`, `@depends_on`, `@install_path`)
- [ ] Classe tem doc-comment na declaração explicando responsabilidade
- [ ] Métodos públicos têm doc-comment quando não forem auto-evidentes
- [ ] Nenhuma bifurcação `if(MQL5_TESTING)` na lógica do módulo
- [ ] Nenhum `Sleep` bloqueante
- [ ] Nenhum acesso a `TimeCurrent()` direto (usa `IClock` injetado)
- [ ] Nenhum acesso a `OrderSend`/`PositionSelect` direto fora do `CMksBroker`
- [ ] Unit tests cobrem: caminho feliz, casos de borda, condições de erro
- [ ] Unit tests passam
- [ ] Determinismo verificado (duas execuções com mesma entrada produzem mesma saída)
- [ ] `ARCHITECTURE.md` atualizado se a conclusão do módulo trouxe decisões arquiteturais novas
- [ ] `CHANGELOG.md` atualizado na seção "Não lançado"
- [ ] Commit na convenção (`feat:` ou `refactor:` conforme o caso)

Se qualquer item está "não" — o módulo não está pronto.

---

## Protocolo 2 — Antes de rodar um EA em backtest pela primeira vez

- [ ] Símbolo, timeframe e janela temporal conferidos
- [ ] Qualidade de dados do MT5 verificada (ideal: "Every tick based on real ticks")
- [ ] Histórico baixado e validado (sem gaps suspeitos no período testado)
- [ ] Configuração de custos explícita: spread, comissão, swap
- [ ] Parâmetros do EA revisados (SL, TP, lot size, horários de trading)
- [ ] Logger configurado em nível INFO no mínimo
- [ ] Pasta de logs verificada com espaço em disco
- [ ] `MagicNumber` do EA único e não conflita com outros EAs

Se qualquer item está "não" — não roda o backtest.

---

## Protocolo 3 — Depois de rodar um backtest

- [ ] Número de trades > 30 (amostra mínima estatística)
- [ ] Relatório salvo em `logs/backtest/<data>_<estrategia>.html`
- [ ] Log estruturado salvo
- [ ] Gráfico de equity revisado — procurar por: curva suspeita demais (perfeita), quedas bruscas únicas, padrões de trade em horários específicos
- [ ] Drawdown máximo registrado
- [ ] Trade de maior perda investigado individualmente
- [ ] Resultado comparado contra backtest anterior da mesma estratégia (se houver)
- [ ] Entrada no `CHANGELOG.md` ou diário técnico se for backtest de release

---

## Protocolo 4 — Antes de rodar no StressLab

Aplicável após backtest normal ter passado.

- [ ] Backtest normal passou no Protocolo 3
- [ ] Parâmetros do StressLab definidos por escrito antes de rodar (evita tuning reativo)
- [ ] Níveis de estresse a testar: leve, médio, alto (mínimo 3 passes)
- [ ] Critério de "aprovação" definido antes — ex: "sobrevive a stress alto com drawdown < 2x o drawdown do backtest normal"
- [ ] Resultados de cada nível documentados em tabela comparativa

---

## Protocolo 5 — Antes de rodar em conta demo live

Aplicável após StressLab ter passado.

- [ ] StressLab passou em todos os níveis definidos no Protocolo 4
- [ ] Conta demo configurada com capital realista (não 1M pra "segurança")
- [ ] Broker da demo é o mesmo que será usado em real
- [ ] Horário do servidor conferido
- [ ] Logger configurado para salvar em arquivo persistente
- [ ] Plano de monitoramento definido: quem olha, com que frequência, o que dispara intervenção
- [ ] Condição de parada definida por escrito: "se acontecer X, desligo o EA"
- [ ] Duração mínima da demo definida antes de cogitar live real — recomendado: 30 dias ou 100 trades, o que for maior

---

## Protocolo 6 — Antes de rodar em conta real

**Este é o protocolo mais crítico.** Violação dele foi o que quebrou o V5.

- [ ] Demo passou no Protocolo 5 por pelo menos a duração mínima estabelecida
- [ ] Log-diff entre backtest e demo validado — a divergência máxima por trade é aceitável e documentada
- [ ] Risk manager configurado com limites duros: daily loss, max positions, circuit breaker
- [ ] Capital inicial definido — começar pequeno, escalar depois. Regra sugerida: nunca começar com mais do que o dono estaria confortável em perder 100%.
- [ ] Plano de contingência escrito: "se EA cair, se broker cair, se internet cair — o que eu faço?"
- [ ] Backup do EA e configurações em local seguro
- [ ] Contato de suporte do broker à mão
- [ ] Notificação de emergência configurada (push, SMS, email) para eventos críticos
- [ ] Verificação final: o dono está fisicamente disponível nas primeiras horas de execução?

Se qualquer item está "não" — não vai pra real.

---

## Protocolo 7 — Quando um erro crítico acontece em live

Aplicável em qualquer situação onde comportamento inesperado em live pode afetar capital.

Em ordem, sem pular:

1. **Parar o EA.** Desabilitar AutoTrading no MT5 ou fechar o terminal se necessário.
2. **Fechar posições abertas manualmente** se o estado do EA é suspeito. Preferir perda controlada a exposição descontrolada.
3. **Não reiniciar o EA imediatamente.** A tentação é forte; resistir.
4. **Preservar logs.** Copiar arquivos de log antes que rotação ou reinício sobrescreva.
5. **Escrever um relato por escrito** do que aconteceu, antes de esquecer detalhes. Data, hora, símbolo, último trade, sintoma observado.
6. **Só então investigar.** Com o EA parado e logs preservados.
7. **Identificar causa-raiz** antes de qualquer fix. Se não sabe a causa, não pode saber se o fix resolve.
8. **Reproduzir o problema em backtest/demo** com a mesma causa-raiz.
9. **Consertar no código.** Gambiarras proibidas (ver `REGRAS.md`).
10. **Validar fix** em backtest, StressLab, demo — todos os protocolos novamente.
11. **Entrada no CHANGELOG** com descrição, causa-raiz, fix, lição aprendida.

A ordem importa. Pular etapas é o caminho para a segunda quebra de conta.

---

## Protocolo 8 — Atualização destes protocolos

Protocolos evoluem conforme o projeto amadurece. Mudanças aqui exigem:

- [ ] Razão da mudança descrita no commit
- [ ] Se a mudança remove um checklist item — justificativa explícita do porquê
- [ ] Se a mudança adiciona um checklist item — exemplo concreto do que motivou
- [ ] Commit: `docs(protocols): <descrição curta>`

Protocolos só ficam mais rigorosos com o tempo, não menos. Remoção de etapa é exceção, não regra.
