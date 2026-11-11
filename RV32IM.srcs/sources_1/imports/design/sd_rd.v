// --------------------------------------------------------------------
// Copyright (c) 2022 by MicroPhase Technologies Inc. 
// --------------------------------------------------------------------
//
// Permission:
//
//   MicroPhase grants permission to use and modify this code for use
//   in synthesis for all MicroPhase Development Boards.
//   Other use of this code, including the selling 
//   ,duplication, or modification of any portion is strictly prohibited.
//
// Disclaimer:
//
//   This VHDL/Verilog or C/C++ source code is intended as a design reference
//   which illustrates how these types of functions can be implemented.
//   It is the user's responsibility to verify their design for
//   consistency and functionality through the use of formal
//   verification methods.  MicroPhase provides no warranty regarding the use 
//   or functionality of this code.
//
// --------------------------------------------------------------------
//           
//                     MicroPhase Technologies Inc
//                     Shanghai, China
//
//                     web: http://www.microphase.cn/   
//                     email: support@microphase.cn
//
// --------------------------------------------------------------------
// --------------------------------------------------------------------
//   
// Major Functions:   
//
// --------------------------------------------------------------------
// --------------------------------------------------------------------
//
//  Revision History    
//  Date          By            Revision    Change Description
//---------------------------------------------------------------------
// 2022.08.25     Ao Guohua     1.0          Original
//                                                      
// --------------------------------------------------------------------
// --------------------------------------------------------------------
module sd_rd(
       input        clk             ,
       input        rst_n           ,
       //sd卡接口
       output reg   sd_cs_n          ,
       input        sd_miso          ,
       output  reg  sd_mosi          ,
       //用户接口  
       input             sd_rd_start         ,
       input      [31:0] sd_rd_sec_addr      ,
       output reg        sd_rd_data_valid    ,
       output reg [7:0]  sd_rd_data          ,
       output            sd_rd_busy          ,
       output    reg     sd_rd_done          
                 
    );
localparam IDLE      =4'b0001;
localparam WR_CMD17  =4'b0010;
localparam RD_DATA   =4'b0100;//接受数据前导码、数据、数据校验码
localparam RD_DONE   =4'b1000;
reg [3:0]      state ;
//reg define 
reg            ack_done           ;//接受的使能信号，接受完成产生一个高电平
reg            ack_flag           ;
reg [5:0]      ack_bit_cnt        ;
reg [7:0]      ack_data           ;//应答命令的数据
reg            rx_data_done       ;//接受数据完成
reg            rx_data_flag       ;//接受数据标志
reg [5:0]      rx_data_bit_cnt    ;//接受一次数据中的bit数
reg [9:0]      rx_data_cnt        ;
reg            rx_data_valid      ;
reg [7:0]      rx_data            ;
reg  [5:0]     cmd_bit_cnt        ;   //读命令的计数器
reg  [5:0]     wait_cnt           ;
wire[47:0]     cmd17              ;
reg   [31:0]   r_sd_rd_sec_addr   ;
//**************r_sd_rd_sec_addr***********************
always@(posedge clk or negedge rst_n)begin
  if(!rst_n)                           
        r_sd_rd_sec_addr<='d0;                       
  else if(sd_rd_start)                    
            r_sd_rd_sec_addr<=sd_rd_sec_addr;                                                     
  else                           
            r_sd_rd_sec_addr<=r_sd_rd_sec_addr;                                                       
