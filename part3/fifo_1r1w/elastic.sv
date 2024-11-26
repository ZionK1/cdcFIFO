module elastic
  #(parameter [31:0] width_p = 8
    /* verilator lint_off WIDTHTRUNC */
   ,parameter [0:0] datapath_gate_p = 0
   ,parameter [0:0] datapath_reset_p = 0
   /* verilator lint_on WIDTHTRUNC */
   )
  (input [0:0] clk_i
  ,input [0:0] reset_i

  ,input [width_p - 1:0] data_i
  ,input [0:0] valid_i
  ,output [0:0] ready_o 

  ,output [0:0] valid_o 
  ,output [width_p - 1:0] data_o 
  ,input [0:0] ready_i
  );

  logic [0:0] full_r;  
  logic [width_p-1:0] data_r; 

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      full_r <= 1'b0;  
      if (datapath_reset_p)
        data_r <= '0;  
    end
    else begin
      if (ready_o & valid_i)   // Ready-valid handshake
        full_r <= 1'b1;
      else if (ready_i)       
        full_r <= 1'b0;
      
      if (datapath_gate_p) begin // When datapath_gate_p == 1
        if (valid_i & ready_o) // and valid_i & ready_o == 1
          data_r <= data_i;
      end
      else begin
        if (ready_o) // If ready_o == 1, update data_o
          data_r <= data_i;
      end
    end
  end

  assign ready_o = ~full_r | ready_i;  // Ready to accept new data if empty or downstream is ready
  assign valid_o = full_r;              // Output is valid when we have data stored
  assign data_o = data_r;

endmodule