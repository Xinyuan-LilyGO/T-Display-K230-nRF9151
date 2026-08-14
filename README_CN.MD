<div align="center" markdown="1">
  <img src=".github/LilyGo_logo.png" alt="LilyGo logo" width="100"/>
</div>

<h1 align = "center">🌟 T-Display K230 nRF9151 固件 🌟</h1>

[English](./README.MD) | [中文](./README_CN.MD)


这个仓库保存 LILYGO T-Display K230 项目当前使用的 nRF9151 固件源码、overlay、补丁和 K230 侧测试脚本

## 硬件连接

K230 侧：

```text
K230 GPIO2  -> nRF9151 使能 / 电源控制，高电平启用 nRF9151，低电平关闭 nRF9151
K230 GPIO28 -> nRF9151 UART1 RX, P0.26
K230 GPIO29 <- nRF9151 UART1 TX, P0.27
```

nRF9151 侧：

```text
UART1 TX1 = P0.27, 向 K230 返回 AT 响应
UART1 RX1 = P0.26, 接收 K230 AT 命令
UART2 TX2 = P0.29, 调试日志输出
UART2 RX2 = P0.28, 调试日志输入，目前可选
LED       = P0.23
波特率    = 115200 8N1
流控      = 禁用，无 RTS/CTS
```

K230 BSP 侧补丁在：

```text
bsp-patches/0061-riscv-dts-rm69a10-enable-uart3-nrf9151.patch
```

这个补丁启用 GPIO28/GPIO29 对应的 `/dev/ttyS3`，并将 GPIO2 配置为用户态可控制的 nRF9151 使能脚。

## 固件选项

仓库保留两个固件配置：

```text
serial_modem_k230/     推荐使用，基于 Nordic Serial LTE Modem
at_client_k230/        底层 AT 透传调试固件
```

K230 phone UI 的 Cellular app 应使用 `serial_modem_k230`。它包含 UI 需要的 LTE、SIM、GNSS、NMEA 和 LED 控制行为。

`at_client_k230` 只建议在底层串口和硬件 bring-up 时使用。

## AT 命令说明

- [K230 nRF9151 AT 命令说明](docs/AT_COMMANDS_CN.md)
- Nordic 官方 nRF91 AT Commands Reference Guide v0.7.1：
  <https://www.nordicsemi.com/-/media/Restricted/ProductKeys/L984675KPNS/nrf91atcommandsv071.pdf>

## 前置条件

