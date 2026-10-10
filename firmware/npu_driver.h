#ifndef NPU_DRIVER_H
#define NPU_DRIVER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 1. AXI4-Stream Packet Identifiers */
#define NPU_TUSER_CONFIG        0x00U  /* 2'b00: Runtime Configuration */
#define NPU_TUSER_WEIGHT        0x01U  /* 2'b01: Weight Matrix Stream  */
#define NPU_TUSER_ACTIVATION    0x02U  /* 2'b10: Activation Vector     */

#define NPU_ARRAY_DIM           4U     /* 4x4 Systolic Array           */
#define NPU_NUM_WEIGHTS         16U    /* 4x4 = 16 INT8 weights        */
#define NPU_DEFAULT_TIMEOUT_US  50U    /* 50 us hardware watchdog      */

/* 2. Return Status Codes */
typedef enum {
    NPU_STATUS_OK               = 0,
    NPU_STATUS_BUSY             = 1,
    NPU_STATUS_TIMEOUT          = 2,
    NPU_STATUS_INVALID_ARG      = 3,
    NPU_STATUS_NOT_INITIALIZED  = 4
} npu_status_t;

/* 3. Activation Functions */
typedef enum {
    NPU_ACT_PASSTHROUGH         = 0x00,
    NPU_ACT_RELU                = 0x01,
    NPU_ACT_LEAKY_RELU          = 0x02,
    NPU_ACT_SIGMOID             = 0x03
} npu_act_type_t;

/* 4. Hardware Transport Callbacks */
typedef struct {
    bool (*send_packet)(uint32_t tdata, uint8_t tuser, bool tlast);
    bool (*recv_packet)(uint32_t *tdata, bool *tlast);
    uint32_t (*get_time_us)(void);
} npu_transport_t;

/* 5. Device Handle */
typedef struct {
    npu_transport_t transport;
    npu_act_type_t  current_act;
    uint8_t         current_shift;
    uint32_t        timeout_us;
    bool            is_initialized;
    uint32_t        inferences_count;
    uint32_t        timeout_count;
} npu_dev_t;

/* 6. Public API Prototypes */
npu_status_t npu_init(npu_dev_t *dev, const npu_transport_t *transport);
npu_status_t npu_configure(npu_dev_t *dev, npu_act_type_t act_type, uint8_t shift_amount);
npu_status_t npu_load_weights_4x4(npu_dev_t *dev, const int8_t weights[NPU_NUM_WEIGHTS]);
npu_status_t npu_infer_vector(npu_dev_t *dev, const int8_t act_in[NPU_ARRAY_DIM], int8_t act_out[NPU_ARRAY_DIM]);
npu_status_t npu_reset(npu_dev_t *dev);

/* 7. Utility Packing Functions */
static inline uint32_t npu_pack_int8x4(int8_t b0, int8_t b1, int8_t b2, int8_t b3) {
    return (((uint32_t)(uint8_t)b0)       ) |
           (((uint32_t)(uint8_t)b1) << 8  ) |
           (((uint32_t)(uint8_t)b2) << 16 ) |
           (((uint32_t)(uint8_t)b3) << 24 );
}

static inline void npu_unpack_int8x4(uint32_t word, int8_t *b0, int8_t *b1, int8_t *b2, int8_t *b3) {
    if (b0) *b0 = (int8_t)(word & 0xFFU);
    if (b1) *b1 = (int8_t)((word >> 8) & 0xFFU);
    if (b2) *b2 = (int8_t)((word >> 16) & 0xFFU);
    if (b3) *b3 = (int8_t)((word >> 24) & 0xFFU);
}

#ifdef __cplusplus
}
#endif

#endif /* NPU_DRIVER_H */