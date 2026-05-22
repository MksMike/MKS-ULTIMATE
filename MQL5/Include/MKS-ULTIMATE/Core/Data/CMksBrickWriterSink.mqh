//+------------------------------------------------------------------+
//| @file           : CMksBrickWriterSink.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Data
//| @responsibility : Sink que encaminha cada brick fechado para um
//|                   CMksBrickFileWriter (.mksbk) e contabiliza
//|                   sucessos e falhas de I/O. Opcionalmente imprime
//|                   cada brick no journal para debug.
//| @depends_on     : Core/Interfaces/IRenkoSink.mqh,
//|                   Core/Data/CMksBrickFileWriter.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Data/CMksBrickWriterSink.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_DATA_CMKSBRICKWRITERSINK_MQH
#define MKS_ULTIMATE_CORE_DATA_CMKSBRICKWRITERSINK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

class CMksBrickWriterSink : public IRenkoSink
{
public:
   CMksBrickFileWriter *writer;
   int  bricksWritten;
   int  writeFailures;
   bool printBricks;
   int  digits;

   CMksBrickWriterSink()
   {
      writer        = NULL;
      bricksWritten = 0;
      writeFailures = 0;
      printBricks   = false;
      digits        = 2;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      if(writer == NULL) return;
      MksError err;
      if(!writer.WriteBrick(brick, err))
      {
         writeFailures++;
         PrintFormat("WRITE FAIL: %s", err.ToString());
         return;
      }
      bricksWritten++;
      if(printBricks)
      {
         PrintFormat("BRICK %s open=%s close=%s M=%d trigger=%s time=%s",
                     brick.IsBull() ? "BULL" : "BEAR",
                     DoubleToString(brick.open, digits),
                     DoubleToString(brick.close, digits),
                     brick.thresholdsCrossed,
                     DoubleToString(brick.triggerPrice, digits),
                     TimeToString((datetime)(brick.closeTimeMsc / 1000),
                                  TIME_DATE|TIME_SECONDS));
      }
   }
};

#endif // MKS_ULTIMATE_CORE_DATA_CMKSBRICKWRITERSINK_MQH
