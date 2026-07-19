//+------------------------------------------------------------------+
//| @file           : Test_MksTickBatchCursor.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do MksTickBatchCursor — dedup por
//|                   contagem na fronteira de time_msc (fix do
//|                   achado H5, auditoria 2026-07-19). Cobre a
//|                   regressão central (burst same-ms preservado),
//|                   overlap de fronteira entre batches, âncora,
//|                   tick atrasado e determinismo.
//| @depends_on     : Core/Data/TickBatchCursor.mqh,
//|                   Core/Testing/Asserts.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_MksTickBatchCursor.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Data/TickBatchCursor.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>

//==================================================================
// Helper: roda um batch inteiro pelo cursor, devolve quantos ticks
// foram admitidos e o veredito individual em admitted[].
//==================================================================
int RunBatch(MksTickBatchCursor &c, const long &mscs[], bool &admitted[])
{
   int n = ArraySize(mscs);
   ArrayResize(admitted, n);
   int count = 0;
   c.BeginBatch();
   for(int i = 0; i < n; i++)
   {
      admitted[i] = c.Admit(mscs[i]);
      if(admitted[i]) count++;
   }
   return count;
}

//==================================================================
// Regressão H5: burst same-ms é preservado
//==================================================================

void Test_Cursor_DistinctMs_AllAdmitted()
{
   MksTickBatchCursor c;
   long b[3] = {1000, 1001, 1002};
   bool adm[];
   MKS_ASSERT_EQ_INT(3, RunBatch(c, b, adm), "3 ms distintos -> 3 admitidos");
   MKS_ASSERT_EQ_LONG(1002, c.FromMsc(), "fronteira avancou para o ultimo ms");
}

void Test_Cursor_SameMsBurst_AllAdmitted()
{
   // O caso do H5: 4 ticks no mesmo ms (burst de noticia). O dedup
   // antigo (msc <= ultimo visto) admitia SO o primeiro — o brick
   // fechava em outro tick, com outro triggerPrice.
   MksTickBatchCursor c;
   long b[4] = {5000, 5000, 5000, 5000};
   bool adm[];
   MKS_ASSERT_EQ_INT(4, RunBatch(c, b, adm), "burst same-ms: 4 de 4 admitidos");
}

void Test_Cursor_MixedBatch_AllNewAdmitted()
{
   MksTickBatchCursor c;
   long b[5] = {1000, 1000, 1001, 1001, 1001};
   bool adm[];
   MKS_ASSERT_EQ_INT(5, RunBatch(c, b, adm), "batch misto novo: 5 de 5 admitidos");
}

//==================================================================
// Overlap de fronteira entre batches (o que o dedup existe p/ tratar)
//==================================================================

void Test_Cursor_BoundaryOverlap_NoReprocess()
{
   MksTickBatchCursor c;

   // Batch 1: fronteira termina em 2000 com 2 ticks vistos nesse ms.
   long b1[3] = {1000, 2000, 2000};
   bool adm1[];
   MKS_ASSERT_EQ_INT(3, RunBatch(c, b1, adm1), "batch1: 3 admitidos");

   // Batch 2 (CopyTicks from=2000 devolve os 2 ja vistos + 1 NOVO no
   // mesmo ms + 1 ms novo): pula exatamente os 2 repetidos.
   long b2[4] = {2000, 2000, 2000, 3000};
   bool adm2[];
   MKS_ASSERT_EQ_INT(2, RunBatch(c, b2, adm2), "batch2: so os 2 novos admitidos");
   MKS_ASSERT_FALSE(adm2[0], "repeticao 1 da fronteira pulada");
   MKS_ASSERT_FALSE(adm2[1], "repeticao 2 da fronteira pulada");
   MKS_ASSERT_TRUE(adm2[2], "tick NOVO no mesmo ms admitido");
   MKS_ASSERT_TRUE(adm2[3], "ms novo admitido");
}

void Test_Cursor_ExactRefetch_NothingAdmitted()
{
   MksTickBatchCursor c;
   long b1[3] = {1000, 1000, 1000};
   bool adm1[];
   RunBatch(c, b1, adm1);

   // Refetch identico (nenhum tick novo chegou): tudo pulado.
   bool adm2[];
   MKS_ASSERT_EQ_INT(0, RunBatch(c, b1, adm2), "refetch identico: 0 admitidos");
}

