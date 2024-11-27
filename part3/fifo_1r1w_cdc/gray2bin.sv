module gray2bin
  #(parameter width_p = 5)
   (input [width_p - 1 : 0] gray_i
    ,output [width_p - 1 : 0] bin_o);

  logic [width_p-1:0] temp_o;

  always_comb begin
    // MSB passed down
    temp_o[width_p-1] = gray_i[width_p-1];
    
    // Xor prev bit of temp_o and curr bit of gray_i as we go
    for (int i = width_p-2; i >= 0; i--) begin
      temp_o[i] = temp_o[i+1] ^ gray_i[i];
    end
  end

  assign bin_o = temp_o;

endmodule
