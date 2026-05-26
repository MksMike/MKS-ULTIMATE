//+------------------------------------------------------------------+
//| @file           : IBrickSizer.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Contrato que fornece o tamanho-base do brick
//|                   Renko em pontos, ao CMksRenkoBuilder. Recebe
//|                   notificação do builder a cada brick emitido,
//|                   permitindo cálculo dinâmico (ATR — ADR-018).
//| @depends_on     : MksError, MksBrick
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/IBrickSizer.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_IBRICKSIZER_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_IBRICKSIZER_MQH

#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>

// Fornece o tamanho-base do brick ao CMksRenkoBuilder. A origem do
// tamanho — constante fixa ou cálculo por ATR — é trocável no
// composition root sem o builder saber qual implementação usa (ADR-010).
// O tamanho de reversão (revSizeRatio) pertence a MksRenkoGeometry,
// não ao sizer.
// OnBrick recebe cada brick fechado emitido pelo builder, permitindo
// sizers dinâmicos (ATR sobre bricks fechados — ADR-018). Sizers
// constantes implementam como no-op.
class IBrickSizer
{
public:
   virtual ~IBrickSizer() {}

   // Tamanho-base do brick, em UNIDADES DE PREÇO do símbolo (USD
   // para XAUUSD, EUR para EURUSD, BTC para BTCUSD, etc — NÃO é o
   // ponto do símbolo via Symbol::Point()). O nome "SizePoints" é
   // histórico; o builder soma o valor retornado diretamente no
   // preço (CMksRenkoBuilder.ContinuationThreshold/ReversalThreshold:
   //   threshold = base ± (1-PO) * SizePoints()
   // onde 'base' está em unidades de preço). Sem conversão
   // multiplicativa por Point().
   // Snapshot: um sizer variável pode devolver valores diferentes a
   // cada brick. Só é válido quando IsReady() == true.
   virtual double SizePoints() const = 0;

   // true quando SizePoints() devolve um valor utilizável. Um sizer
   // de tamanho fixo é sempre pronto; um sizer derivado de dados
   // devolve true desde o início se usar fallback (ex.: defaultSizePoints
   // no CMksAtrBrickSizer) — caso contrário causaria deadlock com o
   // builder que não emite enquanto !IsReady() (ADR-018 §4).
   virtual bool IsReady() const = 0;

   // Verifica se os parâmetros de configuração do sizer são válidos.
   // Estático — independe de estado de runtime, distinto de IsReady().
   virtual bool Validate(MksError &err) const = 0;

   // Chamado pelo CMksRenkoBuilder após cada EmitBrick. Permite ao
   // sizer atualizar estado interno (janela rolante, etc.) e
   // recalcular SizePoints (ADR-018 §2). Sizers constantes
   // implementam como no-op.
   virtual void OnBrick(const MksBrick &brick) = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_IBRICKSIZER_MQH
