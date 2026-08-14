#!/bin/sh
set -u

TTY="${TTY:-/dev/ttyS3}"
BAUD="${BAUD:-115200}"
LOG="${LOG:-/tmp/k230_nrf9151_at_console_$(date +%Y%m%d_%H%M%S).log}"
RAW_LOG="${RAW_LOG:-${LOG}.raw}"
FIX_IOMUX="${FIX_IOMUX:-1}"
READ_SECONDS="${READ_SECONDS:-2}"

usage() {
    cat <<'USAGE'
Usage:
  k230_nrf9151_at_console.sh

Environment:
  TTY=/dev/ttyS3             K230 UART connected to nRF9151 UART1 AT port
  BAUD=115200                UART baud rate
  LOG=/tmp/name.log          Decoded console log path
  RAW_LOG=/tmp/name.log.raw  Raw UART RX capture path
  FIX_IOMUX=1                Configure K230 UART3 IOMUX only
  READ_SECONDS=2             Response read window after each AT command

Important:
  This tool does not request or change nRF9151 EN/GPIO2.
  It keeps the UART device open for the full console session. This avoids
  losing responses due to repeated open/close of /dev/ttyS3.

Interactive commands:
  Type an AT command, press Enter, and the tool sends it with CRLF.
  .help             Show help and recommended GNSS/SIM sequence
  .listen [seconds] Keep listening for async URCs/logs
  .log              Print log paths
  .iomux            Print current K230 UART3 IOMUX registers
  .stats            Print current K230 UART3 serial counters
  .probe            Send AT, AT+CMEE=1, AT+CGMR, AT#XGNSS?
  .sim              Send AT, AT+CMEE=1, AT+CFUN=1, AT+CPIN?, AT+CIMI, AT%XSIM?
  .quit             Exit

Recommended SIM probe:
  AT
  AT+CMEE=1
  AT+CFUN=1
  AT+CPIN?
  AT+CIMI
  AT%XSIM?

Recommended manual GNSS crash-capture sequence:
  AT
  AT+CMEE=1
  AT+CGMR
  AT#XGNSS?
  AT+CFUN=0
  AT%XSYSTEMMODE=0,0,1,0
  AT+CFUN=31
  AT#XNMEA=1
  AT#XGNSS=1,0,0,0
  .listen 30

While running the sequence, watch nRF9151 UART2 log output on P0.29/P0.28.
USAGE
}

serial3_stats() {
    if [ -r /proc/tty/driver/serial ]; then
        grep '^3:' /proc/tty/driver/serial 2>/dev/null || true
    fi
}

configure_uart3_iomux() {
    [ "$FIX_IOMUX" = "1" ] || return 0
    [ "$TTY" = "/dev/ttyS3" ] || return 0
    command -v devmem >/dev/null 2>&1 || {
        echo "warning: devmem missing; UART3 IOMUX not changed" >&2
        return 0
    }

    # Do not touch nRF9151 EN/GPIO2 here.
    devmem 0x91105070 32 0x00001191 >/dev/null
    devmem 0x91105074 32 0x00001111 >/dev/null
    devmem 0x911050c8 32 0x00000010 >/dev/null
    devmem 0x911050cc 32 0x00000010 >/dev/null
}

