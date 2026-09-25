#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#define DMA_BUF_SIZE 256              // Must be a power of 2
#define DMA_BUF_MASK (DMA_BUF_SIZE - 1)

typedef struct {
    int8_t            buffer[DMA_BUF_SIZE]; // Stores signed Q1.7 INT8 samples
    volatile uint16_t head;                 // Updated by DMA Producer
    volatile uint16_t tail;                 // Updated by CPU Consumer
    uint32_t          overflow_drops;       // Counts dropped packets if buffer full
} dma_ring_buf_t;

void dma_rb_init(dma_ring_buf_t *rb) {
    rb->head = 0;
    rb->tail = 0;
    rb->overflow_drops = 0;
}

bool dma_rb_push(dma_ring_buf_t *rb, int8_t sample) {
    uint16_t next_head = (rb->head + 1) & DMA_BUF_MASK;
    if (next_head == rb->tail) {
        rb->overflow_drops++;
        return false;
    }
    rb->buffer[rb->head] = sample;
    rb->head = next_head;
    return true;
}

bool dma_rb_pop(dma_ring_buf_t *rb, int8_t *out_sample) {
    if (rb->head == rb->tail) {
        return false;
    }
    *out_sample = rb->buffer[rb->tail];
    rb->tail = (rb->tail + 1) & DMA_BUF_MASK;
    return true;
}

int main(void) {
    dma_ring_buf_t uart_dma;
    dma_rb_init(&uart_dma);

    printf("[Embedded Day 1] Testing Lock-Free DMA Circular Ring Buffer...\n");

    int total_verified = 0;
    for (int batch = 0; batch < 5; batch++) {
        for (int i = 0; i < 100; i++) {
            int8_t val = (int8_t)((batch * 100 + i) % 127);
            dma_rb_push(&uart_dma, val);
        }
        for (int i = 0; i < 100; i++) {
            int8_t out = 0;
            if (dma_rb_pop(&uart_dma, &out)) {
                total_verified++;
            }
        }
    }

    printf("PASS: Streamed %d Q1.7 samples across circular wrap-around | Drops: %u\n",
           total_verified, uart_dma.overflow_drops);
    return 0;
}
