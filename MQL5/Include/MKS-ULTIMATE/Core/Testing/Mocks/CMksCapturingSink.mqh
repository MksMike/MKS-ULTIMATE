//+------------------------------------------------------------------+
//| @file           : CMksCapturingSink.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Testing / Mocks
//| @responsibility : Mock de IRenkoSink — captura bricks fechados
//|                   (OnBrickClose) e snapshots de brick em formação
//|                   (OnBrickForming, ADR-021) em arrays públicos
//|                   para inspeção campo-a-campo nos testes. Ver
//|                   ADR-005.
//| @depends_on     : Core/Interfaces/IRenkoSink.mqh,
//|                   Core/Types/Brick.mqh,
//|                   Core/Types/FormingBrick.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Testing/Mocks/CMksCapturingSink.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TESTING_MOCKS_CAPTURINGSINK_MQH
#define MKS_ULTIMATE_CORE_TESTING_MOCKS_CAPTURINGSINK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/FormingBrick.mqh>

class CMksCapturingSink : public IRenkoSink
{
public:
   MksBrick        bricks[];
   int             count;
   MksFormingBrick formings[];
   int             formingCount;

   CMksCapturingSink()
   {
      count = 0;
      formingCount = 0;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      ArrayResize(bricks, count + 1);
      bricks[count] = brick;
      count++;
   }

   void OnBrickForming(const MksFormingBrick &fb) override
   {
      ArrayResize(formings, formingCount + 1);
      formings[formingCount] = fb;
      formingCount++;
   }

   //--- Limpa o estado interno; reuso de instância entre testes.
   void Reset()
   {
      ArrayResize(bricks, 0);
      count = 0;
      ArrayResize(formings, 0);
      formingCount = 0;
   }
};

#endif // MKS_ULTIMATE_CORE_TESTING_MOCKS_CAPTURINGSINK_MQH
