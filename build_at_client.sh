#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NCS_ROOT="${NCS_ROOT:-$SCRIPT_DIR/ncs/v3.4.0}"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/build/at_client_k230_dual_uart}"
BOARD="${BOARD:-nrf9151dk/nrf9151/ns}"
APP="${APP:-$SCRIPT_DIR/at_client_k230}"
OVERLAY="${OVERLAY:-$SCRIPT_DIR/k230_dual_uart_pins.overlay}"

if [[ ! -d "$NCS_ROOT/zephyr" ]]; then
	echo "NCS workspace not found: $NCS_ROOT" >&2
	echo "Install it under this repository with:" >&2
	echo "  nrfutil sdk-manager install --install-dir \"$SCRIPT_DIR/ncs\" v3.4.0" >&2
	echo "or set NCS_ROOT=/path/to/ncs/v3.4.0" >&2
	exit 1
fi

nrfutil sdk-manager toolchain launch --ncs-version v3.4.0 \
	--chdir "$NCS_ROOT" \
	-- west build -p always \
	-b "$BOARD" \
	"$APP" \
	-d "$BUILD_DIR" \
	-- -DEXTRA_DTC_OVERLAY_FILE="$OVERLAY"

echo
echo "Build complete:"
find "$BUILD_DIR" -path '*/zephyr/tfm_merged.hex' -o -path '*/zephyr/zephyr.elf' | sort | sed 's/^/  /'
