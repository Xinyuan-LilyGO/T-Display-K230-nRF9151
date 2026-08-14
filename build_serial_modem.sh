#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/serial_modem_k230"

NCS_ROOT="${NCS_ROOT:-$SCRIPT_DIR/ncs/v3.4.0}"
UPSTREAM_SRC="${UPSTREAM_SRC:-$SCRIPT_DIR/third_party/ncs-serial-modem}"
WORK_SRC="${WORK_SRC:-$SCRIPT_DIR/work/serial_modem_k230_src}"
SYSBUILD="${SYSBUILD:-0}"
if [[ "$SYSBUILD" == "1" ]]; then
	BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/build/serial_modem_k230_sys}"
else
	BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/build/serial_modem_k230}"
fi
BOARD="${BOARD:-nrf9151dk/nrf9151/ns}"
CONF="${CONF:-$PROFILE_DIR/k230_serial_modem.conf}"
OVERLAY="${OVERLAY:-$PROFILE_DIR/k230_serial_modem.overlay}"

if [[ ! -d "$NCS_ROOT/zephyr" ]]; then
	echo "NCS workspace not found: $NCS_ROOT" >&2
	echo "Install it under this repository with:" >&2
	echo "  nrfutil sdk-manager install --install-dir \"$SCRIPT_DIR/ncs\" v3.4.0" >&2
	echo "or set NCS_ROOT=/path/to/ncs/v3.4.0" >&2
	exit 1
fi

if [[ ! -d "$UPSTREAM_SRC/app" ]]; then
	echo "Serial Modem source not found: $UPSTREAM_SRC/app" >&2
	echo "Initialize the bundled submodule first:" >&2
	echo "  git submodule update --init --recursive third_party/ncs-serial-modem" >&2
	exit 1
fi

if [[ -d "$WORK_SRC" ]]; then
	mv "$WORK_SRC" "${WORK_SRC}.old.$(date +%Y%m%d_%H%M%S)"
fi
mkdir -p "$WORK_SRC"
rsync -a --delete --exclude '.git' "$UPSTREAM_SRC"/ "$WORK_SRC"/

find "$WORK_SRC/app" -type f \( -name '*.c' -o -name '*.h' -o -name 'Kconfig' -o -name 'CMakeLists.txt' -o -name '*.conf' -o -name '*.overlay' \) \
	-exec perl -pi -e 's/\r$//' {} +

for patch_file in "$PROFILE_DIR"/patches/*.patch; do
	[[ -f "$patch_file" ]] || continue
	patch -d "$WORK_SRC" -p1 < "$patch_file"
done

if [[ -d "$BUILD_DIR" ]]; then
	mv "$BUILD_DIR" "${BUILD_DIR}.old.$(date +%Y%m%d_%H%M%S)"
fi

west_args=(west build --no-sysbuild -p always)
if [[ "$SYSBUILD" == "1" ]]; then
	west_args=(west build -p always)
elif [[ "${NO_SYSBUILD:-1}" == "0" ]]; then
	echo "NO_SYSBUILD=0 is deprecated for this script; use SYSBUILD=1 instead."
	west_args=(west build -p always)
else
	west_args=(west build --no-sysbuild -p always)
fi

cmake_args=(
	-DZEPHYR_EXTRA_MODULES="$WORK_SRC"
	-DEXTRA_CONF_FILE="$CONF"
	-DEXTRA_DTC_OVERLAY_FILE="$OVERLAY"
)

# The standalone Serial Modem tree can repeatedly trigger CMake regeneration
# with NCS v3.4.0/Zephyr 4.4 when built outside its original west workspace.
# Suppressing regeneration keeps the generated Kconfig inputs stable after the
# fresh configure done by "west build -p always".
if [[ "$SYSBUILD" != "1" ]]; then
	cmake_args+=(-DCMAKE_SUPPRESS_REGENERATION=ON)
fi

nrfutil sdk-manager toolchain launch --ncs-version v3.4.0 \
	--chdir "$NCS_ROOT" \
	-- "${west_args[@]}" \
	-b "$BOARD" \
	"$WORK_SRC/app" \
	-d "$BUILD_DIR" \
	-- \
	"${cmake_args[@]}"

echo
echo "Serial Modem build complete:"
find "$BUILD_DIR" \
	-path '*/zephyr/tfm_merged.hex' -o \
	-path '*/zephyr/merged.hex' -o \
	-path '*/zephyr/zephyr.hex' -o \
	-path '*/zephyr/zephyr.elf' -o \
	-name 'merged.hex' \
	| sort | sed 's/^/  /'
