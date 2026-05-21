//+------------------------------------------------------------------+
//| @file           : Test_CMksAtrBrickSizer.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksAtrBrickSizer — Validate, warm-up,
//|                   transição, fórmula TR + Wilder, clamp, determinismo.
//| @depends_on     : Core/RenkoBuilder/CMksAtrBrickSizer.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksAtrBrickSizer.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksAtrBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//+------------------------------------------------------------------+
//| Estado global e helpers de assertion                              |
//+------------------------------------------------------------------+
int    g_passed = 0;
int    g_failed = 0;
string g_currentTest = "";

void StartTest(const string name)
{
   g_currentTest = name;
}

void AssertEqualInt(int expected, int actual, const string what)
{
   if(expected == actual) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=%d actual=%d", g_currentTest, what, expected, actual);
}

void AssertEqualDouble(double expected, double actual, const string what)
{
   if(MathAbs(expected - actual) < 1e-9) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=%.9f actual=%.9f",
               g_currentTest, what, expected, actual);
}

void AssertNearDouble(double expected, double actual, double tol,
                      const string what)
{
   if(MathAbs(expected - actual) < tol) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=%.9f actual=%.9f tol=%.9f",
               g_currentTest, what, expected, actual, tol);
}

void AssertTrue(bool cond, const string what)
{
   if(cond) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=true", g_currentTest, what);
}

void AssertFalse(bool cond, const string what)
{
   if(!cond) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=false", g_currentTest, what);
}

//+------------------------------------------------------------------+
//| Helper: monta um MksBrick a partir de OHLC                        |
//+------------------------------------------------------------------+
MksBrick MakeBrick(double open, double high, double low, double close)
{
   MksBrick b;
   b.open  = open;
   b.high  = high;
   b.low   = low;
   b.close = close;
   b.direction = (close >= open) ? MKS_BRICK_BULL : MKS_BRICK_BEAR;
   b.thresholdsCrossed = 1;
   b.triggerPrice  = close;
   b.triggerTickId = 0;
   b.closeTimeMsc  = 0;
   b.volume = 0;
   return b;
}

//+------------------------------------------------------------------+
//| Test 1: Validate rejeita parâmetros inválidos                     |
//+------------------------------------------------------------------+
void Test_ValidateRejectsBadParams()
{
   StartTest("validate_rejects_bad");

   MksError err;

   CMksAtrBrickSizer s1(0, 0.5, 3.0);
   AssertFalse(s1.Validate(err), "period=0");
   AssertEqualInt((int)MKS_ERR_RENKO_INVALID_BRICK_SIZE, (int)err.code, "err.code(period)");

   CMksAtrBrickSizer s2(14, 0.0, 3.0);
   AssertFalse(s2.Validate(err), "multiplier=0");

   CMksAtrBrickSizer s3(14, -1.0, 3.0);
   AssertFalse(s3.Validate(err), "multiplier<0");

   CMksAtrBrickSizer s4(14, 0.5, 0.0);
   AssertFalse(s4.Validate(err), "defaultSize=0");

   CMksAtrBrickSizer s5(14, 0.5, 3.0, -1.0);
   AssertFalse(s5.Validate(err), "minSize<0");

   CMksAtrBrickSizer s6(14, 0.5, 3.0, 10.0, 5.0);
   AssertFalse(s6.Validate(err), "min>max");
}

//+------------------------------------------------------------------+
//| Test 2: Validate aceita parâmetros válidos                        |
//+------------------------------------------------------------------+
void Test_ValidateAcceptsGoodParams()
{
   StartTest("validate_accepts_good");

   MksError err;
   CMksAtrBrickSizer s;          // defaults
   AssertTrue(s.Validate(err), "defaults validate");

   CMksAtrBrickSizer s2(20, 0.7, 5.0, 1.0, 100.0);
   AssertTrue(s2.Validate(err), "explicit args validate");
}

//+------------------------------------------------------------------+
//| Test 3: IsReady sempre true (não deadlock com o builder)          |
//+------------------------------------------------------------------+
void Test_IsReadyAlwaysTrue()
{
   StartTest("is_ready_always_true");

   CMksAtrBrickSizer s(5, 0.5, 3.0);
   AssertTrue(s.IsReady(), "ready before any brick");

   // Durante warm-up
   MksBrick b = MakeBrick(100.0, 100.5, 99.5, 100.3);
   s.OnBrick(b);
   AssertTrue(s.IsReady(), "ready after 1 brick");
   AssertFalse(s.IsWarmedUp(), "not warmed up after 1");

   // Após warm-up
   for(int i = 0; i < 4; i++) s.OnBrick(b);
   AssertTrue(s.IsReady(), "ready after 5 bricks");
   AssertTrue(s.IsWarmedUp(), "warmed up after period");
}

