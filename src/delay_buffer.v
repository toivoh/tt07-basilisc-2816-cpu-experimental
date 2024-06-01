/*
 * Copyright (c) 2024 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`include "common.vh"


module delay_buffer #( parameter BITS=16, ENABLE_MASK=-1 ) (
		input wire [BITS-1:0] in,
		output wire [BITS-1:0] out
	);
`ifdef USE_DELAY_BUFFERS
	genvar i;

	wire [BITS-1:0] delayed;
	wire [BITS-1:0] enable_mask = ENABLE_MASK;
	generate
		for (i = 0; i < BITS; i++) begin
			sky130_fd_sc_hd__dlygate4sd3_1 delay(.A(in[i]), .X(delayed[i]));
			assign out[i] = enable_mask[i] ? delayed[i] : in[i];
			/*
			sky130_fd_sc_hd__buf_1 delay(.A(in[i]), .X(out[i]));
			*/
		end
	endgenerate
`else
	assign out = in;
`endif
endmodule : delay_buffer
