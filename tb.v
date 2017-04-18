`timescale 1ns / 10ps

module testbench();

//assume basic clock is 100Mhz
reg clk;
initial clk=0;
always
  #5 clk = ~clk;

//simulate delay line
reg hi_clk;
initial hi_clk=0;
always
  #0.01 hi_clk = ~hi_clk;

wire [19:0]w_io;
wire w_test; assign w_test = w_io[6];
reg [4095:0]delay_regs;
always @(posedge hi_clk)
	delay_regs <= {delay_regs[4094:0], w_test};
wire w_echo; assign w_echo = delay_regs[217];
assign w_io[7]=w_echo;
assign w_io[5:0]=6'hz;
assign w_io[19:8]=11'hz;
wire w_serial;

top top_inst(
	.KEY0( 1'b1 ),
	.KEY1( 1'b1 ),
	.CLK100MHZ( clk ),
	.IO(w_io),
	.LED(),
	.FTDI_BD1(w_serial)
);

initial
begin
`ifdef IVERILOG
	$dumpfile("out.vcd");
	$dumpvars(0,testbench);
`endif
end

endmodule