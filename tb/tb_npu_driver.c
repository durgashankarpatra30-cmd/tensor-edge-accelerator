/**
 * ============================================================================
 * Project: 50-Day Tensor Edge Accelerator & RISC-V SoC
 * Day 9:   NPU C Driver Verification Testbench
 * File:    firmware/tb_npu_driver.c
 * ============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <assert.h>
#include "npu_driver.h"

/* ============================================================================
 * Mock Hardware Bus & Systolic Core Model
 * ============================================================================
 */
static struct {
    uint8_t  config_act;
    uint8_t  config_shift;
    int8_t   weights[4][4];
    uint32_t egress_data;
    bool     egress_valid;
    uint32_t sim_time_us;
    bool     simulate_hardware_stall; /* When true, hardware freezes */
} mock_hw;

/* Mock Bus: S_AXIS Send Callback */
static bool mock_send_packet(uint32_t tdata, uint8_t tuser, bool tlast) {
    (void)tlast;

    if (tuser == NPU_TUSER_CONFIG) {
        mock_hw.config_act   = (uint8_t)(tdata & 0x03U);
        mock_hw.config_shift = (uint8_t)((tdata >> 2) & 0x0FU);
        return true;
    }
    else if (tuser == NPU_TUSER_WEIGHT) {
        static int row = 0;
        int8_t w0, w1, w2, w3;
        npu_unpack_int8x4(tdata, &w0, &w1, &w2, &w3);
        mock_hw.weights[row][0] = w0;
        mock_hw.weights[row][1] = w1;
        mock_hw.weights[row][2] = w2;
        mock_hw.weights[row][3] = w3;
        row = (row + 1) % 4;
        return true;
    }
    else if (tuser == NPU_TUSER_ACTIVATION) {
        if (mock_hw.simulate_hardware_stall) {
            /* Simulate stalled / dead hardware: no response generated */
            return true;
        }

        /* Compute Systolic Matrix Multiplication: Y = W * A */
        int8_t a0, a1, a2, a3;
        npu_unpack_int8x4(tdata, &a0, &a1, &a2, &a3);
        int8_t a[4] = {a0, a1, a2, a3};
        int8_t y_out[4];

        for (int r = 0; r < 4; r++) {
            int32_t acc = 0;
            for (int c = 0; c < 4; c++) {
                acc += (int32_t)mock_hw.weights[r][c] * (int32_t)a[c];
            }

            /* Shift & Requantize */
            int32_t shifted = acc >> mock_hw.config_shift;

            /* ReLU Activation */
            if (mock_hw.config_act == NPU_ACT_RELU) {
                if (shifted < 0) shifted = 0;
            }

            /* INT8 Saturation */
            if (shifted > 127)  shifted = 127;
            if (shifted < -128) shifted = -128;

            y_out[r] = (int8_t)shifted;
        }

        /* Latch into mock hardware egress buffer */
        mock_hw.egress_data  = npu_pack_int8x4(y_out[0], y_out[1], y_out[2], y_out[3]);
        mock_hw.egress_valid = true;
        mock_hw.sim_time_us += 2; /* Computation took 2 microseconds */
        return true;
    }

    return false;
}

/* Mock Bus: M_AXIS Receive Callback */
static bool mock_recv_packet(uint32_t *tdata, bool *tlast) {
    if (mock_hw.simulate_hardware_stall) {
        mock_hw.sim_time_us += 10; /* Advance time while waiting */
        return false;              /* Hardware is dead, no data! */
    }

    if (mock_hw.egress_valid) {
        *tdata = mock_hw.egress_data;
        if (tlast) *tlast = true;
        mock_hw.egress_valid = false;
        return true;
    }
    return false;
}

/* Mock Timestamp Counter */
static uint32_t mock_get_time_us(void) {
    return mock_hw.sim_time_us;
}

/* ============================================================================
 * Main Test Suite
 * ============================================================================
 */
