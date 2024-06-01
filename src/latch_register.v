/*
 * Copyright (c) 2024 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`include "common.vh"

/*
Latch based register
*/
module latch_register #( parameter BITS=16 ) (
		input wire clk, reset,

		input wire [BITS-1:0] in,
		output wire [BITS-1:0] out,

		input wire we, // Initiate write, in must be stable between next cycle and the one after.
		output wire sampling_in, // When high, in must not be changed during the next cycle.
//		output wire in_sampled, // When high, in can be changed next cycle. Doesn't go high until we goes low.
		input wire invalidate,
		output wire out_valid // out is valid. Goes high after writing, low after invalidate.
	);

	genvar i;

	(* keep = "true" *) reg we_reg;
//	reg in_sampled_reg;
	reg valid_reg;

	always @(posedge clk) begin
		if (reset) begin
			we_reg <= 0;
//			in_sampled_reg <= 0;
			valid_reg <= 0;
		end else begin
			we_reg <= we;
//			in_sampled_reg <= we_reg && !we;
			valid_reg <= (valid_reg && !invalidate) || we;
		end
	end

`ifdef TEST_LATE_OPEN_LATCHES
	// Assume that the gate stays open an additional cycle
	reg late_we_reg;
	wire gate = we_reg || late_we_reg;

	// Model the latch with a flipflop and a mux
	reg [BITS-1:0] value;
	assign out = gate ? in : value;

	always @(posedge clk) begin
		if (reset) late_we_reg <= 0;
		else late_we_reg <= we_reg;

		if (gate) value <= in;
	end
`else
	wire gate = we_reg;
`ifdef SIM
	// Infer latches
	reg [BITS-1:0] out_latch;
	always @(*) if (gate) out_latch <= in;
	assign out = out_latch;
`else
	generate
		for (i = 0; i < BITS; i++) begin
			(* keep = "true" *) sky130_fd_sc_hd__dlxtp_1 latch(
				.D(in[i]), .GATE(gate), .Q(out[i])
			);
		end
	endgenerate
`endif
`endif

	assign sampling_in = we_reg;
//	assign in_sampled = in_sampled_reg;
	assign out_valid = valid_reg;
endmodule : latch_register
