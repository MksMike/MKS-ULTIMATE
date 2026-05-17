//+------------------------------------------------------------------+
//| @file           : IBrickSizer.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Contrato que fornece o tamanho-base do brick
//|                   Renko em pontos, ao CMksRenkoBuilder.
//| @depends_on     : MksError
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/IBrickSizer.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_IBRICKSIZER_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_IBRICKSIZER_MQH

#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Fornece o tamanho-base do brick ao CMksRenkoBuilder. A origem do
// tamanho — constante fixa ou cálculo por ATR — é trocável no
// composition root sem o builder saber qual implementação usa (ADR-010).
// O tamanho de reversão (revSizeRatio) pertence a MksRenkoGeometry,
// não ao sizer.
// Não há método de alimentação de dados aqui: a forma desse feed depende
// da cadência de recálculo do ATR (adiada para o CAtrBrickSizer) e poderá
// vir por composição via IRenkoSink, não como método novo desta interface.
class IBrickSizer
{
public:
   virtual ~IBrickSizer() {}

   // Tamanho-base do brick, em pontos. Snapshot: um sizer variável
   // pode devolver valores diferentes a cada brick. Só é válido
   // quando IsReady() == true.
   virtual double SizePoints() const = 0;

   // true quando SizePoints() devolve um valor utilizável. Um sizer
   // de tamanho fixo é sempre pronto; um sizer derivado de dados
   // devolve false enquanto não acumulou histórico (warm-up).
   virtual bool IsReady() const = 0;

   // Verifica se os parâmetros de configuração do sizer são válidos.
   // Estático — independe de estado de runtime, distinto de IsReady().
   virtual bool Validate(MksError &err) const = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_IBRICKSIZER_MQH