print_iomux() {
    if ! command -v devmem >/dev/null 2>&1; then
        echo "devmem missing"
        return
    fi
    printf 'IO28=0x%s\n' "$(devmem 0x91105070 32 | sed 's/^0x//')"
    printf 'IO29=0x%s\n' "$(devmem 0x91105074 32 | sed 's/^0x//')"
    printf 'IO50=0x%s\n' "$(devmem 0x911050c8 32 | sed 's/^0x//')"
    printf 'IO51=0x%s\n' "$(devmem 0x911050cc 32 | sed 's/^0x//')"
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

if [ ! -c "$TTY" ]; then
    echo "error: missing character device: $TTY" >&2
    exit 1
fi

PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"
if [ -z "$PYTHON_BIN" ]; then
    echo "error: python3 is required for stable UART console mode" >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG")" "$(dirname "$RAW_LOG")"
: > "$RAW_LOG"
{
    echo "===== start $(date) ====="
    echo "tty=$TTY baud=$BAUD"
    echo "log=$LOG"
    echo "raw_log=$RAW_LOG"
    echo "fix_iomux=$FIX_IOMUX"
    echo "note=does not touch nRF9151 EN/GPIO2"
    echo "note=keeps UART open for full session"
    echo "serial_before=$(serial3_stats)"
} >> "$LOG"

configure_uart3_iomux
{
    echo "iomux:"
    print_iomux
} >> "$LOG"

export TTY BAUD LOG RAW_LOG READ_SECONDS
PY_HELPER="${TMPDIR:-/tmp}/k230_nrf9151_at_console_$$.py"
trap 'rm -f "$PY_HELPER"' EXIT INT TERM
cat > "$PY_HELPER" <<'PY'
import atexit
import os
import select
import subprocess
import sys
import termios
import time

TTY = os.environ.get("TTY", "/dev/ttyS3")
BAUD = os.environ.get("BAUD", "115200")
LOG = os.environ.get("LOG", "/tmp/k230_nrf9151_at_console.log")
RAW_LOG = os.environ.get("RAW_LOG", LOG + ".raw")
READ_SECONDS = os.environ.get("READ_SECONDS", "2")

BAUD_MAP = {}
for _baud_name in ("B9600", "B19200", "B38400", "B57600", "B115200",
                   "B230400", "B460800", "B921600"):
    if hasattr(termios, _baud_name):
        BAUD_MAP[_baud_name[1:]] = getattr(termios, _baud_name)

HELP = """Interactive commands:
  .help             Show help
  .listen [seconds] Keep listening for async URCs/logs
  .log              Print log paths
  .iomux            Print current K230 UART3 IOMUX registers
  .stats            Print current K230 UART3 serial counters
  .probe            Send AT, AT+CMEE=1, AT+CGMR, AT#XGNSS?
  .sim              Send AT, AT+CMEE=1, AT+CFUN=1, AT+CPIN?, AT+CIMI, AT%XSIM?
  .quit             Exit
"""


def log_line(text):
    with open(LOG, "a", encoding="utf-8", errors="replace") as fp:
        fp.write(text + "\n")


def serial3_stats():
    try:
        with open("/proc/tty/driver/serial", "r", encoding="utf-8",
                  errors="replace") as fp:
            for line in fp:
                if line.startswith("3:"):
                    return line.strip()
    except OSError:
        pass
    return ""


def devmem(addr):
    try:
        out = subprocess.check_output(["devmem", addr, "32"],
                                      stderr=subprocess.DEVNULL)
        return out.decode("ascii", "replace").strip()
    except Exception:
        return "unavailable"


def print_iomux():
    for name, addr in (("IO28", "0x91105070"),
                       ("IO29", "0x91105074"),
                       ("IO50", "0x911050c8"),
                       ("IO51", "0x911050cc")):
        print(f"{name}={devmem(addr)}")


def parse_seconds(text, default):
    try:
        value = int(text)
    except Exception:
        return default
    return value if value > 0 else default


def configure_uart(fd):
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] |= termios.CLOCAL | termios.CREAD
    attrs[2] &= ~(termios.PARENB | termios.CSTOPB | termios.CSIZE)
    if hasattr(termios, "CRTSCTS"):
        attrs[2] &= ~termios.CRTSCTS
    attrs[2] |= termios.CS8
    attrs[3] = 0
    speed = BAUD_MAP.get(BAUD, termios.B115200)
    attrs[4] = speed
    attrs[5] = speed
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 1
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)


