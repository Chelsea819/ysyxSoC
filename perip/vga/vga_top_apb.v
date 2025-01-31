module vga_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable, // ignore
  input  [2:0]  in_pprot,   // ignore
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output  reg      in_pready,  // ignore
  output [31:0] in_prdata,  // ignore
  output        in_pslverr, // ignore

  //红绿蓝颜色信号
  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,

  //生成同步信号   
  output        vga_hsync,
  output        vga_vsync,
  //消隐信号
  output        vga_valid 
);

localparam MEM_SIZE           = 2 ** MEM_ADDR;
localparam MEM_ADDR           = MEM_COK_ADDR + MEM_ROW_ADDR;
localparam MEM_COK_ADDR       = 10;
localparam MEM_ROW_ADDR       = 10;

//在标准的640x480的VGA上有效地显示一行信号需要96+48+640+16=800个像素点的时间
parameter h_frontporch = 96;    // 行同步负脉冲宽度为96个像素点时间   
parameter h_active = 144;       // 行消隐后沿需要48个像素点时间
parameter h_backporch = 784;    // 每行显示640个像素点
parameter h_total = 800;        // 最后行消隐前沿需要16个像素点的时间
// 所以一行中显示像素的时间为640个像素点时间，一行消隐时间为160个像素点时间。


//在标准的640x480的VGA上有效显示一帧图像需要2+33+480+10=525行时间
parameter v_frontporch = 2;     // 场同步负脉冲宽度为2个行显示时间
parameter v_active = 35;        // 场消隐后沿需要33个行显示时间
parameter v_backporch = 515;    // 每场显示480行
parameter v_total = 525;        // 场消隐前沿需要10个行显示时间
// 一帧显示时间为525行显示时间，一帧消隐时间为45行显示时间

// 在640x480的VGA上的一幅图像需要个像素点的时间。
// 每秒扫描60帧共需要约25M个像素点的时间

reg [9:0] x_cnt;
reg [9:0] y_cnt;
wire h_valid;
wire v_valid;

wire [9:0] h_addr;
wire [9:0] v_addr;
wire [23:0] vga_data;

always @(posedge clock) begin
    if(reset == 1'b1) begin
        x_cnt <= 1;
        y_cnt <= 1;
    end
    else begin
        if(x_cnt == h_total)begin
            x_cnt <= 1;
            if(y_cnt == v_total) y_cnt <= 1;
            else y_cnt <= y_cnt + 1;
        end
        else x_cnt <= x_cnt + 1;
    end
end

//生成同步信号    
assign vga_hsync = (x_cnt > h_frontporch);
assign vga_vsync = (y_cnt > v_frontporch);
//生成消隐信号
assign h_valid = (x_cnt > h_active) & (x_cnt <= h_backporch);
assign v_valid = (y_cnt > v_active) & (y_cnt <= v_backporch);
assign vga_valid = h_valid & v_valid;

//计算当前有效像素坐标
assign h_addr = h_valid ? (x_cnt - 10'd145) : 10'd0;
assign v_addr = v_valid ? (y_cnt - 10'd36) : 10'd0;
//设置输出的颜色值
assign {vga_r, vga_g, vga_b} = mem[{v_addr, h_addr}];

/*
  对VGA的读：
  读出屏幕大小
  16^5 = 2^20 = 2MB

  对VGA的写:
  写入像素点
*/
  parameter [1:0] STATE_IDLE = 2'b0, STATE_WRITE = 2'b10;
  reg [1:0] con_state;
  reg [1:0] next_state;
  reg [31:0] rdata;

  reg [23:0] mem [MEM_SIZE-1:0];

  wire [19:0] addr = in_paddr[21:2];

  always @(posedge clock ) begin
    if (reset) begin
      for (logic [19:0] i = 20'h0; i < 20'hfffff; i += 20'h1) begin
        mem[i[19:0]] = 24'h000000;	// rocket-chip/src/main/scala/util/DescribedSRAM.scala:17:26
      end
    end else if (in_psel & in_pwrite) begin
        mem[addr] <= in_pwdata[23:0] & {{8{in_pstrb[2]}}, {8{in_pstrb[1]}}, {8{in_pstrb[0]}}};
    end
  end

  always @(posedge clock ) begin
    if (reset) begin
      in_pready <= 0;
    end else if (in_psel & in_pwrite) begin
      in_pready <= 1;
    end else begin
      in_pready <= 0;
    end
  end

always @(*) begin
  if(in_psel & ~in_pwrite)
    $error("Error Read!");
end




endmodule
