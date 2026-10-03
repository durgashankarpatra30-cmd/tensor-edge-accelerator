// ============================================================================
// Module Name:  tensor_core_4x4
// Project:      50-Day Tensor Edge Accelerator (Day 7 - Friend A / Hardware)
// Description:  Integrated 4x4 Tensor Core.
//               Combines:
//                 1. Input Triangular Skew Buffer (0, 1, 2, 3 cycle delays)
//                 2. 4x4 Weight-Stationary Systolic Array (16 PEs)
//                 3. Output Reverse-Triangular Deskew Buffer (3, 2, 1, 0 delays)
//                 4. 4x Parallel Activation & Re-quantization Units (Q8.8 -> INT8)
//                 5. Control Handshake (start, busy, valid_out, done)
// ============================================================================

`timescale 1ns / 1ps

module tensor_core_4x4 #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 16
)(
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               start,
    input  wire [ARRAY_SIZE-1:0]              load_weight,

    input  wire signed [ARRAY_SIZE*DATA_WIDTH-1:0] weight_in,
    input  wire signed [ARRAY_SIZE*DATA_WIDTH-1:0] act_in,
    input  wire signed [ARRAY_SIZE*ACC_WIDTH-1:0]  psum_in,

    input  wire [1:0]                         act_type,    // 00: Linear, 01: ReLU, 10: LeakyReLU
    input  wire [3:0]                         shift_amount,// Re-quantization bit shift

    output wire signed [ARRAY_SIZE*DATA_WIDTH-1:0] data_out,    // 4x 8-bit activated/quantized outputs
    output wire signed [ARRAY_SIZE*DATA_WIDTH-1:0] act_out,     // 4x 8-bit forwarded activations

    output reg                                valid_out,
    output reg                                done,
    output reg                                busy
);

    // =========================================================================
    // PART 2: Input Triangular Skew Buffer
    // Row 0: 0 cycles delay (direct wire)
    // Row 1: 1 cycle delay
    // Row 2: 2 cycles delay
    // Row 3: 3 cycles delay
    // =========================================================================
    reg signed [DATA_WIDTH-1:0] r1d1;
    reg signed [DATA_WIDTH-1:0] r2d1, r2d2;
    reg signed [DATA_WIDTH-1:0] r3d1, r3d2, r3d3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1d1 <= {DATA_WIDTH{1'b0}};
            r2d1 <= {DATA_WIDTH{1'b0}};
            r2d2 <= {DATA_WIDTH{1'b0}};
            r3d1 <= {DATA_WIDTH{1'b0}};
            r3d2 <= {DATA_WIDTH{1'b0}};
            r3d3 <= {DATA_WIDTH{1'b0}};
        end else begin
            r1d1 <= act_in[2*DATA_WIDTH-1 : DATA_WIDTH];
            r2d1 <= act_in[3*DATA_WIDTH-1 : 2*DATA_WIDTH];
            r2d2 <= r2d1;
            r3d1 <= act_in[4*DATA_WIDTH-1 : 3*DATA_WIDTH];
            r3d2 <= r3d1;
            r3d3 <= r3d2;
        end
    end

    wire signed [ARRAY_SIZE*DATA_WIDTH-1:0] act_skewed;
    assign act_skewed = {r3d3, r2d2, r1d1, act_in[DATA_WIDTH-1:0]};

    // =========================================================================
    // PART 3: Systolic Array Instantiation
    // =========================================================================
    wire [ARRAY_SIZE-1:0]             sa_load_weight;
    assign sa_load_weight = load_weight;
    wire                              clr_acc;
    wire [ARRAY_SIZE-1:0]             sa_valid_in;
    wire [ARRAY_SIZE-1:0]             sa_valid_out;
    wire signed [ARRAY_SIZE*ACC_WIDTH-1:0] sa_psum_out; // 64-bit skewed partial sums

    systolic_array_4x4 #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_systolic_array (
        .clk        (clk),
        .rst_n      (rst_n),
        .load_weight(sa_load_weight),
        .clr_acc    (clr_acc),
        .valid_in   (sa_valid_in),
        .valid_out  (sa_valid_out),
        .weight_in  (weight_in),
        .act_in     (act_skewed),
        .psum_in    (psum_in),
        .act_out    (act_out),
        .psum_out   (sa_psum_out)
    );

    // =========================================================================
    // PART 4: Output Reverse Triangular Deskew Buffer
    // Col 0: 3 cycles delay
    // Col 1: 2 cycles delay
    // Col 2: 1 cycle delay
    // Col 3: 0 cycles delay
    // =========================================================================
    reg signed [ACC_WIDTH-1:0] c0d1, c0d2, c0d3;
    reg signed [ACC_WIDTH-1:0] c1d1, c1d2;
    reg signed [ACC_WIDTH-1:0] c2d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c0d1 <= {ACC_WIDTH{1'b0}};
            c0d2 <= {ACC_WIDTH{1'b0}};
            c0d3 <= {ACC_WIDTH{1'b0}};
            c1d1 <= {ACC_WIDTH{1'b0}};
            c1d2 <= {ACC_WIDTH{1'b0}};
            c2d1 <= {ACC_WIDTH{1'b0}};
        end else begin
            c0d1 <= sa_psum_out[ACC_WIDTH-1:0];
            c0d2 <= c0d1;
            c0d3 <= c0d2;
            c1d1 <= sa_psum_out[2*ACC_WIDTH-1:ACC_WIDTH];
            c1d2 <= c1d1;
            c2d1 <= sa_psum_out[3*ACC_WIDTH-1:2*ACC_WIDTH];
        end
    end

    wire signed [ARRAY_SIZE*ACC_WIDTH-1:0] psum_aligned;
    assign psum_aligned = {sa_psum_out[4*ACC_WIDTH-1 : 3*ACC_WIDTH], c2d1, c1d2, c0d3};

    // =========================================================================
    // PART 5: 4x Parallel Activation & Re-quantization Units
    // =========================================================================
    genvar col;
    generate 
        for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : gen_activation_unit
            activation_unit #(
                .in_width (ACC_WIDTH),
                .out_width(DATA_WIDTH)
            ) u_activation_unit (
                .in_data      (psum_aligned[(col+1)*ACC_WIDTH-1 : col*ACC_WIDTH]),
                .mode_i       (act_type),
                .scale_shift_i(shift_amount),
                .out_data     (data_out[(col+1)*DATA_WIDTH-1 : col*DATA_WIDTH]),
                .overflow_o   ()
            );
        end
    endgenerate

    // =========================================================================
    // PART 6: Control Handshake & Valid Skewing
    // =========================================================================
    reg val_r1_d1;
    reg val_r2_d1, val_r2_d2;
    reg val_r3_d1, val_r3_d2, val_r3_d3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            val_r1_d1 <= 1'b0;
            val_r2_d1 <= 1'b0;
            val_r2_d2 <= 1'b0;  
            val_r3_d1 <= 1'b0;  
            val_r3_d2 <= 1'b0;
            val_r3_d3 <= 1'b0;
        end else begin
            val_r1_d1 <= start;
            val_r2_d1 <= start;
            val_r2_d2 <= val_r2_d1;
            val_r3_d1 <= start;
            val_r3_d2 <= val_r3_d1;
            val_r3_d3 <= val_r3_d2;
        end
    end

    assign sa_valid_in = {val_r3_d3, val_r2_d2, val_r1_d1, start};
    assign clr_acc     = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            done      <= 1'b0;
            busy      <= 1'b0;
        end else begin
            valid_out <= sa_valid_out[3];
            done      <= sa_valid_out[3];

            if (start || (|load_weight))
                busy <= 1'b1;
            else if (sa_valid_out[3])
                busy <= 1'b0;
        end
    end

endmodule
