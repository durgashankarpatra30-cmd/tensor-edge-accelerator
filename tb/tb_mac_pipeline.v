`timescale 1ns / 1ps

module tb_mac_pipeline;

    // 1. Testbench signals
    reg                 tb_clk;
    reg                 tb_rst_n;
    reg                 tb_clear_acc_i;
    reg                 tb_acc_en_i;
    reg  signed [7:0]   tb_ai;
    reg  signed [7:0]   tb_bi;
    wire signed [31:0]  tb_acc_o;
    wire signed [7:0]   tb_result_saturation_o;
    wire                tb_overflow_o;
    wire                tb_valid_o;

    // 2. Connect your mac_pipeline module (Device Under Test)
    mac_pipeline #(
        .Q(7),
        .N(8)
    ) dut (
        .clk                   (tb_clk),
        .rst_n                 (tb_rst_n),
        .clear_acc_i           (tb_clear_acc_i),
        .acc_en_i              (tb_acc_en_i),
        .ai                    (tb_ai),
        .bi                    (tb_bi),
        .acc_o                 (tb_acc_o),
        .result_saturation_o   (tb_result_saturation_o),
        .overflow_o            (tb_overflow_o),
        .valid_o               (tb_valid_o)
    );

    always #5 tb_clk = ~tb_clk;

    initial begin
        $dumpfile("sim/mac_pipeline.vcd");
        $dumpvars(0, tb_mac_pipeline);

        // 1. Reset all 3 workers
        tb_clk = 0; tb_rst_n = 0; tb_clear_acc_i = 0; tb_acc_en_i = 0; tb_ai = 0; tb_bi = 0;
        #20;
        tb_rst_n = 1;

        // 2. Test Your Supermarket Example (32 -> 48 -> 0)
        @(posedge tb_clk); tb_acc_en_i = 1; tb_ai = 8'sd64;  tb_bi = 8'sd64;  // Item 1: (64*64)>>>7 = +32
        @(posedge tb_clk); tb_acc_en_i = 1; tb_ai = 8'sd64;  tb_bi = 8'sd32;  // Item 2: (64*32)>>>7 = +16 (Total = 48)
        @(posedge tb_clk); tb_acc_en_i = 0; tb_clear_acc_i = 1;               // Clear Total back to 0!
        @(posedge tb_clk); tb_clear_acc_i = 0;

        // 3. Test Positive Saturation (Add +126 twice -> 252, clamps to +127!)
        @(posedge tb_clk); tb_acc_en_i = 1; tb_ai = 8'sd127; tb_bi = 8'sd127; // +126
        @(posedge tb_clk); tb_acc_en_i = 1; tb_ai = 8'sd127; tb_bi = 8'sd127; // +126 + 126 = +252 -> saturates to +127!
        @(posedge tb_clk); tb_acc_en_i = 0;

        // Wait for pipeline stages to finish and print results
        #50;
        $display("---------------------------------------------------------------");
        $display("Final 32-bit Accumulator (tb_acc_o)      = %0d (Expected: 252)", tb_acc_o);
        $display("Saturated 8-bit Output (tb_result_sat_o) = %0d (Expected: 127)", tb_result_saturation_o);
        $display("Hardware Overflow Flag (tb_overflow_o)   = %0b   (Expected: 1)", tb_overflow_o);
        $display("---------------------------------------------------------------");
        if (tb_acc_o == 252 && tb_result_saturation_o == 127 && tb_overflow_o == 1)
            $display("PASS: Day 2 3-Stage MAC Pipeline & Saturation Verified 100%%!");
        else
            $display("FAIL: Check pipeline values.");
        $finish;
    end

endmodule