//+------------------------------------------------------------------+
//| Test 4: SizePoints retorna defaultSize durante warm-up             |
//+------------------------------------------------------------------+
void Test_WarmupReturnsDefault()
{
   StartTest("warmup_returns_default");

   const int    N       = 5;
   const double DEFAULT = 3.0;
   CMksAtrBrickSizer s(N, 0.5, DEFAULT);

   AssertEqualDouble(DEFAULT, s.SizePoints(), "before any brick");

   MksBrick b = MakeBrick(100.0, 101.0, 99.0, 100.5);
   for(int i = 1; i < N; i++) // N-1 bricks
   {
      s.OnBrick(b);
      AssertEqualDouble(DEFAULT, s.SizePoints(),
                        StringFormat("after %d bricks (warmup)", i));
   }
}

//+------------------------------------------------------------------+
//| Test 5: Transição no N-ésimo brick — SizePoints muda para ATR     |
//+------------------------------------------------------------------+
void Test_TransitionAtNthBrick()
{
   StartTest("transition_at_nth_brick");

   const int    N       = 5;
   const double DEFAULT = 3.0;
   const double MULT    = 0.5;
   CMksAtrBrickSizer s(N, MULT, DEFAULT);

   // 5 bricks com TR=2.0 cada (sem prev_close no primeiro, depois same OHLC).
   // TR para todos os bricks idênticos = 2.0.
   MksBrick b = MakeBrick(100.0, 101.0, 99.0, 100.5);
   for(int i = 1; i < N; i++) s.OnBrick(b);

   // Antes do N-ésimo, ainda default.
   AssertEqualDouble(DEFAULT, s.SizePoints(), "before nth brick");

   // N-ésimo brick — ativa transição.
   s.OnBrick(b);
   AssertTrue(s.IsWarmedUp(), "warmed up after N");
   AssertNearDouble(2.0, s.Atr(), 1e-9, "atr is SMA of TRs");
   AssertNearDouble(2.0 * MULT, s.SizePoints(), 1e-9, "size = atr * mult");
}

//+------------------------------------------------------------------+
//| Test 6: TR fórmula — first brick = high - low                     |
//+------------------------------------------------------------------+
void Test_TrFormulaFirstBrick()
{
   StartTest("tr_formula_first_brick");

   const int N = 1;
   CMksAtrBrickSizer s(N, 1.0, 3.0); // multiplier=1 para ler ATR direto

   MksBrick b = MakeBrick(100.0, 102.0, 99.0, 101.0);
   s.OnBrick(b);

   // Após 1 brick (N=1), warm-up termina. ATR = TR_1 = high - low = 3.0
   AssertNearDouble(3.0, s.Atr(), 1e-9, "tr first brick = high-low");
   AssertNearDouble(3.0, s.SizePoints(), 1e-9, "size = atr (mult=1)");
}

//+------------------------------------------------------------------+
//| Test 7: TR fórmula — brick com gap (TR = |high - prev_close|)     |
//+------------------------------------------------------------------+
void Test_TrFormulaWithGap()
{
   StartTest("tr_formula_with_gap");

   const int N = 2;
   CMksAtrBrickSizer s(N, 1.0, 3.0);

   // Brick 1: prev_close = 100.0
   MksBrick b1 = MakeBrick(99.0, 100.5, 98.5, 100.0);
   s.OnBrick(b1);
   // TR_1 = high - low = 100.5 - 98.5 = 2.0 (sem prev_close)

   // Brick 2: gap up — high=105, low=104, prev_close=100
   // r1 = 105 - 104 = 1
   // r2 = |105 - 100| = 5
   // r3 = |104 - 100| = 4
   // TR_2 = max = 5.0
   MksBrick b2 = MakeBrick(104.5, 105.0, 104.0, 104.8);
   s.OnBrick(b2);

   // ATR após N=2 = (2.0 + 5.0) / 2 = 3.5
   AssertNearDouble(3.5, s.Atr(), 1e-9, "atr SMA of TRs with gap");
}

//+------------------------------------------------------------------+
//| Test 8: Wilder smoothing pós-warm-up                              |
//+------------------------------------------------------------------+
void Test_WilderSmoothingPostWarmup()
{
   StartTest("wilder_smoothing");

   const int N = 3;
   CMksAtrBrickSizer s(N, 1.0, 3.0);

   // 3 bricks idênticos com TR=2 cada → ATR inicial = 2.0
   MksBrick b = MakeBrick(100.0, 101.0, 99.0, 100.5);
   for(int i = 0; i < N; i++) s.OnBrick(b);
   AssertNearDouble(2.0, s.Atr(), 1e-9, "atr initial SMA");

   // Brick novo com TR = ? primeiro calcular:
   // open=100.5 (prev close), high=103, low=100.5, close=102.5
   // r1 = high - low = 2.5
   // r2 = |103 - 100.5| = 2.5
   // r3 = |100.5 - 100.5| = 0
   // TR_4 = 2.5
   // Wilder: ATR_4 = (2.0 * 2 + 2.5) / 3 = 6.5 / 3 ≈ 2.16667
   MksBrick b2 = MakeBrick(100.5, 103.0, 100.5, 102.5);
   s.OnBrick(b2);
   AssertNearDouble(6.5 / 3.0, s.Atr(), 1e-9, "wilder atr after 4th");
}

