`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//Simulates a Low Pass Filter
//Antonio Sanchez (TheSonders)
//////////////////////////////////////////////////////////////////////////////////
`define PRESCALER       (clkspeed/(filterfreq*32))

module LPFilter
    #(parameter clkspeed=27000000,
    parameter filterfreq=1500)
    (
	  input wire [17:0]inSound,
	  output reg [17:0]outSound,
     input wire clk
	);

reg [$clog2(`PRESCALER)-1:0] prescaler=`PRESCALER;
wire [20:0]diff=inSound-outSound;

always @(posedge clk) begin
   		if (prescaler) prescaler<=prescaler-1;
		else begin
			prescaler<=`PRESCALER;
			if (inSound!=outSound) outSound<=outSound+(diff>>>3);
		end
	 
end
endmodule
