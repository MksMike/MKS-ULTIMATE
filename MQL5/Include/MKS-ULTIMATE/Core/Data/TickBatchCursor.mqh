//+------------------------------------------------------------------+
//| @file           : TickBatchCursor.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Data
//| @responsibility : Cursor de consumo incremental de CopyTicks com
//|                   dedup por CONTAGEM na fronteira de time_msc.
//|                   Preserva ticks legítimos do mesmo milissegundo:
//|                   o dedup antigo ("timeMsc <= último visto")
//|                   decimava o feed em bursts e violava a captura
//|                   crua da ADR-012 §1 (achado H5, auditoria
//|                   2026-07-19). Usado por Producer, ColorReversal
//|                   e TickRecorder — o MESMO critério nos três, por
//|                   construção (anti-eixo-2).
//| @depends_on     : (nenhum)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Data/TickBatchCursor.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_DATA_TICKBATCHCURSOR_MQH
#define MKS_ULTIMATE_CORE_DATA_TICKBATCHCURSOR_MQH

//+------------------------------------------------------------------+
//| MksTickBatchCursor                                                |
//|                                                                   |
//| Contrato de uso (por batch de CopyTicks):                         |
//|   1. CopyTicks(symbol, ticks, COPY_TICKS_ALL, FromMsc(), 0)       |
//|   2. BeginBatch()  — uma vez, antes do loop                       |
//|   3. Admit(ticks[i].time_msc) por tick, NA ORDEM do batch:        |
//|        true  = tick novo (processar). Conta como visto MESMO que  |
//|                o caller o descarte depois (ex.: lixo estrutural   |
//|                bid<=0&&ask<=0) — assim a repetição na fronteira   |
//|                do próximo batch é pulada corretamente.            |
//|        false = repetição da fronteira (já visto em batch          |
//|                anterior) ou tick atrasado (msc < fronteira).      |
//|                                                                   |
//| Por quê contagem, e não timestamp: CopyTicks(from) retorna TODOS  |
//| os ticks com time_msc >= from — inclusive os já processados no    |
//| ms da fronteira. Pular por "msc <= último" descarta também os     |
//| ticks NOVOS do mesmo ms (4 ticks no ms de uma notícia viram 1 —   |
//| e o brick fecha em outro tick, com outro triggerPrice). Pular     |
//| por contagem descarta exatamente os já vistos, nada além.         |
//+------------------------------------------------------------------+
struct MksTickBatchCursor
{
   long lastMsc;       // time_msc da fronteira (último ms visto)
   int  seenAtLastMsc; // quantos ticks desse ms já foram admitidos
                       // (INT_MAX = ms inteiro consumido — âncora)
   int  pendingSkip;   // repetições da fronteira a pular no batch atual

   MksTickBatchCursor() { ResetEmpty(); }

   // Estado virgem: primeiro batch processa tudo que o CopyTicks der.
   void ResetEmpty()
   {
      lastMsc       = 0;
      seenAtLastMsc = 0;
      pendingSkip   = 0;
   }

   // Âncora "começa do agora" (SymbolInfoTick no fim do OnInit): o ms
   // inteiro da âncora é considerado consumido. Limitação deliberada,
   // idêntica ao comportamento pré-H5, restrita ao instante único de
   // startup: ticks que ainda cheguem nesse exato ms são pulados —
   // preferível a reprocessar ticks anteriores do mesmo ms que o
   // builder nunca deve ver (fill histórico já os cobriu, ou o
   // operador pediu "só a partir de agora").
   void ResetAfter(const long anchorMsc)
   {
      lastMsc       = anchorMsc;
      seenAtLastMsc = INT_MAX;
      pendingSkip   = 0;
   }

   // Valor para o parâmetro `from` do CopyTicks.
   long FromMsc() const { return lastMsc; }

   // Chamar uma vez por batch, antes de iterar.
   void BeginBatch() { pendingSkip = seenAtLastMsc; }

   // Decide o tick corrente do batch. Ver contrato no header.
   bool Admit(const long tickMsc)
   {
      if(tickMsc < lastMsc) return false;   // atrasado: nunca reprocessa
      if(tickMsc == lastMsc)
      {
         if(pendingSkip > 0) { pendingSkip--; return false; } // já visto
         if(seenAtLastMsc < INT_MAX) seenAtLastMsc++;
         return true;                        // tick NOVO no mesmo ms
      }
      lastMsc       = tickMsc;               // avançou de ms
      seenAtLastMsc = 1;
      pendingSkip   = 0;
      return true;
   }
};

#endif // MKS_ULTIMATE_CORE_DATA_TICKBATCHCURSOR_MQH