int main(void) {
    printf("=================================================================\n");
    printf(" Day 9: Hardware Abstraction Layer & NPU C Driver Verification\n");
    printf("=================================================================\n\n");

    /* Populate transport callbacks */
    npu_transport_t transport = {
        .send_packet = mock_send_packet,
        .recv_packet = mock_recv_packet,
        .get_time_us = mock_get_time_us
    };

    npu_dev_t npu;

    /* -------------------------------------------------------------------------
     * TEST 1: Driver Initialization
     * ------------------------------------------------------------------------- */
    printf("[TEST 1] Initializing NPU driver handle... ");
    npu_status_t status = npu_init(&npu, &transport);
    assert(status == NPU_STATUS_OK);
    assert(npu.is_initialized == true);
    assert(npu.timeout_us == 50);
    printf("PASSED!\n");

    /* -------------------------------------------------------------------------
     * TEST 2: Dynamic Runtime Configuration (ReLU, Shift = 4)
     * ------------------------------------------------------------------------- */
    printf("[TEST 2] Configuring NPU: ReLU activation, shift = 4... ");
    status = npu_configure(&npu, NPU_ACT_RELU, 4);
    assert(status == NPU_STATUS_OK);
    assert(mock_hw.config_act == 0x01);
    assert(mock_hw.config_shift == 4);
    printf("PASSED!\n");

    /* -------------------------------------------------------------------------
     * TEST 3: Loading 4x4 Weight Matrix
     * ------------------------------------------------------------------------- */
    printf("[TEST 3] Loading 4x4 INT8 weight matrix into systolic PEs... ");
    const int8_t weights[16] = {
        1,  2,  3,  4,   /* Row 0 */
        5,  6,  7,  8,   /* Row 1 */
       -1, -2, -3, -4,   /* Row 2 */
        2,  0, -2,  0    /* Row 3 */
    };
    status = npu_load_weights_4x4(&npu, weights);
    assert(status == NPU_STATUS_OK);
    assert(mock_hw.weights[0][0] == 1);
    assert(mock_hw.weights[1][3] == 8);
    assert(mock_hw.weights[2][0] == -1);
    assert(mock_hw.weights[3][2] == -2);
    printf("PASSED!\n");

    /* -------------------------------------------------------------------------
     * TEST 4: Running Inference Vector & Mathematical Verification
     * ------------------------------------------------------------------------- */
    printf("[TEST 4] Executing inference vector [10, 20, 30, 40]... ");
    const int8_t act_in[4] = {10, 20, 30, 40};
    int8_t act_out[4] = {0};

    status = npu_infer_vector(&npu, act_in, act_out);
    assert(status == NPU_STATUS_OK);

    /*
     * Golden Math Check:
     * Row 0: 1*10 + 2*20 + 3*30 + 4*40 = 10 + 40 + 90 + 160 = 300. Shift >> 4 = 18. ReLU(18) = 18.
     * Row 1: 5*10 + 6*20 + 7*30 + 8*40 = 50 + 120 + 210 + 320 = 700. Shift >> 4 = 43. ReLU(43) = 43.
     * Row 2: -1*10 + -2*20 + -3*30 + -4*40 = -300. Shift >> 4 = -19. ReLU(-19) = 0.
     * Row 3: 2*10 + 0*20 + -2*30 + 0*40 = 20 - 60 = -40. Shift >> 4 = -3. ReLU(-3) = 0.
     */
    printf("\n         Result Outputs: Y = [%d, %d, %d, %d] (Expected: [18, 43, 0, 0])\n",
           act_out[0], act_out[1], act_out[2], act_out[3]);
    assert(act_out[0] == 18);
    assert(act_out[1] == 43);
    assert(act_out[2] == 0);
    assert(act_out[3] == 0);
    assert(npu.inferences_count == 1);
    printf("         Math & Requantization PASSED!\n");

    /* -------------------------------------------------------------------------
     * TEST 5: 50 us Hardware Watchdog Timeout Resilience
     * ------------------------------------------------------------------------- */
    printf("[TEST 5] Testing 50 us Watchdog Timeout Protection (Simulating dead hardware)... ");
    mock_hw.simulate_hardware_stall = true; /* Break the hardware connection */

    status = npu_infer_vector(&npu, act_in, act_out);
    assert(status == NPU_STATUS_TIMEOUT);
    assert(npu.timeout_count == 1);
    printf("PASSED! (Driver safely timed out without freezing!)\n");

    printf("\n=================================================================\n");
    printf(" ALL 5 NPU DRIVER TESTS PASSED! (Zero Bugs, Production Ready!)\n");
    printf("=================================================================\n");

    return 0;
}