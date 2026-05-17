import time
import random
import sys
import os
import subprocess

# =====================================================================
# SISTEMA DE AUTO-INJEÇÃO DE DEPENDÊNCIAS
# =====================================================================
try:
    from colorama import Fore, Back, Style, init
except ImportError:
    print("[SYS] Dependência 'colorama' não detectada no ambiente atual.")
    print("[SYS] Iniciando injeção automatizada de pacotes via pip...")
    try:
        # Executa o pip usando exatamente o mesmo interpretador que rodou o script
        subprocess.check_call([sys.executable, "-m", "pip", "install", "colorama"])
        print("[SUCCESS] Biblioteca injetada com sucesso. Inicializando subsistemas...")
        time.sleep(1.5)
        from colorama import Fore, Back, Style, init
    except Exception as e:
        print(f"[CRITICAL ERROR] Falha na auto-instalação: {e}")
        print("[WARN] Rodando em modo de compatibilidade sem cores secundárias.")
        sys.exit(1)

# Inicializa o colorama para resetar as cores automaticamente a cada print
init(autoreset=True)

# =====================================================================
# BANCO DE DADOS DE SIMULAÇÃO (ESTRUTURAS E STRINGS)
# =====================================================================
DIR_STRUCTURE = [
    "📂 MKS_ULTIMATE_FRAMEWORK/",
    " ├── 📂 config/",
    " │   ├── settings.json",
    " │   └── secret_keys.enc",
    " ├── 📂 core_kernel/",
    " │   ├── __init__.py",
    " │   ├── mt5_bridge.dll",
    " │   ├── memory_allocator.cpp",
    " │   └── matrix_calc.pyd",
    " ├── 📂 indicators_ai/",
    " │   ├── neural_network.ex5",
    " │   ├── quantum_rsi.mqh",
    " │   └── bollinger_gradient.py",
    " ├── 📂 order_manager/",
    " │   ├── execution_hook.py",
    " │   └── slippage_control.cpp",
    " └── 📂 logs_backtest/",
    "     └── tick_history_2026.bin"
]

MODULE_DIAGRAM = f"""
{Fore.BLUE}┌─────────────────────────────────────────────────────────┐
│              QUANTUM TRADING SYSTEM FLOW                │
└─────────────────────────────────────────────────────────┘
        {Fore.CYAN}[ MT5 TERMINAL ] {Fore.WHITE}──(Low Latency API)──> {Fore.GREEN}[ KERNEL BRIDGE ]
                                                    │
                                                    ▼
{Fore.YELLOW}[ NEURAL AI RECON ] <──(Tensor Flow Matrix)── {Fore.GREEN}[ RISK MANAGER ]
        │                                           │
        ▼                                           ▼
{Fore.MAGENTA}[ PATTERN RECOGNITION ]                     {Fore.RED}[ ORDER INJECTOR ]{Fore.RESET}
"""

MESSAGES = [
    "[INFO] Sincronizando clock do servidor com a Bolsa de Valores (B3/NYSE)...",
    "[SUCCESS] Canal de comunicação IPC (Inter-Process Communication) estabelecido.",
    "[WARN] Anomalia de spread detectada no par XAUUSD. Recalibrando ordens...",
    "[DECRYPT] Abrindo túnel criptografado SSH-256 com o Broker...",
    "[SECURITY] Firewall ativado. Varredura de antilatência concluída. Ping: 0.23ms",
    "[ALGO] Otimizando pesos neurais usando algoritmo genético adaptativo...",
    "[SYS] Desalocando buffers antigos de memória RAM do MetaTrader 5...",
    "[INJECT] Injetando ordens fantasmas (HFT Spoofing Detection active)..."
]

# =====================================================================
# FUNÇÕES VISUAIS AUXILIARES
# =====================================================================
def typing_effect(text, speed=0.01):
    for char in text:
        sys.stdout.write(char)
        sys.stdout.flush()
        time.sleep(speed)
    print()

def draw_progress_bar(label, total_steps=30):
    sys.stdout.write(Fore.WHITE + f"{label} [")
    for _ in range(total_steps):
        time.sleep(random.uniform(0.02, 0.07))
        sys.stdout.write(Fore.GREEN + "█")
        sys.stdout.flush()
    print(Fore.GREEN + f"] 100% - {Fore.CYAN}SUCCESS")

