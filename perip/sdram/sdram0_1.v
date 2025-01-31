/*
    DSRAM工作原理：
    读：
      1. 先根据存储体编号选择一个目标存储体
      2. 通过行地址激活(active)目标存储体中的一行: 
        目标存储体中的读出放大器(sence amplifier)会检测这一行所有存储单元中的电量, 从而得知每个存储单元存放的是1还是0
        一个读出放大器主要由一对交叉配对反相器构成, 因此可以存储信息, 故存储体中的读出放大器也称行缓冲(row buffer), 可以存储一行信息.
      3. 根据列地址从目标存储体的行缓冲中各选出数据, 作为读出的结果输出到DRAM颗粒芯片的外部
    写：
      1. 先将需要写入的数据写到行缓冲中的相应位置
      2. 然后对相应存储单元中的电容进行充电或放电操作, 从而将行缓冲中的内容转移到存储单元中. 如果要访问另一行的数据, 在激活另一行之前, 还需要先将已激活的当前行的信息写回存储单元, 这个过程称为预充电(precharge).
    DSRAM实现逻辑：
      1. 读
        输入：
        输出：读到的数据

      2. 写
        输入：
        输出：z
  */

module sdram0_1(
  input        clk, // 时钟信号
  input        cke, // 时钟使能信号
  input        cs,  // 命令信号
  input        ras, // 命令信号
  input        cas, // 命令信号
  input        we,  // 命令信号
  input [12:0] a,   // 地址（行）   13行-9列
  input [ 1:0] ba,  // 存储体地址（矩阵）
  input [ 1:0] dqm, // 数据掩码  11-0byte 10-1byte
  inout [15:0] dq   // 数据
);
  /*
    状态机设置：IDLE(NOP or COMMAND INHIBIT) --(cmd=0b0100)--> WRITE --> IDLE
                                            --(cmd=0b0101)--> READ --(去看控制器逻辑，判断等待几个周期)-->  IDLE

  */
  wire  [2:0]  cmd = {ras, cas, we};
  //-----------------------------------------------------------------
// Key Params
//-----------------------------------------------------------------
parameter SDRAM_MHZ              = 50;
parameter SDRAM_ADDR_W           = 24;
parameter SDRAM_COL_W            = 9;
parameter SDRAM_READ_LATENCY     = 2;
  localparam SDRAM_BANK_W          = 2;
localparam SDRAM_DQM_W           = 2;
localparam SDRAM_BANKS           = 2 ** SDRAM_BANK_W;
localparam SDRAM_ROW_W           = SDRAM_ADDR_W - SDRAM_COL_W - SDRAM_BANK_W;

  reg   [15:0]  wdata;
  reg   [15:0]  rdata;
  reg   [15:0]  dout;
  reg   [1:0]   bank_addr;
  reg   [8:0]   col_addr;
    // 高地址为1 7'b101000【1】
  wire  [31:0]  addr = {7'b1010001, {active_row_q[bank_addr], bank_addr, col_addr}, 1'b0};
  reg   [1:0]   data_mask;
  reg   [2:0]   read_delay_counter;

  reg   [2:0]  mode_reg_cas;
  reg   [2:0]  mode_reg_burst_len;

  reg   [2:0]   next_state;
  reg   [2:0]   con_state;

  reg [SDRAM_ROW_W-1:0]  active_row_q[0:SDRAM_BANKS-1];
  
 

  import "DPI-C" function void sdram_read(input int raddr, output int rdata, input byte mask);
  import "DPI-C" function void sdram_write(input int raddr, input int rdata, input byte mask);

  parameter [2:0] STATE_IDLE = 3'b0, STATE_WRITE0 = 3'b01, STATE_READ = 3'b11, STATE_ACTIVATE = 3'b101, STATE_LOAD_MODEREG = 3'b110;
  parameter [2:0] CMD_NOP = 3'b111, CMD_ACTIVE = 3'b011, CMD_READ = 3'b101, CMD_WRITE = 3'b100, CMD_BTERMINATE = 3'b110, CMD_LOAD_MODEREG = 3'b000;

  always @(posedge clk ) begin
    if(~cke) begin
      con_state <= STATE_IDLE;
    end else begin
      con_state <= next_state;
    end
  end

  always @(*) begin
    next_state = con_state;
    case (con_state)
      STATE_IDLE: begin
        next_state = STATE_IDLE;
        if(cs | cmd == CMD_NOP) begin
          // next_state <= STATE_IDLE;
        end else if(cmd == CMD_WRITE) begin
          next_state = STATE_WRITE0;
        end else if(cmd == CMD_READ) begin
          next_state = STATE_READ;
        end else if(cmd == CMD_ACTIVE) begin
          next_state = STATE_ACTIVATE;
        end else if(cmd == CMD_BTERMINATE) begin
          next_state = STATE_IDLE;
        end else if(cmd == CMD_LOAD_MODEREG) begin
          next_state = STATE_LOAD_MODEREG;
        end
      end
      // get data
      STATE_WRITE0: begin
        if(cmd == CMD_WRITE) begin
          next_state = STATE_WRITE0;
        end else begin
          next_state = STATE_IDLE;
        end
      end
      STATE_ACTIVATE: begin
        next_state = STATE_IDLE;
      end
      STATE_READ: begin
        if (read_delay_counter >= mode_reg_cas) begin
          next_state = STATE_IDLE;
        end
      end
      STATE_LOAD_MODEREG: begin
        next_state = STATE_IDLE;
      end
      default: begin
        $error("Invalid State--[%s]", con_state);  
      end
    endcase
  end
