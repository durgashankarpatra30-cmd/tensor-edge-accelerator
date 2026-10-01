// ============================================================================
// Module Name:  processing_element
// Project:      50-Day Tensor Edge Accelerator (Day 5 - Friend A / Hardware)
// Description:  Systolic Processing Element (PE) for Weight-Stationary 2D 
//               Matrix Multiply Tensor Unit.
//
// Key Features:
//   1. Weight-Stationary Register: Latches weight_in when load_weight is high.
//   2. Q4.4 x Q4.4 Signed Fixed-Point Multiplier -> 16-bit Q8.8 Product.
//   3. 16-bit Q8.8 Accumulator with Saturation (+32767 / -32768).
//   4. Systolic Forwarding:
//      - Horizontal forwarding: act_in registered to act_out (1-cycle delay).
//      - Vertical forwarding: psum_out registered (1-cycle delay).
//      - Handshake: valid_in registered to valid_out.
// ============================================================================

`timescale 1ns / 1ps

module processing_element #(
    parameter DATA_WIDTH = 8,            // Q4.4 Fixed-Point (1 sign, 3 int, 4 frac)
    parameter ACC_WIDTH  = 16            // Q8.8 Fixed-Point (1 sign, 7 int, 8 frac)
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // Control Signals
    input  wire                          load_weight, // Latches weight_in into stationary register
    input  wire                          clr_acc,     // Clears internal accumulator/psum
    input  wire                          valid_in,    // Input data valid strobe
    output reg                           valid_out,   // Output data valid strobe

    // Data Streaming Inputs
    input  wire signed [DATA_WIDTH-1:0]  weight_in,   // Preloaded weight from BRAM
    input  wire signed [DATA_WIDTH-1:0]  act_in,      // Activation streamed from left neighbor
    input  wire signed [ACC_WIDTH-1:0]   psum_in,     // Partial sum streamed from top neighbor

    // Systolic Forwarded Outputs
    output reg  signed [DATA_WIDTH-1:0]  act_out,     // Forwarded activation to right neighbor
    output reg  signed [ACC_WIDTH-1:0]   psum_out     // Forwarded partial sum to bottom neighbor
);

    // ========================================================================
    // 1. Stationary Weight Storage Register
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] weight_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            weight_reg <= {DATA_WIDTH{1'b0}};
        end else if (load_weight) begin
            weight_reg <= weight_in;
        end
    end

    // ========================================================================
    // 2. Fixed-Point Q4.4 x Q4.4 Multiplier Stage
    //    Signed 8-bit * 8-bit = Signed 16-bit Product (Q8.8)
    // ========================================================================
    wire signed [ACC_WIDTH-1:0] mult_product;
    assign mult_product = act_in * weight_reg;

    // ========================================================================
    // 3. 17-Bit Addition & Saturation Stage
    //    psum_in (16-bit Q8.8) + mult_product (16-bit Q8.8)
    // ========================================================================
    wire signed [ACC_WIDTH:0] sum_extended; // 17 bits for carry/overflow detection
    assign sum_extended = (clr_acc) ? 
                          {mult_product[ACC_WIDTH-1], mult_product} :
                          {psum_in[ACC_WIDTH-1], psum_in} + {mult_product[ACC_WIDTH-1], mult_product};

    // Saturation Logic:
    // Positive overflow occurs when sum > +32767 (sum_extended[16]=0, sum_extended[15]=1)
    // Negative overflow occurs when sum < -32768 (sum_extended[16]=1, sum_extended[15]=0)
    wire signed [ACC_WIDTH-1:0] saturated_sum;
    assign saturated_sum = (sum_extended > 17'sd32767)  ? 16'sh7FFF :
                           (sum_extended < -17'sd32768) ? 16'sh8000 :
                           sum_extended[ACC_WIDTH-1:0];

    // ========================================================================
    // 4. Systolic Output Pipeline Registers (1-Cycle Latency)
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            act_out   <= {DATA_WIDTH{1'b0}};
            psum_out  <= {ACC_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;

            if (valid_in) begin
                // Forward the activation to the right neighbor
                act_out  <= act_in;
                // Forward the updated partial sum to the bottom neighbor
                psum_out <= saturated_sum;
            end else if (clr_acc) begin
                psum_out <= {ACC_WIDTH{1'b0}};
            end
        end
    end

endmodule
