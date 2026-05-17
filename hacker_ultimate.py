import time
import random
import sys
import os
import subprocess
from datetime import datetime

# =====================================================================
# SISTEMA DE AUTO-INJEÇÃO DE DEPENDÊNCIAS (RICH)
# =====================================================================
try:
    from rich.console import Console
    from rich.layout import Layout
    from rich.panel import Panel
    from rich.live import Live
    from rich.table import Table
    from rich.progress import Progress, BarColumn, TextColumn
    from rich.align import Align
except ImportError:
    print("[SYS] Dependência crítica 'rich' não detectada no ambiente atual.")
    print("[SYS] Iniciando injeção automatizada de pacotes via pip...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "rich"])
        print("[SUCCESS] Biblioteca 'rich' injetada. Inicializando subsistemas...")
        time.sleep(1.5)
        from rich.console import Console
        from rich.layout import Layout
        from rich.panel import Panel
        from rich.live import Live
        from rich.table import Table
        from rich.progress import Progress, BarColumn, TextColumn
        from rich.align import Align
    except Exception as e:
        print(f"[CRITICAL ERROR] Falha na auto-instalação: {e}")
        sys.exit(1)

console = Console()

# =====================================================================
# HISTÓRICOS DOS GRÁFICOS (Para criar o efeito de linha contínua)
# =====================================================================
cpu_history = [random.randint(40, 70) for _ in range(25)]
ram_history = [random.randint(50, 80) for _ in range(25)]
traffic_history = [random.randint(30, 60) for _ in range(25)]

# Banco de dados de logs para a esteira inferior
OLD_TERMINAL_LOGS = [
    "[INFO] Sincronizando clock do servidor com a Bolsa de Valores (B3/NYSE)...",
    "[SUCCESS] Canal de comunicação IPC (Inter-Process Communication) estabelecido.",
    "[WARN] Anomalia de spread detectada no par XAUUSD. Recalibrando ordens...",
    "[DECRYPT] Abrindo túnel criptografado SSH-256 com o Broker...",
    "[SECURITY] Firewall ativado. Varredura de antilatência concluída. Ping: 0.23ms",
    "[ALGO] Otimizando pesos neurais usando algoritmo genético adaptativo...",
    "[SYS] Desalocando buffers antigos de memória RAM do MetaTrader 5...",
    "[INJECT] Injetando ordens fantasmas (HFT Spoofing Detection active)...",
    "LOAD_FILE -> Kernel_MT5_Bridge.dll [====================] 100% - OK",
    "LOAD_FILE -> Strategy_Quantum_V4.mqh [====================] 100% - OK",
    "LOAD_FILE -> Indicator_Neural_Net.ex5 [====================] 100% - OK",
    "bash-5.2# rm -rf /tmp/cache_buffers/old_ticks.bin && mkdir -p /var/log/mt5",
    "bash-5.2# python3 -m framework.core.optimizer --generations=100 --pop=500"
]

# =====================================================================
# FUNÇÃO AUXILIAR: DESENHAR GRÁFICOS DE LINHA EM TEXTO
# =====================================================================
def render_line_chart(history_list, is_overloaded=False):
    # Caracteres Unicode para subida de blocos/linhas
    chars = [" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    rendered_str = ""
    
    for val in history_list:
        # Mapeia valores de 0-100 para o índice dos caracteres (0 a 7)
        idx = int((val / 100) * 7)
        idx = max(0, min(idx, 7))
        
        # Se estiver muito alto (sobrecarga), plota em vermelho piscante/negrito
        if val >= 85 and is_overloaded:
            rendered_str += f"[bold red]{chars[idx]}[/bold red]"
        elif val >= 70:
            rendered_str += f"[bold yellow]{chars[idx]}[/bold yellow]"
        else:
            rendered_str += f"[bold green]{chars[idx]}[/bold green]"
            
    return rendered_str

# =====================================================================
# GERADORES DE DADOS DO DASHBOARD SUPERIOR
# =====================================================================
def get_header():
    now = datetime.now().strftime("%H:%M:%S")
    return Panel(
        f"[bold green]CYBERHACK DASHBOARD[/bold green] | FRAMEWORK MKS v5.0"
        f"[align right][bold cyan]STATUS:[/bold cyan] OVERLOADED  "
        f"[bold red]ALERTS: ACTIVE[/bold red]  "
        f"[bold cyan]TIME:[/bold cyan] {now}[/align right]",
        style="green",
        border_style="green"
    )

def generate_missions():
    table = Table.grid(padding=1)
    table.add_column(style="green")
    
    table.add_row("[bold]Operation Backdoor[/bold]")
    table.add_row("[dim]Injecting bypass hooks into MT5 Core Executable[/dim]")
    table.add_row(f"Status: [bold red]CRITICAL OVERLOAD[/bold red]")
    table.add_row("")
    table.add_row("[bold]Data Exfiltration[/bold]")
    table.add_row("[dim]Streaming tick_history_2026.bin via proxy grid[/dim]")
    table.add_row("Status: [bold green]Active HFT Loop[/bold green]")
    
    return Panel(table, title="[bold green]Active Operations[/bold green]", border_style="green")

def generate_system_status():
    table = Table(show_header=False, expand=True, border_style="green")
    table.add_column()
    table.add_column()
    
    # Valores sempre altos refletindo o estresse do PC
    cpu = f"[bold red]{cpu_history[-1]}%[/bold red]"
    ram = f"[bold yellow]{(ram_history[-1] * 16 / 100):.2f} / 16.0 GB[/bold yellow]"
    traffic = f"[bold red]{(traffic_history[-1] * 12.5 / 100):.1f} MB/s[/bold red]"
    conn = f"[bold cyan]{random.randint(180, 245)} active[/bold cyan]"
    
    table.add_row(Panel(f"[bold green]Core CPU Temp[/bold green]\n{cpu} [dim](CRIT)[/dim]", border_style="green"), 
                  Panel(f"[bold green]RAM Commitment[/bold green]\n{ram}", border_style="green"))
    table.add_row(Panel(f"[bold green]Network Outflow[/bold green]\n{traffic}", border_style="green"), 
                  Panel(f"[bold green]Sockets Closed/s[/bold green]\n{conn}", border_style="green"))
    
    return Panel(table, title="[bold green]System Hardware Matrix[/bold green]", border_style="green")

# NOVO BLOCO: Gráficos de Linha de CPU e Memória Estilo Grafana
def generate_hardware_load_charts():
    # Atualiza histórico simulando carga pesada (40% a 100%)
    cpu_history.pop(0)
    cpu_history.append(random.randint(45, 100) if random.random() > 0.3 else random.randint(85, 100))
    
    ram_history.pop(0)
    ram_history.append(random.randint(60, 95))
    
    cpu_chart = render_line_chart(cpu_history, is_overloaded=True)
    ram_chart = render_line_chart(ram_history, is_overloaded=False)
    
    content = f"[bold white]CPU Utilization Line (40% - 100%):[/bold white]\n{cpu_chart} [bold red]{cpu_history[-1]}%[/bold red]\n\n"
    content += f"[bold white]Memory Allocation Line (60% - 100%):[/bold white]\n{ram_chart} [bold yellow]{ram_history[-1]}%[/bold yellow]"
    
    return Panel(content, title="[bold green]SYSTEM HARDWARE LOAD (HISTORICAL)[/bold green]", border_style="green")

def generate_health_monitor():
    chars = [" ", " ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    graph = ""
    for _ in range(32):
        val = random.randint(0, 8)
        if val > 5:
            graph += f"[bold red]{chars[val]}[/bold red]"  
        else:
            graph += f"[bold green]{chars[val]}[/bold green]"
            
    content = f"[dim]Anomalies on Liquidity Providers streams[/dim]\n\n{graph}\n"
    content += "[dim]T-45       T-30       T-15       T-5        NOW[/dim]"
    return Panel(Align.center(content), title="[bold green]MT5 API HEALTH MONITOR[/bold green]", border_style="green")

def generate_network_indicators():
    progress = Progress(
        TextColumn("[bold green]{task.description}"),
        BarColumn(bar_width=20, complete_style="red" if random.random() > 0.5 else "yellow", finished_style="bold red"),
        TextColumn("[cyan]{task.percentage:>3.0f}%"),
    )
    progress.add_task("SOCKET FLOOD   ", total=100, completed=random.randint(90, 100))
    progress.add_task("BGP PACKETS    ", total=100, completed=random.randint(75, 88))
    progress.add_task("SSL PROXY LAYER", total=100, completed=random.randint(80, 95))
    
    return Panel(Layout(progress), title="[bold green]BUFFER NETWORK PACKETS[/bold green]", border_style="green")

log_history = []
def generate_activity_log():
    now = datetime.now().strftime("%H:%M:%S")
    events = [
        ("[bold green]>>> ACCESS GRANTED: SYSTEM_KERNEL.SECURE <<<[/bold green]", "green"),
        ("[bold red]>>> ACCESS DENIED: ROOT_BUFFER.ACCESS_DENIED <<<[/bold red]", "red"),
        ("[bold red]>>> WARNING: NETWORK BANDWIDTH OVER 90% <<<[/bold red]", "red"),
        ("[bold green]>>> ACCESS GRANTED: DATA_SILO.SECURE <<<[/bold green]", "green"),
        ("[bold yellow]>>> WARNING: HIGH SLIPPAGE DETECTED IN ORDER INJECTOR <<<[/bold yellow]", "yellow"),
    ]
    if len(log_history) == 0 or random.random() > 0.4:
        evt = random.choice(events)
        log_history.append(f"[{now}] {evt}")
        if len(log_history) > 4:  
            log_history.pop(0)
            
    return Panel("\n".join(log_history), title="[bold green]Critical Security Log[/bold green]", border_style="green")

# NOVO BLOCO (Substituindo o Quick Access): Monitor de Tráfego de Rede com Sobrecarga
def generate_traffic_monitor():
    # Simula tráfego violento batendo nos 100%
    traffic_history.pop(0)
    traffic_history.append(random.randint(55, 100) if random.random() > 0.2 else random.randint(90, 100))
    
    traffic_chart = render_line_chart(traffic_history, is_overloaded=True)
    
    content = f"[bold white]Bandwidth Throughput Variance:[/bold white]\n{traffic_chart} [bold red]MAX CRIT[/bold red]\n"
    content += f"[bold red]ALERT:[/bold red] Network pipeline saturated. [blink]DROP PACKETS ACTIVE[/blink]"
    
    return Panel(content, title="[bold green]TRAFFIC NETWORK MONITOR[/bold green]", border_style="green")

def generate_rsi_stream():
    chars = [" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    stream = " ".join([f"[bold red]{random.choice(chars)}[/bold red]" if random.random() > 0.7 else f"[bold green]{random.choice(chars)}[/bold green]" for _ in range(16)])
    return Panel(Align.center(f"{stream}\n[dim]T-0   T-5   T-10   T-55   T-100[/dim]"), title="[bold green]QUANTUM VOLATILITY STREAM[/bold green]", border_style="green")

# =====================================================================
# GERADOR DO FLUXO DO TERMINAL INFERIOR (EXPANDIDO)
# =====================================================================
bottom_terminal_lines = []
def generate_bottom_terminal():
    if random.random() > 0.3:
        log = random.choice(OLD_TERMINAL_LOGS)
        if "[SUCCESS]" in log or "100%" in log:
            line = f"[bold green]{log}[/bold green]"
        elif "[WARN]" in log or "WARNING" in log:
            line = f"[bold yellow]{log}[/bold yellow]"
        elif "bash" in log:
            line = f"[bold white]{log}[/bold white]"
        else:
            line = f"[bold cyan]{log}[/bold cyan]"
        bottom_terminal_lines.append(line)
    else:
        hex_data = " ".join([f"{random.randint(0, 255):02X}" for _ in range(14)])
        line = f"[green]MEM_DUMP [0x{random.randint(1000, 9999)}FFF] -> {hex_data} | [bold red]OVERFLOW_WARN[/bold red][/green]"
        bottom_terminal_lines.append(line)
        
    # Limite aumentado para 12 linhas aproveitando o espaço do terminal expandido
    if len(bottom_terminal_lines) > 12:
        bottom_terminal_lines.pop(0)
        
    return Panel("\n".join(bottom_terminal_lines), title="[bold green]MKS_ULTIMATE_FRAMEWORK v1.0 - CORES LIVE DOWNSTREAM[/bold green]", border_style="green")

# =====================================================================
# ESTRUTURAÇÃO DO LAYOUT (PROPORÇÕES ATUALIZADAS)
# =====================================================================
layout = Layout()
layout.split(
    Layout(name="header", size=3),
    Layout(name="body", ratio=3),            # Dashboard Superior
    Layout(name="old_terminal", ratio=2)     # TERMINAL INFERIOR EXPANDIDO (Ganhou mais espaço de tela)
)

layout["body"].split_row(
    Layout(name="left_col", ratio=1),
    Layout(name="right_col", ratio=1)
)

layout["left_col"].split(
    Layout(name="missions", ratio=2),
    Layout(name="hardware_charts", ratio=3), # Inserção do painel duplo de CPU/RAM Grafana
    Layout(name="activity", ratio=2),
    Layout(name="rsi", size=4)
)

layout["right_col"].split(
    Layout(name="status", ratio=3),
    Layout(name="indicators", ratio=2),
    Layout(name="traffic", ratio=2)          # Inserção do Monitor de Tráfego no lugar do Quick Access
)

# =====================================================================
# LOOP DE EXECUÇÃO
# =====================================================================
if __name__ == "__main__":
    with Live(layout, refresh_per_second=5, screen=True) as live:
        try:
            while True:
                layout["header"].update(get_header())
                layout["missions"].update(generate_missions())
                layout["hardware_charts"].update(generate_hardware_load_charts())
                layout["activity"].update(generate_activity_log())
                layout["rsi"].update(generate_rsi_stream())
                
                layout["status"].update(generate_system_status())
                layout["indicators"].update(generate_network_indicators())
                layout["traffic"].update(generate_traffic_monitor())
                
                layout["old_terminal"].update(generate_bottom_terminal())
                
                time.sleep(0.15)
        except KeyboardInterrupt:
            pass