#include <stdint.h>

#include "soc_lib.h"

#define GPIO_ENABLE_MASK 0x00000FFFu
#define GPIO_DIRECTION    0x00000555u
#define GPIO_INPUT_MASK   0x00000AAAu

static int key_pressed(uint32_t value)
{
    return ((value & 0x1u) == 0u);
}

int main(void)
{
    uint32_t heartbeat = 0u;
    uint32_t key2_prev = 1u;
    uint32_t led0 = 0u;

    soc_gpio_enable(GPIO_ENABLE_MASK);
    soc_gpio_set_dir(GPIO_DIRECTION);
    soc_gpio_write(0u);
    soc_led_write(0u);

    for (;;) {
        uint32_t key2 = soc_key2_read();

        if (!key_pressed(key2_prev) && key_pressed(key2)) {
            led0 ^= 1u;
        }
        key2_prev = key2;

        soc_gpio_write((soc_gpio_read() & GPIO_INPUT_MASK) >> 1);

        if ((++heartbeat % 1000u) == 0u) {
            uint32_t led = led0 ? 0x1u : 0x0u;
            led ^= 0x2u;
            soc_led_write(led);
        }

        delayus(1000u);
    }
}
