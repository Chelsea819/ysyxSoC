module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);
  wire reset = ss;
/**
1. 接收一个8位的数据
2. 输出该数据的位翻转结果

**/
  typedef enum [0:0] {data_t, result_t} state_t;
  reg       state;
  reg [2:0] counter;
  reg [7:0] data;
  reg [7:0] result;

  wire [7:0] data_reverse = {data[1], data[2], data[3], data[4], data[5], data[6], data[7], mosi};
  
  // wire [31:0] data_bswap = {rdata[7:0], rdata[15:8], rdata[23:16], rdata[31:24]};
  always @(posedge sck or posedge reset) begin
    if (reset) begin
      state <= data_t;
    end else begin
      case (state)
        data_t: state <= (counter == 3'd7) ? result_t : state;
        result_t: state <= state;
      endcase
    end
  end

  always @(posedge sck or posedge  reset) begin
    if (reset) begin
      counter <= 0;
    end else begin
      case (state)
        data_t:   counter <= (counter < 3'd7 ) ? counter + 3'd1 : 3'd0;
        result_t: counter <= (counter < 3'd7 ) ? counter + 3'd1 : 3'd0;
      endcase
    end
  end

  always @(posedge sck or posedge reset) begin
    if (reset) begin
      data <= 0;
    end else if (state == data_t && counter < 3'd7) begin
      data <= {mosi, data[7:1]};
    end
  end

  always @(posedge sck or posedge reset) begin
    if (reset) begin
      result <= 0;
    end else if (state == result_t) begin
      result <= {1'b0, {counter == 3'd0 ? data_reverse : result}[7:1]};
    end
  end

  // assign miso = ss ? 1'b1 : ({(state == data_t && counter == 8'd0) ? data_bswap : data}[31]);
  assign miso = ss ? 1'b1 : ({(state == result_t && counter == 3'd0) ? data_reverse : result}[0]);
endmodule
