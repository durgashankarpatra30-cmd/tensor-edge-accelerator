#include "npu_driver.h"

npu_status_t npu_init(npu_dev_t *dev, const npu_transport_t *transport){
    if (dev == NULL || transport == NULL) {
        return NPU_STATUS_INVALID_ARG;
    }

    dev->transport = *transport;
    dev->current_act = NPU_ACT_PASSTHROUGH;
    dev->current_shift = 0;
    dev->timeout_us = NPU_DEFAULT_TIMEOUT_US;
    dev->is_initialized = true;
    dev->inferences_count = 0;
    dev->timeout_count = 0;

    return NPU_STATUS_OK;
}

npu_status_t npu_reset(npu_dev_t *dev) {
    if (dev == NULL || !dev->is_initialized) {
        return NPU_STATUS_INVALID_ARG;
    }

    dev->current_act = NPU_ACT_PASSTHROUGH;
    dev->current_shift = 0;
    dev->inferences_count = 0;
    dev->timeout_count = 0;

    return NPU_STATUS_OK;
}

npu_status_t npu_configure(npu_dev_t *dev, npu_act_type_t act_type, uint8_t shift_amount) {
    if (dev == NULL || !dev->is_initialized) {
        return NPU_STATUS_INVALID_ARG;
    }

    if(shift_amount>15){
        return NPU_STATUS_INVALID_ARG;
    }
    uint32_t config_word =(uint32_t)act_type | ((uint32_t)shift_amount << 2);
    bool send_success = dev->transport.send_packet(config_word, 0x00, true);
    if (!send_success) {
        return NPU_STATUS_TIMEOUT;
    }
    dev->current_act = act_type;
    dev->current_shift = shift_amount;

    return NPU_STATUS_OK;

    
}

npu_status_t npu_load_weights_4x4(npu_dev_t *dev, const int8_t weights[NPU_NUM_WEIGHTS]) {
    if (dev == NULL || !dev->is_initialized || weights == NULL) {
        return NPU_STATUS_INVALID_ARG;
    }

    for(uint32_t i=0; i<NPU_ARRAY_DIM; i++){
        uint32_t packed_weights =npu_pack_int8x4(weights[i*4], weights[i*4+1], weights[i*4+2], weights[i*4+3]);
        bool is_last =(i==NPU_ARRAY_DIM-1);
        bool send_sucess = dev->transport.send_packet(packed_weights, 0x01, is_last);
        if (!send_sucess) {
            return NPU_STATUS_TIMEOUT;
        }
    }
    return NPU_STATUS_OK;
}


/* ============================================================================
 * 5. Execute Inference Vector with 50 us Hardware Watchdog Protection
 * ============================================================================
 */
npu_status_t npu_infer_vector(npu_dev_t *dev, const int8_t act_in[NPU_ARRAY_DIM], int8_t act_out[NPU_ARRAY_DIM]) {
    /* Safety Check */
    if ((dev == NULL) || (!dev->is_initialized) || (act_in == NULL) || (act_out == NULL)) {
        return NPU_STATUS_INVALID_ARG;
    }

    /* 1. Pack 4 input activations into one 32-bit word */
    uint32_t act_word = npu_pack_int8x4(act_in[0], act_in[1], act_in[2], act_in[3]);

    /* 2. Send activation beat: TUSER = 0x02 (ACTIVATION), TLAST = 1 */
    bool sent = dev->transport.send_packet(act_word, NPU_TUSER_ACTIVATION, true);
    if (!sent) {
        return NPU_STATUS_TIMEOUT;
    }

    /* 3. Wait for hardware output with 50 us Watchdog Protection */
    uint32_t start_time = 0;
    if (dev->transport.get_time_us != NULL) {
        start_time = dev->transport.get_time_us();
    }

    uint32_t rx_data = 0;
    bool rx_last = false;
    bool got_result = false;

    while (!got_result) {
        got_result = dev->transport.recv_packet(&rx_data, &rx_last);
        if (got_result) {
            break;
        }

        /* Check Watchdog Timeout */
        if (dev->transport.get_time_us != NULL) {
            uint32_t elapsed = dev->transport.get_time_us() - start_time;
            if (elapsed >= dev->timeout_us) {
                dev->timeout_count++;
                return NPU_STATUS_TIMEOUT;
            }
        }
    }

    /* 4. Unpack 32-bit hardware output into 4 signed INT8 results */
    npu_unpack_int8x4(rx_data, &act_out[0], &act_out[1], &act_out[2], &act_out[3]);

    /* 5. Update telemetry counter */
    dev->inferences_count++;

    return NPU_STATUS_OK;
}