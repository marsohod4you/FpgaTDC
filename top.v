

module top(
	input wire KEY0,
	input wire KEY1,
	input wire CLK100MHZ,
	inout wire [19:0]IO,
	output wire [7:0]LED,
	output wire FTDI_BD1 //serial TX
);

localparam TEST_PERIOD = 64;
localparam TEST_IMP_LENGTH = 4;
localparam TEST_IMP_START = TEST_PERIOD-TEST_IMP_LENGTH;
localparam TEST_CAP_TIME  = TEST_IMP_START;
localparam PHASE_CHANGE_TIME  = 8;

localparam MAX_TRIES = 127;

reg [31:0]timer = 0;

reg cap = 1'b0;

wire wc0;
wire wc1;
//wire wc2;
wire wlocked;

assign IO[5:0] = 0;
assign IO[19:8] = 0;

//test impulse is sent on wc1 clock
reg test_impulse; 
reg [7:0]wc1_timer;
always @( posedge wc1 or negedge wlocked )
begin
	if( ~wlocked ) begin
		wc1_timer <= 0;
		test_impulse <= 1'b0;
	end
	else begin
		if( wc1_timer==TEST_PERIOD-1 )
			wc1_timer <= 0;
		else
			wc1_timer <= wc1_timer + 1;
		test_impulse <= ( wc1_timer>=TEST_IMP_START );
	end
end

assign IO[6] = test_impulse; //send test impulse to output pin
wire echo_impulse;	
assign echo_impulse = IO[7]; //echo impulse received after delay from input pin

//manage phase shift direction and position on clock wc0
reg [7:0]wc0_timer;
reg [7:0]try;
reg dir;
/*
always @( posedge wc0 or negedge wlocked )
	if( ~wlocked ) begin
		try <= 0;
		dir <= 1'b0;
	end
	else begin
		if( wc0_timer==PHASE_CHANGE_TIME-1 ) begin
			if( dir )
				try <= try-1'b1;
			else
				try <= try+1'b1;
			if( (dir==0 && try==MAX_TRIES-1) || (dir==1 && try==1) )
				dir <= ~dir;
		end
	end
*/

//define key0/key1 poll freq
reg [23:0]cnt;
wire key_poll_freq; assign key_poll_freq = (cnt==25000);
always @( posedge wc0 or negedge wlocked )
	if(~wlocked)
		cnt<=0;
	else
	if(key_poll_freq)
		cnt<=0;
	else
		cnt<=cnt+1;


reg [1:0]key0_;
reg [1:0]key1_;
always @( posedge wc0 )
	if( key_poll_freq ) begin
		key0_ <= { key0_[0], KEY0 };
		key1_ <= { key1_[0], KEY1 };
	end

wire cap_time_up; assign cap_time_up = key_poll_freq & key0_==2'b10;
wire cap_time_dn; assign cap_time_dn = key_poll_freq & key1_==2'b10;

reg [7:0]cap_time;
always @( posedge wc0 or negedge wlocked )
	if(~wlocked)
		cap_time <= TEST_CAP_TIME;
	else
	if( cap_time_up )
		cap_time <= cap_time + 1;
	else
	if( cap_time_dn )
		cap_time <= cap_time - 1;
		
assign LED = cap_time;
	
//echo impulse is captured on wc0 clock
reg echo_fixed; //fix echo input into this reg
reg [127:0]echo_fixed_array;
reg [1:0]capture_;
always @( posedge wc0 or negedge wlocked )
	if( ~wlocked )
		capture_ <=	2'b00;
	else
		capture_ <= { capture_[0], (wc0_timer==cap_time) };
wire capture0; assign capture0 = (capture_==2'b01);
wire capture1; assign capture1 = (capture_==2'b10);

always @( posedge wc0 or negedge wlocked )
begin
	if( ~wlocked ) begin
		wc0_timer <= 0;
		echo_fixed <= 1'b0;
		echo_fixed_array <= 0;
	end
	else begin
		if( wc0_timer==TEST_PERIOD-1 )
			wc0_timer <= 0;
		else
			wc0_timer <= wc0_timer + 1;
		if( capture0 )
			echo_fixed <= echo_impulse;
		if( capture1 /*& dir*/ )
			echo_fixed_array[try] <= echo_fixed;
	end
end

//on every new try change phase of wc1
reg phase_step = 1'b0;
wire wpdone; wire phase_done; assign phase_done = ~wpdone;
always @( negedge wc0 )
	if( wc0_timer==PHASE_CHANGE_TIME )
		phase_step<=1'b1;
	else
	if( phase_done )
		phase_step<=1'b0;

always @( negedge wc0 or negedge wlocked )
	if( ~wlocked )
		try <= 0;
	else
	if( phase_done ) begin
			if( dir )
				try <= try-1'b1;
			else
				try <= try+1'b1;
	end

always @( posedge wc0 or negedge wlocked )
	if( ~wlocked )
		dir <= 1'b0;
	else
		if( wc0_timer==PHASE_CHANGE_TIME-8 ) begin
			if( (dir==0 && try==MAX_TRIES-1) || (dir==1 && try==1) )
				dir <= ~dir;
	end

//PLL
mypll mypll_ (
	.areset( 1'b0 ),
	.inclk0( CLK100MHZ ),
	.phasecounterselect( 3'b011 ),
	.phasestep( phase_step ),
	.phaseupdown( dir ),
	.scanclk( wc0 ),
	.c0( wc0 ),
	.c1( wc1 ),
	//.c2( wc2 ),
	.locked( wlocked ),
	.phasedone( wpdone )
	);

reg [3:0]state;
reg [7:0]sending_bit_idx = 0;
wire [7:0]w_send_byte;
assign w_send_byte = (sending_bit_idx < 128) ? (echo_fixed_array[sending_bit_idx] ? 8'h31 : 8'h30 ) :
							(sending_bit_idx== 128) ? 8'h0D : 8'h0A;
wire w_send; assign w_send = (state==1);
wire w_busy;

serial serial_inst(
	.reset( ~wlocked ),
	.clk100( wc0 ),
	.rx( 1'b0 ) ,
	.sbyte( w_send_byte ),
	.send( w_send ),
	.rx_byte(),
	.rbyte_ready(),
	.tx( FTDI_BD1 ),
	.busy( w_busy ),
	.rb()
	);
	
always @(posedge wc0 or negedge wlocked )
	if(~wlocked)
		state <= 0;
	else
	case(state)
		0: if( ~w_busy ) state <= 1; //wait send completed
		1: state <= 2;
		2: state <= 3;
		3: state <= 0;
	endcase
	
always @(posedge wc0 or negedge wlocked )
	if(~wlocked)
		sending_bit_idx <= 0;
	else
	if( state==3 ) begin
		if( sending_bit_idx==129 )
			sending_bit_idx <= 0;
		else
			sending_bit_idx <= sending_bit_idx+1;
	end
	
endmodule
