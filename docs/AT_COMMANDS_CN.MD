<div align="center" markdown="1">
  <img src="../.github/LilyGo_logo.png" alt="LilyGo logo" width="100"/>
</div>

<h1 align = "center">🌟 nRF9151 AT 命令说明 🌟</h1>

[English](./AT_COMMANDS.MD) | [中文](./AT_COMMANDS_CN.MD)

当前固件基于 Nordic Serial LTE Modem，K230 通过 UART 访问 nRF91 标准 modem
AT 命令，同时增加少量 K230 项目自定义命令。

## 官方参考

- nRF91 AT Commands Reference Guide v0.7.1：
  <https://www.nordicsemi.com/-/media/Restricted/ProductKeys/L984675KPNS/nrf91atcommandsv071.pdf>

- Serial LTE Modem 上游文档：
  `third_party/ncs-serial-modem/doc/app/`

标准 modem 命令请以 Nordic 官方 PDF 为准，例如 `AT+CFUN`、`AT+CPIN?`、
`AT+CEREG?`、`AT+COPS?`、`%XSYSTEMMODE`、`%XSIM?`、`%XMONITOR` 和 GNSS
相关命令。

## K230 UART 链路

```text
K230 /dev/ttyS3 <-> nRF9151 UART1
波特率：115200
格式：8N1
硬件流控：关闭
换行：根据主机工具可使用 CR、LF 或 CRLF
```

UART2 保留为调试日志串口。

## 基础连通性测试

```text
AT
AT+CMEE=1
AT+CGMR
AT+CFUN=1
AT%XSIM?
AT+CPIN?
AT+CIMI
```

SIM 存在时应看到类似：

```text
%XSIM: 1
+CPIN: READY
```

## LTE 注册

```text
AT+CFUN=1
AT+CEREG?
AT+COPS?
AT+CGDCONT?
AT+CGPADDR
```

如果 SIM 卡需要指定 APN，请按运营商要求用 `AT+CGDCONT` 设置 PDP context。

## GNSS 和 NMEA

K230 配置启用了 GNSS，并增加本项目使用的 NMEA URC 开关。

```text
AT#XNMEA=1
AT%XSYSTEMMODE=0,0,1,0
AT+CFUN=31
AT#XGNSS=1,0,0,0
```

NMEA 会通过下面的 URC 输出：

```text
#XGNSSNMEA: <NMEA sentence>
```

关闭 NMEA URC：

```text
AT#XNMEA=0
```

## K230 自定义命令

### `AT#XNMEA=<0|1>`

开启或关闭 AT UART 上的 NMEA URC。

```text
AT#XNMEA=1
OK
```

查询支持范围：

```text
AT#XNMEA=?
#XNMEA: (0,1)
OK
```

### `AT#XK230LED=<0|1|2>`

控制 nRF9151 底板 `P0.23` LED。

```text
0 = 关闭
1 = 常亮
2 = 自动
```

自动模式下，GNSS 未修复前 LED 常亮；GNSS 修复后变为每秒约亮 300 ms 的闪烁。

查询当前状态：

```text
AT#XK230LED?
#XK230LED: <mode>,<gnss_fix_seen>
OK
```

查询支持范围：

```text
AT#XK230LED=?
#XK230LED: (0,1,2)
OK
```

## 已启用的 Serial LTE Modem 功能

当前 K230 配置启用了：

```text
CONFIG_SM_SMS=y
CONFIG_SM_MQTTC=y
CONFIG_SM_HTTPC=y
CONFIG_SM_COAPC=y
CONFIG_SM_GNSS=y
CONFIG_SM_NRF_CLOUD=y
CONFIG_NRF_CLOUD_AGNSS=y
```

也就是 SMS、MQTT、HTTP、CoAP、GNSS、nRF Cloud A-GNSS 相关命令组已编译进固件。
这些命令的详细语法由 Nordic 在 `third_party/ncs-serial-modem/doc/app/` 中维护。

## DFU / UART 更新状态

当前 K230 no-sysbuild 固件有意关闭 UART DFU：

```text
CONFIG_SM_XDFU=n
```

`AT#XDFUINIT`、`AT#XDFUWRITE`、`AT#XDFUAPPLY` 当前由 stub 接管，会返回不支持。
