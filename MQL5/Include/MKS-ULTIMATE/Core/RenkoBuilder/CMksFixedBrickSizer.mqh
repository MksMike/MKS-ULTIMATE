//+------------------------------------------------------------------+
//| @file           : CMksFixedBrickSizer.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / RenkoBuilder
//| @responsibility : Implementação de IBrickSizer com tamanho de brick
//|                   fixo em pontos, constante durante toda a sessão.
//| @depends_on     : Core/Interfaces/IBrickSizer.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSFIXEDBRICKSIZER_MQH
#define MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSFIXEDBRICKSIZER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Sizer de tamanho fixo: devolve sempre o mesmo tamanho de brick, em
// pontos, definido na construção. Sempre pronto — não tem warm-up.
// Implementa IBrickSizer (ADR-010, eixo de tamanho).
class CMksFixedBrickSizer : public IBrickSizer
{
private:
   double m_sizePoints;

public:
   CMksFixedBrickSizer(double sizePoints)
   {
      m_sizePoints = sizePoints;
   }

   double SizePoints() const override { return m_sizePoints; }

   bool IsReady() const override { return true; }

   bool Validate(MksError &err) const override
   {
      if(m_sizePoints <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_INVALID_BRICK_SIZE,
                       "tamanho de brick deve ser > 0",
                       StringFormat("sizePoints=%.4f", m_sizePoints));
         return false;
      }
      return true;
   }
};

#endif // MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSFIXEDBRICKSIZER_MQH
