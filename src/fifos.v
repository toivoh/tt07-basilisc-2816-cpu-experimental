/*
 * Copyright (c) 2024 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`include "common.vh"

module FIFO #( parameter DEPTH=3, BITS=1 ) (
		input wire clk, reset,

		input wire add, remove,
		input wire [BITS-1:0] new_entry,
		output wire [BITS-1:0] last_entry,
		output wire empty, full,
		output reg [$clog2(DEPTH+1)-1:0] num_entries
	);
	localparam NE_BITS = $clog2(DEPTH + 1);

	genvar i;

	reg [BITS-1:0] entries[0:DEPTH];
	always @(posedge clk) entries[0] <= 'X;

	always @(posedge clk) begin
		if (reset) begin
			num_entries <= 0;
		end else begin
			num_entries <= num_entries + ({{(NE_BITS-1){1'b0}}, add} - {{(NE_BITS-1){1'b0}}, remove});
		end

		if (add) begin
			entries[1] <= new_entry;
		end
	end

	generate
		for (i=2; i <= DEPTH; i++) begin
			reg [BITS-1:0] entry_delayed;
			delay_buffer #(.BITS(BITS), .ENABLE_MASK(`DELAY_BUFFER_FIFO_MASK)) delay_entry(.in(entries[i-1]), .out(entry_delayed));
			always @(posedge clk) begin
				if (add) entries[i] <= entry_delayed;
			end
		end
	endgenerate

	assign last_entry = entries[num_entries];
	assign empty = (num_entries == 0);
	assign full  = (num_entries == DEPTH);
endmodule : FIFO

/*
Shift register based FIFO.
Entries start at the top (depth=0) and fall to the bottom if there is no valid entry at the next depth.
Has a latency of at least DEPTH, but should be more area efficient.
*/
module SRFIFO #( parameter DEPTH=3, BITS=1 ) (
		input wire clk, reset,

		input wire add, remove, // only add when can_add is high, only remove when last_valid is
		input wire [BITS-1:0] new_entry,
		output wire [BITS-1:0] last_entry,
		output wire can_add, last_valid,
		output reg [$clog2(DEPTH+1)-1:0] num_entries // should track the number of valid entries as long as only adding/removing when allowed
	);
	localparam NE_BITS = $clog2(DEPTH + 1);

	genvar i;

	reg [BITS-1:0] sr_entries[DEPTH];
	reg [DEPTH-1:0] valid;

	wire [DEPTH:0] valid_ext = {!remove, valid};

	always @(posedge clk) begin
		if (reset) begin
			num_entries <= 0;
		end else begin
			num_entries <= num_entries + ({{(NE_BITS-1){1'b0}}, add} - {{(NE_BITS-1){1'b0}}, remove});
		end

		if (reset) begin
			valid[0] <= 0;
		end else if (add) begin
			valid[0] <= 1;
			sr_entries[0] <= new_entry;
		end else if (!valid_ext[1]) begin // empty space ahead; shift forward
			valid[0] <= 0;
		end
	end

	generate
		for (i=1; i < DEPTH; i++) begin
			always @(posedge clk) begin
				if (reset) begin
					valid[i] <= 0;
				end else if (valid[i-1] && !valid[i]) begin // shift in from position i
					valid[i]   <= 1;
					sr_entries[i] <= sr_entries[i-1];
				end else if (!valid_ext[i+1]) begin // empty space ahead; shift forward and 
					valid[i] <= 0;
				end
			end
		end
	endgenerate

	assign can_add = !valid[0];
	assign last_valid = valid[DEPTH-1];
	assign last_entry = sr_entries[DEPTH-1];
endmodule : SRFIFO


/*
Like SRFIFO, but using latches.
new_entry must be stable between the cycle after add is raised and the next cycle.
*/
module SRFIFO_latched #( parameter DEPTH=3, BITS=1 ) (
		input wire clk, reset,

		input wire add, remove, // only add when can_add is high, only remove when last_valid is
		input wire [BITS-1:0] new_entry, // new_entry must be stable between the cycle after add is raised and the next cycle.
		output wire new_entry_sampled, // when high, new_entry can be changed next cycle
		output wire [BITS-1:0] last_entry,
		output wire can_add, last_valid
	);

	genvar i;

	wire [BITS-1:0] data[DEPTH+1];
	assign data[0] = new_entry;
	assign last_entry = data[DEPTH];

	wire [DEPTH:0] valid; // 1 .. DEPTH are for the latch registers
	assign valid[0] = add;
	assign can_add = !valid[1];
	assign last_valid = valid[DEPTH];

	wire [DEPTH:0] sampling_in; // 0 .. DEPTH - 1 are the latch registers
	assign sampling_in[DEPTH] = remove;

	// Transfer if the current position is valid and the next one is free
	wire [DEPTH-1:0] we = valid[DEPTH-1:0] & ~valid[DEPTH:1];
	// Invalidate when the next register reads ==> can update one cycle after the read.
	wire [DEPTH-1:0] invalidate = sampling_in[DEPTH:1];
	assign new_entry_sampled = sampling_in[0];

	generate
		for (i = 0; i < DEPTH; i++) begin
			latch_register #(.BITS(BITS)) register(
				.clk(clk), .reset(reset),
				.in(data[i]), .out(data[i+1]),
				.we(we[i]), .sampling_in(sampling_in[i]),
				.invalidate(invalidate[i]), .out_valid(valid[i+1])
			);
		end
	endgenerate
endmodule : SRFIFO_latched
