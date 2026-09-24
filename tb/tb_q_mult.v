`timescale 1ns / 1ps

module tb_q_mult;

    // 1. Testbench signals
    reg  signed [7:0] tb_ai;
    reg  signed [7:0] tb_bi;
    wire signed [7:0] tb_result;
    wire              tb_overflow;

    // 2. Connect your q_mult module (Device Under Test)
    q_mult #(
        .Q(7),
        .N(8)
    ) dut (
        .ai       (tb_ai),
        .bi       (tb_bi),
        .result_0 (tb_result),
        .overflow (tb_overflow)
    );

    integer i, j;
    integer expected_prod;
    integer expected_shift;
    reg signed [7:0] expected_res;
    reg              expected_ovf;
    integer errors = 0;

    initial begin
        // Save waveforms for GTKWave / WaveTrace
        $dumpfile("sim/q_mult.vcd");
        $dumpvars(0, tb_q_mult);

        

        // Loop through all 256 x 256 = 65,536 signed 8-bit pairs
        for (i = -128; i <= 127; i = i + 1) begin
            for (j = -128; j <= 127; j = j + 1) begin
                tb_ai = i[7:0];
                tb_bi = j[7:0];
                #1; // Wait 1 ns for combinational gates to settle

                // Golden Reference Math
                expected_prod  = i * j;
                expected_shift = expected_prod >>> 7;

                if (expected_shift > 127) begin
                    expected_res = 8'sd127;
                    expected_ovf = 1'b1;
                end else if (expected_shift < -128) begin
                    expected_res = -8'sd128;
                    expected_ovf = 1'b1;
                end else begin
                    expected_res = expected_shift[7:0];
                    expected_ovf = 1'b0;
                end

                // Compare Hardware vs. Golden Reference
                if ((tb_result !== expected_res) || (tb_overflow !== expected_ovf)) begin
                    $display("ERROR at a=%0d, b=%0d | HW: res=%0d, ovf=%b | EXP: res=%0d, ovf=%b",
                             tb_ai, tb_bi, tb_result, tb_overflow, expected_res, expected_ovf);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) begin
            $display("PASS: All 65,536 / 65,536 test vectors matched Golden Model!");
        end else begin
            $display("FAIL: Found %0d errors out of 65,536 vectors.", errors);
        end
        $finish;
    end

endmodule