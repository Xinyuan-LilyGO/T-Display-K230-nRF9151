/*
 * Copyright (c) 2018 Nordic Semiconductor ASA
 *
 * SPDX-License-Identifier: LicenseRef-Nordic-5-Clause
 */

#include <zephyr/kernel.h>
#include <stdio.h>
#include <string.h>
#include <modem/nrf_modem_lib.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/drivers/clock_control.h>
#include <zephyr/drivers/clock_control/nrf_clock_control.h>

#define RUN_LED_NODE DT_ALIAS(k230_run_led)

#if DT_NODE_HAS_STATUS(RUN_LED_NODE, okay)
static const struct gpio_dt_spec run_led = GPIO_DT_SPEC_GET(RUN_LED_NODE, gpios);

static void k230_run_led_thread(void *arg1, void *arg2, void *arg3)
{
	ARG_UNUSED(arg1);
	ARG_UNUSED(arg2);
	ARG_UNUSED(arg3);

	if (!gpio_is_ready_dt(&run_led)) {
		printk("K230 run LED GPIO is not ready\n");
		return;
	}

	if (gpio_pin_configure_dt(&run_led, GPIO_OUTPUT_INACTIVE) != 0) {
		printk("K230 run LED GPIO configure failed\n");
		return;
	}

	while (true) {
		gpio_pin_set_dt(&run_led, 1);
		k_sleep(K_MSEC(300));
		gpio_pin_set_dt(&run_led, 0);
		k_sleep(K_MSEC(700));
	}
}

K_THREAD_DEFINE(k230_run_led_tid, 512, k230_run_led_thread,
		NULL, NULL, NULL, 7, 0, 0);
#endif

#if defined(CONFIG_CLOCK_CONTROL_NRF)
/* To strictly comply with UART timing, enable external XTAL oscillator. */
void enable_xtal(void)
{
	struct onoff_manager *clk_mgr;
	static struct onoff_client cli = {};

	clk_mgr = z_nrf_clock_control_get_onoff(CLOCK_CONTROL_NRF_SUBSYS_HF);
	sys_notify_init_spinwait(&cli.notify);
	(void)onoff_request(clk_mgr, &cli);
}
#endif /* CONFIG_CLOCK_CONTROL_NRF */

int main(void)
{
	int err;

	printk("K230 nRF9151 AT host started\n");

	err = nrf_modem_lib_init();
	if (err) {
		printk("Modem library initialization failed, error: %d\n", err);
		return 0;
	}

#if defined(CONFIG_CLOCK_CONTROL_NRF)
	enable_xtal();
#endif /* CONFIG_CLOCK_CONTROL_NRF */

	printk("K230 nRF9151 AT host ready\n");

	return 0;
}
