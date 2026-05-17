import time
import random
import sys
import os
import subprocess
import hashlib
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
# BANCO DE DADOS E HISTÓRICOS DE ROLAGEM REAL (SCROLLING MEMORY)
# =====================================================================
# Iniciando com 45 pontos para preencher toda a largura da janela de forma suave
GRAPH_WIDTH = 45
cpu_history = [random.randint(40, 60) for _ in range(GRAPH_WIDTH)]
ram_history = [random.randint(65, 75) for _ in range(GRAPH_WIDTH)]
traffic_history = [random.randint(30, 50) for _ in range(GRAPH_WIDTH)]

OLD_TERMINAL_LOGS = [
    "📌 [SYS_INIT] Initializing IPC Core Bridge via socket descriptor #4092...",
    "🚀 [SUCCESS] MT5 Bridge API connection verified. Latency: 0.12ms.",
    "⚠️ [METRICS] Spread variance anomaly on XAUUSD -> Recalibrating order pool.",
    "🔒 [SECURE] Tuning SSH-256 encrypted tunnel with Singapore Broker cluster...",
    "🛡️ [FIREWALL] Antilatency filter engaged. Deep Packet Inspection active.",
    "🧠 [NEURAL] Retraining LSTM genetic weights. Mutation pool ratio: 0.14",
    "🧹 [GC] Flushed 142MB of orphaned MetaTrader 5 memory buffers.",
    "🔥 [INJECT] High-Frequency Trading (HFT) Spoofing loop engaged.",
    "📁 [LOAD] Imported symbols matrix -> Kernel_MT5_Bridge.dll successfully.",
    "🤖 [ALGO] Strategy_Quantum_V5.mqh execution hook deployed natively.",
    "💻 bash-5.2# rm -rf /tmp/cache_buffers/ && mkdir -p /var/log/mt5_core",
    "💻 bash-5.2# python3 -m framework.core.optimizer --hft-mode=enabled"
]

