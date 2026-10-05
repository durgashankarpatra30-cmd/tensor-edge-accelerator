module tensor_core_axis #(
    parameter DATA_WIDTH =8,
    parameter ARRAY_WIDTH =4,
    parameter ACC_WIDTH =16,
    parameter AXIS_WIDTH=32
)
(
    //Global clock and reset
input wire aclk,
input wire aresetn,

//Input Axis Interferace 
input wire [AXIS_WIDTH-1:0] s_axis_tdata,// 32-bit input data
input wire s_axis_tvalid,// 1-bit input valid
output reg s_axis_tready,// 1-bit input ready
input wire s_axis_tlast,// 1-bit input last
input wire [1:0] s_axis_tuser,// 2-bit input user (packet type: 00=Config, 01=Weight, 10=Activation)

//Output Axis Interferace
output reg [AXIS_WIDTH-1:0] m_axis_tdata,// 32-bit output data
output reg m_axis_tvalid,// 1-bit output valid
input wire m_axis_tready,// 1-bit output ready
output reg m_axis_tlast,// 1-bit output last

output wire busy,
output wire done_pulse

);

reg [1:0]config_act_type;
reg[3:0] config_shift_amount;

wire handshake_done;
assign handshake_done = s_axis_tvalid && s_axis_tready;

always @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
        config_act_type <= 2'b00;
        config_shift_amount <= 4'd4;
    end
    else if (handshake_done && (s_axis_tuser == 2'b00)) begin
        // Latch configuration when a Config packet (tuser == 2'b00) arrives
        config_act_type     <= s_axis_tdata[1:0];
        config_shift_amount <= s_axis_tdata[5:2];
    end
end


// 2. The Traffic Cop that activates the correct row:
    // =========================================================================
    // PART 3: Ingress Weight Routing & Activation Control
    // =========================================================================
    reg [1:0] weight_row_cnt; // Counts 0, 1, 2, 3 as 4 weight rows arrive

    // Internal wires connecting to the Day 7 Tensor Core
    reg  [ARRAY_WIDTH-1:0]             core_load_weight;
    wire signed [AXIS_WIDTH-1:0]       core_weight_in;
    wire signed [AXIS_WIDTH-1:0]       core_act_in;
    reg                                core_start;

    // Direct data connections
    assign core_weight_in = s_axis_tdata;
    assign core_act_in    = s_axis_tdata;

    // Weight Row Counter: Increments on each accepted weight beat
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            weight_row_cnt <= 2'b00;
        end else if (handshake_done && (s_axis_tuser == 2'b01)) begin
            if (s_axis_tlast || (weight_row_cnt == 2'd3))
                weight_row_cnt <= 2'b00; // Reset after 4th row
            else
                weight_row_cnt <= weight_row_cnt + 1'b1;
        end
    end

    // Combinatorial Steering of load_weight and start
    always @(*) begin
        core_load_weight = {ARRAY_WIDTH{1'b0}};
        core_start       = 1'b0;

        if (handshake_done) begin
            case (s_axis_tuser)
                2'b01: begin // WEIGHT PACKET: One-hot decode to Row 0, 1, 2, 3
                    core_load_weight = (4'b0001 << weight_row_cnt);
                end

                2'b10: begin // ACTIVATION PACKET: Pulse start to compute
                    core_start = 1'b1;
                end

                default: begin
                    core_load_weight = {ARRAY_WIDTH{1'b0}};
                    core_start       = 1'b0;
                end
            endcase
        end
    end


    wire signed [AXIS_WIDTH-1:0] core_data_out;
    wire                         core_valid_out;
    wire                         core_done;
    wire                         core_busy;

    tensor_core_4x4 #(
        .ARRAY_SIZE(ARRAY_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_tensor_core (
        .clk         (aclk),
        .rst_n       (aresetn),
        .start       (core_start),
        .load_weight (core_load_weight),
        .weight_in   (core_weight_in),
        .act_in      (core_act_in),
        .psum_in     ({(ARRAY_WIDTH*ACC_WIDTH){1'b0}}), // 64'd0 top boundary
        .act_type    (config_act_type),                 // Dynamic config from Part 2!
        .shift_amount(config_shift_amount),             // Dynamic config from Part 2!
        .data_out    (core_data_out),                   // 32-bit activated result
        .act_out     (),                                // Unconnected
        .valid_out   (core_valid_out),
        .done        (core_done),
        .busy        (core_busy)
    );

    // Direct wire hookup for status flags
    assign busy       = core_busy;
    assign done_pulse = core_done;

        // =========================================================================
    // PART 5: Egress Stream Controller (M_AXIS Output Handshake)
    // =========================================================================
    wire m_axis_handshake;
    assign m_axis_handshake = m_axis_tvalid && m_axis_tready;

    // Ingress Backpressure: We accept new input when core is idle and output isn't stalled
    always @(*) begin
        s_axis_tready = !core_busy && (!m_axis_tvalid || m_axis_tready);
    end

    // Egress Registering: Latch result on core_valid_out, hold until m_axis_tready
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            m_axis_tdata  <= {AXIS_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else begin
            // When core produces a valid result:
            if (core_valid_out) begin
                m_axis_tdata  <= core_data_out;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= 1'b1; // Assert tlast on matrix result
            end
            // When external DMA accepts the data, clear valid:
            else if (m_axis_handshake) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
            end
        end
    end

endmodule