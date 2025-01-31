module ps2_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,    // 选择键盘设备
  input         in_penable, 
  input  [2:0]  in_pprot,   // ignore
  input         in_pwrite,  // ignore
  input  [31:0] in_pwdata,  // ignore
  input  [3:0]  in_pstrb,   // ignore
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,   // ignore

  input         ps2_clk,
  input         ps2_data
);
// 外面需要套一个状态机控制输出和存入
    wire reset_n = ~reset;
    wire nextdata_n;    // internal signal, for test
    reg [9:0] buffer;        // ps2_data bits
    reg [7:0] fifo[7:0];     // data fifo
    reg [2:0] w_ptr;   // fifo write and read pointers
    reg [2:0] r_ptr;   // fifo write and read pointers
    reg [3:0] count;  // count ps2_data bits
    reg       ready;

    always @(*) begin
        if(in_psel & in_pwrite)
            $error("Error Write!");
    end

    parameter [1:0] STATE_IDLE = 2'b0, STATE_DATA = 2'b1, STATE_NULL = 2'b10;
    reg [1:0] next_state;
    reg [1:0] con_state;
    reg [7:0] rdata;


    always @(posedge clock ) begin
        if(~reset_n) begin
            con_state <= STATE_IDLE;
        end else begin
            con_state <= next_state;
        end
    end

    always @(*) begin
        next_state = con_state;
        case (con_state)
            STATE_IDLE: begin
                if(in_psel & ready) begin
                    next_state = STATE_DATA;
                end else if (in_psel) begin
                    next_state = STATE_NULL;
                end
            end 
            STATE_DATA: begin
                next_state = STATE_IDLE;
            end
            STATE_NULL: begin
                next_state = STATE_IDLE;
            end
            default: begin
                
            end 
        endcase
    end

    assign nextdata_n = ~(con_state == STATE_DATA);


    // detect falling edge of ps2_clk
    reg [2:0] ps2_clk_sync; // 记录PS2时钟信号的历史信息，并检测时钟下降沿

    always @(posedge clock) begin
        ps2_clk_sync <=  {ps2_clk_sync[1:0],ps2_clk};
    end

    wire sampling = ps2_clk_sync[2] & ~ps2_clk_sync[1]; // 发现时钟下降沿时，将sampling置一

    // 读写按照原本正常的逻辑进行
    /*
    额外对通码断码的数目进行处理，读出，改变读指针的量
    要控制next_n的逻辑，其实也是在控制读指针的量
    */
    always @(posedge clock) begin
        if (reset_n == 0) begin // reset
            count <= 0; w_ptr <= 0; r_ptr <= 0; ready<= 0;
        end
        else begin
            if ( ready ) begin // read to output next data
                if(nextdata_n == 1'b0) //read next data
                begin
                    r_ptr <= r_ptr + 3'b1;
                    if(w_ptr==(r_ptr+1'b1)) //empty
                        ready <= 1'b0;
                end
            end
            if (sampling) begin // 逐位接受数据并放入缓冲区fifo队列，收集完11个bit后将缓冲区转移至数据fifo
                if (count == 4'd10) begin
                if ((buffer[0] == 0) &&  // start bit
                    (ps2_data)       &&  // stop bit
                    (^buffer[9:1])) begin      // odd  parity
                    fifo[w_ptr] <= buffer[8:1];  // kbd scan code
                    w_ptr <= w_ptr+3'b1;
                    ready <= 1'b1;
                end
                count <= 0;     // for next
                end else begin
                buffer[count] <= ps2_data;  // store ps2_data
                count <= count + 3'b1;
                end
            end
        end
    end
    assign in_prdata = ((in_paddr[3:0] == 0 && (con_state == STATE_DATA)) ? {4{fifo[r_ptr]}} : 0); //always set output data


    assign in_pready = (con_state == STATE_DATA) || (con_state == STATE_NULL);

endmodule
