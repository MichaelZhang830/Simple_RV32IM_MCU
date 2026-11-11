#include "soc_lib.h"

static volatile uint32_t *const soc_led_reg      = (volatile uint32_t *)(uintptr_t)SOC_MMIO_LED;
static volatile uint32_t *const soc_gpio_dir_reg = (volatile uint32_t *)(uintptr_t)SOC_MMIO_GPIO_DIR;
static volatile uint32_t *const soc_gpio_out_reg = (volatile uint32_t *)(uintptr_t)SOC_MMIO_GPIO_OUT;
static volatile uint32_t *const soc_gpio_in_reg  = (volatile uint32_t *)(uintptr_t)SOC_MMIO_GPIO_IN;
static volatile uint32_t *const soc_gpio_en_reg  = (volatile uint32_t *)(uintptr_t)SOC_MMIO_GPIO_EN;
static volatile uint32_t *const soc_uart_tx_reg  = (volatile uint32_t *)(uintptr_t)SOC_MMIO_UART_TX;
static volatile uint32_t *const soc_uart_rx_reg  = (volatile uint32_t *)(uintptr_t)SOC_MMIO_UART_RX;
static volatile uint8_t  *const soc_vram8        = (volatile uint8_t *)(uintptr_t)SOC_VRAM_BASE;

void soc_delay_cycles(uint32_t cycles)
{
    while (cycles-- != 0u) {
        __asm__ volatile("nop");
    }
}

void delayus(uint32_t us)
{
    while (us-- != 0u) {
        soc_delay_cycles(SOC_CYCLES_PER_US);
    }
}

void soc_led_write(uint32_t value)
{
    *soc_led_reg = value;
}

void soc_gpio_enable(uint32_t mask)
{
    *soc_gpio_en_reg = mask;
}

void soc_gpio_set_dir(uint32_t dir)
{
    *soc_gpio_dir_reg = dir;
}

void soc_gpio_write(uint32_t value)
{
    *soc_gpio_out_reg = value;
}

uint32_t soc_gpio_read(void)
{
    return *soc_gpio_in_reg;
}

uint32_t soc_key1_read(void)
{
    return (uint32_t)(*(((volatile uint32_t *)(uintptr_t)SOC_MMIO_KEY1)) & 0x1u);
}

uint32_t soc_key2_read(void)
{
    return (uint32_t)(*(((volatile uint32_t *)(uintptr_t)SOC_MMIO_KEY2)) & 0x1u);
}

void soc_uart_write_byte(uint8_t byte)
{
    while ((*soc_uart_tx_reg & 0x1u) != 0u) {
        /* Wait for the TX MMIO port to go idle. */
    }

    *soc_uart_tx_reg = (uint32_t)byte;
}

void soc_uart_write_str(const char *text)
{
    if (text == 0) {
        return;
    }

    while (*text != '\0') {
        if (*text == '\n') {
            soc_uart_write_byte((uint8_t)'\r');
        }
        soc_uart_write_byte((uint8_t)*text++);
    }
}

int soc_uart_try_read_byte(uint8_t *byte)
{
    uint32_t value = *soc_uart_rx_reg;

    if ((value & 0x00000100u) == 0u) {
        return 0;
    }

    if (byte != 0) {
        *byte = (uint8_t)(value & 0xFFu);
    }

    return 1;
}

int soc_uart_read_line(char *buffer, uint32_t capacity)
{
    uint32_t length = 0u;
    uint8_t byte;

    if (buffer == 0 || capacity == 0u) {
        return -1;
    }

    for (;;) {
        if (!soc_uart_try_read_byte(&byte)) {
            continue;
        }

        if (byte == (uint8_t)'\r') {
            continue;
        }

        if (byte == (uint8_t)'\n') {
            break;
        }

        if (length + 1u < capacity) {
            buffer[length++] = (char)byte;
        }
    }

    buffer[length] = '\0';
    return (int)length;
}

void soc_vram_put_pixel(int x, int y, uint8_t color)
{
    if ((unsigned)x < SOC_FB_WIDTH && (unsigned)y < SOC_FB_HEIGHT) {
        soc_vram8[(uint32_t)y * SOC_FB_WIDTH + (uint32_t)x] = color;
    }
}

void soc_vram_fill_rect(int x, int y, int width, int height, uint8_t color)
{
    int x0 = x;
    int y0 = y;
    int x1 = x + width;
    int y1 = y + height;

    if (width <= 0 || height <= 0) {
        return;
    }

    if (x0 < 0) {
        x0 = 0;
    }
    if (y0 < 0) {
        y0 = 0;
    }
    if (x1 > SOC_FB_WIDTH) {
        x1 = SOC_FB_WIDTH;
    }
    if (y1 > SOC_FB_HEIGHT) {
        y1 = SOC_FB_HEIGHT;
    }

    for (int yy = y0; yy < y1; ++yy) {
        uint32_t row = (uint32_t)yy * SOC_FB_WIDTH;
        for (int xx = x0; xx < x1; ++xx) {
            soc_vram8[row + (uint32_t)xx] = color;
        }
    }
}

void soc_vram_clear(uint8_t color)
{
    soc_vram_fill_rect(0, 0, SOC_FB_WIDTH, SOC_FB_HEIGHT, color);
}
