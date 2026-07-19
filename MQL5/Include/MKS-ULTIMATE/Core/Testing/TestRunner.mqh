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
   int    m_emptyTests;         // testes que rodaram SEM nenhuma assertion (M20)
   int    m_testFailedAtStart;  // baseline de falhas para detectar falha do teste
   int    m_assertionsAtStart;  // baseline de assertions para detectar teste vazio
   string m_currentTest;
   bool   m_inTest;

public:
   CMksTestRunner()
   {
      m_passedAssertions  = 0;
      m_failedAssertions  = 0;
      m_passedTests       = 0;
      m_failedTests       = 0;
      m_emptyTests        = 0;
      m_testFailedAtStart = 0;
      m_assertionsAtStart = 0;
      m_currentTest       = "";
      m_inTest            = false;
   }

   //--- Início do escopo de um teste. Captura baselines para saber se
   //--- alguma assertion entre Begin e End falhou E se alguma rodou.
   void Begin(const string testName)
   {
      m_currentTest       = testName;
      m_testFailedAtStart = m_failedAssertions;
      m_assertionsAtStart = m_passedAssertions + m_failedAssertions;
      m_inTest            = true;
   }

   void End()
   {
      if(m_inTest)
      {
         int assertionsInTest = (m_passedAssertions + m_failedAssertions)
                                - m_assertionsAtStart;
         if(assertionsInTest == 0)
         {
            // Teste sem NENHUMA assertion: cobertura fantasma (refactor que
            // apagou asserts, early-return, MKS_RUN de função vazia). NÃO
            // conta como passado — "suíte verde sem cobertura" é a classe
            // que o projeto teme (M20, auditoria 2026-07-19).
            m_emptyTests++;
            PrintFormat("EMPTY [%s] teste sem nenhuma assertion (cobertura fantasma)",
                        m_currentTest);
         }
         else if(m_failedAssertions > m_testFailedAtStart) m_failedTests++;
         else                                              m_passedTests++;
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
      if(m_emptyTests > 0)
         PrintFormat("=== %d/%d assertions in %d tests (%d failed, %d EMPTY) ===",
                     m_passedAssertions, totalAssertions,
                     totalTests, m_failedTests, m_emptyTests);
      else
         PrintFormat("=== %d/%d assertions in %d tests (%d failed) ===",
                     m_passedAssertions, totalAssertions,
                     totalTests, m_failedTests);
      // Alerta em QUALQUER condição de falha — incl. suíte vazia (nenhum
      // teste rodou) e testes sem assertion (M20). Antes só alertava em
      // failedAssertions>0, deixando suíte vazia/fantasma passar calada.
      if(totalTests == 0 && m_emptyTests == 0)
         Alert("MKS Tests: NENHUM teste rodou (suíte vazia)");
      else if(m_failedAssertions > 0 || m_failedTests > 0)
         Alert(StringFormat("MKS Tests: %d assertion(s), %d test(s) FAILED",
                            m_failedAssertions, m_failedTests));
      else if(m_emptyTests > 0)
         Alert(StringFormat("MKS Tests: %d teste(s) SEM ASSERTION (cobertura fantasma)",
                            m_emptyTests));
   }

   int    PassedAssertions() const { return m_passedAssertions; }
   int    FailedAssertions() const { return m_failedAssertions; }
   int    PassedTests()      const { return m_passedTests; }
   int    FailedTests()      const { return m_failedTests; }
   int    EmptyTests()       const { return m_emptyTests; }
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