// WRITE
  integer idx;
  always @(posedge clk ) begin
    if(~cke) begin
      // WRITE or READ
      wdata <= 0;
      col_addr <= 0;
      bank_addr <= 0;
      data_mask <= 0;
      dout <= 0;

      // MODE REG
      mode_reg_burst_len <= 0;
      mode_reg_cas <= 0;

      // ACTIVATE
      for (idx=0;idx<SDRAM_BANKS;idx=idx+1)
      active_row_q[idx] <= {SDRAM_ROW_W{1'b0}};
    end else begin
      case (con_state)
        // write: wdata wmask waddr
        STATE_IDLE: begin
          // write
          if(next_state == STATE_WRITE0) begin
            wdata <= dq;
            col_addr <= a[8:0];
            bank_addr <= ba;
            data_mask <= dqm;
          // store the row add = open the row activate
          end else if(next_state == STATE_ACTIVATE) begin
            bank_addr <= ba;
            active_row_q[ba]  <= a;
          end else if(next_state == STATE_READ) begin
            col_addr <= a[8:0];
            bank_addr <= ba;
            data_mask <= dqm;
          end else if(next_state == STATE_LOAD_MODEREG) begin
            {mode_reg_cas, mode_reg_burst_len} <= {a[6:4],a[2:0]};
          end
        end
        STATE_WRITE0: begin
          if(next_state == STATE_WRITE0) begin
            wdata <= dq;
            col_addr <= a[8:0];
            bank_addr <= ba;
            data_mask <= dqm;
          end else begin
            wdata <= dq;
            data_mask <= dqm;
          end
        end
        default: begin
          
        end
      endcase
      
    end
    
  end

  always @(posedge clk ) begin
    if (~cke || next_state == STATE_IDLE) begin
      read_delay_counter <= 0;
    end else begin
      read_delay_counter <= read_delay_counter + 1;
    end 
  end


  always @(posedge clk ) begin
    if (con_state == STATE_WRITE0) 
      sdram_write(addr, {16'b0, wdata}, {{6{1'b1}},data_mask});
  end

  always @(posedge clk ) begin
    if (~cke) begin
      rdata = 0;
    end else if (con_state == STATE_READ) 
      sdram_read(addr, {16'b0, rdata}, {{6{1'b1}},data_mask});
  end


  assign dq = (next_state == STATE_IDLE && con_state == STATE_READ) ? rdata : 16'bz;

endmodule
