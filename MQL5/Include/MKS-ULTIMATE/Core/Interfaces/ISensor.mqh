//+------------------------------------------------------------------+
//| @file           : ISensor.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface ISensor — categoria arquitetural de
//|                   detectores de estado de mercado (ADR-025). Cada
//|                   implementação consulta o que precisa (bricks,
//|                   indicadores, sub-sensores) e expõe estado
//|                   semântico + níveis numéricos + confiança.
//|                   Sensores NÃO tomam decisões de trade — quem
//|                   decide é o EA consultando state + Risk + Trade.
//| @depends_on     : ENUM_MKS_SENSOR_STATE (Core/Types/SensorState.mqh),
//|                   MksError (Core/Types/Error.mqh)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/ISensor.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_ISENSOR_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_ISENSOR_MQH

#include <MKS-ULTIMATE/Core/Types/SensorState.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//--- Interface: sensor de estado de mercado (ADR-025 / ADR-004).
//
// Convenções da ADR-004: prefixo I, zero campos, destrutor virtual vazio,
// todos os métodos virtuais puros, const em métodos de leitura, override
// na implementação, argumentos por const& ou ponteiro.
//
// Ciclo de vida:
//   1. Concreto recebe dependências por injeção no construtor.
//   2. EA/consumidor chama Update(err) quando quiser reavaliar.
//   3. EA/consumidor lê State(), Level(), Confidence() para decidir.
//
// Update é falível (ADR-009): retorna false e preenche err em caso de
// problema irreparável (ex.: dados insuficientes, dependência morta).
// Sucesso significa "rodei minha análise"; o estado resultante (mesmo
// MKS_SENSOR_INACTIVE) é resposta válida.
class ISensor
{
public:
   virtual ~ISensor() {}

   //--- Estado atual do sensor (ADR-025 §2).
   virtual ENUM_MKS_SENSOR_STATE State() const = 0;

   //--- Quantos níveis o sensor expõe (ex.: Caixote = 2 — topo e fundo).
   virtual int LevelCount() const = 0;

   //--- Lê o nível idx (0 = primário; semântica documentada por sensor).
   //    Comportamento para idx fora de [0, LevelCount()) é responsabilidade
   //    do concreto (tipicamente: devolve 0.0 ou EMPTY_VALUE; nunca crasha).
   virtual double Level(int idx) const = 0;

   //--- Confiança em [0..1] do sinal atual. 0 = sem confiança (ou estado
   //    INACTIVE), 1 = todas as condições satisfeitas. Semântica fina é
   //    de cada sensor; a faixa é o invariante.
   virtual double Confidence() const = 0;

   //--- Timestamp da última chamada bem-sucedida a Update() (em msc).
   //    Permite consumidor detectar staleness sem manter próprio relógio.
   virtual long LastUpdateMsc() const = 0;

   //--- Reavalia o sensor. Retorna true em sucesso, false + err se
   //    falha irreparável. Mesmo INACTIVE é resposta válida (não é erro).
   virtual bool Update(MksError &err) = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_ISENSOR_MQH