def show_indicators_table():
    print(Fore.YELLOW + "\n┌──────────────────────────────┬────────────────────────┐")
    print(Fore.YELLOW + "│      METRIC INDICATOR        │         VALUE          │")
    print(Fore.YELLOW + "├──────────────────────────────┼────────────────────────┤")
    print(Fore.YELLOW + f"│ Sharpe Ratio                 │ {Fore.GREEN}{random.uniform(2.1, 3.8):.2f}                   {Fore.YELLOW}│")
    print(Fore.YELLOW + f"│ Max Drawdown                 │ {Fore.RED}-{random.uniform(1.2, 4.5):.2f}%                 {Fore.YELLOW}│")
    print(Fore.YELLOW + f"│ Win/Loss Ratio               │ {Fore.GREEN}{random.uniform(68.2, 82.5):.1f}%                  {Fore.YELLOW}│")
    print(Fore.YELLOW + f"│ HFT Latency                  │ {Fore.CYAN}{random.uniform(120, 450):.2f} ms               {Fore.YELLOW}│")
    print(Fore.YELLOW + f"│ Thread Pool Allocation       │ {Fore.WHITE}{random.randint(16, 64)} Cores / Active        {Fore.YELLOW}│")
    print(Fore.YELLOW + "└──────────────────────────────┴────────────────────────┘\n")

# =====================================================================
# LOOP PRINCIPAL DA TELA DE HACKER
# =====================================================================
def run_ultimate_hacker():
    # Limpa o terminal antes de começar o show
    os.system('cls' if os.name == 'nt' else 'clear')
    
    print(Fore.GREEN + Style.BRIGHT + "=====================================================================")
    print(Fore.GREEN + Style.BRIGHT + "          CORE FRAMEWORK INITIALIZATION - MKS ULTIMATE v4.0          ")
    print(Fore.GREEN + Style.BRIGHT + "=====================================================================")
    time.sleep(1.5)

    while True:
        # Alterna dinamicamente entre os modos visuais para prender a atenção
        mode = random.choice(["tree", "diagram", "table", "logs", "progress"])
        
        if mode == "tree":
            print(Fore.CYAN + "\n[SYS] Escaneando integridade da árvore de diretórios do Framework...")
            time.sleep(0.5)
            for line in DIR_STRUCTURE:
                print(Fore.WHITE + line)
                time.sleep(0.08)
            print(Fore.GREEN + "[OK] Todos os módulos carregados e assinados em ambiente isolado.\n")
            
        elif mode == "diagram":
            print(MODULE_DIAGRAM)
            time.sleep(2.5)
            
        elif mode == "table":
            print(Fore.MAGENTA + "[EVAL] Computando métricas quantitativas de performance das estratégias...")
            time.sleep(0.8)
            show_indicators_table()
            time.sleep(2.0)
            
        elif mode == "progress":
            print()
            draw_progress_bar("[MEM] Alocando matriz de Ticks históricos ")
            draw_progress_bar("[AI] Treinando rede neural LSTM G-3       ")
            draw_progress_bar("[NET] Tunelando conexões com a API MT5    ")
            print()
            
        elif mode == "logs":
            # Chuva frenética de logs textuais e blocos de memória Hexadecimal
            for _ in range(random.randint(8, 15)):
                if random.random() > 0.4:
                    msg = random.choice(MESSAGES)
                    color = Fore.CYAN if "[INFO]" in msg else (Fore.GREEN if "[SUCCESS]" in msg else Fore.YELLOW)
                    typing_effect(color + msg, speed=0.003)
                else:
                    hex_data = " ".join([f"{random.randint(0, 255):02X}" for _ in range(12)])
                    print(Fore.GREEN + f"MEM_DUMP [0x{random.randint(1000, 9999)}FFF] -> {hex_data} | ACTIVE_THREAD")
                    time.sleep(0.04)
                    
        # Pequena pausa orgânica entre transições de blocos
        time.sleep(random.uniform(1.2, 2.8))

# =====================================================================
# GATILHO DE EXECUÇÃO
# =====================================================================
if __name__ == "__main__":
    try:
        run_ultimate_hacker()
    except KeyboardInterrupt:
        print(Fore.RED + Style.BRIGHT + "\n\n[CRITICAL HALT] Processo abortado pelo operador.")