class UartReader:
    def __init__(self, fd):
        self.fd = fd
        self.partial = b""
        self.lines = []

    def _emit_lines(self, data, final=False):
        if not data and not final:
            return False
        self.partial += data
        text = self.partial.replace(b"\r", b"\n")
        lines = text.split(b"\n")
        if text.endswith(b"\n") or final:
            self.partial = b""
        else:
            self.partial = lines.pop()

        done = False
        for raw in lines:
            if not raw:
                continue
            line = raw.decode("latin1", "replace")
            print(f"< {line}", flush=True)
            log_line(f"< {line}")
            self.lines.append(line)
            clean = line.strip()
            if clean in ("OK", "ERROR") or clean.startswith("+CME ERROR") or \
               clean.startswith("+CMS ERROR"):
                done = True
        return done

    def read_for(self, seconds, stop_on_final=False):
        self.lines = []
        deadline = time.monotonic() + seconds
        done = False
        while time.monotonic() < deadline:
            timeout = max(0.0, min(0.1, deadline - time.monotonic()))
            r, _, _ = select.select([self.fd], [], [], timeout)
            if not r:
                continue
            try:
                chunk = os.read(self.fd, 4096)
            except BlockingIOError:
                continue
            if not chunk:
                continue
            with open(RAW_LOG, "ab") as raw_fp:
                raw_fp.write(chunk)
            if self._emit_lines(chunk) and stop_on_final:
                done = True
                break
        self._emit_lines(b"", final=True)
        return done, list(self.lines)


def send_command(fd, reader, cmd, seconds=None):
    if seconds is None:
        seconds = parse_seconds(READ_SECONDS, 2)
    print(f"> {cmd}", flush=True)
    log_line(f"> {cmd}")
    os.write(fd, (cmd + "\r\n").encode("ascii", "replace"))
    _, lines = reader.read_for(seconds, stop_on_final=True)
    return lines


def sim_ready(lines):
    for line in lines:
        clean = line.strip()
        if clean == "+CPIN: READY" or clean.startswith("%XSIM: 1"):
            return True
    return False


def run_sim_probe(fd, reader):
    for sim_cmd in ("AT", "AT+CMEE=1"):
        send_command(fd, reader, sim_cmd, 2)
    send_command(fd, reader, "AT+CFUN=1", 5)

    ready = False
    for attempt in range(1, 16):
        print(f"SIM probe poll {attempt}/15", flush=True)
        log_line(f"SIM probe poll {attempt}/15")
        time.sleep(1)
        cpin_lines = send_command(fd, reader, "AT+CPIN?", 2)
        xsim_lines = send_command(fd, reader, "AT%XSIM?", 2)
        if sim_ready(cpin_lines) or sim_ready(xsim_lines):
            ready = True
            break

    if ready:
        send_command(fd, reader, "AT+CIMI", 3)
    else:
        print("SIM not ready after 15s")
        log_line("SIM not ready after 15s")


fd = os.open(TTY, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
configure_uart(fd)
reader = UartReader(fd)


@atexit.register
def cleanup():
    try:
        os.close(fd)
    except Exception:
        pass
    log_line("")
    log_line("===== stop %s =====" % time.strftime("%a %b %d %H:%M:%S UTC %Y",
                                                time.gmtime()))
    log_line("serial_after=%s" % serial3_stats())


print("nRF9151 AT console started")
print(f"TTY={TTY} BAUD={BAUD}")
print(f"LOG={LOG}")
print(f"RAW_LOG={RAW_LOG}")
print(f"READ_SECONDS={READ_SECONDS}")
print("This tool does not touch nRF9151 EN/GPIO2.")
print("UART is kept open for the full console session.")
print("Type .help for commands, .quit to exit.")

while True:
    try:
        cmd = input("nrf9151> ").strip()
    except EOFError:
        print()
        break
    except KeyboardInterrupt:
        print()
        break

    if not cmd:
        continue
    if cmd in (".quit", ".exit"):
        break
    if cmd == ".help":
        print(HELP)
        continue
    if cmd == ".log":
        print(f"LOG={LOG}")
        print(f"RAW_LOG={RAW_LOG}")
        continue
    if cmd == ".iomux":
        print_iomux()
        continue
    if cmd == ".stats":
        print(serial3_stats())
        continue
    if cmd == ".probe":
        for probe_cmd in ("AT", "AT+CMEE=1", "AT+CGMR", "AT#XGNSS?"):
            send_command(fd, reader, probe_cmd, 2)
        continue
    if cmd == ".sim":
        run_sim_probe(fd, reader)
        continue
    if cmd.startswith(".listen"):
        parts = cmd.split()
        seconds = parse_seconds(parts[1], 10) if len(parts) > 1 else 10
        print(f"listening for {seconds}s...")
        reader.read_for(seconds, stop_on_final=False)
        continue

    send_command(fd, reader, cmd)

print("bye")
PY
"$PYTHON_BIN" "$PY_HELPER"