# =====================================================================
# FUNÇÃO AVANÇADA: DESENHAR GRÁFICOS COM DEGRADÊ E SCROLLING REAL
# =====================================================================
def render_smooth_chart(history_list):
    # Caracteres de bloco vertical Unicode para criar a onda contínua
    chars = [" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    rendered_str = ""
    
    for val in history_list:
        idx = int((val / 100) * 7)
        idx = max(0, min(idx, 7))
        
        # Sistema de cores sofisticado baseado em zonas reais de estresse
        if val >= 90:
            rendered_str += f"[bold red]{chars[idx]}[/bold red]"       # Crítico (Vermelho Puro)
        elif val >= 75:
            rendered_str += f"[bold color(202)]{chars[idx]}[/bold color(202)]" # Sobrecarga (Laranja)
        elif val >= 55:
            rendered_str += f"[bold yellow]{chars[idx]}[/bold yellow]"    # Alerta (Amarelo)
        else:
            rendered_str += f"[color(34)]{chars[idx]}[/color(34)]"       # Normal (Verde Escuro)
            
    return rendered_str

# =====================================================================
# GERADORES DE COMPONENTES VISUAIS
# =====================================================================
def get_header():
    now = datetime.now().strftime("%H:%M:%S.%f")[:-4] # Inclui milissegundos para realismo
    status = "[bold blink red]OVERLOADED[/bold blink red]" if cpu_history[-1] > 85 else "[bold color(208)]STRESSED[/bold color(208)]"
    return Panel(
        f"⚡ [bold green]MKS QUANTUM CONTROL TERMINAL v5.0[/bold green] | [dim]SYS_STATUS:[/dim] {status}  "
        f"[align right][dim]IP:[/dim] 192.168.1.1  [dim]NODE:[/dim] SG-HFT-01  [dim]TICK:[/dim] [bold cyan]{now}[/bold cyan][/align right]",
        style="green",
        border_style="color(24)" # Borda azul-escura/cinza sofisticada
    )

def generate_operations():
    table = Table.grid(padding=1)
    table.add_column(style="green")
    
    # Adiciona um hash gerado dinamicamente que muda a cada frame simulando chaves de segurança
    current_hash = hashlib.md5(str(time.time()).encode()).hexdigest()[:16].upper()
    
    table.add_row("💎 [bold]QUANTUM HFT PIPELINE[/bold]")
    table.add_row(f"[dim]Memory Tunneling Mode:[/dim] [bold red]CRITICAL THROTTLING[/bold red]")
    table.add_row(f"[dim]Active Cipher Key:[/dim] [cyan]0x{current_hash}[/cyan]")
    table.add_row("")
    table.add_row("📡 [bold]REALTIME TELEMETRY STREAM[/bold]")
    table.add_row("[dim]Exfiltrating packet stream to target silo:[/dim] [bold green]tick_history_2026.bin[/bold green]")
    
    return Panel(table, title="⚙️ [bold color(46)]Core Engine Status[/bold color(46)]", border_style="color(28)")

def generate_hardware_matrix():
    table = Table(show_header=False, expand=True, border_style="color(28)")
    table.add_column()
    table.add_column()
    
    # Sincroniza os valores textuais exatamente com a última posição do histórico do gráfico
    cpu_val = cpu_history[-1]
    ram_val = ram_history[-1]
    traffic_val = traffic_history[-1]
    
    cpu_style = "bold red" if cpu_val > 85 else "bold yellow"
    traffic_style = "bold red" if traffic_val > 85 else "bold yellow"
    
    table.add_row(Panel(f"[dim]Processor Load[/dim]\n[{cpu_style}]{cpu_val}% [dim]CRIT_ZONE[/dim]", border_style="color(239)"), 
                  Panel(f"[dim]RAM Allocation[/dim]\n[bold color(220)]{(ram_val * 16 / 100):.2f} / 16.0 GB[/bold color(220)]", border_style="color(239)"),)
    table.add_row(Panel(f"[dim]BGP Link Pipeline[/dim]\n[{traffic_style}]{(traffic_val * 14.2 / 100):.1f} MB/s[ /]", border_style="color(239)"), 
                  Panel(f"[dim]API Requests / Sec[/dim]\n[bold cyan]{random.randint(1420, 1890)} req/s[/bold cyan]", border_style="color(239)"))
    
    return Panel(table, title="📊 [bold color(46)]Hardware Telemetry Matrix[/bold color(46)]", border_style="color(28)")

# SEÇÃO DE MONITORAMENTO DE HARDWARE (ROLAGEM REAL ESTILO GRAFANA)
def generate_hardware_charts():
    # Desloca a fila para a esquerda e insere um dado novo na ponta direita
    cpu_history.pop(0)
    cpu_history.append(random.randint(50, 100) if random.random() > 0.2 else random.randint(88, 100))
    
    ram_history.pop(0)
    ram_history.append(random.randint(70, 95))
    
    cpu_chart = render_smooth_chart(cpu_history)
    ram_chart = render_smooth_chart(ram_history)
    
    content = f"📈 [bold white]CPU Utilization Line History[/bold white]\n{cpu_chart} [bold red]{cpu_history[-1]}%[/bold red]\n\n"
    content += f"📟 [bold white]Memory Paging Buffer History[/bold white]\n{ram_chart} [bold yellow]{ram_history[-1]}%[/bold yellow]"
    
    return Panel(content, title="📈 [bold color(46)]Grafana Engine Analytics (Live Timeline)[/bold color(46)]", border_style="color(28)")

# SEÇÃO DE TRÁFEGO DE REDE (ROLAGEM REAL COM DETECÇÃO DE QUEDA DE PACOTE)
def generate_traffic_monitor():
    traffic_history.pop(0)
    # Gera picos violentos propositais batendo em 98%-100%
    traffic_history.append(random.randint(60, 100) if random.random() > 0.15 else random.randint(95, 100))
    
    traffic_chart = render_smooth_chart(traffic_history)
    alert_msg = "[bold blink red]⚠️ INTERNET PIPELINE SATURATED[/bold blink red]" if traffic_history[-1] > 92 else "[dim]Channel bandwidth stability: NOMINAL[/dim]"
    
    content = f"📉 [bold white]Network Outflow Throughput Variance[/bold white]\n{traffic_chart} [bold red]MAX OVERFLOW[/bold red]\n\n"
    content += f"{alert_msg}"
    
    return Panel(content, title="🌐 [bold color(46)]B3/NYSE Dedicated Gateway Pipeline[/bold color(46)]", border_style="color(28)")

def generate_health_monitor():
    chars = [" ", " ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    graph = "".join([f"[bold red]{random.choice(chars)}[/bold red]" if random.random() > 0.7 else f"[color(34)]{random.choice(chars)}[/color(34)]" for _ in range(45)])
    
    content = f"[dim]Asynchronous spread jitter mapping / execution queues[/dim]\n\n{graph}\n"
    content += "[dim]T-60s      T-45s      T-30s      T-15s      NOW[/dim]"
    return Panel(Align.center(content), title="📡 [bold color(46)]Asynchronous Socket Thread Jitter[/bold color(46)]", border_style="color(28)")

def generate_network_indicators():
    progress = Progress(
        TextColumn("[bold green]{task.description}"),
        BarColumn(bar_width=24, complete_style="color(196)" if random.random() > 0.4 else "color(214)", finished_style="bold red"),
        TextColumn("[cyan]{task.percentage:>3.0f}%"),
    )
    progress.add_task("SOCKET INJECTION ", total=100, completed=random.randint(92, 100))
    progress.add_task("TCP FLOOD BUFFER ", total=100, completed=random.randint(80, 95))
    progress.add_task("TLS HANDSHAKE   ", total=100, completed=random.randint(85, 99))
    
    return Panel(Layout(progress), title="🛡️ [bold color(46)]HFT Proxy Packets Anti-Throttling[/bold color(46)]", border_style="color(28)")

log_history = []
def generate_activity_log():
    now = datetime.now().strftime("%H:%M:%S")
    events = [
        ("[bold color(46)]>>> SECURITY ACCESS GRANTED: KERNEL_RING_0.SYS <<<[/bold color(46)]", "green"),
        ("[bold red]>>> ERR_CODE 429: SERVER BUFFER OVERFLOW DETECTED <<<[/bold red]", "red"),
        ("[bold red]>>> CRITICAL: HIGH SLIPPAGE ON ORDER INJECTOR CORE <<<[/bold red]", "red"),
        ("[bold color(46)]>>> INTEGRITY VERIFIED: DATA_SILO_RECONCILIATION_OK <<<[/bold color(46)]", "green"),
        ("[bold yellow]>>> WARNING: PACKET DROP RATE REACHED 4.2% ON PROXY #04 <<<[/bold yellow]", "yellow"),
    ]
    if len(log_history) == 0 or random.random() > 0.4:
        log_history.append(f"[{now}] {random.choice(events)}")
        if len(log_history) > 4:  
            log_history.pop(0)
            
    return Panel("\n".join(log_history), title="🚨 [bold color(46)]Security Event Handler Interceptor[/bold color(46)]", border_style="color(28)")

# =====================================================================
# GERADOR DO FLUXO DO TERMINAL INFERIOR (VERSÃO ANTIGA EXPANDIDA)
# =====================================================================
bottom_terminal_lines = []
def generate_bottom_terminal():
    if random.random() > 0.25:
        log = random.choice(OLD_TERMINAL_LOGS)
        if "[SUCCESS]" in log or "100%" in log:
            line = f"[bold color(46)]{log}[/bold color(46)]"
        elif "[WARN]" in log or "CRITICAL" in log or "WARNING" in log:
            line = f"[bold color(202)]{log}[/bold color(202)]"
        elif "bash" in log:
            line = f"[bold color(250)]{log}[/bold color(250)]"
        else:
            line = f"[bold color(38)]{log}[/bold color(38)]"
        bottom_terminal_lines.append(line)
    else:
        # Gera Dumps hexadecimais complexos e realistas
        hex_data = " ".join([f"{random.randint(0, 255):02X}" for _ in range(16)])
        addr = f"0x{random.randint(0x1000, 0x9FFF):04X}8F"
        line = f"[color(240)]MEM_DUMP[/color(240)] [bold color(34)]{addr}[/bold color(34)] -> {hex_data} | [bold red]EIP_OVERFLOW[/bold red]"
        bottom_terminal_lines.append(line)
        
    if len(bottom_terminal_lines) > 13: # Ajustado milimetricamente para o tamanho do painel expandido
        bottom_terminal_lines.pop(0)
        
    return Panel("\n".join(bottom_terminal_lines), title="💻 [bold color(46)]MKS_ULTIMATE_CORE_DOWNSTREAM_DEBUGGER v1.0.4[/bold color(46)]", border_style="color(24)")

# =====================================================================
# ESTRUTURAÇÃO DO LAYOUT EM PROPORÇÕES CINEMATOGRÁFICAS
# =====================================================================
layout = Layout()
layout.split(
    Layout(name="header", size=3),
    Layout(name="body", ratio=3),            # Dashboard Superior Estilo Grafana
    Layout(name="old_terminal", ratio=2)     # Terminal Inferior Gigante de Logs Brutos
)

layout["body"].split_row(
    Layout(name="left_col", ratio=1),
    Layout(name="right_col", ratio=1)
)

layout["left_col"].split(
    Layout(name="missions", ratio=2),
    Layout(name="hardware_charts", ratio=3), # Linhas de processamento
    Layout(name="activity", ratio=2),
    Layout(name="rsi", size=4)
)

layout["right_col"].split(
    Layout(name="status", ratio=3),
    Layout(name="indicators", ratio=2),
    Layout(name="traffic", ratio=2)          # Tráfego saturado
)

# =====================================================================
# LOOP DE EXECUÇÃO EM ALTA VELOCIDADE (SENSATION ENGINE)
# =====================================================================
if __name__ == "__main__":
    with Live(layout, refresh_per_second=6, screen=True) as live:
        try:
            while True:
                layout["header"].update(get_header())
                layout["missions"].update(generate_operations())
                layout["hardware_charts"].update(generate_hardware_charts())
                layout["activity"].update(generate_activity_log())
                layout["rsi"].update(generate_health_monitor())
                
                layout["status"].update(generate_hardware_matrix())
                layout["indicators"].update(generate_network_indicators())
                layout["traffic"].update(generate_traffic_monitor())
                
                layout["old_terminal"].update(generate_bottom_terminal())
                
                time.sleep(0.12) # Ritmo frenético de trading quantitativo de alta frequência
        except KeyboardInterrupt:
            pass