//+------------------------------------------------------------------+
//| Test 9: Clamp em maxSize                                          |
//+------------------------------------------------------------------+
void Test_ClampMax()
{
   StartTest("clamp_max");

   const int N = 1;
   CMksAtrBrickSizer s(N, 1.0, 3.0, 0.0, 5.0);

   // Brick com range 10.0 → ATR=10 → size sem clamp = 10*1 = 10
   // Com clamp max=5, size deve ser 5.
   MksBrick b = MakeBrick(100.0, 110.0, 100.0, 105.0);
   s.OnBrick(b);

   AssertNearDouble(10.0, s.Atr(), 1e-9, "atr is 10");
   AssertNearDouble(5.0, s.SizePoints(), 1e-9, "size clamped to max");
}

//+------------------------------------------------------------------+
//| Test 10: Clamp em minSize                                         |
//+------------------------------------------------------------------+
void Test_ClampMin()
{
   StartTest("clamp_min");

   const int N = 1;
   CMksAtrBrickSizer s(N, 1.0, 3.0, 2.0, 100.0);

   // Brick com range 1.0 → ATR=1 → size sem clamp = 1*1 = 1
   // Com clamp min=2, size deve ser 2.
   MksBrick b = MakeBrick(100.0, 100.5, 99.5, 100.0);
   s.OnBrick(b);

   AssertNearDouble(1.0, s.Atr(), 1e-9, "atr is 1");
   AssertNearDouble(2.0, s.SizePoints(), 1e-9, "size clamped to min");
}

//+------------------------------------------------------------------+
//| Test 11: Determinismo — dois sizers idênticos → mesmas saídas     |
//+------------------------------------------------------------------+
void Test_Determinism()
{
   StartTest("determinism");

   const int N = 5;
   CMksAtrBrickSizer s1(N, 0.5, 3.0);
   CMksAtrBrickSizer s2(N, 0.5, 3.0);

   // Sequência variada de 20 bricks.
   double opens[]  = {100, 100.5, 101, 100.7, 100.3, 100.8, 101.5, 102, 101.6, 101.2,
                      101.7, 102.3, 102.0, 101.5, 101.8, 102.5, 103.0, 102.8, 102.3, 102.7};
   double highs[]  = {100.8, 101.2, 101.4, 100.9, 100.6, 101.6, 102.1, 102.3, 101.9, 101.5,
                      102.4, 102.6, 102.2, 101.9, 102.6, 103.1, 103.2, 102.9, 102.6, 103.0};
   double lows[]   = {99.7,  100.2, 100.6, 100.2, 100.0, 100.4, 101.1, 101.5, 101.0, 100.8,
                      101.0, 101.8, 101.5, 101.3, 101.5, 102.1, 102.6, 102.2, 102.0, 102.4};
   double closes[] = {100.5, 101.0, 100.7, 100.3, 100.5, 101.4, 102.0, 101.7, 101.2, 101.4,
                      102.3, 102.0, 101.5, 101.7, 102.4, 103.0, 102.7, 102.4, 102.5, 102.8};

   int n = ArraySize(opens);
   for(int i = 0; i < n; i++)
   {
      MksBrick b = MakeBrick(opens[i], highs[i], lows[i], closes[i]);
      s1.OnBrick(b);
      s2.OnBrick(b);
      AssertEqualDouble(s1.SizePoints(), s2.SizePoints(),
                        StringFormat("size match at brick %d", i + 1));
      AssertEqualDouble(s1.Atr(), s2.Atr(),
                        StringFormat("atr match at brick %d", i + 1));
   }
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksAtrBrickSizer ===");

   Test_ValidateRejectsBadParams();
   Test_ValidateAcceptsGoodParams();
   Test_IsReadyAlwaysTrue();
   Test_WarmupReturnsDefault();
   Test_TransitionAtNthBrick();
   Test_TrFormulaFirstBrick();
   Test_TrFormulaWithGap();
   Test_WilderSmoothingPostWarmup();
   Test_ClampMax();
   Test_ClampMin();
   Test_Determinism();

   PrintFormat("RESUMO: passed=%d  failed=%d", g_passed, g_failed);
   if(g_failed == 0)
      Print("=== TODOS OS TESTES PASSARAM ===");
   else
      PrintFormat("=== %d TESTES FALHARAM ===", g_failed);
}
//+------------------------------------------------------------------+
