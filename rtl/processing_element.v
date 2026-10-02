// ============================================================================
// Module Name:  processing_element
// Project:      50-Day Tensor Edge Accelerator (Day 5 - Friend A / Hardware)
// Description:  Systolic Processing Element (PE) for Weight-Stationary 2D 
//               Matrix Multiply Tensor Unit.
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

    
    // TODO 1: Stationary Weight Storage Register
    
    
reg signed[DATA_WIDTH-1:0] weight_reg;
always @(posedge clk) begin
    if (!rst_n) begin
        weight_reg <= 1'b0;
    end
    else if (load_weight) begin
        weight_reg <= weight_in;
    end
end





    
    // TODO 2: Multiplier Stage

    wire signed[ACC_WIDTH-1:0] mult_product;
    assign mult_product =act_in * weight_reg;




    
    // TODO 3: Accumulation & Saturation Stage
    
    wire signed [ACC_WIDTH:0] sum_extended;
    assign sum_extended = (clr_acc) ? 
                          {mult_product[ACC_WIDTH-1], mult_product} :
                          {psum_in[ACC_WIDTH-1], psum_in} + {mult_product[ACC_WIDTH-1], mult_product};

    wire signed [ACC_WIDTH-1:0] saturated_sum;
    assign saturated_sum = (sum_extended > 17'sd32767)  ? 16'sh7FFF :
                           (sum_extended < -17'sd32768) ? 16'sh8000 :
                           sum_extended[ACC_WIDTH-1:0];



    
always @(posedge clk) begin
    if (!rst_n) begin
        act_out<=0;
        psum_out<= 0;
        valid_out<=0;
    end
    else begin
        valid_out <= valid_in;
        if (valid_in) begin
            act_out<= act_in;
            psum_out<= saturated_sum;
        end
        else if (clr_acc) begin
            psum_out <= 0;
        end
    end
end





endmodule
