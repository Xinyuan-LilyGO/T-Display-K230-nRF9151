# Flashing the nRF9151 with pyOCD (CMSIS-DAP)

The main README lists **DAPLink/CMSIS-DAP** as a supported programmer but only
documents the nRF Connect Programmer path, which requires a J-Link. This is the
CMSIS-DAP procedure, end to end.

It needs no J-Link and no nRF9151 DK — only a CMSIS-DAP probe, three wires, and
pyOCD. The host may be x86_64 or arm64: pyOCD is pure Python, so an arm64 Linux
box works even though Nordic ships no arm64 `nrfutil` for *building* the image.

Verified on an early unit (keyboard panel opened for SWD access), flashing
`tfm_merged.hex` built from this repository, with a Raspberry Pi Debug Probe on
an arm64 Debian 13 host, pyOCD 0.45.1.

## 1. Probe and wiring

Any CMSIS-DAP probe works. On the Raspberry Pi Debug Probe, use the **"D"
port** — the 3-pin JST-SH debug connector, not the **"U"** UART port next to
it. Both enumerate identically over USB, and a cable in "U" gives a probe that
`pyocd list` finds and a target that never answers.

Three wires is all SWD needs; the connector carries no reset pin and none is
required — pyOCD's `nrf91` target unlocks through CTRL-AP.

| Debug Probe "D" pin | Signal | nRF9151 pad |
|---|---|---|
| 1 (orange) | SC / SWCLK | `SWCLK` |
| 2 (black)  | GND        | `GND`   |
| 3 (yellow) | SD / SWDIO | `SWDIO` |

The pads are the row of eight unpopulated through-holes beside the module,
shown in [`images/swd.png`](../images/swd.png). Counting from the **square**
pad they are `RST`, `SWCLK`, `SWDIO`, `GND`, `3.3V`, `RXD2`, `TXD2`, `VDO-5V`.

> [!IMPORTANT]
> As the main README states, connect **only SWDIO, SWCLK and GND**. Do not
> connect `3.3V` or `VDO-5V` — the module is powered by the docked K230.
>
> Do not use the 8-pin **Expansion** header on the bottom edge. It also reads
> `SWDIO SWCLK RST`, but it belongs to the **nRF52840**.

The pads sit deep in the chassis on units whose casing has no battery-
compartment access hole. Spring-loaded probes in a frame (the kind sold for car
ECU work) hold contact where clips cannot reach.

## 2. Power the target first

**GPIO2 on the K230 must be high before the nRF9151 will answer SWD at all.**
Keep the module docked to the K230 and let the K230 boot fully — the
application raises GPIO2, and nothing on the SWD side can substitute for it.

If the module is unpowered, pyOCD reports:

```
Error while initing target: SWD/JTAG communication failure (Unexpected ACK '0');
check USB cable, reduce debugger clock
```

The message suggests a signal-integrity problem, but on this board it almost
always means GPIO2 is low. Reducing the clock does not help — the same wiring
fails identically at 2 MHz and at 100 kHz, then succeeds at 1 MHz once the
module has power.

## 3. Install pyOCD

```sh
python3 -m venv ~/.venvs/pyocd        # distros with PEP 668 need a venv
~/.venvs/pyocd/bin/pip install pyocd  # 0.44.1 or newer
```

`nrf91` is a **builtin** target, so no CMSIS-Pack needs to be installed.

On Linux, add your user to the group your udev rules grant the probe (commonly
`plugdev`) rather than running pyOCD as root.

## 4. Check before writing

```sh
pyocd list                                  # the probe is enumerated
pyocd cmd -t nrf91 -M attach -c 'status'    # the target answers, read-only
```

A healthy target prints its core state, for example:

```
Core 0 (None):  Sleeping [Nonsecure]
```

`Skipping CoreSight discovery for AHB-AP#1 because it is disabled` is expected
on nRF91 and is not an error. If `status` cannot connect, fix that before
erasing — nothing has been written yet.

## 5. Flash

```sh
pyocd erase -t nrf91 --chip
pyocd flash -t nrf91 --frequency 1000000 build/serial_modem_k230/zephyr/tfm_merged.hex
pyocd reset -t nrf91
```

`--chip` erases the application core only and **leaves the modem firmware
intact**; `AT+CGMR` still reports the same `mfw_nrf91x1_*` afterwards. Prefer it
over a `recover`/mass erase, which is what makes a modem firmware rewrite
necessary in the first place.

1 MHz is a good default with the longer leads a probe frame needs; the bundled
cable is fine at higher speeds.

## 6. Verify from the K230

```sh
ssh root@<k230-ip>
TTY=/dev/ttyS3 /root/k230_nrf9151_at_console.sh
```

| Command | Expected after flashing |
|---|---|
| `AT#XSMVER` | `"<version>","<ncs>","k230-dual-uart-nmea"` |
| `AT#XCLAC`  | includes `AT#XGNSS`, `AT#XGNSSDEL`, `AT#XNMEA` |
| `AT#XGNSS?` | answers, e.g. `#XGNSS: 1,0` |
| `AT+CGMR`   | unchanged `mfw_nrf91x1_*` |

> [!NOTE]
> This firmware answers **`AT#XSMVER`**. The stock Nordic Serial LTE Modem
> answers `AT#XSLMVER`, and after a successful flash that older name returns
> `+CME ERROR: 0` — which reads like a failed flash if you check for it.

If a reply comes back empty or interleaved with the previous command's output,
drain the port and accumulate for a couple of seconds before reading. Short
fixed-delay reads truncate longer replies such as `AT#XCLAC`.

## 7. If the modem firmware was erased

pyOCD implements modem firmware update over the same CMSIS-DAP probe:

```sh
pyocd cmd -t nrf91 -c 'nrf91-update-modem-fw -f mfw_nrf91x1_2.0.4.zip'
```

*(Present in pyOCD 0.45.1; not exercised in this procedure, because the
`--chip` erase above leaves the modem alone and it never needed rewriting.)*
It is included because it means a CMSIS-DAP probe can recover the modem too, so
a J-Link is not required for any step on this board.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Unexpected ACK '0'`, at any clock | GPIO2 low / module unpowered; or the cable is in the probe's "U" port |
| `pyocd list` empty | Probe USB or udev permissions, not the target |
| Flash succeeds, no AT response | Check P0.23. If it indicates the application is running, the fault is downstream — see the main README on the UART path to the pogo-pin board — and re-erasing will not help |
| `AT#XSLMVER` returns `+CME ERROR: 0` | Expected. Use `AT#XSMVER` |
