module q_mult #(
    parameter Q=7,
    parameter N=8
)
(
    input wire signed [N-1:0] ai,
    input wire signed [N-1:0] bi,
    output reg signed [N-1:0] result_0,
    output reg signed         overflow); 

//Initialize the maximum and minimum possible value here
localparam signed [N-1:0] MAX_VAL = (1 << (N-1)) -1;//127
localparam signed [N-1:0] MIN_VAL = -(1<<(N-1));//-128

//Intialize the full product and shifted product here
wire  signed [2*N-1: 0] full_product;
wire  signed [2*N-1: 0] shifted_product;

assign full_product =ai * bi;
assign shifted_product = full_product >>> Q;

//Check for overflow and assign the result
always @(*) begin 
    if (shifted_product > MAX_VAL) begin
        result_0 = MAX_VAL;
        overflow = 1'b1;
    end else if (shifted_product < MIN_VAL) begin
        result_0 = MIN_VAL;
        overflow = 1'b1;
    end else begin
        result_0 = shifted_product [N-1:0];
        overflow = 1'b0;
    end
end

endmodule 

