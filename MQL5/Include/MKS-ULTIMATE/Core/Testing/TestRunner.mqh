//+------------------------------------------------------------------+
//| @file           : TestRunner.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Testing
//| @responsibility : Runner singleton para suítes de teste do core.
//|                   Carrega o estado agregado (assertions e tests
//|                   passados/falhados), o nome do teste corrente e a
//|                   macro MKS_RUN(funcName) que liga o nome do teste
//|                   ao nome da função via stringification. Ver
//|                   ADR-005.
//| @depends_on     : Nenhuma (autocontido)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Testing/TestRunner.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TESTING_TESTRUNNER_MQH
#define MKS_ULTIMATE_CORE_TESTING_TESTRUNNER_MQH

class CMksTestRunner
{
private:
   int    m_passedAssertions;
   int    m_failedAssertions;
   int    m_passedTests;
   int    m_failedTests;
   int    m_testFailedAtStart; // baseline para detectar falha do teste corrente
   string m_currentTest;
   bool   m_inTest;

public:
   CMksTestRunner()
   {
      m_passedAssertions  = 0;
      m_failedAssertions  = 0;
      m_passedTests       = 0;
      m_failedTests       = 0;
      m_testFailedAtStart = 0;
      m_currentTest       = "";
      m_inTest            = false;
   }

   //--- Início do escopo de um teste. Captura baseline para saber se
   //--- alguma assertion entre Begin e End falhou.
   void Begin(const string testName)
   {
      m_currentTest       = testName;
      m_testFailedAtStart = m_failedAssertions;
      m_inTest            = true;
   }

   void End()
   {
      if(m_inTest)
      {
         if(m_failedAssertions > m_testFailedAtStart) m_failedTests++;
         else                                         m_passedTests++;
      }
      m_inTest      = false;
      m_currentTest = "";
   }

   void Pass() { m_passedAssertions++; }

   //--- Reporta falha de assertion: contabiliza e imprime no journal.
   //--- Mensagem composta — Asserts.mqh monta o "expected/actual" e
   //--- chama esta API com a string pronta.
   void Fail(const string &message, const string &file, int line)
   {
      m_failedAssertions++;
      PrintFormat("FAIL [%s] %s | %s:%d",
                  m_currentTest, message, file, line);
   }

   //--- Saída final padronizada (ADR-005 §6).
   void Summary()
   {
      const int totalAssertions = m_passedAssertions + m_failedAssertions;
      const int totalTests      = m_passedTests + m_failedTests;
      Print("");
      PrintFormat("=== %d/%d assertions in %d tests (%d failed) ===",
                  m_passedAssertions, totalAssertions,
                  totalTests, m_failedTests);
      if(m_failedAssertions > 0)
         Alert(StringFormat("MKS Tests: %d FAILED", m_failedAssertions));
   }

   int    PassedAssertions() const { return m_passedAssertions; }
   int    FailedAssertions() const { return m_failedAssertions; }
   int    PassedTests()      const { return m_passedTests; }
   int    FailedTests()      const { return m_failedTests; }
   string CurrentTest()      const { return m_currentTest; }
};

//--- Singleton global. Cada script de teste consome este símbolo.
CMksTestRunner g_mksTestRunner;

//--- Macro de execução. Liga o nome do teste ao nome da função via
//--- stringification (#funcName), eliminando a string livre que o
//--- padrão inline atual usa em g_currentTest.
#define MKS_RUN(funcName) \
   do { \
      g_mksTestRunner.Begin(#funcName); \
      funcName(); \
      g_mksTestRunner.End(); \
   } while(false)

#endif // MKS_ULTIMATE_CORE_TESTING_TESTRUNNER_MQH
