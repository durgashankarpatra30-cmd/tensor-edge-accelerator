// ============================================================================
// Module Name:  systolic_array_4x4
// Project:      50-Day Tensor Edge Accelerator (Day 6 - Friend A / Hardware)
// Description:  2D Systolic Array Matrix Multiplication Unit (MXU).
//               Instantiates 16 Processing Elements (PEs) in a 4x4 mesh.
//
// Dataflow Architecture:
//   - Weight-Stationary (WS): 16 weights preloaded row-by-row into PEs.
//   - Horizontal Flow: Activations stream West -> East across rows.
//   - Vertical Flow: Partial sums accumulate North -> South down columns.
//   - Throughput: 16 MAC operations per clock cycle at 125 MHz (2 GOPS).
// ============================================================================

`timescale 1ns / 1ps

module systolic_array_4x4 #(
    parameter ARRAY_SIZE = 4,   // 4x4 = 16 PEs
    parameter DATA_WIDTH = 8,   // 8-bit Q4.4 Fixed-Point
    parameter ACC_WIDTH  = 16   // 16-bit Q8.8 Fixed-Point
)(
    input  wire                               clk,
    input  wire                               rst_n,

    // Control Signals
    input  wire [ARRAY_SIZE-1:0]              load_weight, // 1-bit strobe per row (Row 0 to 3)
    input  wire                               clr_acc,     // Clears all 16 accumulators
    input  wire [ARRAY_SIZE-1:0]              valid_in,    // 1-bit strobe per row
    output wire [ARRAY_SIZE-1:0]              valid_out,   // 1-bit strobe per column (at bottom)

    // Data Streaming Inputs
    // 4 weights in parallel (one for each column): 4 × 8b = 32 bits
    input  wire signed [ARRAY_SIZE*DATA_WIDTH-1:0] weight_in,

    // 4 activations in parallel (one for each row): 4 × 8b = 32 bits
    input  wire signed [ARRAY_SIZE*DATA_WIDTH-1:0] act_in,

    // 4 initial partial sums (top boundary, typically 0): 4 × 16b = 64 bits
    input  wire signed [ARRAY_SIZE*ACC_WIDTH-1:0]  psum_in,

    // Outputs
    // 4 forwarded activations exiting the East boundary: 4 × 8b = 32 bits
    output wire signed [ARRAY_SIZE*DATA_WIDTH-1:0] act_out,

    // 4 final accumulated dot products exiting the South boundary: 4 × 16b = 64 bits
    output wire signed [ARRAY_SIZE*ACC_WIDTH-1:0]  psum_out
);

    // ========================================================================
    // 1. Internal Wire Grid Mesh
    // ========================================================================
    // Horizontal activations: 4 rows, 5 segments per row
    wire signed [DATA_WIDTH-1:0] act_wire   [0:ARRAY_SIZE-1][0:ARRAY_SIZE];
    
    // Vertical partial sums: 5 segments down each of the 4 columns
    wire signed [ACC_WIDTH-1:0]  psum_wire  [0:ARRAY_SIZE][0:ARRAY_SIZE-1];
    
    // Horizontal valid flag wavefront (propagates along with activations)
    wire                         valid_wire [0:ARRAY_SIZE-1][0:ARRAY_SIZE];

    // ========================================================================
    // 2. Boundary Connections (West, East, North, South)
    // ========================================================================
    genvar b;
    generate
        for (b = 0; b < ARRAY_SIZE; b = b + 1) begin : BOUNDARIES
            // West Boundary: Connect act_in slices to column 0 of act_wire
            assign act_wire[b][0] = act_in[(b+1)*DATA_WIDTH-1 : b*DATA_WIDTH];
            
            // East Boundary: Connect rightmost act_wire column to act_out slices
            assign act_out[(b+1)*DATA_WIDTH-1 : b*DATA_WIDTH] = act_wire[b][ARRAY_SIZE];

            // North Boundary: Connect psum_in slices to row 0 of psum_wire
            assign psum_wire[0][b] = psum_in[(b+1)*ACC_WIDTH-1 : b*ACC_WIDTH];

            // South Boundary: Connect bottommost psum_wire row to psum_out slices
            assign psum_out[(b+1)*ACC_WIDTH-1 : b*ACC_WIDTH] = psum_wire[ARRAY_SIZE][b];

            // West Valid Boundary: Feed valid_in into column 0 of valid_wire
            assign valid_wire[b][0] = valid_in[b];
        end
    endgenerate

    // South Valid Boundary: Column c valid_out emerges when Bottom Row (Row 3) PE completes
    // For column c, PE(ARRAY_SIZE-1, c) outputs valid_wire[ARRAY_SIZE-1][c+1]
    generate
        for (b = 0; b < ARRAY_SIZE; b = b + 1) begin : VALID_SOUTH
            assign valid_out[b] = valid_wire[ARRAY_SIZE-1][b+1];
        end
    endgenerate

    // ========================================================================
    // 3. 2D Generate Loop: Instantiate 16 Processing Elements
    // ========================================================================
    genvar r, c;
    generate
        for (r = 0; r < ARRAY_SIZE; r = r + 1) begin : GEN_ROW
            for (c = 0; c < ARRAY_SIZE; c = c + 1) begin : GEN_COL
                processing_element #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .ACC_WIDTH  (ACC_WIDTH)
                ) pe_inst (
                    .clk         (clk),
                    .rst_n       (rst_n),
                    .load_weight (load_weight[r]),
                    .clr_acc     (clr_acc),
                    .valid_in    (valid_wire[r][c]),
                    .valid_out   (valid_wire[r][c+1]),
                    .weight_in   (weight_in[(c+1)*DATA_WIDTH-1 : c*DATA_WIDTH]),
                    .act_in      (act_wire[r][c]),
                    .act_out     (act_wire[r][c+1]),
                    .psum_in     (psum_wire[r][c]),
                    .psum_out    (psum_wire[r+1][c])
                );
            end
        end
    endgenerate

endmodule
