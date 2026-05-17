import time
import random
import sys
from colorama import Fore, Style, init

# Inicializa as cores do terminal
init(autoreset=True)

# Lista de mensagens falsas com cara de "alta tecnologia" e trading
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

def typing_effect(text, speed=0.02):
    for char in text:
        sys.stdout.write(char)
        sys.stdout.flush()
        time.sleep(speed)
    print()

def fake_hacker_screen():
    print(Fore.GREEN + Style.BRIGHT + "==================================================")
    print(Fore.GREEN + Style.BRIGHT + "       INITIALIZING MT5 QUANTUM FRAMEWORK v3.0    ")
    print(Fore.GREEN + Style.BRIGHT + "==================================================")
    time.sleep(1)

    while True:
        # Escolhe uma ação aleatória para variar o visual
        action = random.choice(["message", "loading", "matrix"])
        
        if action == "message":
            msg = random.choice(MESSAGES)
            color = Fore.CYAN if "[INFO]" in msg else (Fore.GREEN if "[SUCCESS]" in msg else Fore.YELLOW)
            typing_effect(color + msg, speed=0.01)
            
        elif action == "loading":
            current_file = random.choice(FILES)
            sys.stdout.write(Fore.WHITE + f"[LOAD] Carregando {current_file}: [")
            for _ in range(20):
                time.sleep(random.uniform(0.05, 0.15))
                sys.stdout.write(Fore.GREEN + "#")
                sys.stdout.flush()
            print(Fore.GREEN + "] 100% - OK")
            
        elif action == "matrix":
            # Simula aquela chuva de dados/números hexadecimais
            for _ in range(random.randint(5, 15)):
                hex_data = " ".join([f"{random.randint(0, 255):02X}" for _ in range(8)])
                float_data = f"| Price: {random.uniform(1.0500, 1.1200):.5f} | Vol: {random.randint(100, 5000)}"
                print(Fore.GREEN + f"HEX_DUMP -> {hex_data} {float_data}")
                time.sleep(0.05)
                
        time.sleep(random.uniform(0.2, 0.8))

if __name__ == "__main__":
    try:
        fake_hacker_screen()
    except KeyboardInterrupt:
        print(Fore.RED + "\n[HALT] Processo interrompido pelo usuário.")