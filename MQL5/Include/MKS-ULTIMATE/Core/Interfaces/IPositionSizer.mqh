//+------------------------------------------------------------------+
//| @file           : IPositionSizer.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Contrato que calcula o volume (lots) de uma
//|                   ordem a partir da distância do stop-loss em
//|                   pontos. Polimórfico via ADR-004; usado pela
//|                   estratégia antes de montar MksOrderRequest, e
//|                   pelo CMksRiskManager para validar tamanho
//|                   máximo (ADR-019).
//| @depends_on     : MksError
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/IPositionSizer.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_IPOSITIONSIZER_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_IPOSITIONSIZER_MQH

#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Calcula lots a partir da distância de SL em pontos. Implementações
// concretas recebem ISymbol*/IAccount* no construtor — esta interface
// não os exige porque modos triviais (FixedLot) só precisam do símbolo
// para clamp em [VolumeMin, VolumeMax].
//
// Contrato de erro: ComputeLots retorna false e preenche err em:
//   - config inválida (MKS_ERR_TRADE_SIZER_INVALID_PARAM)
//   - input inválido em runtime (MKS_ERR_TRADE_SIZER_INVALID_INPUT)
//   - resultado fora de [VolumeMin, VolumeMax] (MKS_ERR_TRADE_SIZER_OUT_OF_RANGE)
//
// Política out-of-range: ADR-019. Errar em vez de clampar — clamp
// silencioso esconderia distorção do risk% efetivo.
class IPositionSizer
{
public:
   virtual ~IPositionSizer() {}

   // Calcula lots para uma ordem com SL a slDistancePoints do ponto
   // de entrada. Retorna true e preenche &lots em sucesso, false e
   // preenche &err em qualquer falha.
   virtual bool ComputeLots(double slDistancePoints,
                            double &lots,
                            MksError &err) = 0;

   // Verifica se a configuração passada no construtor é válida.
   // Estático — independe de estado de runtime, distinto de qualquer
   // verificação que ComputeLots faça.
   virtual bool Validate(MksError &err) const = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_IPOSITIONSIZER_MQH
