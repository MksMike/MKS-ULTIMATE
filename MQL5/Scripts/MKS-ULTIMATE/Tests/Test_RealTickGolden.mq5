//+------------------------------------------------------------------+
//| @file           : Test_RealTickGolden.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : E2.2 — golden de bricks headless (Layer A). Le um
//|                   fixture .mkstick REAL via CMksFileTickSource, roda o
//|                   CMksRenkoBuilder REAL (o produtor unico) e compara os
//|                   bricks campo-a-campo (incl. triggerPrice, triggerTickId,
//|                   high, low, closeTimeMsc) contra um .mksbk golden
//|                   versionado. Falha o TestRunner em QUALQUER divergencia
//|                   — a paridade feed->brick vira rede de regressao
//|                   automatica, nao procedimento manual (verify-parity).
//|                   Wiring IDENTICO ao Replayer (mesmo sizer/geometria/L/K):
//|                   os bricks capturados sao os do produtor unico.
//|                   InpRegenGolden=true GERA o golden com o MESMO writer do
//|                   Producer/Replayer; default COMPARA (o teste).
//| @depends_on     : Core/Data/CMksFileTickSource.mqh,
//|                   Core/Data/CMksTickFileReader.mqh,
//|                   Core/Data/CMksBrickFileWriter.mqh,
//|                   Core/Data/CMksBrickFileReader.mqh,
//|                   Core/Data/CMksBrickWriterSink.mqh,
//|                   Core/RenkoBuilder/CMksRenkoBuilder.mqh,
//|                   Core/RenkoBuilder/CMksFixedBrickSizer.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksCapturingSink.mqh,
//|                   Core/Types/RenkoGeometry.mqh, Tick, Brick, Error
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_RealTickGolden.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksTickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickWriterSink.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksCapturingSink.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Config espelha o golden da decisao (tests/golden/e2-decision) e o
// Producer/Replayer: brick 3.0, L=10, K=20, geometria classic.
input string InpFixturePath      = "MKS-ULTIMATE\\golden\\XAUUSDm_CR_20260720T233245.mkstick";
input string InpGoldenPath       = "MKS-ULTIMATE\\golden\\XAUUSDm_CR_20260720T233245.golden.mksbk";
input double InpBrickSize        = 3.0;   // mesmo valor do Producer/decision-golden
input int    InpInvalidTickLimit = 10;    // L (ADR-006)
input int    InpThresholdLimit   = 20;    // K (ADR-011)
input bool   InpRegenGolden      = false; // true = GERA o golden e sai; false = COMPARA (teste)

// Resultado da corrida do builder sobre o fixture.
struct GoldenRunResult
{
   bool   ok;
   string broker;
   long   account;
   string symbol;
   int    digits;
   long   ticksConsumed;
   long   ticksInvalid;
   bool   streamCorrupt;
};

//+------------------------------------------------------------------+
//| Roda source(fixture) -> builder -> sink. Wiring IDENTICO ao       |
//| Replayer (mesmo sizer/geometria/L/K), garantindo que os bricks    |
//| capturados/escritos sejam os do produtor unico (CMksRenkoBuilder).|
//+------------------------------------------------------------------+
bool RunBuilderOverFixture(IRenkoSink *sink, GoldenRunResult &res)
{
   res.ok = false; res.ticksConsumed = 0; res.ticksInvalid = 0; res.streamCorrupt = false;
   MksError err;

   // 1. Proveniencia do fixture (mesmo padrao do Replayer).
   CMksTickFileReader prov;
   if(!prov.Open(InpFixturePath, err))
   {
      PrintFormat("FAIL: nao abriu fixture '%s': %s", InpFixturePath, err.ToString());
      return false;
   }
   res.broker  = prov.Broker();
   res.account = prov.AccountLogin();
   res.symbol  = prov.Symbol();
   res.digits  = prov.Digits();
   prov.Close();

   // 2. Source hermetica — le do .mkstick, NAO de CopyTicksRange.
   CMksFileTickSource src(InpFixturePath, res.broker, res.account, res.symbol);
   if(!src.Open(err))
   {
      PrintFormat("FAIL: source.Open '%s': %s", InpFixturePath, err.ToString());
      return false;
   }

   // 3. Sizer + geometria classic — identico ao Replayer (ADR-026).
   CMksFixedBrickSizer sizer(InpBrickSize);
   if(!sizer.Validate(err)) { PrintFormat("FAIL: sizer invalido: %s", err.ToString()); return false; }
   MksRenkoGeometry geom = MksGeometryClassic();
   if(!geom.Validate(err)) { PrintFormat("FAIL: geometria invalida: %s", err.ToString()); return false; }

   // 4. Builder real — o produtor unico. Sem forming (throughput).
   CMksRenkoBuilder builder(geom, GetPointer(sizer), sink,
                            InpInvalidTickLimit, InpThresholdLimit);
   builder.SetEmitForming(false);

   // 5. Ingesta todos os ticks. INVALID (103) / K102 / recovery (105) sao
   //    normais (descarta/recupera); so STREAM_CORRUPT (104) aborta.
   MksTick t;
   while(src.Next(t))
   {
      res.ticksConsumed++;
      if(!builder.IngestTick(t, err))
      {
         if(err.code == MKS_ERR_RENKO_INVALID_TICK)
            res.ticksInvalid++;
         else if(err.code == MKS_ERR_RENKO_TICK_STREAM_CORRUPT)
         {
            res.streamCorrupt = true;
            PrintFormat("WARN: stream corrupt no tick seq=%I64u", t.seq);
            break;
         }
         // K102/K105/outros: descarte/recovery esperados — segue.
      }
   }
   res.ok = true;
   return true;
}

