//+------------------------------------------------------------------+
//| @file           : RenkoGeometry.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Types
//| @responsibility : Struct MksRenkoGeometry — o triplo (PO, PRO,
//|                   revSizeRatio) que define a geometria do brick,
//|                   e as funções de fábrica de preset. Ver ADR-010.
//| @depends_on     : Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TYPES_RENKOGEOMETRY_MQH
#define MKS_ULTIMATE_CORE_TYPES_RENKOGEOMETRY_MQH

#include <MKS-ULTIMATE/Core/Types/Error.mqh>

struct MksRenkoGeometry
{
   double po;            // abertura de continuação, fração [0, 1)
   double pro;           // abertura de reversão, fração [0, 1)
   double revSizeRatio;  // tamanho do brick de reversão / tamanho normal; > 0

   //--- Default: classic renko (PO=PRO=0, reversão do mesmo tamanho).
   //    Mudado de median (0.5/0.5) para classic (0/0) na ADR-026 — median
   //    abre espaço de preços fictício (brick.close ≠ preço real do trigger);
   //    classic preserva fidelidade entre brick.close e o threshold cruzado.
   //    Fábricas explícitas (MksGeometryMedian/Classic/Custom) continuam
   //    existindo no core para testes e leitura de .mksbk antigos.
   MksRenkoGeometry()
   {
      po = 0.0; pro = 0.0; revSizeRatio = 1.0;
   }

   //--- Valida o triplo. NÃO loga (ADR-009) — o chamador decide.
   bool Validate(MksError &err) const
   {
      if(po < 0.0 || po >= 1.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_INVALID_GEOMETRY,
                       "PO fora do intervalo [0, 1)",
                       StringFormat("po=%.4f", po));
         return false;
      }
      if(pro < 0.0 || pro >= 1.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_INVALID_GEOMETRY,
                       "PRO fora do intervalo [0, 1)",
                       StringFormat("pro=%.4f", pro));
         return false;
      }
      if(revSizeRatio <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_INVALID_GEOMETRY,
                       "revSizeRatio deve ser > 0",
                       StringFormat("revSizeRatio=%.4f", revSizeRatio));
         return false;
      }
      return true;
   }

   string ToString() const
   {
      return StringFormat("po=%.4f pro=%.4f revRatio=%.4f",
                          po, pro, revSizeRatio);
   }
};

//--- Fábricas de preset. O nome da função é o preset; não há enum de modo.

//--- Median renko: bricks centrados no close anterior, sobreposição de 50%.
MksRenkoGeometry MksGeometryMedian()
{
   MksRenkoGeometry g;
   g.po = 0.50; g.pro = 0.50; g.revSizeRatio = 1.0;
   return g;
}

//--- Renko clássico: brick abre no close anterior, sem sobreposição.
MksRenkoGeometry MksGeometryClassic()
{
   MksRenkoGeometry g;
   g.po = 0.0; g.pro = 0.0; g.revSizeRatio = 1.0;
   return g;
}

//--- Geometria custom: triplo do chamador. Validar antes de usar.
MksRenkoGeometry MksGeometryCustom(double po, double pro, double revSizeRatio)
{
   MksRenkoGeometry g;
   g.po = po; g.pro = pro; g.revSizeRatio = revSizeRatio;
   return g;
}

#endif // MKS_ULTIMATE_CORE_TYPES_RENKOGEOMETRY_MQH
