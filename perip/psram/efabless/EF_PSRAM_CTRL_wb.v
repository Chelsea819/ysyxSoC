/*
	Copyright 2020 Efabless Corp.

	Author: Mohamed Shalan (mshalan@efabless.com)

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at:
	http://www.apache.org/licenses/LICENSE-2.0
	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.
*/

`timescale              1ns/1ps
`default_nettype        none


module PSRAM_QPI_MODE_TRANS (
    input   wire            clk,
    input   wire            rst_n,
    output  wire            done,

    // API
    output  reg             sck,
    output  reg             ce_n,
    input   wire [3:0]      din,
    output  wire [3:0]      dout,
    output  wire            douten
);
    localparam STATE_IDLE = 0;
    localparam STATE_CMD = 1;

    reg             state;
    reg             nstate;
    reg     [3:0]   counter;
    wire    [7:0]   CMD_EBH = 8'h35;

    always @(*) begin
        case (state)
        STATE_IDLE : 
            nstate = STATE_IDLE;
        STATE_CMD  : begin
            if (counter < 4'd8) nstate = STATE_CMD;
            else nstate = STATE_IDLE;
        end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_CMD;
        end
        else begin 
            state <= nstate;
        end
    end

    always @ (posedge clk or negedge rst_n)
        if(!rst_n) counter <= 0;
        else begin
            if (sck & ~done) begin
                counter <= counter + 1;
            end
        end

    // ce_n logic
        always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            ce_n <= 1'b1;
        else if(state == STATE_CMD & rst_n)
            ce_n <= 1'b0;
        else
            ce_n <= 1'b1;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sck <= 1'b0;
        end else if (~ce_n) begin
            sck <= ~ sck;
        end else if (state == STATE_IDLE) begin
            sck <= 1'b0;
        end
    end

    assign dout     = {3'b0, CMD_EBH[7 - counter]};
    assign douten   = ~ce_n;
    assign done     = (counter == 4'd8);

endmodule

// Using EBH Command
module EF_PSRAM_CTRL_wb (
    // WB bus Interface
    input   wire        clk_i,
    input   wire        rst_i,
    input   wire [31:0] adr_i,
    input   wire [31:0] dat_i,
    output  wire [31:0] dat_o,
    input   wire [3:0]  sel_i,
    input   wire        cyc_i,
    input   wire        stb_i,
    output  wire        ack_o,
    input   wire        we_i,

    // External Interface to Quad I/O
    output  wire            sck,
    output  wire            ce_n,
    input   wire [3:0]      din,
    output  wire [3:0]      dout,
    output  wire [3:0]      douten
);

    localparam  ST_IDLE = 1'b0,
                ST_WAIT = 1'b1;

    wire        mr_sck;
    wire        mr_ce_n;
    wire [3:0]  mr_din;
    wire [3:0]  mr_dout;
    wire        mr_doe;

    wire        mw_sck;
    wire        mw_ce_n;
    wire [3:0]  mw_din;
    wire [3:0]  mw_dout;
    wire        mw_doe;

    wire        qpi_sck;
    wire        qpi_ce_n;
    wire [3:0]  qpi_din;
    wire [3:0]  qpi_dout;
    wire        qpi_doe;
    wire        qpi_done;

    // PSRAM Reader and Writer wires
    wire        mr_rd;
    wire        mr_done;
    wire        mw_wr;
    wire        mw_done;

    //wire        doe;

    // WB Control Signals
    wire        wb_valid        =   cyc_i & stb_i;
    wire        wb_we           =   we_i & wb_valid;
    wire        wb_re           =   ~we_i & wb_valid;
    //wire[3:0]   wb_byte_sel     =   sel_i & {4{wb_we}};

    // The FSM
    reg         state, nstate;
    always @ (posedge clk_i or posedge rst_i)
        if(rst_i)
            state <= ST_IDLE;
        else
            state <= nstate;

    always @* begin
        case(state)
            ST_IDLE :
                if(wb_valid)
                    nstate = ST_WAIT;
                else
                    nstate = ST_IDLE;

            ST_WAIT :
                if((mw_done & wb_we) | (mr_done & wb_re))
                    nstate = ST_IDLE;
                else
                    nstate = ST_WAIT;
        endcase
    end

    wire [2:0]  size =  (sel_i == 4'b0001) ? 1 :
                        (sel_i == 4'b0010) ? 1 :
                        (sel_i == 4'b0100) ? 1 :
                        (sel_i == 4'b1000) ? 1 :
                        (sel_i == 4'b0011) ? 2 :
                        (sel_i == 4'b1100) ? 2 :
                        (sel_i == 4'b1111) ? 4 : 4;



    wire [7:0]  byte0 = (sel_i[0])          ? dat_i[7:0]   :
                        (sel_i[1] & size==1)? dat_i[15:8]  :
                        (sel_i[2] & size==1)? dat_i[23:16] :
                        (sel_i[3] & size==1)? dat_i[31:24] :
                        (sel_i[2] & size==2)? dat_i[23:16] :
                        dat_i[7:0];

    wire [7:0]  byte1 = (sel_i[1])          ? dat_i[15:8]  :
                        dat_i[31:24];

    wire [7:0]  byte2 = dat_i[23:16];

    wire [7:0]  byte3 = dat_i[31:24];

    wire [31:0] wdata = {byte3, byte2, byte1, byte0};

    /*
    wire [1:0]  waddr = (size==1 && sel_i[0]==1) ? 2'b00 :
                        (size==1 && sel_i[1]==1) ? 2'b01 :
                        (size==1 && sel_i[2]==1) ? 2'b10 :
                        (size==1 && sel_i[3]==1) ? 2'b11 :
                        (size==2 && sel_i[2]==1) ? 2'b10 :
                        2'b00;
                      */

    assign mr_rd    = ( (state==ST_IDLE ) & wb_re );
    assign mw_wr    = ( (state==ST_IDLE ) & wb_we );

    PSRAM_READER MR (
        .clk(clk_i),
        .rst_n(~rst_i),
        .addr({adr_i[23:2],2'b0}),
        .rd(mr_rd),
        //.size(size), Always read a word
        .size(3'd4),
        .done(mr_done),
        .line(dat_o),
        .sck(mr_sck),
        .ce_n(mr_ce_n),
        .din(mr_din),
        .dout(mr_dout),
        .douten(mr_doe)
    );

    PSRAM_WRITER MW (
        .clk(clk_i),
        .rst_n(~rst_i),
        .addr({adr_i[23:0]}),
        .wr(mw_wr),
        .size(size),
        .done(mw_done),
        .line(wdata),
        .sck(mw_sck),
        .ce_n(mw_ce_n),
        .din(mw_din),
        .dout(mw_dout),
        .douten(mw_doe)
    );


    PSRAM_QPI_MODE_TRANS QPI_TRANS (
        .clk(clk_i),
        .rst_n(~rst_i),
        .done(qpi_done),
        .sck(qpi_sck),
        .ce_n(qpi_ce_n),
        .din(qpi_din),
        .dout(qpi_dout),
        .douten(qpi_doe)
    );


    wire qpi_do = ~rst_i & ~qpi_done;
    assign sck  = qpi_do ? qpi_sck : wb_we ? mw_sck  : mr_sck;
    assign ce_n = qpi_do ? qpi_ce_n : wb_we ? mw_ce_n : mr_ce_n;
    assign dout = qpi_do ? qpi_dout : wb_we ? mw_dout : mr_dout;
    assign douten  = qpi_do ? {4{qpi_doe}} : wb_we ? {4{mw_doe}}  : {4{mr_doe}};

    assign mw_din = din;
    assign mr_din = din;
    assign qpi_din = din;
    assign ack_o = qpi_do ? qpi_done : wb_we ? mw_done :mr_done ;
endmodule