void Test_Cursor_GarbageStillCounted()
{
   // Contrato: Admit()==true conta como visto MESMO que o caller
   // descarte o tick depois (lixo bid<=0). A repeticao da fronteira
   // no proximo batch e pulada do mesmo jeito.
   MksTickBatchCursor c;
   long b1[2] = {1000, 1000};
   bool adm1[];
   MKS_ASSERT_EQ_INT(2, RunBatch(c, b1, adm1), "2 admitidos (1 seria lixo p/ caller)");

   long b2[3] = {1000, 1000, 1000};
   bool adm2[];
   int count2 = RunBatch(c, b2, adm2);
   MKS_ASSERT_EQ_INT(1, count2, "so o 3o (novo) admitido — lixo nao volta");
   MKS_ASSERT_TRUE(adm2[2], "o novo do mesmo ms e o admitido");
}

//==================================================================
// Ancora e ticks atrasados
//==================================================================

void Test_Cursor_AnchorMs_FullyConsumed()
{
   // ResetAfter: o ms inteiro da ancora e considerado consumido
   // (semantica pre-H5 preservada no instante unico de startup).
   MksTickBatchCursor c;
   c.ResetAfter(5000);
   MKS_ASSERT_EQ_LONG(5000, c.FromMsc(), "FromMsc = ancora");

   long b[3] = {5000, 5000, 5001};
   bool adm[];
   MKS_ASSERT_EQ_INT(1, RunBatch(c, b, adm), "so o pos-ancora admitido");
   MKS_ASSERT_FALSE(adm[0], "tick no ms da ancora pulado");
   MKS_ASSERT_FALSE(adm[1], "tick no ms da ancora pulado (2)");
   MKS_ASSERT_TRUE(adm[2], "primeiro ms depois da ancora admitido");
}

void Test_Cursor_LateTick_Rejected()
{
   MksTickBatchCursor c;
   long b1[1] = {2000};
   bool adm1[];
   RunBatch(c, b1, adm1);

   long b2[2] = {1500, 2500};
   bool adm2[];
   MKS_ASSERT_EQ_INT(1, RunBatch(c, b2, adm2), "atrasado rejeitado, novo admitido");
   MKS_ASSERT_FALSE(adm2[0], "msc < fronteira nunca reprocessa");
   MKS_ASSERT_TRUE(adm2[1], "ms novo admitido");
}

void Test_Cursor_EmptyStart_FromMscZero()
{
   MksTickBatchCursor c;
   MKS_ASSERT_EQ_LONG(0, c.FromMsc(), "estado virgem: from=0");
   long b[2] = {100, 100};
   bool adm[];
   MKS_ASSERT_EQ_INT(2, RunBatch(c, b, adm), "estado virgem processa tudo");
}

//==================================================================
// Determinismo (mesmo stream -> mesmas decisoes)
//==================================================================

void Test_Cursor_Determinism_TwoCursorsSameStream()
{
   MksTickBatchCursor a, b;
   a.ResetAfter(1000);
   b.ResetAfter(1000);

   long s1[4] = {1000, 1001, 1001, 1002};
   long s2[5] = {1002, 1002, 1002, 1003, 1003};

   bool admA[], admB[];
   int ca1 = RunBatch(a, s1, admA);
   int cb1 = RunBatch(b, s1, admB);
   MKS_ASSERT_EQ_INT(ca1, cb1, "batch1: mesmas contagens");
   for(int i = 0; i < ArraySize(admA); i++)
      MKS_ASSERT_TRUE(admA[i] == admB[i], StringFormat("batch1[%d] identico", i));

   int ca2 = RunBatch(a, s2, admA);
   int cb2 = RunBatch(b, s2, admB);
   MKS_ASSERT_EQ_INT(ca2, cb2, "batch2: mesmas contagens");
   for(int i = 0; i < ArraySize(admA); i++)
      MKS_ASSERT_TRUE(admA[i] == admB[i], StringFormat("batch2[%d] identico", i));
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_MksTickBatchCursor ===");

   MKS_RUN(Test_Cursor_DistinctMs_AllAdmitted);
   MKS_RUN(Test_Cursor_SameMsBurst_AllAdmitted);
   MKS_RUN(Test_Cursor_MixedBatch_AllNewAdmitted);

   MKS_RUN(Test_Cursor_BoundaryOverlap_NoReprocess);
   MKS_RUN(Test_Cursor_ExactRefetch_NothingAdmitted);
   MKS_RUN(Test_Cursor_GarbageStillCounted);

   MKS_RUN(Test_Cursor_AnchorMs_FullyConsumed);
   MKS_RUN(Test_Cursor_LateTick_Rejected);
   MKS_RUN(Test_Cursor_EmptyStart_FromMscZero);

   MKS_RUN(Test_Cursor_Determinism_TwoCursorsSameStream);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
