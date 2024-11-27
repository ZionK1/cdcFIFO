module inelastic
  #(parameter [31:0] width_p = 8
   /* verilator lint_off WIDTHTRUNC */
   ,parameter [0:0] datapath_reset_p = 0
   /* verilator lint_on WIDTHTRUNC */
   )
  (input [0:0] clk_i
  ,input [0:0] reset_i

  ,input [0:0] en_i

  // Fill in the ranges of the busses below
  ,input [width_p - 1 : 0] data_i
  ,output [width_p - 1 : 0] data_o);

  logic [width_p - 1:0] data_r;

  always @(posedge clk_i) begin
    if (reset_i & datapath_reset_p) begin // Reset to 0 when datapath_reset_p and reset_i == 1
      data_r <= {width_p{1'b0}};
    end else if (en_i) begin
      data_r <= data_i;               // Save the data when en_i is 1
    end
  end

  assign data_o = data_r;

endmodule