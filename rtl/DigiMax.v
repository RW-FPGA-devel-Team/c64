module digimax
(
	input         clk,
   input         reset_n,
	input         wr_n,
	input  [15:0] addr,
	input   [7:0] data_in,
   output  reg   sid_sample,
	output  reg [7:0] dac_0,
	output  reg [7:0] dac_1,
	output  reg [7:0] dac_2,
	output  reg [7:0] dac_3
);


////////////////////////////////////////////////////////////////

always @(posedge clk) begin
   if (!wr_n) begin
	   sid_sample <= 1'b0;
	   case (addr)
			16'hde00: dac_0 <= data_in;
			16'hde01: dac_1 <= data_in;
			16'hde02: dac_2 <= data_in;
			16'hde03: dac_3 <= data_in;
			16'hd418: begin
			            sid_sample <= 1'b1;
							dac_0 <= {1'b0,data_in[3:0],3'b0};
							dac_2 <= dac_0;
						 end
	   endcase
	end
end

endmodule
