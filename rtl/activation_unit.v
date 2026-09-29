`timescale 1ns / 1ps

module activation_unit #(
    parameter in_width  = 32,
    parameter out_width = 8
)(
    input  wire signed [in_width-1:0]  in_data,
    input  wire        [1:0]           mode_i,
    input  wire        [3:0]           scale_shift_i,

    output reg  signed [out_width-1:0] out_data,
    output reg                         overflow_o
);

    // Clamping thresholds for 8-bit signed output: +127 and -128
    localparam signed [in_width-1:0] max_val =  (1 <<< (out_width - 1)) - 1; // +127
    localparam signed [in_width-1:0] min_val = -(1 <<< (out_width - 1));     // -128

    // =========================================================================
    // STEP 1: Activation Function Selection (Linear / ReLU / LeakyReLU)
    // =========================================================================
    reg signed [in_width-1:0] act_value;

    always @(*) begin
        case (mode_i)
            2'b00: begin // Linear Pass-Through
                act_value = in_data;
            end

            2'b01: begin // ReLU: If negative, kill to 0
                if (in_data < 0)
                    act_value = 0;
                else
                    act_value = in_data;
            end

            2'b10: begin // LeakyReLU: If negative, arithmetic shift right by 3 (divide by 8)
                if (in_data < 0)
                    act_value = in_data >>> 3;
                else
                    act_value = in_data;
            end

            default: begin // Fallback
                act_value = in_data;
            end
        endcase
    end

    // =========================================================================
    // STEP 2: Re-Quantization (Configurable Arithmetic Right Shift)
    // =========================================================================
    wire signed [in_width-1:0] scaled_value = act_value >>> scale_shift_i;

    // =========================================================================
    // STEP 3: Saturation Clamping (-128 to +127)
    // =========================================================================
    always @(*) begin
        if (scaled_value > max_val) begin
            out_data   = max_val[out_width-1:0]; // Clamp to +127 (0x7F)
            overflow_o = 1'b1;
        end else if (scaled_value < min_val) begin
            out_data   = min_val[out_width-1:0]; // Clamp to -128 (0x80)
            overflow_o = 1'b1;
        end else begin
            out_data   = scaled_value[out_width-1:0];
            overflow_o = 1'b0;
        end
    end

    // =========================================================================
    // Warning Assertion for Invalid Mode (2'b11)
    // =========================================================================
    // synthesis translate_off
    always @(*) begin
        if (mode_i == 2'b11) begin
            $display("[WARNING activation_unit] Invalid mode_i = 2'b11 at time %0t!", $time);
        end
    end
    // synthesis translate_on

endmodule
