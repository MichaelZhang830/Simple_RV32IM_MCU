#include <stdint.h>

#define FB_W 480
#define FB_H 270

#define VRAM_BASE 0x00010000u
#define LED_REG   0x00000400u
#define KEY1_REG  0x0000041Cu
#define KEY2_REG  0x00000420u

#define COLOR_BLACK 0x00u
#define COLOR_WHITE 0xFFu
#define COLOR_CYAN  0x1Fu

#define PADDLE_W 72
#define PADDLE_H 6
#define PADDLE_Y (FB_H - 10)
#define PADDLE_SPEED 3
#define BALL_SIZE 6

#define BALL_STEP_NUM 4u
#define BALL_STEP_DEN 9u
#define LED_HEARTBEAT_MASK 0x2u
#define LED_HIT_MASK 0x3u
#define LED_BASE_MASK 0x1u
#define FRAME_DELAY_CYCLES (45u * 1000u)

static volatile uint8_t *const vram = (volatile uint8_t *)(uintptr_t)VRAM_BASE;
static volatile uint32_t *const led = (volatile uint32_t *)(uintptr_t)LED_REG;
static volatile uint32_t *const key1 = (volatile uint32_t *)(uintptr_t)KEY1_REG;
static volatile uint32_t *const key2 = (volatile uint32_t *)(uintptr_t)KEY2_REG;

typedef struct {
    int x;
    int y;
    int w;
    int h;
} Rect;

typedef struct {
    int x;
    int y;
    int vx;
    int vy;
    int size;
} Ball;

typedef struct {
    int x;
    int y;
    int w;
    int h;
} Paddle;

typedef struct {
    Paddle paddle;
    Ball ball;
    uint32_t tick;
    uint32_t ball_phase;
} GameState;

static void delay_cycles(uint32_t cycles)
{
    while (cycles-- != 0u) {
        __asm__ volatile("nop");
    }
}

static int key_pressed(uint32_t value)
{
    return (value & 0x1u) == 0u;
}

static int clamp_int(int value, int min_v, int max_v)
{
    if (value < min_v) {
        return min_v;
    }
    if (value > max_v) {
        return max_v;
    }
    return value;
}

static void fill_rect(int x, int y, int w, int h, uint8_t color)
{
    int x0 = x;
    int y0 = y;
    int x1 = x + w;
    int y1 = y + h;

    if (w <= 0 || h <= 0) {
        return;
    }

    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > FB_W) x1 = FB_W;
    if (y1 > FB_H) y1 = FB_H;

    for (int yy = y0; yy < y1; ++yy) {
        uint32_t row = (uint32_t)yy * FB_W;
        for (int xx = x0; xx < x1; ++xx) {
            vram[row + (uint32_t)xx] = color;
        }
    }
}

static void clear_fb(uint8_t color)
{
    for (uint32_t i = 0; i < (uint32_t)(FB_W * FB_H); ++i) {
        vram[i] = color;
    }
}

static void draw_frame_border(void)
{
    fill_rect(0, 0, FB_W, 1, COLOR_CYAN);
    fill_rect(0, FB_H - 1, FB_W, 1, COLOR_CYAN);
    fill_rect(0, 0, 1, FB_H, COLOR_CYAN);
    fill_rect(FB_W - 1, 0, 1, FB_H, COLOR_CYAN);
}

static void init_game(GameState *game)
{
    game->paddle.x = (FB_W - PADDLE_W) / 2;
    game->paddle.y = PADDLE_Y;
    game->paddle.w = PADDLE_W;
    game->paddle.h = PADDLE_H;

    game->ball.x = FB_W / 2;
    game->ball.y = FB_H / 3;
    game->ball.vx = 2;
    game->ball.vy = 2;
    game->ball.size = BALL_SIZE;

    game->tick = 0u;
    game->ball_phase = 0u;
}

static void update_led_heartbeat(uint32_t tick)
{
    if ((tick & 0x3FFu) == 0u) {
        *led ^= LED_HEARTBEAT_MASK;
    }
}

static void update_paddle(Paddle *paddle)
{
    int right_pressed = key_pressed(*key1);
    int left_pressed = key_pressed(*key2);

    if (right_pressed && !left_pressed) {
        paddle->x += PADDLE_SPEED;
    } else if (left_pressed && !right_pressed) {
        paddle->x -= PADDLE_SPEED;
    }

    paddle->x = clamp_int(paddle->x, 0, FB_W - paddle->w);
}

static int should_advance_ball(GameState *game)
{
    game->ball_phase = (game->ball_phase + 1u) % BALL_STEP_DEN;
    return game->ball_phase < BALL_STEP_NUM;
}

static void reset_ball(Ball *ball)
{
    ball->x = FB_W / 2;
    ball->y = FB_H / 3;
    ball->vx = 2;
    ball->vy = 2;
}

static void update_ball(GameState *game)
{
    Ball *ball = &game->ball;
    const Paddle *paddle = &game->paddle;

    ball->x += ball->vx;
    ball->y += ball->vy;

    if (ball->x <= 0) {
        ball->x = 0;
        ball->vx = -ball->vx;
    } else if (ball->x >= (FB_W - ball->size)) {
        ball->x = FB_W - ball->size;
        ball->vx = -ball->vx;
    }

    if (ball->y <= 0) {
        ball->y = 0;
        ball->vy = -ball->vy;
    }

    if (ball->y + ball->size >= paddle->y) {
        int ball_mid = ball->x + (ball->size / 2);
        int in_paddle = (ball_mid >= paddle->x) && (ball_mid < (paddle->x + paddle->w));

        if (in_paddle && ball->vy > 0) {
            ball->y = paddle->y - ball->size;
            ball->vy = -ball->vy;
            *led = LED_HIT_MASK;
        } else if (ball->y + ball->size >= FB_H) {
            reset_ball(ball);
            *led = LED_BASE_MASK;
        }
    }
}

static void render_frame(Rect old_paddle, Rect old_ball, const GameState *game)
{
    fill_rect(old_paddle.x, old_paddle.y, old_paddle.w, old_paddle.h, COLOR_BLACK);
    fill_rect(old_ball.x, old_ball.y, old_ball.w, old_ball.h, COLOR_BLACK);
    fill_rect(game->paddle.x, game->paddle.y, game->paddle.w, game->paddle.h, COLOR_WHITE);
    fill_rect(game->ball.x, game->ball.y, game->ball.size, game->ball.size, COLOR_WHITE);
    draw_frame_border();
}

int main(void)
{
    GameState game;
    Rect old_paddle;
    Rect old_ball;

    *led = LED_BASE_MASK;

    clear_fb(COLOR_BLACK);
    draw_frame_border();
    init_game(&game);
    fill_rect(game.paddle.x, game.paddle.y, game.paddle.w, game.paddle.h, COLOR_WHITE);
    fill_rect(game.ball.x, game.ball.y, game.ball.size, game.ball.size, COLOR_WHITE);

    for (;;) {
        old_paddle.x = game.paddle.x;
        old_paddle.y = game.paddle.y;
        old_paddle.w = game.paddle.w;
        old_paddle.h = game.paddle.h;

        old_ball.x = game.ball.x;
        old_ball.y = game.ball.y;
        old_ball.w = game.ball.size;
        old_ball.h = game.ball.size;

        update_led_heartbeat(game.tick);
        update_paddle(&game.paddle);
        if (should_advance_ball(&game)) {
            update_ball(&game);
        }
        render_frame(old_paddle, old_ball, &game);

        ++game.tick;
        delay_cycles(FRAME_DELAY_CYCLES);
    }
}
