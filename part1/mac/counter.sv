module counter
  #(parameter width_p = 4,
    // Students: Using lint_off/lint_on commands to avoid lint checks,
    // will result in 0 points for the lint grade.
    /* verilator lint_off WIDTHTRUNC */
    parameter [width_p-1:0] reset_val_p = '0,
    // sat_val will always be greater than reset_val_p, and less than (1<< (width_p - 1))
    parameter [width_p-1:0] sat_val_p = '0
    )
    /* verilator lint_on WIDTHTRUNC */
   (input [0:0] clk_i
   ,input [0:0] reset_i
   ,input [0:0] up_i
   ,input [0:0] down_i
   ,output [width_p-1:0] count_o);

  // Your code here:
   logic [width_p-1:0] temp_o;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin // If reset_i == 1, set to reset_val_p
      temp_o <= reset_val_p; 
    end else if (up_i && !down_i) begin // If up_i == 1, count up if under sat_val_p, otherwise stay at sat_val_p
      temp_o <= (temp_o < sat_val_p) ? temp_o + 1'b1 : '0; 
    end else if (!up_i && down_i) begin // If down_i == 1, count down if above 0, otherwise stay at 0
      temp_o <= (temp_o > 0) ? temp_o - 1'b1 : '0;
    end
  end

  assign count_o = temp_o;

endmodule