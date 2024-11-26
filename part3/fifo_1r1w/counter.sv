module counter
  #(parameter width_p = 4,
    // Students: Using lint_off/lint_on commands to avoid lint checks,
    // will result in 0 points for the lint grade.
    /* verilator lint_off WIDTHTRUNC */
    parameter [width_p-1:0] reset_val_p = '0)
    /* verilator lint_on WIDTHTRUNC */
   (input [0:0] clk_i
   ,input [0:0] reset_i
   ,input [0:0] up_i
   ,input [0:0] down_i
   ,output [width_p-1:0] count_o);

  // Your code here:
  logic [width_p-1:0] temp_o;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin // If reset_i, set reset_val_p
      temp_o <= reset_val_p;
    end else if (up_i && !down_i) begin // If up_i == 1, count up
      temp_o <= temp_o + 1'b1;
    end else if (!up_i && down_i) begin // If down_i == 1, count down
      temp_o <= temp_o - 1'b1;
    end // Otherwise do nothing
  end

  assign count_o = temp_o;
endmodule