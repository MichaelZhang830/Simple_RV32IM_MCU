#ifndef SOC_LIB_H
#define SOC_LIB_H

#include <stdint.h>

#define SOC_CLK_FREQ_HZ      50000000u
#define SOC_CYCLES_PER_US    (SOC_CLK_FREQ_HZ / 1000000u)

#define SOC_FB_WIDTH         480
#define SOC_FB_HEIGHT        270
#define SOC_VRAM_BASE        0x00010000u

#define SOC_MMIO_LED         0x00000400u
#define SOC_MMIO_GPIO_DIR    0x00000404u
#define SOC_MMIO_GPIO_OUT    0x00000408u
#define SOC_MMIO_GPIO_IN     0x0000040Cu
#define SOC_MMIO_GPIO_EN     0x00000410u
#define SOC_MMIO_UART_TX     0x00000414u
#define SOC_MMIO_UART_RX     0x00000418u
#define SOC_MMIO_KEY1        0x0000041Cu
#define SOC_MMIO_KEY2        0x00000420u

void soc_delay_cycles(uint32_t cycles);
void delayus(uint32_t us);

void soc_led_write(uint32_t value);
void soc_gpio_enable(uint32_t mask);
void soc_gpio_set_dir(uint32_t dir);
void soc_gpio_write(uint32_t value);
uint32_t soc_gpio_read(void);
uint32_t soc_key1_read(void);
uint32_t soc_key2_read(void);

void soc_uart_write_byte(uint8_t byte);
void soc_uart_write_str(const char *text);
int  soc_uart_try_read_byte(uint8_t *byte);
int  soc_uart_read_line(char *buffer, uint32_t capacity);

void soc_vram_put_pixel(int x, int y, uint8_t color);
void soc_vram_fill_rect(int x, int y, int width, int height, uint8_t color);
void soc_vram_clear(uint8_t color);

#endif /* SOC_LIB_H */