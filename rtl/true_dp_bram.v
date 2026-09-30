// ============================================================================
// Module Name:  true_dp_bram
// Project:      50-Day Tensor Edge Accelerator (Day 4 - Friend A / Hardware)
// Description:  True Dual-Port Synchronous Block RAM with Ping-Pong Bank 
//               Partitioning for Zero-Collision Dual-Clock Domain Access.
//
// Features:
//   - Fully independent Port A and Port B (clocks, enables, addresses, data)
//   - Hardware synthesis directive (* ram_style = "block" *) for BRAM inference
//   - 1-cycle synchronous read latency (Registered read output)
//   - Hardware collision prevention via MSB Bank Select inversion:
//       Port A accesses Bank { bank_sel_i}
//       Port B accesses Bank {~bank_sel_i}
// ============================================================================

`timescale 1ns / 1ps

module true_dp_bram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10,
    parameter RAM_DEPTH  = 1024
)(
    // Port A (Sensor / Ingestion domain - e.g. 50 MHz)
    input  wire                  clka,
    input  wire                  ena,
    input  wire                  wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [DATA_WIDTH-1:0] dina,
    output reg  [DATA_WIDTH-1:0] douta,

    // Port B (Computation / MAC Array domain - e.g. 125 MHz)
    input  wire                  clkb,
    input  wire                  enb,
    input  wire                  web,
    input  wire [ADDR_WIDTH-1:0] addrb,
    input  wire [DATA_WIDTH-1:0] dinb,
    output reg  [DATA_WIDTH-1:0] doutb,

    // Ping-Pong Bank Select:
    // 0: Port A accesses Bank 0 (0-511), Port B accesses Bank 1 (512-1023)
    // 1: Port A accesses Bank 1 (512-1023), Port B accesses Bank 0 (0-511)
    input  wire                  bank_sel_i
);

    // Synthesis attribute: Force FPGA tool (Vivado, Quartus, Yosys) to infer dedicated Block RAM
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] ram_block [0:RAM_DEPTH-1];

    // Hardware Bank Addressing:
    // Replace the MSB (bit 9) with bank_sel_i and ~bank_sel_i.
    // Lower 9 bits ([8:0]) provide 512 entries per bank.
    wire [ADDR_WIDTH-1:0] physical_addra = { bank_sel_i, addra[ADDR_WIDTH-2:0]};
    wire [ADDR_WIDTH-1:0] physical_addrb = {~bank_sel_i, addrb[ADDR_WIDTH-2:0]};

    // ========================================================================
    // Port A: Synchronous Read / Write (clka domain)
    // ========================================================================
    always @(posedge clka) begin
        if (ena) begin
            if (wea) begin
                ram_block[physical_addra] <= dina;
            end
            douta <= ram_block[physical_addra]; // 1-cycle registered read
        end
    end

    // ========================================================================
    // Port B: Synchronous Read / Write (clkb domain)
    // ========================================================================
    always @(posedge clkb) begin
        if (enb) begin
            if (web) begin
                ram_block[physical_addrb] <= dinb;
            end
            doutb <= ram_block[physical_addrb]; // 1-cycle registered read
        end
    end

endmodule
