#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-root@192.168.100.210}"
UART_DEV="${UART_DEV:-/dev/ttyS3}"

ssh "$TARGET" "UART_DEV='$UART_DEV' sh -s" <<'REMOTE'
set -eu

uart="${UART_DEV:-/dev/ttyS3}"

gpio_set() {
	gpio="$1"
	value="$2"

	if command -v gpioset >/dev/null 2>&1; then
		gpioset -m time -s 1 gpiochip0 "$gpio=$value" >/dev/null 2>&1 || return 1
		return 0
	fi

	if [ -d /sys/class/gpio ]; then
		[ -e "/sys/class/gpio/gpio$gpio" ] || echo "$gpio" > /sys/class/gpio/export 2>/dev/null || true
		echo out > "/sys/class/gpio/gpio$gpio/direction" 2>/dev/null || true
		echo "$value" > "/sys/class/gpio/gpio$gpio/value" 2>/dev/null || return 1
		return 0
	fi

	return 1
}

read_for_seconds() {
	seconds="$1"

	if command -v timeout >/dev/null 2>&1; then
		timeout "$seconds" cat "$uart" 2>/dev/null || true
		return
	fi

	end=$(( $(date +%s) + seconds ))
	while [ "$(date +%s)" -lt "$end" ]; do
		dd if="$uart" bs=256 count=1 iflag=nonblock 2>/dev/null || true
		sleep 0.1
	done
}

send_at() {
	cmd="$1"
	printf '\n> %s\n' "$cmd"
	printf '%s\r\n' "$cmd" > "$uart"
	read_for_seconds 2
}

echo "Powering nRF9151 EN GPIO2 high"
gpio_set 2 1 || echo "warning: failed to set GPIO2"
sleep 1

if [ ! -e "$uart" ]; then
	echo "missing UART device: $uart"
	exit 1
fi

stty -F "$uart" 115200 raw -echo -crtscts cs8 -cstopb -parenb min 0 time 5

send_at "AT"
send_at "AT+CMEE=1"
send_at "ATI"
send_at "AT+CGSN"
send_at "AT+CGMR"
send_at "AT%XSIM=1"
send_at "AT%XSIM?"
send_at "AT+CPIN?"
send_at "AT%XICCID"
send_at "AT+CIMI"
send_at "AT+CRSM=176,12258,0,0,10"
send_at "AT+CFUN?"
send_at "AT%XSYSTEMMODE?"
send_at "AT+CEREG?"
send_at "AT+CESQ"
send_at "AT%XMONITOR"
send_at "AT#XGPS?"
send_at "AT#XGNSS?"
send_at "AT#XGNSSNMEA?"
REMOTE
