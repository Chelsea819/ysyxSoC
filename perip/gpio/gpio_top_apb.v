module gpio_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr, // 地址
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot, // 访问权限--暂时忽略
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output reg [15:0] gpio_out, // 流水灯
  input  [15:0] gpio_in,
  output reg [7:0]  gpio_seg_0,
  output reg [7:0]  gpio_seg_1,
  output reg [7:0]  gpio_seg_2,
  output reg [7:0]  gpio_seg_3,
  output reg [7:0]  gpio_seg_4,
  output reg [7:0]  gpio_seg_5,
  output reg [7:0]  gpio_seg_6,
  output reg [7:0]  gpio_seg_7
);

parameter [1:0] STATE_IDLE = 2'b00, STATE_WRITE = 2'b01, STATE_READ = 2'b10;
parameter [3:0] LED_ADDR = 4'h0, SWITCH_ADDR = 4'h4, PIPE_ADDR = 4'h8;

reg [1:0] con_state;
reg [1:0] next_state;
reg [15:0] rdata;


wire [7:0] segs [15:0];
assign segs[0] = ~8'b11111100;
assign segs[1] = ~8'b01100000;
assign segs[2] = ~8'b11011010;
assign segs[3] = ~8'b11110010;
assign segs[4] = ~8'b01100110;
assign segs[5] = ~8'b10110110;
assign segs[6] = ~8'b10111110;
assign segs[7] = ~8'b11100000;
assign segs[8] = ~8'b11111110;
assign segs[9] = ~8'b11110110;
assign segs[10] = ~8'b11101110;  // A
assign segs[11] = ~8'b00111110;  // b
assign segs[12] = ~8'b10011100;  // C
assign segs[13] = ~8'b01111010;  // d
assign segs[14] = ~8'b10011110;  // E
assign segs[15] = ~8'b10001110;  // F


wire [3:0] addr = in_paddr[3:0];
wire [31:0] data_mask = {{8{in_pstrb[3]}}, {8{in_pstrb[2]}}, {8{in_pstrb[1]}}, {8{in_pstrb[0]}}};

assign in_pready = (con_state == STATE_WRITE) || (con_state == STATE_READ);
assign in_prdata = {16'b0, rdata};

always @(posedge clock ) begin
  if (reset) begin
    con_state <= STATE_IDLE;
  end else begin
    con_state <= next_state;
  end
end


  always @(*) begin
    next_state = con_state;
    case (con_state)
      STATE_IDLE: begin
        if (in_psel) begin
          if (in_pwrite) begin
            next_state = STATE_WRITE;
          end else begin 
            next_state = STATE_READ;
          end 
        end 
      end 
      STATE_WRITE: begin
        next_state = STATE_IDLE;
      end
      STATE_READ: begin
        next_state = STATE_IDLE;
      end
      default: begin
      end 
    endcase
  end

  always @(posedge clock ) begin
    if (reset) begin
      gpio_out <= 0;
    end else if (con_state == STATE_IDLE && next_state == STATE_WRITE) begin
      case (addr)
        LED_ADDR: begin
          gpio_out <= in_pwdata[15:0] & data_mask[15:0];
          // $display("gpio-led!--%x",gpio_out);
        end
        PIPE_ADDR: begin
          if (in_pstrb[0]) begin
            gpio_seg_0 <= segs[in_pwdata[3:0]];
            gpio_seg_1 <= segs[in_pwdata[7:4]];
          end
          if (in_pstrb[1]) begin
            gpio_seg_2 <= segs[in_pwdata[11:8]];
            gpio_seg_3 <= segs[in_pwdata[15:12]];
          end
          if (in_pstrb[2]) begin
            gpio_seg_4 <= segs[in_pwdata[19:16]];
            gpio_seg_5 <= segs[in_pwdata[23:20]];
          end
          if (in_pstrb[3]) begin
            gpio_seg_6 <= segs[in_pwdata[27:24]];
            gpio_seg_7 <= segs[in_pwdata[31:28]];
          end
        end
        default: begin
        end
      endcase
          
    end
      
  end

  always @(posedge clock ) begin
    if (reset) begin
      rdata <= 0;
    end else if (con_state == STATE_IDLE && next_state == STATE_READ) begin
      if (addr == SWITCH_ADDR) begin
        rdata <= gpio_in;
      end
    end
  end


endmodule
