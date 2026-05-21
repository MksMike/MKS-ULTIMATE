//+------------------------------------------------------------------+
//| @file           : Test_MksTestFramework.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Smoke test do framework Core/Testing. Valida que
//|                   (a) cada macro MKS_ASSERT_* incrementa
//|                   PassedAssertions em 1 quando a condição passa;
//|                   (b) MKS_RUN(funcName) propaga o nome da função
//|                   via stringification (#) do pré-processador;
//|                   (c) os contadores agregados (assertions e
//|                   tests, passed e failed) batem com o esperado.
//|                   Não usa as macros para validar a si mesmo —
//|                   bootstrap honesto via raw if/PrintFormat.
//| @depends_on     : Core/Testing/Asserts.mqh,
//|                   Core/Testing/TestRunner.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_MksTestFramework.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>

//+------------------------------------------------------------------+
//| Contador local de checks de meta-validação (não usa o runner)     |
//+------------------------------------------------------------------+
int g_metaPass = 0;
int g_metaFail = 0;

void MetaCheck(bool cond, const string what)
{
   if(cond) { g_metaPass++; PrintFormat("PASS: %s", what); }
   else     { g_metaFail++; PrintFormat("FAIL: %s", what); }
}

//+------------------------------------------------------------------+
//| Captura do nome do teste durante execução (Phase 2)               |
//+------------------------------------------------------------------+
string g_capturedTestName = "";

void TestSmokeStringification()
{
   g_capturedTestName = g_mksTestRunner.CurrentTest();
}

//+------------------------------------------------------------------+
//| Teste totalmente passante — alimenta contador de tests passed     |
//+------------------------------------------------------------------+
void TestSmokeAllPass()
{
   MKS_ASSERT_TRUE(true,  "true literal");
   MKS_ASSERT_FALSE(false, "false literal");
}

void OnStart()
{
   Print("=== Smoke test: Core/Testing framework ===");

   //--- Phase 1: cada macro incrementa PassedAssertions em 1 ---------+
   int passBefore = g_mksTestRunner.PassedAssertions();

   g_mksTestRunner.Begin("smoke_phase1_macros");
   MKS_ASSERT_TRUE(true,                       "true");
   MKS_ASSERT_FALSE(false,                     "false");
   MKS_ASSERT_EQ_INT(42, 42,                   "int");
   MKS_ASSERT_EQ_LONG((long)123456789012345,
                      (long)123456789012345,   "long");
   MKS_ASSERT_EQ_ULONG((ulong)1, (ulong)1,     "ulong");
   MKS_ASSERT_EQ_STRING("abc", "abc",          "string");
   MKS_ASSERT_EQ_DOUBLE(1.0, 1.0 + 1e-12,      "double default tol");
   MKS_ASSERT_NEAR_DOUBLE(1.0, 1.4, 0.5,       "double near tol");
   g_mksTestRunner.End();

   int passAfter = g_mksTestRunner.PassedAssertions();
   const int expected = 8;
   MetaCheck(passAfter - passBefore == expected,
             StringFormat("8 macros incrementaram PassedAssertions (delta=%d, esperado=%d)",
                          passAfter - passBefore, expected));

   //--- Phase 2: stringification de #funcName via MKS_RUN ------------+
   g_capturedTestName = "<not_set>";
   MKS_RUN(TestSmokeStringification);
   MetaCheck(g_capturedTestName == "TestSmokeStringification",
             StringFormat("MKS_RUN propagou nome via stringification (capturado='%s')",
                          g_capturedTestName));

   //--- Phase 3: PassedTests incrementa após MKS_RUN totalmente passante
   int testsBefore = g_mksTestRunner.PassedTests();
   MKS_RUN(TestSmokeAllPass);
   int testsAfter = g_mksTestRunner.PassedTests();
   MetaCheck(testsAfter - testsBefore == 1,
             StringFormat("PassedTests incrementou em 1 após teste passante (delta=%d)",
                          testsAfter - testsBefore));

   //--- Phase 4: CurrentTest é vazio após End() ----------------------+
   MetaCheck(g_mksTestRunner.CurrentTest() == "",
             StringFormat("CurrentTest vazio após End (corrente='%s')",
                          g_mksTestRunner.CurrentTest()));

   //--- Phase 5: chamada manual a Fail() incrementa FailedAssertions -+
   //--- Não usa macro de assertion — invoca a API direta pra deixar
   //--- a expectativa de "FAIL" abaixo visível no journal de propósito.
   Print("--- a próxima linha 'FAIL' no journal é esperada (Phase 5) ---");
   int failBefore = g_mksTestRunner.FailedAssertions();
   g_mksTestRunner.Begin("smoke_phase5_fail_path");
   g_mksTestRunner.Fail("synthetic failure", __FILE__, __LINE__);
   g_mksTestRunner.End();
   int failAfter = g_mksTestRunner.FailedAssertions();
   MetaCheck(failAfter - failBefore == 1,
             StringFormat("Fail() incrementou FailedAssertions em 1 (delta=%d)",
                          failAfter - failBefore));

   //--- Phase 6: FailedTests incrementa quando um teste tem ≥1 falha -+
   //--- (continuando o estado da Phase 5 — o teste já fechou com falha
   //--- e deve ter sido contabilizado como teste falhado)
   //--- Comparação: total de tests = passed + failed deve ser ao menos 2
   const int totalTests = g_mksTestRunner.PassedTests()
                        + g_mksTestRunner.FailedTests();
   MetaCheck(g_mksTestRunner.FailedTests() >= 1,
             StringFormat("FailedTests >= 1 após teste com Fail (failed=%d, total=%d)",
                          g_mksTestRunner.FailedTests(), totalTests));

   //--- Resumo do smoke test (não é o Summary do runner — separados) -+
   Print("");
   PrintFormat("=== Smoke test meta: %d/%d checks ok ===",
               g_metaPass, g_metaPass + g_metaFail);

   //--- Exibe o Summary padrão do runner para inspeção visual --------+
   g_mksTestRunner.Summary();

   if(g_metaFail > 0)
      Alert(StringFormat("Smoke test do framework: %d META-FALHAS", g_metaFail));
}
//+------------------------------------------------------------------+
