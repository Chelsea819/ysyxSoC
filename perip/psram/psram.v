module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);
  wire reset = ce_n;
  /*
  实现两种命令
  QSPI协议
  EBh-Quad IO Read
    其命令按1 bit传输, 但地址和数据按4 bit传输, 记为(1-4-4). 
    以读出32位数据为例, EBh命令需要执行8 + 24/4 + 6(读延迟) + 32/4 = 28个SCK时钟.
  Dual SPI协议
  38h-Quad IO Write

  EBh-Quad IO Read四个阶段：
  command(8)->addr(24/4=6)->wait cycle(6)->data(32/4=8)

  38h-Quad IO Write三个阶段：
  command(8)->addr(24/4=6)->data(32/4=8)

  */
  typedef enum [2:0] {cmd_t, addr_t, wait_t, data_t, idle_t} state_t;
  reg  [2:0]     next_state;
  reg   [2:0]     con_state;
  wire            cmd_read_flag = (cmd == 8'heb);
  reg   [2:0]     counter; 
  wire            ren = (con_state == wait_t) && (counter == 3'd0);
  wire            wen = (cmd == 8'h38);
  reg             qpi_mode;
  wire            qpi_mode_check = (cmd == 8'h35) & (con_state == cmd_t) & (counter == 3'd7);    
  reg   [7:0]     cmd;
  reg   [3:0]     dout;
  wire  [3:0]     douten;
  reg   [23:0]    addr;
  reg   [31:0]    data;
  reg   [31:0]    rdata;
  reg   [31:0]    rdata_mv;

  import "DPI-C" function void psram_read(input int addr, output int data);
  import "DPI-C" function void psram_write(input int addr, input int data, input byte len);

  // read data from psram
  always @(posedge sck) begin
    if (cmd_read_flag) begin
      if (ren) begin
        psram_read({8'b0,addr},rdata);
      end 
    end
  end

  // read data from psram
  // TODO
  always @(posedge sck) begin
    if (cmd_read_flag) begin
      if (next_state == data_t) begin
        rdata_mv <= {rdata_mv[27:0],4'b0};
      end else begin
        rdata_mv <= rdata;
      end
    end
  end

  // read data from psram
  always @(posedge ce_n) begin
    if (wen) begin
        psram_write({8'b0,addr},data,{5'b0,counter});
    end
  end

  // output reading data
  always @(posedge sck or posedge reset) begin
    if (reset) begin
      dout <= 0;
    end else if (cmd_read_flag) begin
      if (next_state == data_t) begin
        dout <= rdata_mv[31:28];
      end
    end
  end

  // next_state
  always @(*) begin
      case (con_state)
        idle_t: begin
          next_state = cmd_t;
        end
        cmd_t: begin
          if (counter == 3'd1 & qpi_mode | counter == 3'd7 & ~qpi_mode) begin
            next_state = addr_t;           
          end else
            next_state = cmd_t;
        end
        addr_t: begin
          if (counter == 3'd5) begin
            if (cmd_read_flag) begin
              next_state = wait_t;
            end else begin
              next_state = data_t;
            end
          end else
            next_state = addr_t;
        end
        wait_t: begin
          if (counter == 3'd5) begin
            next_state = data_t;
          end else
            next_state = wait_t;
        end
        data_t: begin
            next_state = data_t;
        end
        default: begin
          next_state = idle_t;
        end
      endcase
  end

  // con_state
  always @(posedge sck or posedge reset) begin
    if (reset) begin
      con_state <= idle_t;
    end else begin
      con_state <= next_state;
    end
  end

  // counter
  always @(posedge sck or posedge reset) begin
    if (reset) begin
      counter <= 0;
    end else begin
      case (con_state)
        idle_t: begin
        end
        cmd_t: begin
          if (counter < 3'd1 & qpi_mode | counter < 3'd7 & ~qpi_mode) begin
            counter <= counter + 3'd1;
          end else begin
            counter <= 0;
          end
        end
        addr_t: begin
          if (counter < 3'd5) begin
            counter <= counter + 3'd1;
          end else begin
            counter <= 0;
          end
        end
        wait_t: begin
          if (counter < 3'd5) begin
            counter <= counter + 3'd1;
          end else begin
            counter <= 0;
          end
        end
        data_t: begin
          if (counter < 3'd7) begin
            counter <= counter + 3'd1;
          end else begin
            counter <= 0;
          end
        end
        default: begin
          
        end
      endcase
    end
  end


  // cmd
  always @(posedge sck or posedge reset) begin
    if (reset) begin
      cmd <= 0;
    end else if(qpi_mode & next_state == cmd_t) begin
      cmd <= {cmd[3:0], dio[3:0]};
    end else if(next_state == cmd_t) begin
      cmd <= {cmd[6:0], dio[0]};
    end
  end

  always @(posedge qpi_mode_check) begin
    if (qpi_mode_check == 1'b1) begin
      qpi_mode <= 1;
    end
  end

  // addr
  always @(posedge sck or posedge reset) begin
    if (reset) begin
      addr <= 0;
    end else if(next_state == addr_t) begin
      addr <= {addr[19:0], dio[3], dio[2], dio[1], dio[0]};
    end
  end

  // write data
  always @(posedge sck or posedge reset) begin
    if (reset) begin
      data <= 0;
    end else if(next_state == data_t) begin
      if (cmd == 8'h38) begin
        data <= {data[27:0], dio[3], dio[2], dio[1], dio[0]}; // write   
    end
  end
end


  assign douten  = cmd_read_flag ? {4{(con_state == data_t)}} : 0;

  // dio write in , read out+in
  assign dio[0] = douten[0] ? dout[0] : 1'bz;
  assign dio[1] = douten[1] ? dout[1] : 1'bz;
  assign dio[2] = douten[2] ? dout[2] : 1'bz;
  assign dio[3] = douten[3] ? dout[3] : 1'bz;


endmodule