先安装 Nordic nrfutil 工具, [点击我下载 nRFUtil](https://www.nordicsemi.com/Products/Development-tools/nRF-Util)。

```sh
# 按 Nordic 官方文档安装 nrfutil
nrfutil install sdk-manager
```

将 NCS v3.4.0 安装到本仓库内。构建脚本默认使用下面这个仓库相对路径：

```text
./ncs/v3.4.0
```

```sh
nrfutil sdk-manager install --install-dir "$PWD/ncs" v3.4.0
```

如果你的 NCS 已经安装在其他位置，可以通过 `NCS_ROOT` 覆盖：

```sh
export NCS_ROOT=/path/to/ncs/v3.4.0
```

Nordic Serial LTE Modem 已作为 git 子模块放在仓库中，这样每次构建都使用固定
源码版本：

```text
third_party/ncs-serial-modem
commit 13c80da97fe4d55ecb5a9745834d97be22821307
```

克隆仓库时建议直接拉取子模块：

```sh
git clone --recurse-submodules https://github.com/Xinyuan-LilyGO/T-Display-K230-nRF9151 t-display-k230-nrf9151
cd t-display-k230-nrf9151
```

如果克隆时没有拉取子模块：

```sh
git submodule update --init --recursive
```

## 编译 Serial LTE Modem

```sh
cd t-display-k230-nrf9151
./build_serial_modem.sh
```

默认输出：

```text
build/serial_modem_k230/zephyr/tfm_merged.hex
```

如果上游构建目录结构变化，可以用下面命令查找：

```sh
find build/serial_modem_k230 -path '*/zephyr/tfm_merged.hex' -o -path '*/zephyr/zephyr.hex' -o -path '*/zephyr/zephyr.elf'
```

K230 配置会对官方 Serial LTE Modem 源码应用这些补丁：

```text
serial_modem_k230/patches/0001-k230-gnss-nmea-urc-and-led.patch
serial_modem_k230/patches/0002-k230-optional-xdfu.patch
serial_modem_k230/patches/0003-k230-uart-diag.patch
serial_modem_k230/patches/0004-k230-gnss-nmea-urc-worker.patch
serial_modem_k230/patches/0005-k230-led-at-control.patch
```

关键行为：

- UART1 是 K230 AT 命令链路。
- UART2 是调试日志控制台。
- P0.23 默认常亮，可通过 AT 命令控制。
- GNSS 修复后 LED 变为约 300 ms 亮、700 ms 灭的一秒周期闪烁。
- `AT#XNMEA=0|1` 用于开关 AT UART 上的 NMEA URC 输出。
- SIM 检测前需要先执行 `AT+CFUN=1`，再执行 `AT+CPIN?` 等命令。
- `tfm_merged.hex` 包含 TF-M 和非安全侧应用，不包含 `mfw_nrf91x1_*.zip` 蜂窝 modem 固件更新。

## 编译 AT Client

```sh
cd t-display-k230-nrf9151
./build_at_client.sh
```

默认输出：

```text
build/at_client_k230_dual_uart/at_client_k230/zephyr/tfm_merged.hex
```

## 烧录

> [!IMPORTANT]
> 
> 1. 烧录时必须保持与K230主机的连接,K230侧必须将GPIO2设置为高电平
> 2. 烧录时只接**SWDIO**,**SWCLK**,**GND**三个Pin,不要接**3.3V**
> 3. 无论插不插SIM卡都可以烧录,烧录和SIM卡没有关系
>

- 将生成的 `tfm_merged.hex` 通过 nRF Connect Programmer、**J-Link**或者**DAPLink/CMSIS-DAP** 进行烧录,如果使用 **nRF Connect Programmer** 必须使用 **Jlink** 进行烧录
- 烧录的时候必须要在K230侧将K230 GPIO2设置为高电平打开nRF9151电源之后才能进行烧录
- 烧录接口必须拆开键盘面板才能看到**SWD**接口进行烧录,烧录时只接**SWDIO**,**SWCLK**,**GND**三个Pin即可,请不要接3V3电源到JLink或者其他下载器
- 下载接口如下图

  <img src="images/swd.png" alt="LilyGo" width="800"/>

- nRF Connect Programmer烧录演示(视频第二步写入**mfw_nrf91x1_2.0.4.zip**是不需要操作的,除非被全擦除了,或者写了其他的固件包覆盖才需要重新写LTE固件包)
  
  <video src="https://github.com/user-attachments/assets/668f1def-420b-4c83-ae40-9d57c0a985e4" controls width="100%"></video>

## K230 运行测试

烧录并给 nRF9151 上电后：

- P0.23 应显示固件运行状态。
- K230 应通过 `/dev/ttyS3` 访问 nRF9151。
- 串口参数是 `115200 8N1`，无硬件流控。

交互控制台：

```sh
scp k230_nrf9151_at_console.sh root@<k230-ip>:/root/
ssh root@<k230-ip>
TTY=/dev/ttyS3 /root/k230_nrf9151_at_console.sh
```

基础 SIM/LTE 测试：

```text
AT
AT+CMEE=1
AT+CFUN=1
AT%XSIM?
AT+CPIN?
AT+CIMI
AT+CGMR
```

检测到 SIM 时应类似：

```text
%XSIM: 1
+CPIN: READY
```

GNSS/NMEA 测试：

```text
AT#XNMEA=1
AT%XSYSTEMMODE=0,0,1,0
AT+CFUN=31
AT#XGNSS=1,0,0,0
```

## 目录说明

```text
at_client_k230/                 K230 AT Client Zephyr 应用
serial_modem_k230/              K230 Serial LTE Modem 配置和补丁
third_party/ncs-serial-modem/   Nordic Serial LTE Modem 上游子模块
bsp-patches/                    K230 Linux SDK UART3/GPIO2 设备树补丁
build_at_client.sh              AT Client 一键构建脚本
build_serial_modem.sh           Serial LTE Modem 一键构建脚本
k230_at_probe.sh                K230 侧自动 AT 探测脚本
k230_nrf9151_at_console.sh      K230 侧交互 AT 控制台
k230_dual_uart_pins.overlay     nRF9151 UART1/UART2/LED overlay
```

## 注意事项

- `mfw_nrf91x1_*.zip` 是 Nordic modem 固件，和 `tfm_merged.hex` 是两个东西；需要时用 Nordic 工具单独更新。
- 默认出厂已经烧录了 **[mfw_nrf91x1_2.0.4.zip](https://nsscprodmedia.blob.core.windows.net/prod/software-and-other-downloads/sip/nrf91x1-sip/nrf91x1-lte-modem-firmware/mfw_nrf91x1_2.0.4.zip)** SiP LTE 固件 
- 当前硬件只连接 TX/RX，必须关闭硬件流控。
- GPIO2 由 K230 app 和测试脚本控制。调 GNSS 时不要随意拉低 GPIO2，除非明确要重启模块。
- 如果要使用NTN卫星通讯功能，那么需要更新 [SiP NTN 固件底层包](https://www.nordicsemi.com/Products/nRF9151/Download)


## nRF9151 / nRF91x1 三种固件的区别

这三种固件的核心区别在于它们支持的**通信网络**和**功能**完全不同。简单来说，它们分别用于连接**卫星网络**、**地面蜂窝网络**和**DECT NR+ 本地网络**。

---

## 核心对比表格

| 特性                | **NTN 固件**                               | **LTE 固件**                           | **DECT NR+ 固件**                          |
| :------------------ | :----------------------------------------- | :------------------------------------- | :----------------------------------------- |
| **固件文件名**      | `mfw_nrf9151-ntn`                          | `mfw_nrf91x1`                          | `mfw-nr+_nrf91x1`                          |
| **核心网络**        | **非地面网络 (NTN)**，即**卫星通信**       | **地面蜂窝网络** (LTE-M / NB-IoT)      | **DECT NR+** (一种非蜂窝的本地无线技术)    |
| **主要功能**        | 支持 **NB-IoT NTN** (3GPP Rel-17) 卫星直连 | 标准 LTE-M/NB-IoT 蜂窝数据连接         | 专用 DECT NR+ 物理层 (PHY) 通信            |
| **GNSS (GPS)**      | **支持**                                   | **支持**                               | **不支持**                                 |
| **蜂窝网络 (LTE)**  | **支持** (作为补充)                        | **支持** (核心功能)                    | **不支持**                                 |
| **DECT NR+**        | **不支持**                                 | **不支持**                             | **支持** (核心功能)                        |
| **套接字 (Socket)** | **支持**                                   | **支持**                               | **不支持**                                 |
| **主要用途**        | 海洋、偏远地区等无地面网络覆盖的物联网应用 | 智慧城市、工业监控等常规蜂窝物联网应用 | 大规模、长距离、高可靠性的本地网状网络应用 |
| **获取方式**        | 官网免费下载 (Alpha版)                     | 官网免费下载                           | 需联系 Nordic 销售获取                     |


## 关键要点与差异详解

- **功能互斥，不可同时使用**  
  nRF9151 的调制解调器硬件虽然强大，但在同一时间**只能运行一种固件**。这意味着无法同时使用 LTE 和 DECT NR+，或同时使用 NTN 和 DECT NR+。

- **DECT NR+ 是“专用”模式**  
  选择 DECT NR+ 固件，相当于把 nRF9151 变成一个**专用的 DECT NR+ 电台**，它会**完全放弃**蜂窝网络和 GPS/GNSS 功能。

- **NTN 是 LTE 的“增强”模式**  
  `mfw_nrf9151-ntn` 固件可以看作是标准 LTE 固件的**一个特殊版本**。它在保留地面 LTE 和 GNSS 功能的基础上，额外增加了连接卫星网络的“超能力”。


## 如何选择？

- **选 NTN 固件**：如果你的设备需要在**海洋、沙漠、偏远山区**等完全没有地面蜂窝网络的地方工作。  
- **选 LTE 固件**：这是**最通用**的选择，如果你的设备在城市、乡村等有常规蜂窝网络覆盖的地方运行。  
- **选 DECT NR+ 固件**：如果你想利用 DECT NR+ 技术构建一个**私有的、大规模的本地网络**（如智能路灯、工业传感器网络），并且不需要蜂窝网络和 GPS 功能。


> [!IMPORTANT]
> 
> 默认出厂写入的固件是LTE 固件
> 