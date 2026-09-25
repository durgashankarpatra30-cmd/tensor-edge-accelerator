`timescale 1ns / 1ps

module mac_pipeline #(
    parameter Q = 7,
    parameter N = 8
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                clear_acc_i,
    input  wire                acc_en_i,
    input  wire signed [N-1:0] ai,
    input  wire signed [N-1:0] bi,

    output reg  signed [31:0]  acc_o,
    output reg  signed [N-1:0] result_saturation_o,
    output reg                 overflow_o,
    output reg                 valid_o
);

    localparam signed [31:0] MAX_VAL =  (1 <<< (N-1)) - 1; // +127
    localparam signed [31:0] MIN_VAL = -(1 <<< (N-1));     // -128

    // =========================================================================
    // Worker 1 (Stage 1): Latch inputs ai, bi, clear_acc_i, and acc_en_i
    // =========================================================================
    reg signed [N-1:0] s1_a, s1_b;
    reg                s1_clear_acc_i, s1_acc_en_i;

    always @(posedge clk) begin
        if (!rst_n) begin
            s1_a           <= 0;
            s1_b           <= 0;
            s1_clear_acc_i <= 1'b0;
            s1_acc_en_i    <= 1'b0;
        end else begin
            s1_a           <= ai;
            s1_b           <= bi;
            s1_clear_acc_i <= clear_acc_i;
            s1_acc_en_i    <= acc_en_i;
        end
    end

    // =========================================================================
    // Worker 2 (Stage 2): Multiply s1_a * s1_b and arithmetic right-shift by Q
    // =========================================================================
    wire signed [2*N-1:0] full_product;
    wire signed [2*N-1:0] shifted_product;
    reg  signed [2*N-1:0] s2_product;
    reg                   s2_acc_en_i, s2_clear_acc_i;

    assign full_product    = s1_a * s1_b;
    assign shifted_product = full_product >>> Q;

    always @(posedge clk) begin
        if (!rst_n) begin
            s2_product     <= 0;
            s2_acc_en_i    <= 1'b0;
            s2_clear_acc_i <= 1'b0;
        end else begin
            s2_product     <= shifted_product;
            s2_acc_en_i    <= s1_acc_en_i;
            s2_clear_acc_i <= s1_clear_acc_i;
        end
    end

    // =========================================================================
    // Worker 3 (Stage 3): 32-bit Accumulator & 8-bit Saturation Clamping
    // =========================================================================
    wire signed [31:0] next_acc = acc_o + s2_product;

    always @(posedge clk) begin
        if (!rst_n) begin
            acc_o               <= 32'sd0;
            overflow_o          <= 1'b0;
            result_saturation_o <= 8'sd0;
            valid_o             <= 1'b0;
        end else begin
            if (s2_clear_acc_i) begin
                acc_o               <= 32'sd0;
                overflow_o          <= 1'b0;
                result_saturation_o <= 8'sd0;
                valid_o             <= 1'b0;
            end else if (s2_acc_en_i) begin
                acc_o   <= next_acc;
                valid_o <= 1'b1;

                if (next_acc > MAX_VAL) begin
                    overflow_o          <= 1'b1;
                    result_saturation_o <= MAX_VAL[N-1:0];
                end else if (next_acc < MIN_VAL) begin
                    overflow_o          <= 1'b1;
                    result_saturation_o <= MIN_VAL[N-1:0];
                end else begin
                    overflow_o          <= 1'b0;
                    result_saturation_o <= next_acc[N-1:0];
                end
            end else begin
                valid_o <= 1'b0;
            end
        end
    end

endmodule
