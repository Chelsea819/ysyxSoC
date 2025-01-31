// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
// `define FAST_FLASH

`define SPI_ADDR 32'h10001000
`define SPI_MASTER_TX0  	`SPI_ADDR + 0 
`define SPI_MASTER_TX1  	`SPI_ADDR + 4
`define SPI_MASTER_RX1  	`SPI_ADDR + 4 
`define SPI_MASTER_RX0  	`SPI_ADDR + 0 
`define SPI_MASTER_DIVIDER  `SPI_ADDR + 32'h14
`define SPI_MASTER_SS  		`SPI_ADDR + 32'h18
`define SPI_MASTER_CTRL  	`SPI_ADDR + 32'h10

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else
reg [31:0] prdata_reg;
wire    xip_enable;  
wire    finish_data_trans;  
reg [1:0] con_state ;
reg [1:0] next_state ;
reg [2:0] counter; // 5 
wire [31:0] spi_top_in_paddr  ;
wire        spi_top_in_psel   ;
wire        spi_top_in_penable;
wire [2:0]  spi_top_in_pprot  ;
wire        spi_top_in_pwrite ;
wire [31:0] spi_top_in_pwdata ;
wire [3:0]  spi_top_in_pstrb  ;
wire        spi_top_in_pready ;
wire [31:0] spi_top_in_prdata ;
wire        spi_top_in_pslverr;
assign xip_enable = (in_paddr[31:28] == 4'd3);
parameter SPI_REGISTER = 2'b0, DATA_TRANS = 2'b01, DATA_RX_READ = 2'b10, RESET_SS = 2'b11;
parameter [7:0] write_cmd = 8'h03;

always @(*) begin
  if (in_pwrite & xip_enable) begin
    $error;
  end
end

// con state
always @(posedge clock) begin
  if (reset) begin
    con_state <= SPI_REGISTER;
  end else begin
    con_state <= next_state;
  end
end

always @(*) begin
  case (con_state)
  /* 写寄存器
    *(volatile uint64_t *)(SPI_MASTER_TX0) = 0x0300000000000000 | ((((uint64_t)addr)<<32) & 0x00ffffff00000000);	// cmd and raddr
	*(volatile uint32_t *)(SPI_MASTER_DIVIDER) = 60;
	*(volatile uint32_t *)(SPI_MASTER_SS) = 0b00000001;		// select flash
	*(volatile uint32_t *)(SPI_MASTER_CTRL) = 0x00000040;	// set CHAR_LEN
	*(volatile uint32_t *)(SPI_MASTER_CTRL) = 0x00000140;	// set start bit to begin transfer and 
  */
    SPI_REGISTER: begin
      // next_state = (counter == 3'd4) ? DATA_TRANS : next_state;
      if (counter == 3'd4 && spi_top_in_pready) begin
        next_state = DATA_TRANS;
      end else begin
        next_state = SPI_REGISTER;
      end
    end
    // 传完之后进入最后一个状态
    DATA_TRANS: begin
      // next_state = (spi_top_in_prdata[8] == 1'b0 && spi_top_in_pready) ? DATA_RX_READ : next_state;
      if (spi_top_in_prdata[8] == 1'b0 && spi_top_in_pready) begin
        next_state = DATA_RX_READ;
      end else begin
        next_state = DATA_TRANS;
      end
    end
    // 直接读取即可并设置SS为0
    DATA_RX_READ: begin
      // next_state = spi_top_in_pready ? RESET_SS : next_state;
      if (spi_top_in_pready) begin
        next_state = RESET_SS;
      end else begin
        next_state = DATA_RX_READ;
      end
    end
    // 直接读取即可并设置SS为0
    RESET_SS: begin
      // next_state = spi_top_in_pready ? SPI_REGISTER : next_state;
      if (spi_top_in_pready) begin
        next_state = SPI_REGISTER;
      end else begin
        next_state = RESET_SS;
      end
    end
    default: begin
      $error;
    end
  endcase
end

always @(posedge clock ) begin
  if (reset) begin
    counter <= 0;
  end else begin
    case (con_state)
      SPI_REGISTER: begin
        if (xip_enable & spi_top_in_pready) begin
          counter <= (counter < 3'd4 ) ? counter + 3'd1 : 3'd0;
        end
      end
      default: begin
        counter <= 0;
      end
    endcase
  end
end

// 根据状态机的情况，判断此时应该进行什么传输
/* 写寄存器
    *(volatile uint64_t *)(SPI_MASTER_TX0) = 0x0300000000000000 | ((((uint64_t)addr)<<32) & 0x00ffffff00000000);	// cmd and raddr
	*(volatile uint32_t *)(SPI_MASTER_DIVIDER) = 60;
	*(volatile uint32_t *)(SPI_MASTER_SS) = 0b00000001;		// select flash
	*(volatile uint32_t *)(SPI_MASTER_CTRL) = 0x00000040;	// set CHAR_LEN
	*(volatile uint32_t *)(SPI_MASTER_CTRL) = 0x00000140;	// set start bit to begin transfer and 
  */
assign {spi_top_in_paddr, spi_top_in_pwdata, spi_top_in_pstrb, spi_top_in_pwrite} 
    = (counter == 3'd0 && xip_enable && con_state == SPI_REGISTER) ? {`SPI_MASTER_TX1, ({write_cmd, 24'b0} | {8'b0, in_paddr[23:0]}), 4'hf, 1'b1} :    
                    (counter == 3'd1) ? {`SPI_MASTER_DIVIDER,  32'd1, 4'hf, 1'b1} :
                    (counter == 3'd2) ? {`SPI_MASTER_SS,       32'b1, 4'hf, 1'b1} :
                    (counter == 3'd3) ? {`SPI_MASTER_CTRL,     32'h00000040, 4'hf, 1'b1} :
                    (counter == 3'd4) ? {`SPI_MASTER_CTRL,     32'h00000140, 4'hf, 1'b1} :
                    (con_state == DATA_TRANS) ? {`SPI_MASTER_CTRL,32'h0,4'h0,1'b0} :
                    (con_state == DATA_RX_READ) ? {`SPI_MASTER_RX0,32'h0,4'h0,1'h0} : 
                    (con_state == RESET_SS) ? {`SPI_MASTER_SS, 32'b0, 4'hf, 1'b1} : 0;

assign {in_pready, in_prdata} = {con_state == RESET_SS} ? {spi_top_in_pready, prdata_reg}: 0;


always @(posedge clock) begin
  if (reset) begin
    prdata_reg <= 0;
  end else if(con_state == DATA_RX_READ && next_state == RESET_SS) begin
    prdata_reg <= spi_top_in_prdata;
  end
end

spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(spi_top_in_paddr[4:0]), // waddr raddr
  .wb_dat_i(spi_top_in_pwdata),
  .wb_dat_o(spi_top_in_prdata),
  .wb_sel_i(spi_top_in_pstrb),
  .wb_we_i (spi_top_in_pwrite),
  .wb_stb_i(in_psel),
  .wb_cyc_i(in_penable),
  .wb_ack_o(spi_top_in_pready), // 数据读完了 or 写完了
  .wb_err_o(in_pslverr),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);
// spi_top u0_spi_top (
//   .wb_clk_i(clock),
//   .wb_rst_i(reset),
//   .wb_adr_i(in_paddr[4:0]),
//   .wb_dat_i(in_pwdata),
//   .wb_dat_o(in_prdata),
//   .wb_sel_i(in_pstrb),
//   .wb_we_i (in_pwrite),
//   .wb_stb_i(in_psel),
//   .wb_cyc_i(in_penable),
//   .wb_ack_o(in_pready),
//   .wb_err_o(in_pslverr),
//   .wb_int_o(spi_irq_out),

//   .ss_pad_o(spi_ss),
//   .sclk_pad_o(spi_sck),
//   .mosi_pad_o(spi_mosi),
//   .miso_pad_i(spi_miso)
// );

`endif // FAST_FLASH

endmodule
