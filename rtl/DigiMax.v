module digimax
(
	input         clk,
   input         reset_n,
	input         wr_n,
	input  [15:0] addr,
	input   [7:0] data_in,
	output  reg [7:0] dac_0,
	output  reg [7:0] dac_1,
	output  reg [7:0] dac_2,
	output  reg [7:0] dac_3
);


////////////////////////////////////////////////////////////////

always @(posedge clk) begin
   if (!wr_n) begin
	   case (addr)
			16'hde00: dac_0 <= data_in;
			16'hde01: dac_1 <= data_in;
			16'hde02: dac_2 <= data_in;
			16'hde03: dac_3 <= data_in;
			16'hdf00: dac_0 <= data_in;
			16'hdf01: dac_1 <= data_in;
			16'hdf02: dac_2 <= data_in;
			16'hdf03: dac_3 <= data_in;
	   endcase
	end
end

endmodule
