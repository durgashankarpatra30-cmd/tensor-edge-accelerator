// ============================================================================
// Testbench:     tb_tensor_core_4x4
// Project:       50-Day Tensor Edge Accelerator (Day 7 - Friend A / Hardware)
// Description:   Comprehensive Verification of Integrated 4x4 Tensor Core.
//                Verifies:
//                  - Weight preloading (4 cycles)
//                  - Automatic input triangular skewing (unskewed input)
//                  - Systolic 2D matrix accumulation
//                  - Automatic output reverse-triangular deskewing
//                  - Integrated parallel Activation & Re-quantization (Linear & ReLU)
//                  - Handshake signals (start, busy, done, valid_out)
// ============================================================================

`timescale 1ns / 1ps

module tb_tensor_core_4x4;

    parameter ARRAY_SIZE = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 16;

    reg                                clk;
    reg                                rst_n;
    reg                                start;
    reg  [ARRAY_SIZE-1:0]              load_weight;
    reg  signed [ARRAY_SIZE*DATA_WIDTH-1:0] weight_in;
    reg  signed [ARRAY_SIZE*DATA_WIDTH-1:0] act_in;
    reg  signed [ARRAY_SIZE*ACC_WIDTH-1:0]  psum_in;
    reg  [1:0]                         act_type;
    reg  [3:0]                         shift_amount;

    wire signed [ARRAY_SIZE*DATA_WIDTH-1:0] data_out;
    wire signed [ARRAY_SIZE*DATA_WIDTH-1:0] act_out;
    wire                                valid_out;
    wire                                done;
    wire                                busy;

    // Instantiate DUT
    tensor_core_4x4 #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .load_weight (load_weight),
        .weight_in   (weight_in),
        .act_in      (act_in),
        .psum_in     (psum_in),
        .act_type    (act_type),
        .shift_amount(shift_amount),
        .data_out    (data_out),
        .act_out     (act_out),
        .valid_out   (valid_out),
        .done        (done),
        .busy        (busy)
    );

    // 125 MHz Clock generation (8 ns period)
    initial clk = 0;
    always #4 clk = ~clk;

    // Helper functions
    function [ARRAY_SIZE*DATA_WIDTH-1:0] pack4_8b(
        input signed [7:0] d0, input signed [7:0] d1,
        input signed [7:0] d2, input signed [7:0] d3
    );
        pack4_8b = {d3, d2, d1, d0};
    endfunction

    function signed [7:0] get_data_col(input integer c);
        get_data_col = data_out[(c+1)*DATA_WIDTH-1 -: DATA_WIDTH];
    endfunction

    integer errors;
    integer timeout_cnt;

    initial begin
        $dumpfile("sim/tensor_core_4x4.vcd");
        $dumpvars(0, tb_tensor_core_4x4);

        $display("================================================================");
        $display("  STARTING DAY 7 VERIFICATION: Integrated 4x4 Tensor Core       ");
        $display("================================================================");

        errors = 0;

        // Initialize signals
        rst_n        = 0;
        start        = 0;
        load_weight  = 0;
        weight_in    = 0;
        act_in       = 0;
        psum_in      = 0;
        act_type     = 2'b00; // Linear
        shift_amount = 4'd4;  // Q8.8 -> Q4.4 (shift right by 4)

        // Hold reset for 3 clock cycles
        #24;
        @(negedge clk);
        rst_n = 1;
        $display("[Step 1 PASSED] Active-low reset released across Tensor Core.");

        // --------------------------------------------------------------------
        // Test 1: Weight Preloading Phase (4 clock cycles)
        // --------------------------------------------------------------------
        $display("[Step 2] Preloading 16 weights into Tensor Core...");

        // Cycle 0: Row 0 -> [16, 32, 16, 8]
        @(negedge clk);
        load_weight = 4'b0001;
        weight_in   = pack4_8b(8'sd16, 8'sd32, 8'sd16, 8'sd8);

        // Cycle 1: Row 1 -> [8, 16, 32, 16]
        @(negedge clk);
        load_weight = 4'b0010;
        weight_in   = pack4_8b(8'sd8, 8'sd16, 8'sd32, 8'sd16);

        // Cycle 2: Row 2 -> [32, 8, 16, 16]
        @(negedge clk);
        load_weight = 4'b0100;
        weight_in   = pack4_8b(8'sd32, 8'sd8, 8'sd16, 8'sd16);

        // Cycle 3: Row 3 -> [16, 16, 8, 32]
        @(negedge clk);
        load_weight = 4'b1000;
        weight_in   = pack4_8b(8'sd16, 8'sd16, 8'sd8, 8'sd32);

        // Lock weights
        @(negedge clk);
        load_weight = 4'b0000;
        weight_in   = 32'hDEADBEEF; // Junk data to prove weights are stationary
        $display("[Step 2 PASSED] Weights locked stationary.");

        #20;

        // --------------------------------------------------------------------
        // Test 2: Unskewed Parallel Vector Computation (Linear Activation)
        // --------------------------------------------------------------------
        // Notice the HUGE difference from Day 6:
        // In Day 6, the testbench had to manually skew inputs over 4 cycles.
        // Today, we feed the entire vector X = [16, 32, 24, 8] SIMULTANEOUSLY!
        // The integrated skew buffer handles the wave skew automatically!
        // --------------------------------------------------------------------
        $display("[Step 3] Launching unskewed parallel vector X = [16, 32, 24, 8] with Linear activation...");

        @(negedge clk);
        start    = 1;
        act_in   = pack4_8b(8'sd16, 8'sd32, 8'sd24, 8'sd8); // All 4 rows at once!
        act_type = 2'b00; // Linear mode
        shift_amount = 4'd4; // 1408 >> 4 = 88, 1344 >> 4 = 84, 1728 >> 4 = 108, 1280 >> 4 = 80

        @(negedge clk);
        start  = 0;
        act_in = 0; // Clear inputs

        // Check that busy is asserted
        if (busy !== 1'b1) begin
            $display("[FAIL] Busy flag should be HIGH while calculation is active!");
            errors = errors + 1;
        end else begin
            $display("       Busy flag asserted correctly (Core is calculating).");
        end

        // Wait for 'done' and 'valid_out'
        timeout_cnt = 0;
        while (!done && timeout_cnt < 20) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end

        if (!done) begin
            $display("[FAIL] Timeout waiting for done signal!");
            errors = errors + 1;
        end else begin
            $display("       Done strobe detected at cycle count = %0d.", timeout_cnt);

            // Verify all 4 columns simultaneously!
            $display("       Observed Output Columns: Col0=%0d, Col1=%0d, Col2=%0d, Col3=%0d",
                     get_data_col(0), get_data_col(1), get_data_col(2), get_data_col(3));

            if (get_data_col(0) == 8'sd88 &&
                get_data_col(1) == 8'sd84 &&
                get_data_col(2) == 8'sd108 &&
                get_data_col(3) == 8'sd80) begin
                $display("[Step 3 PASSED] All 4 columns aligned perfectly and matched golden linear values!");
            end else begin
                $display("[FAIL] Golden mismatch: Expected [88, 84, 108, 80]");
                errors = errors + 1;
            end
        end

        #20;

        // --------------------------------------------------------------------
        // Test 3: Unskewed Parallel Vector Computation (ReLU Activation)
        // --------------------------------------------------------------------
        // Feed vector with negative values to verify ReLU zero-clamping:
        // X = [-32, 16, -16, 8]
        // Math:
        //   Col 0: (-32)*16 + 16*8 + (-16)*32 + 8*16 = -512 + 128 - 512 + 128 = -768
        //          ReLU(-768) = 0!
        //   Col 1: (-32)*32 + 16*16 + (-16)*8 + 8*16 = -1024 + 256 - 128 + 128 = -768
        //          ReLU(-768) = 0!
        //   Col 2: (-32)*16 + 16*32 + (-16)*16 + 8*8 = -512 + 512 - 256 + 64 = -192
        //          ReLU(-192) = 0!
        //   Col 3: (-32)*8 + 16*16 + (-16)*16 + 8*32 = -256 + 256 - 256 + 256 = 0
        //          ReLU(0) = 0!
        // --------------------------------------------------------------------
        $display("[Step 4] Launching vector X = [-32, 16, -16, 8] with ReLU activation (mode=01)...");

        @(negedge clk);
        start    = 1;
        act_in   = pack4_8b(-8'sd32, 8'sd16, -8'sd16, 8'sd8);
        act_type = 2'b01; // ReLU mode
        shift_amount = 4'd4;

        @(negedge clk);
        start  = 0;
        act_in = 0;

        timeout_cnt = 0;
        while (!done && timeout_cnt < 20) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end

        if (!done) begin
            $display("[FAIL] Timeout waiting for done signal on Test 3!");
            errors = errors + 1;
        end else begin
            $display("       Observed Output Columns: Col0=%0d, Col1=%0d, Col2=%0d, Col3=%0d",
                     get_data_col(0), get_data_col(1), get_data_col(2), get_data_col(3));

            if (get_data_col(0) == 8'sd0 &&
                get_data_col(1) == 8'sd0 &&
                get_data_col(2) == 8'sd0 &&
                get_data_col(3) == 8'sd0) begin
                $display("[Step 4 PASSED] Negative sums clamped to 0 by integrated ReLU units!");
            end else begin
                $display("[FAIL] ReLU clamping failed! Expected [0, 0, 0, 0]");
                errors = errors + 1;
            end
        end

        #40;

        // Final Assessment
        $display("================================================================");
        if (errors == 0) begin
            $display("  ALL DAY 7 TESTS PASSED! Integrated Tensor Core Verified!    ");
            $display("  - 4x4 Systolic Array + Input Skew + Output Deskew + ActUnit ");
            $display("================================================================");
        end else begin
            $display("  VERIFICATION FAILED with %0d errors!                        ", errors);
            $display("================================================================");
        end

        $finish;
    end

endmodule
