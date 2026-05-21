//+------------------------------------------------------------------+
//| @file           : Asserts.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Testing
//| @responsibility : Vocabulário de assertion uniforme do framework
//|                   de testes do core. Macros MKS_ASSERT_* com
//|                   tolerância default explícita (1e-9), captura de
//|                   __FILE__/__LINE__ no call site, mensagem única
//|                   no formato "<what>: expected=X actual=Y". Ver
//|                   ADR-005.
//| @depends_on     : Core/Testing/TestRunner.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Testing/Asserts.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TESTING_ASSERTS_MQH
#define MKS_ULTIMATE_CORE_TESTING_ASSERTS_MQH

#include "TestRunner.mqh"

//--- Tolerância default para comparações de double. Override per-call
//--- via MKS_ASSERT_NEAR_DOUBLE(expected, actual, tol, what).
#define MKS_ASSERT_DOUBLE_TOL 1e-9

//--- Predicados booleanos --------------------------------------------+
#define MKS_ASSERT_TRUE(cond, what) \
   do { \
      if((cond)) g_mksTestRunner.Pass(); \
      else g_mksTestRunner.Fail( \
         StringFormat("%s: expected=true", (what)), \
         __FILE__, __LINE__); \
   } while(false)

#define MKS_ASSERT_FALSE(cond, what) \
   do { \
      if(!(cond)) g_mksTestRunner.Pass(); \
      else g_mksTestRunner.Fail( \
         StringFormat("%s: expected=false", (what)), \
         __FILE__, __LINE__); \
   } while(false)

//--- Igualdade de inteiros assinados ---------------------------------+
#define MKS_ASSERT_EQ_INT(expected, actual, what) \
   do { \
      const int _mks_e = (int)(expected); \
      const int _mks_a = (int)(actual); \
      if(_mks_e == _mks_a) g_mksTestRunner.Pass(); \
      else g_mksTestRunner.Fail( \
         StringFormat("%s: expected=%d actual=%d", (what), _mks_e, _mks_a), \
         __FILE__, __LINE__); \
   } while(false)

//--- Igualdade de inteiros assinados 64-bit --------------------------+
#define MKS_ASSERT_EQ_LONG(expected, actual, what) \
   do { \
      const long _mks_e = (long)(expected); \
      const long _mks_a = (long)(actual); \
      if(_mks_e == _mks_a) g_mksTestRunner.Pass(); \
      else g_mksTestRunner.Fail( \
         StringFormat("%s: expected=%I64d actual=%I64d", (what), _mks_e, _mks_a), \
         __FILE__, __LINE__); \
   } while(false)

//--- Igualdade de inteiros não-assinados 64-bit ----------------------+
#define MKS_ASSERT_EQ_ULONG(expected, actual, what) \
   do { \
      const ulong _mks_e = (ulong)(expected); \
      const ulong _mks_a = (ulong)(actual); \
      if(_mks_e == _mks_a) g_mksTestRunner.Pass(); \
      else g_mksTestRunner.Fail( \
         StringFormat("%s: expected=%I64u actual=%I64u", (what), _mks_e, _mks_a), \
         __FILE__, __LINE__); \
   } while(false)

//--- Igualdade de strings (comparação exata, StringCompare) ----------+
#define MKS_ASSERT_EQ_STRING(expected, actual, what) \
   do { \
      const string _mks_e = (expected); \
      const string _mks_a = (actual); \
      if(StringCompare(_mks_e, _mks_a) == 0) g_mksTestRunner.Pass(); \
      else g_mksTestRunner.Fail( \
         StringFormat("%s: expected='%s' actual='%s'", (what), _mks_e, _mks_a), \
         __FILE__, __LINE__); \
   } while(false)

//--- Igualdade de double com tolerância default (MKS_ASSERT_DOUBLE_TOL)
#define MKS_ASSERT_EQ_DOUBLE(expected, actual, what) \
   do { \
      const double _mks_e = (double)(expected); \
      const double _mks_a = (double)(actual); \
      if(MathAbs(_mks_e - _mks_a) < MKS_ASSERT_DOUBLE_TOL) \
         g_mksTestRunner.Pass(); \
      else g_mksTestRunner.Fail( \
         StringFormat("%s: expected=%.12f actual=%.12f tol=%.0e", \
                      (what), _mks_e, _mks_a, MKS_ASSERT_DOUBLE_TOL), \
         __FILE__, __LINE__); \
   } while(false)

//--- Igualdade de double com tolerância explícita --------------------+
#define MKS_ASSERT_NEAR_DOUBLE(expected, actual, tol, what) \
   do { \
      const double _mks_e = (double)(expected); \
      const double _mks_a = (double)(actual); \
      const double _mks_t = (double)(tol); \
      if(MathAbs(_mks_e - _mks_a) < _mks_t) g_mksTestRunner.Pass(); \
      else g_mksTestRunner.Fail( \
         StringFormat("%s: expected=%.12f actual=%.12f tol=%.0e", \
                      (what), _mks_e, _mks_a, _mks_t), \
         __FILE__, __LINE__); \
   } while(false)

#endif // MKS_ULTIMATE_CORE_TESTING_ASSERTS_MQH