end
assign cmd17={8'h51,r_sd_rd_sec_addr,8'hff}; 
/*******************接受命令的应答**************************/
//ack_flag
always @(posedge clk or negedge rst_n ) begin
    if(!rst_n)
        ack_flag<=1'b0;
    else if(sd_miso==1'b0&&state==WR_CMD17)
             ack_flag<=1'b1;
    else if(ack_bit_cnt=='d7)
              ack_flag<=1'b0;
    else  ack_flag<=1'b0;
end
//ack_bit_cnt
always @(posedge clk or negedge rst_n ) begin
    if(!rst_n)
        ack_bit_cnt<='d0;
    else if((sd_miso==1'b0||ack_flag)&&state==WR_CMD17)begin
            if(ack_bit_cnt=='d7)
                ack_bit_cnt<='d0;
            else 
                ack_bit_cnt<=ack_bit_cnt+1'b1;
    end
    else 
          ack_bit_cnt<='d0;      
end
//ack_data 
always @(posedge clk or negedge rst_n ) begin
    if(!rst_n)
        ack_data<='d0;
    else if(sd_miso==1'b0||ack_flag)
             ack_data<={ack_data[6:0],sd_miso};
    else 
          ack_data<=ack_data;   
end
//ack_done
always @(posedge clk or negedge rst_n ) begin
    if(!rst_n)
        ack_done<=1'b0;
    else if(ack_bit_cnt=='d7)
            ack_done<=1'b1;
    else  ack_done<=1'b0;    
end
/*******************接受数据的应答****************/
//rx_data_flag
always @(posedge clk or negedge rst_n ) begin
    if(!rst_n)
         rx_data_flag<=1'b0;
    else  if(rx_data_done) 
              rx_data_flag<=1'b0;
    else  if(state==RD_DATA&&sd_miso==1'b0)
              rx_data_flag<=1'b1; 
    else rx_data_flag<=rx_data_flag;
end
//rx_data_bit_cnt
always @(posedge clk or negedge rst_n ) begin
    if(!rst_n)
        rx_data_bit_cnt<='d0;
    else if(rx_data_flag)begin
            if(rx_data_bit_cnt=='d7)
                  rx_data_bit_cnt<='d0;
            else 
                  rx_data_bit_cnt<=rx_data_bit_cnt+1'b1;   
    end
    else rx_data_bit_cnt<='d0;     
end
//rx_data
always @(posedge clk or negedge rst_n ) begin
    if(!rst_n)
        rx_data<='d0;
    else if(rx_data_flag)
            rx_data<={rx_data[6:0],sd_miso};
    else  rx_data<='d0;   
end
//rx_data_valid
always @(posedge clk or negedge rst_n ) begin
    if(!rst_n)
         rx_data_valid<=1'b0;
    else if(rx_data_bit_cnt=='d7&&rx_data_cnt<='d511)
               rx_data_valid<=1'b1;
    else 
               rx_data_valid<=1'b0;
end 
//rx_data_cnt
always @(posedge clk or negedge rst_n ) begin
    if(!rst_n)
        rx_data_cnt<='d0;
    else if(rx_data_bit_cnt=='d7)begin
               if(rx_data_cnt=='d513)
                      rx_data_cnt<='d0; 
                else      
                      rx_data_cnt<=rx_data_cnt+1'b1;
    end
    else 
         rx_data_cnt<=rx_data_cnt;
end
//rx_data_done  
always @(posedge clk or negedge rst_n ) begin
    if(!rst_n)
        rx_data_done<=1'b0;
    else if(rx_data_bit_cnt=='d7&&rx_data_cnt=='d513)
             rx_data_done<=1'b1;
    else  rx_data_done<=1'b0;  
end
/*********************时钟域*****************************/
//rd_data_valid、rd_data
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
         sd_rd_data_valid<=1'b0;
         sd_rd_data<=16'd0;
         
    end
    else if(rx_data_valid) begin
            sd_rd_data_valid<=1'b1;
            sd_rd_data<=rx_data;  
    end
    else begin
            sd_rd_data_valid<=1'b0;
            sd_rd_data<=sd_rd_data;
    end
end
//状态机
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        state<=IDLE;
    else begin
        case (state)
            IDLE: begin
                 if(sd_rd_start)
                    state<=WR_CMD17;
                 else
                    state<=IDLE;
            end
            WR_CMD17:begin
                 if(ack_done)
                    if(ack_data==8'h00)
                         state<=RD_DATA; 
                    else 
                         state<=IDLE;
                 else 
                        state<=WR_CMD17;   
            end
            RD_DATA:begin
                   if(rx_data_done)
                        state<=RD_DONE;
                   else
                        state<=RD_DATA;
            end
            RD_DONE:begin
                  if(wait_cnt=='d15) 
                       state<=IDLE;
            end
            default: state<=IDLE;
        endcase
    end 
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        sd_cs_n<=1'b1;
        sd_mosi<=1'b1;
        cmd_bit_cnt<='d0;
        wait_cnt<='d0;
        sd_rd_done <=1'b0;        
    end 
    else begin
        case (state)
            IDLE:begin
                sd_cs_n<=1'b1;
                sd_mosi<=1'b1;
                cmd_bit_cnt<='d0;
                sd_rd_done <=1'b0;
            end 
            WR_CMD17:begin
               if(cmd_bit_cnt<='d47)begin
                      sd_cs_n     <=1'b0; 
                      sd_mosi     <=cmd17[47-cmd_bit_cnt];
                      cmd_bit_cnt <=cmd_bit_cnt+1'b1;  
                 end 
                 else begin
                      if(ack_done)begin
                         sd_cs_n   <=1'b0;  
                         sd_mosi   <=1'b1;
                         cmd_bit_cnt<='d0;
                      end
                     else begin
                          sd_cs_n    <=1'b0   ;  
                          sd_mosi    <=1'b1   ;
                          cmd_bit_cnt<=cmd_bit_cnt;
                     end          
                 end          
            end
            RD_DATA:begin
                     sd_cs_n    <=sd_cs_n    ;
                     sd_mosi    <=sd_mosi    ;
                     cmd_bit_cnt<=cmd_bit_cnt;
            end 
            RD_DONE:begin
                wait_cnt<=wait_cnt+1'b1;
                if(wait_cnt=='d7) 
                    sd_cs_n <= 1'b1;
                if(wait_cnt=='d15)
                    sd_rd_done <= 1'b1;
            end
            default: begin
                     sd_cs_n<=1'b1;
                     sd_mosi<=1'b1;
                     cmd_bit_cnt<='d0;
                     wait_cnt<='d0;
            end
        endcase
    end     
end
assign sd_rd_busy=state!=IDLE;
endmodule