//+------------------------------------------------------------------+
//| GENERATE: roda o builder e escreve o golden .mksbk via o MESMO     |
//| writer do Producer/Replayer (CMksBrickWriterSink -> writer).       |
//+------------------------------------------------------------------+
void GenerateGolden()
{
   Print("=== Test_RealTickGolden — MODO GENERATE ===");
   if(!FileIsExist(InpFixturePath))
   {
      PrintFormat("SETUP: fixture nao encontrado em Files\\%s — copie de "
                  "tests\\golden\\e2-decision\\ para <terminal>\\MQL5\\Files\\MKS-ULTIMATE\\golden\\",
                  InpFixturePath);
      return;
   }
   MksError err;

   // Proveniencia para o header (a mesma do fixture — como o Replayer).
   CMksTickFileReader prov;
   if(!prov.Open(InpFixturePath, err)) { PrintFormat("FAIL prov.Open: %s", err.ToString()); return; }
   string broker = prov.Broker(); long account = prov.AccountLogin();
   string symbol = prov.Symbol(); int digits = prov.Digits();
   prov.Close();

   MksRenkoGeometry geom = MksGeometryClassic();
   CMksBrickFileWriter writer;
   if(!writer.Open(InpGoldenPath, err)) { PrintFormat("FAIL writer.Open: %s", err.ToString()); return; }
   if(!writer.WriteHeader(broker, account, symbol, digits, geom, InpBrickSize, err))
   { PrintFormat("FAIL writer.WriteHeader: %s", err.ToString()); writer.Close(err); return; }

   CMksBrickWriterSink sink;
   sink.writer      = GetPointer(writer);
   sink.printBricks = false;
   sink.digits      = digits;

   GoldenRunResult res;
   if(!RunBuilderOverFixture(GetPointer(sink), res)) { writer.Close(err); return; }

   long n = writer.BrickCount();
   if(!writer.Close(err)) { PrintFormat("FAIL writer.Close: %s", err.ToString()); return; }

   PrintFormat("GOLDEN GERADO: Files\\%s", InpGoldenPath);
   PrintFormat("  bricks=%I64d ticks=%I64d invalidos=%I64d symbol=%s digits=%d brick=%.4f",
               n, res.ticksConsumed, res.ticksInvalid, res.symbol, res.digits, InpBrickSize);
   Print("  -> commite este .mksbk em tests\\golden\\e2-brick\\ e rode de novo (InpRegenGolden=false).");
}

