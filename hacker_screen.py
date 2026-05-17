import time
import random
import sys

# Códigos de cores ANSI nativos (funcionam direto no terminal do VS Code)
GREEN = "\033[1;32m"
CYAN = "\033[1;36m"
YELLOW = "\033[1;33m"
WHITE = "\033[1;37m"
RED = "\033[1;31m"
RESET = "\033[0m"

MESSAGES = [
    "[INFO] Conectando ao servidor MetaTrader 5 Terminal...",
    "[SUCCESS] Autenticação SSL estabelecida com sucesso.",
    "[FETCH] Baixando ticks históricos para EURUSD, GBPUSD, BTCUSD...",
    "[ANALYSIS] Calculando Bandas de Bollinger e RSI em tempo real...",
    "[DECRYPT] Decodificando pacotes de dados de liquidez do provedor...",
    "[ALGO] Otimizando parâmetros via Algoritmo Genético (Gerações 45/100)...",
    "[WARN] Alta volatilidade detectada no par XAUUSD. Ajustando Stop Loss...",
    "[INJECT] Injetando ordens de teste no ecossistema Sandbox...",
    "[KERNEL] Alocando memória RAM estendida para processamento de matrizes...",
    "[SECURITY] Bypass de latência do Broker concluído. Ping: 0.4ms",
    "[SYS] Compilando arquivos MQL5 compilados dinamicamente...",
    "[DEBUG] Ponteiros C++ alocados na memória do terminal MT5.",
]

FILES = [
    "Kernel_MT5_Bridge.dll", "Strategy_Quantum_V4.mqh", "Indicator_Neural_Net.ex5",
    "Backtest_Matrix_Data.bin", "Risk_Manager_Pro.py", "Order_Execution_Hook.cpp"
]

def typing_effect(text, speed=0.01):
    for char in text:
        sys.stdout.write(char)
        sys.stdout.flush()
        time.sleep(speed)
    print()

def fake_hacker_screen():
    print(GREEN + "==================================================")
    print(GREEN + "       INITIALIZING MT5 QUANTUM FRAMEWORK v3.0    ")
    print(GREEN + "==================================================" + RESET)
    time.sleep(1)

    while True:
        action = random.choice(["message", "loading", "matrix"])
        
        if action == "message":
            msg = random.choice(MESSAGES)
            if "[INFO]" in msg:
                color = CYAN
            elif "[SUCCESS]" in msg:
                color = GREEN
            else:
                color = YELLOW
            typing_effect(color + msg + RESET)
            
        elif action == "loading":
            current_file = random.choice(FILES)
            sys.stdout.write(WHITE + f"[LOAD] Carregando {current_file}: [" + RESET)
            for _ in range(20):
                time.sleep(random.uniform(0.03, 0.10))
                sys.stdout.write(GREEN + "#" + RESET)
                sys.stdout.flush()
            print(GREEN + "] 100% - OK" + RESET)
            
        elif action == "matrix":
            for _ in range(random.randint(5, 15)):
                hex_data = " ".join([f"{random.randint(0, 255):02X}" for _ in range(8)])
                float_data = f"| Price: {random.uniform(1.0500, 1.1200):.5f} | Vol: {random.randint(100, 5000)}"
                print(GREEN + f"HEX_DUMP -> {hex_data} {float_data}" + RESET)
                time.sleep(0.04)
                
        time.sleep(random.uniform(0.1, 0.5))

if __name__ == "__main__":
    try:
        fake_hacker_screen()
    except KeyboardInterrupt:
        print(RED + "\n[HALT] Processo interrompido pelo usuário." + RESET)