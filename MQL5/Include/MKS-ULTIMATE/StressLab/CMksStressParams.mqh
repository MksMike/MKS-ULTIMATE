//+------------------------------------------------------------------+
//| @file           : CMksStressParams.mqh
//| @project        : MKS-ULTIMATE
//| @module         : StressLab
//| @responsibility : Parametros de configuracao do CMksStressLabBroker
//|                   + 5 presets de nivel de stress (None, Light, Medium,
//|                   High, Nightmare) para pipeline progressivo da
//|                   ADR-019 / Fase 7 do ROADMAP.
//| @depends_on     : Nenhuma (tipos nativos)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/StressLab/CMksStressParams.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_STRESSLAB_CMKSSTRESSPARAMS_MQH
#define MKS_ULTIMATE_STRESSLAB_CMKSSTRESSPARAMS_MQH

// Distribuicao do slippage:
//   FIXED : sempre exatamente `mean` pontos de slip
//   NORMAL: Gaussiana com (mean, stdev)
enum ENUM_MKS_STRESS_DIST
{
   MKS_STRESS_DIST_FIXED  = 0,
   MKS_STRESS_DIST_NORMAL = 1
};

// Configuracao completa de um nivel de stress.
//
// Filosofia: cada parametro tem default "sem stress" (1.0 para multiplicadores,
// 0.0 para probabilidades, 0.0 para slippage). Construir um CMksStressParams
// e nao tocar em nada equivale a "broker simulado sem stress" — o wrapper
// se comporta como passthrough.
//
// SPREAD MULTIPLIER:
//   spreadMultiplier = 1.0 = spread do broker subjacente intacto.
//   = 2.0 = spread dobrado. Usado para simular abertura de mercado, news,
//     volatilidade elevada.
//
// SLIPPAGE:
//   slippageMean    : pontos medios de slippage no fill (positivo = contra
//                     o lado da ordem; ex.: BUY paga mais caro, SELL recebe
//                     menos).
//   slippageStdev   : desvio padrao em pontos. So usado em NORMAL.
//   slippageDist    : FIXED ou NORMAL.
//
// REJEICAO:
//   rejectionProb   : probabilidade [0..1] de o broker recusar a ordem
//                     antes mesmo de tentar executar. Retorna REJECTED com
//                     status proprio do StressLab.
//
// REQUOTE:
//   requoteProb     : probabilidade [0..1] de o broker exigir reapresentar
//                     a ordem com novo preco. Modelado como N tentativas
//                     internas — apos atingir maxRequotes, vira REJECTED.
//   maxRequotes     : tetos de tentativas em sequencia.
//
// LATENCIA:
//   latencyMeanMs   : latencia media (informativa, nao bloqueia em backtest).
//                     Gravada no log/metricas para auditoria de impacto.
//   latencyStdevMs  : desvio padrao em ms.
//
// SEED:
//   rngSeed : semente do CMksRandom interno. Mude para explorar
//             cenarios diferentes do mesmo nivel; mantenha para reproduzir.
struct CMksStressParams
{
   // Spread
   double spreadMultiplier;

   // Slippage
   double               slippageMean;
   double               slippageStdev;
   ENUM_MKS_STRESS_DIST slippageDist;

   // Rejeicao
   double rejectionProb;

   // Requote
   double requoteProb;
   int    maxRequotes;

   // Latencia (informativa em v1)
   double latencyMeanMs;
   double latencyStdevMs;

   // RNG
   uint   rngSeed;

   CMksStressParams()
   {
      spreadMultiplier = 1.0;
      slippageMean     = 0.0;
      slippageStdev    = 0.0;
      slippageDist     = MKS_STRESS_DIST_FIXED;
      rejectionProb    = 0.0;
      requoteProb      = 0.0;
      maxRequotes      = 3;
      latencyMeanMs    = 0.0;
      latencyStdevMs   = 0.0;
      rngSeed          = 42;
   }
};

//==================================================================
// Presets
//==================================================================
//
// Os presets cobrem 5 cenarios em escalonamento progressivo. A ideia
// nao e calibracao perfeita — e fornecer pontos discretos para a
// estrategia ser testada em CADA UM deles e ter resultados comparados.
// Estrategia que so funciona em "None" e fragil. Estrategia que
// sobrevive ate "High" e candidata a live. "Nightmare" e teste de
// destruicao — proxy de "broker quebra ou black swan".

// Sem stress: passthrough puro do underlying.
CMksStressParams MksStressNone()
{
   CMksStressParams p;
   // defaults ja sao "sem stress".
   return p;
}

// Broker bom em condicao normal de mercado.
CMksStressParams MksStressLight()
{
   CMksStressParams p;
   p.spreadMultiplier = 1.2;
   p.slippageMean     = 0.5;
   p.slippageStdev    = 0.5;
   p.slippageDist     = MKS_STRESS_DIST_NORMAL;
   p.rejectionProb    = 0.005; // 0.5%
   p.requoteProb      = 0.01;  // 1%
   p.latencyMeanMs    = 50.0;
   p.latencyStdevMs   = 20.0;
   return p;
}

// Broker mediano / condicoes normais a moderadas.
CMksStressParams MksStressMedium()
{
   CMksStressParams p;
   p.spreadMultiplier = 1.8;
   p.slippageMean     = 1.5;
   p.slippageStdev    = 1.5;
   p.slippageDist     = MKS_STRESS_DIST_NORMAL;
   p.rejectionProb    = 0.02;  // 2%
   p.requoteProb      = 0.05;  // 5%
   p.latencyMeanMs    = 120.0;
   p.latencyStdevMs   = 60.0;
   return p;
}

// Broker ruim / abertura volatil / news.
CMksStressParams MksStressHigh()
{
   CMksStressParams p;
   p.spreadMultiplier = 3.0;
   p.slippageMean     = 4.0;
   p.slippageStdev    = 3.0;
   p.slippageDist     = MKS_STRESS_DIST_NORMAL;
   p.rejectionProb    = 0.08;  // 8%
   p.requoteProb      = 0.15;  // 15%
   p.latencyMeanMs    = 300.0;
   p.latencyStdevMs   = 150.0;
   return p;
}

// Pesadelo: teste de destruicao. Se a estrategia sobrevive aqui com
// equity positiva, e provavelmente robusta.
CMksStressParams MksStressNightmare()
{
   CMksStressParams p;
   p.spreadMultiplier = 10.0;
   p.slippageMean     = 15.0;
   p.slippageStdev    = 10.0;
   p.slippageDist     = MKS_STRESS_DIST_NORMAL;
   p.rejectionProb    = 0.25;  // 25%
   p.requoteProb      = 0.40;  // 40%
   p.latencyMeanMs    = 1000.0;
   p.latencyStdevMs   = 500.0;
   return p;
}

#endif // MKS_ULTIMATE_STRESSLAB_CMKSSTRESSPARAMS_MQH