//+------------------------------------------------------------------+
//| COMPARE (o teste): builder real sobre o fixture vs golden .mksbk,  |
//| campo a campo, EXATO (bit-exact — regressao pega qualquer mudanca).|
//+------------------------------------------------------------------+
void Test_RealTickGolden_BricksMatchGolden()
{
   MksError err;

   // 1. Roda o builder real, captura os bricks.
   CMksCapturingSink cap;
   GoldenRunResult res;
   MKS_ASSERT_TRUE(RunBuilderOverFixture(GetPointer(cap), res),
                   "builder rodou sobre o fixture");
   MKS_ASSERT_TRUE(!res.streamCorrupt, "fixture nao corrompeu o stream");
   MKS_ASSERT_TRUE(cap.count > 0, "builder produziu bricks");

   // 2. Abre o golden versionado.
   CMksBrickFileReader gold;
   bool opened = gold.Open(InpGoldenPath, err);
   MKS_ASSERT_TRUE(opened, "golden .mksbk abre");
   if(!opened) return;

   // 3. Header/proveniencia batem (ignora createdAt wall-clock — nao comparado).
   MKS_ASSERT_EQ_INT((int)cap.count, (int)gold.BrickCount(), "contagem de bricks bate");
   MKS_ASSERT_TRUE(gold.Symbol() == res.symbol, "symbol do golden bate com o fixture");
   MKS_ASSERT_EQ_INT(res.digits, gold.Digits(), "digits batem");
   MKS_ASSERT_NEAR_DOUBLE(InpBrickSize, gold.BrickSizePoints(), 1e-9, "brickSize bate");
   MksRenkoGeometry gg = gold.Geometry();
   MKS_ASSERT_TRUE(MathAbs(gg.po) < 1e-9 && MathAbs(gg.pro) < 1e-9
                   && MathAbs(gg.revSizeRatio - 1.0) < 1e-9,
                   "geometria do golden e classic (po=pro=0, rev=1)");

   // 4. Comparacao campo-a-campo EXATA. Doubles round-trippam bit-a-bit pelo
   //    mesmo (de)serializador e o builder e deterministico -> '==' e correto:
   //    qualquer regressao de valor e pega.
   int n = MathMin((int)cap.count, (int)gold.BrickCount());
   string diff = "";
   int firstDiff = -1;
   for(int i = 0; i < n; i++)
   {
      MksBrick g;
      if(!gold.ReadNext(g, err))
      {
         diff = StringFormat("golden.ReadNext falhou em i=%d: %s", i, err.ToString());
         firstDiff = i; break;
      }
      MksBrick b = cap.bricks[i];
      string fld = "";
      if(b.direction        != g.direction)        fld = "direction";
      else if(b.thresholdsCrossed != g.thresholdsCrossed) fld = "thresholdsCrossed(M)";
      else if(b.open         != g.open)            fld = "open";
      else if(b.close        != g.close)           fld = "close";
      else if(b.high         != g.high)            fld = "high";
      else if(b.low          != g.low)             fld = "low";
      else if(b.triggerPrice != g.triggerPrice)    fld = "triggerPrice";
      else if(b.triggerTickId!= g.triggerTickId)   fld = "triggerTickId";
      else if(b.closeTimeMsc != g.closeTimeMsc)    fld = "closeTimeMsc";
      else if(b.volume       != g.volume)          fld = "volume";
      if(fld != "")
      {
         diff = StringFormat("brick[%d] campo '%s' diverge (builder vs golden)", i, fld);
         firstDiff = i; break;
      }
   }
   gold.Close();
   MKS_ASSERT_TRUE(firstDiff < 0, (firstDiff < 0)
                   ? StringFormat("todos os %d bricks batem campo-a-campo com o golden", n)
                   : diff);
}

//+------------------------------------------------------------------+
void OnStart()
{
   if(InpRegenGolden) { GenerateGolden(); return; }

   Print("=== Test_RealTickGolden (E2.2) — MODO COMPARE ===");
   if(!FileIsExist(InpFixturePath))
   {
      Print("=== SETUP INCOMPLETO ===");
      PrintFormat("Fixture nao encontrado: Files\\%s", InpFixturePath);
      Print("Copie tests\\golden\\e2-decision\\*.mkstick para "
            "<terminal>\\MQL5\\Files\\MKS-ULTIMATE\\golden\\ (ver tests\\golden\\e2-brick\\README.md).");
      return;
   }
   if(!FileIsExist(InpGoldenPath))
   {
      Print("=== SETUP INCOMPLETO ===");
      PrintFormat("Golden nao encontrado: Files\\%s", InpGoldenPath);
      Print("Rode 1x com InpRegenGolden=true para gera-lo, commite em tests\\golden\\e2-brick\\, e rode de novo.");
      return;
   }

   MKS_RUN(Test_RealTickGolden_BricksMatchGolden);
   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
