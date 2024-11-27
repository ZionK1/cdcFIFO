module bin2gray
  #(parameter width_p = 5)
  (input [width_p - 1 : 0] bin_i
  ,output [width_p - 1 : 0] gray_o);

   // Your code here 
  /*
  assign gray_o[width_p-1] = bin_i[width_p-1];

  logic [width_p - 2:0] temp_o;
  always_comb begin
    for (int i = 0; i < width_p - 1; i++) begin
      temp_o[i] = bin_i[i+1] ^ bin_i[i];
    end
  end

  assign gray_o[width_p-2:0] = temp_o;
  */

  logic [width_p-1:0] temp_o;
  always_comb begin
    // MSB passed down
    temp_o[width_p-1] = bin_i[width_p-1];

    // Xor bits of bin_i
    for (int i = 0; i < width_p-1; i++) begin
      temp_o[i] = bin_i[i+1] ^ bin_i[i];
    end
  end

  assign gray_o = temp_o;

endmodule
