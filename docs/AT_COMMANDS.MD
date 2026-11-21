<div align="center" markdown="1">
  <img src="../.github/LilyGo_logo.png" alt="LilyGo logo" width="100"/>
</div>

<h1 align = "center">🌟 nRF9151 AT Command Guide 🌟</h1>

[English](./AT_COMMANDS.MD) | [中文](./AT_COMMANDS_CN.MD)

This firmware is based on Nordic Serial LTE Modem and keeps the standard nRF91
modem AT command set available on the K230 UART link.

## Official References

- nRF91 AT Commands Reference Guide v0.7.1:
  <https://www.nordicsemi.com/-/media/Restricted/ProductKeys/L984675KPNS/nrf91atcommandsv071.pdf>
- Serial LTE Modem upstream documentation:
  `third_party/ncs-serial-modem/doc/app/`

The PDF is the authoritative reference for standard modem commands such as
`AT+CFUN`, `AT+CPIN?`, `AT+CEREG?`, `AT+COPS?`, `%XSYSTEMMODE`, `%XSIM?`,
`%XMONITOR`, and GNSS commands.

## K230 UART Link

```text
K230 /dev/ttyS3 <-> nRF9151 UART1
Baud: 115200
Format: 8N1
Flow control: disabled
Line ending: CR, LF, or CRLF depending on the host tool
```

UART2 is reserved for debug logs.

## Basic Smoke Test

```text
AT
AT+CMEE=1
AT+CGMR
AT+CFUN=1
AT%XSIM?
AT+CPIN?
AT+CIMI
```

Expected SIM-present result:

```text
%XSIM: 1
+CPIN: READY
```

## LTE Registration

```text
AT+CFUN=1
AT+CEREG?
AT+COPS?
AT+CGDCONT?
AT+CGPADDR
```

If the SIM requires a specific APN, configure PDP context with `AT+CGDCONT`
according to the carrier requirements.

## GNSS And NMEA

The K230 profile enables GNSS and adds a local NMEA URC switch.

```text
AT#XNMEA=1
AT%XSYSTEMMODE=0,0,1,0
AT+CFUN=31
AT#XGNSS=1,0,0,0
```

NMEA URCs are emitted as:

```text
#XGNSSNMEA: <NMEA sentence>
```

Disable NMEA URCs:

```text
AT#XNMEA=0
```

## K230 Custom Commands

### `AT#XNMEA=<0|1>`

Enable or disable NMEA URCs on the AT UART.

```text
AT#XNMEA=1
OK
```

Query support:

```text
AT#XNMEA=?
#XNMEA: (0,1)
OK
```

### `AT#XK230LED=<0|1|2>`

Control the nRF9151 board LED on `P0.23`.

```text
0 = off
1 = on
2 = auto
```

In auto mode, the LED stays on before GNSS fix. After GNSS fix, it blinks with
about 300 ms on time per second.

Query current state:

```text
AT#XK230LED?
#XK230LED: <mode>,<gnss_fix_seen>
OK
```

Supported values:

```text
AT#XK230LED=?
#XK230LED: (0,1,2)
OK
```

## Serial LTE Modem Features Enabled

The K230 profile currently enables:

```text
CONFIG_SM_SMS=y
CONFIG_SM_MQTTC=y
CONFIG_SM_HTTPC=y
CONFIG_SM_COAPC=y
CONFIG_SM_GNSS=y
CONFIG_SM_NRF_CLOUD=y
CONFIG_NRF_CLOUD_AGNSS=y
CONFIG_NRF_PROVISIONING=y
```

This means SMS, MQTT, HTTP, CoAP, GNSS, nRF Cloud A-GNSS, and nRF Device
Provisioning command groups are compiled in. A-GNSS still requires valid nRF
Cloud credentials and an active `AT#XNRFCLOUD=1` session; provisioning installs
those credentials for a claimed device but is not itself a GNSS assistance mode.
The exact command syntax is maintained by Nordic in the Serial LTE Modem
documentation under `third_party/ncs-serial-modem/doc/app/`.

### nRF Cloud provisioning and A-GNSS

The K230 build loads both `k230_serial_modem.conf` and
`serial_modem_k230/nrf-device-provisioning.conf`. This enables the host-driven
provisioning flow:

```text
AT#XNRFPROV=?
#XNRFPROV
OK
AT%ATTESTTOKEN
AT#XNRFPROV
```

After the device is claimed in nRF Cloud, handle `#XNRFPROV: 1` by taking LTE
offline with `AT+CFUN=4`, then handle `#XNRFPROV: 2` by restoring LTE with
`AT+CFUN=1`. A status of `#XNRFPROV: 0` means provisioning completed or there
were no pending commands. Then connect to nRF Cloud before starting assisted
GNSS:

```text
AT#XNRFCLOUD=1
AT#XGNSS=1,1,0,120
```

If credentials were provisioned by another process, A-GNSS can work without
running `AT#XNRFPROV`; unassisted GNSS remains available with
`AT#XGNSS=1,0,...`.

## DFU / UART Update Status

UART DFU commands are intentionally disabled in the current K230 no-sysbuild
firmware:

```text
CONFIG_SM_XDFU=n
```

`AT#XDFUINIT`, `AT#XDFUWRITE`, and `AT#XDFUAPPLY` are replaced by a stub and
return not supported. 
