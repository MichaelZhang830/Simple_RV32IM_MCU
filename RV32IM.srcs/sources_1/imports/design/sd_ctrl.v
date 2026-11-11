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
// 2022.08.24     Ao Guohua     1.0          Original
//                                                      
// --------------------------------------------------------------------
// --------------------------------------------------------------------
module sd_ctrl  #(parameter   SYS_FRENCY  =50_000_000,
                  parameter   INIT_FRENCY =250_000    
                 )(
        input           clk  ,
        input           rst_n    ,

        output          sd_clk     ,
        output reg      sd_cs_n    ,
        input           sd_miso    ,
        output  reg     sd_mosi    ,
        
        output           init_done  ,
        //写的应用接口
        input              sd_wr_start         ,
        output             sd_wr_data_req      ,
        input  [31:0]      sd_wr_sec_addr      ,
        input  [7:0]       sd_wr_data          ,
        output             sd_wr_done          ,
        //用户接口  
         input             sd_rd_start         ,
         input   [31:0]    sd_rd_sec_addr      ,
         output            sd_rd_data_valid    ,
         output  [7:0]     sd_rd_data          ,
         output            sd_rd_done          ,
         output            sd_busy        
          
    );
wire        init_clk         ;
wire        init_sd_cs_n     ;
wire        init_sd_mosi     ;
wire        wr_sd_cs_n       ;
wire        wr_sd_mosi       ;
wire        rd_sd_cs_n       ;
wire        rd_sd_mosi       ;
wire        sd_wr_busy       ;
wire        sd_rd_busy       ;

sd_init #(
    .SYS_FRENCY  (SYS_FRENCY ), 
    .INIT_FRENCY (INIT_FRENCY)  

)sd_init
(
        .clk    (clk),
        .rst_n      (rst_n  ),

        .sd_clk     (init_clk),   
        .sd_cs_n    (init_sd_cs_n),
        .sd_miso    (sd_miso),
        .sd_mosi    (init_sd_mosi),
        .init_done  (init_done)           
    );
sd_wr  sd_wr(
        .clk       (clk),
        .rst_n     (rst_n),
        //SD card interface
        .sd_cs_n  (wr_sd_cs_n),
        .sd_miso  (sd_miso),
        .sd_mosi  (wr_sd_mosi),
        //User interface
        .sd_wr_start    (sd_wr_start)  ,    
        .sd_wr_data_req (sd_wr_data_req)  ,
        .sd_wr_sec_addr (sd_wr_sec_addr)  ,
        .sd_wr_data     (sd_wr_data)  ,
        .sd_wr_busy     (sd_wr_busy)  ,
        .sd_wr_done     (sd_wr_done) 
    );

sd_rd  sd_rd(
       .clk             (clk),
       .rst_n           (rst_n),
       //SD card interface
       .sd_cs_n          (rd_sd_cs_n),
       .sd_miso          (sd_miso),
       .sd_mosi          (rd_sd_mosi),
       //User interface
       .sd_rd_start          (sd_rd_start ),
       .sd_rd_sec_addr       (sd_rd_sec_addr  ),
       .sd_rd_data_valid     (sd_rd_data_valid),
       .sd_rd_data           (sd_rd_data ),
       .sd_rd_busy           (sd_rd_busy ),
       .sd_rd_done           (sd_rd_done)                
    );
assign   sd_busy=sd_wr_busy|sd_rd_busy;
always @(*) begin
 if(rst_n==1'b0)begin
          sd_cs_n =1'b1;
          sd_mosi =1'b1;
 end   
 else  if(init_done==1'b0)begin
            sd_cs_n =init_sd_cs_n;
            sd_mosi =init_sd_mosi;
    end
 else if(sd_wr_busy)begin
            sd_cs_n =wr_sd_cs_n   ;
            sd_mosi =wr_sd_mosi   ;
    end
else if(sd_rd_busy)begin
             sd_cs_n =rd_sd_cs_n   ;
             sd_mosi =rd_sd_mosi   ;  
    end 
else begin
            sd_cs_n =1'b1  ;
            sd_mosi =1'b1  ;  
end
        
end
assign sd_clk=(init_done==1'b0)?init_clk:~clk;//Output data at the negedge of the clock to meet the timing requirements of the SD card
endmodule
