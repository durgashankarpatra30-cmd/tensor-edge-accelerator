`timescale 1ns / 1ps

module tb_activation_unit;

    reg  signed [31:0] tb_in_data;
    reg         [1:0]  tb_mode_i;
    reg         [3:0]  tb_scale_shift_i;

    wire signed [7:0]  tb_out_data;
    wire               tb_overflow_o;

    // Instantiate Unit Under Test
    activation_unit #(
        .in_width(32),
        .out_width(8)
    ) dut (
        .in_data       (tb_in_data),
        .mode_i        (tb_mode_i),
        .scale_shift_i (tb_scale_shift_i),
        .out_data      (tb_out_data),
        .overflow_o    (tb_overflow_o)
    );

    integer errors = 0;

    initial begin
        $dumpfile("sim/activation_unit.vcd");
        $dumpvars(0, tb_activation_unit);

        $display("===============================================================");
        $display("   DAY 3 ACTIVATION & RE-QUANTIZATION UNIT COMPREHENSIVE TEST  ");
        $display("===============================================================");

        // -------------------------------------------------------------
        // TEST 1: LINEAR MODE (mode_i = 2'b00, scale_shift = 0)
        // -------------------------------------------------------------
        tb_mode_i = 2'b00; tb_scale_shift_i = 4'd0;
        
        tb_in_data = 32'sd50; #10;
        if (tb_out_data !== 8'sd50 || tb_overflow_o !== 1'b0) begin
            $display("FAIL Test 1A: Linear (+50) -> Got %0d, expected +50", tb_out_data);
            errors = errors + 1;
        end

        tb_in_data = -32'sd50; #10;
        if (tb_out_data !== -8'sd50 || tb_overflow_o !== 1'b0) begin
            $display("FAIL Test 1B: Linear (-50) -> Got %0d, expected -50", tb_out_data);
            errors = errors + 1;
        end

        // -------------------------------------------------------------
        // TEST 2: RELU MODE (mode_i = 2'b01, scale_shift = 0)
        // -------------------------------------------------------------
        tb_mode_i = 2'b01; tb_scale_shift_i = 4'd0;

        tb_in_data = 32'sd75; #10;
        if (tb_out_data !== 8'sd75 || tb_overflow_o !== 1'b0) begin
            $display("FAIL Test 2A: ReLU (+75) -> Got %0d, expected +75", tb_out_data);
            errors = errors + 1;
        end

        tb_in_data = -32'sd75; #10; // Must be killed to 0!
        if (tb_out_data !== 8'sd0 || tb_overflow_o !== 1'b0) begin
            $display("FAIL Test 2B: ReLU (-75) -> Got %0d, expected 0", tb_out_data);
            errors = errors + 1;
        end

        // -------------------------------------------------------------
        // TEST 3: LEAKY RELU MODE (mode_i = 2'b10, scale_shift = 0)
        // -------------------------------------------------------------
        tb_mode_i = 2'b10; tb_scale_shift_i = 4'd0;

        tb_in_data = 32'sd64; #10;
        if (tb_out_data !== 8'sd64 || tb_overflow_o !== 1'b0) begin
            $display("FAIL Test 3A: LeakyReLU (+64) -> Got %0d, expected +64", tb_out_data);
            errors = errors + 1;
        end

        tb_in_data = -32'sd64; #10; // -64 >>> 3 = -8!
        if (tb_out_data !== -8'sd8 || tb_overflow_o !== 1'b0) begin
            $display("FAIL Test 3B: LeakyReLU (-64) -> Got %0d, expected -8", tb_out_data);
            errors = errors + 1;
        end

        // -------------------------------------------------------------
        // TEST 4: RE-QUANTIZATION SCALING (Your 3,000 example!)
        // -------------------------------------------------------------
        // Input = +3,000, scale_shift_i = 5 (divide by 32) -> 3000 / 32 = +93!
        tb_mode_i = 2'b00; tb_scale_shift_i = 4'd5; tb_in_data = 32'sd3000; #10;
        if (tb_out_data !== 8'sd93 || tb_overflow_o !== 1'b0) begin
            $display("FAIL Test 4: Re-Quantize (+3000 >> 5) -> Got %0d, expected +93", tb_out_data);
            errors = errors + 1;
        end

        // -------------------------------------------------------------
        // TEST 5: GIANT SPIKE SATURATION CLAMPING (+10,000 and -10,000)
        // -------------------------------------------------------------
        // +10,000 >> 5 = +312 -> Clamps to +127 with overflow = 1!
        tb_mode_i = 2'b00; tb_scale_shift_i = 4'd5; tb_in_data = 32'sd10000; #10;
        if (tb_out_data !== 8'sd127 || tb_overflow_o !== 1'b1) begin
            $display("FAIL Test 5A: Positive Saturation -> Got %0d, ovf=%b", tb_out_data, tb_overflow_o);
            errors = errors + 1;
        end

        // -10,000 >> 5 = -312 -> Clamps to -128 with overflow = 1!
        tb_mode_i = 2'b00; tb_scale_shift_i = 4'd5; tb_in_data = -32'sd10000; #10;
        if (tb_out_data !== -8'sd128 || tb_overflow_o !== 1'b1) begin
            $display("FAIL Test 5B: Negative Saturation -> Got %0d, ovf=%b", tb_out_data, tb_overflow_o);
            errors = errors + 1;
        end

        // -------------------------------------------------------------
        // TEST 6: INVALID MODE WARNING
        // -------------------------------------------------------------
        tb_mode_i = 2'b11; tb_in_data = 32'sd10; #10;

        $display("---------------------------------------------------------------");
        if (errors == 0) begin
            $display("PASS: All Activation, Scaling & Saturation tests passed 100%%!");
        end else begin
            $display("FAIL: Found %0d test errors.", errors);
        end
        $display("===============================================================");
        $finish;
    end

endmodule
