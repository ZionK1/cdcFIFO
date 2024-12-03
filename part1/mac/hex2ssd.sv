module hex2ssd
  (input [3:0] hex_i
  ,output [6:0] ssd_o
  );

  logic [6:0] temp_o;

  // Common cathode configuration, so set parts we want off high
  always_comb begin
    temp_o = 7'b0;
    case (hex_i)
      4'h0 : temp_o = 7'b1000000;
      4'h1: temp_o = 7'b1111001; 
      4'h2: temp_o = 7'b0100100; 
      4'h3: temp_o = 7'b0110000; 
      4'h4: temp_o = 7'b0011001; 
      4'h5: temp_o = 7'b0010010; 
      4'h6: temp_o = 7'b0000010;
      4'h7: temp_o = 7'b1111000; 
      4'h8: temp_o = 7'b0000000; 
      4'h9: temp_o = 7'b0011000; 
      4'hA: temp_o = 7'b0001000; 
      4'hB: temp_o = 7'b0000011; 
      4'hC: temp_o = 7'b1000110;
      4'hD: temp_o = 7'b0100001; 
      4'hE: temp_o = 7'b0000110;
      4'hF: temp_o = 7'b0001110; 
      default : ;
    endcase
  end

  assign ssd_o = temp_o;

endmodule