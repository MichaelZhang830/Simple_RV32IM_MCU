module data_memory(
    input  wire        clk,
    input  wire [2:0]  read_mem,   // 001=lw 110=lh 111=lb 011=lbu 010=lhu, 000=none
    input  wire [1:0]  mem_w_en,   // 01=sw 10=sh 11=sb, 00=none
    input  wire [31:0] addr,
    input  wire [31:0] w_data,
    output wire [31:0] r_data, // read data from RAM or 0 if MMIO region
    output wire        mmio_region,// high when addr is in the MMIO range
    output wire        mmio_wr_en
);
    // 8 KiB data memory implemented as a 2048 x 32-bit BRAM with byte write enables
    (* ram_style = "block" *) reg [31:0] mem [0:2047];
    integer   j;

    wire [12:0] byte_addr  = addr[12:0];        // byte address within data mem
    wire [12:2] word_addr  = byte_addr[12:2];   // word address for 32-bit BRAM
    wire [1:0]  byte_sel   = byte_addr[1:0];
    wire [31:0] word_r_data = mem[word_addr];

    // MMIO region is 0x00000400 to 0x000004FF
    // data memory 0x00000000 to 0x00001FFF
    assign mmio_region = (addr[31:8] == 24'h000004);
    wire data_mem_region = (addr[31:13] == 19'h00000);

    initial begin
        for (j = 0; j < 2048; j = j + 1)
            mem[j] = 32'h00000000;
    end

    reg [31:0] ram_r_data;

    always @(*) begin
        case (read_mem)
            3'b001:  ram_r_data = word_r_data;                                  // lw return full word 32-bit
            3'b110:  ram_r_data = {{16{word_r_data[byte_sel*8+15]}},
                                   word_r_data[byte_sel*8+15 -: 16]};          // lh extract halfword and sign extend to 32-bit
            3'b111:  ram_r_data = {{24{word_r_data[byte_sel*8+7]}},
                                   word_r_data[byte_sel*8+7 -: 8]};            // lb extract byte and sign extend to 32-bit
            3'b011:  ram_r_data = {24'b0, word_r_data[byte_sel*8+7 -: 8]};    // lbu extract byte and zero extend to 32-bit
            3'b010:  ram_r_data = {16'b0, word_r_data[byte_sel*8+15 -: 16]};  // lhu extract halfword and zero extend to 32-bit
            default: ram_r_data = 32'b0;
        endcase
    end

    //pervent from reading outside of the data memory region
    assign r_data = (mmio_region || !data_mem_region) ? 32'b0 : ram_r_data;
    //perform write only if the address is in the data memory region
    assign mmio_wr_en = mmio_region && (mem_w_en != 2'b00);

    reg [3:0] wen;
    always @(*) begin
        case (mem_w_en)
            2'b01:   wen = 4'b1111;                          // sw
            2'b10:   wen = byte_sel[1] ? 4'b1100 : 4'b0011; // sh
            2'b11:   wen = 4'b0001 << byte_sel;              // sb
            default: wen = 4'b0000;
        endcase
    end

    //sb/sh data is in the low bits of w_data, replicate it onto every byte lane
    reg [31:0] w_lanes;
    always @(*) begin
        case (mem_w_en)
            2'b10:   w_lanes = {2{w_data[15:0]}};            // sh
            2'b11:   w_lanes = {4{w_data[7:0]}};             // sb
            default: w_lanes = w_data;
        endcase
    end

    always @(posedge clk) begin
        //perform write only if the address is in the data memory region
        if (!mmio_region && data_mem_region) begin
            //write to the selected bytes of the word in memory based on wen (must for full, half and byte writes)
            if (wen[0]) mem[word_addr][7:0]   <= w_lanes[7:0];

            if (wen[1]) mem[word_addr][15:8]  <= w_lanes[15:8];

            if (wen[2]) mem[word_addr][23:16] <= w_lanes[23:16];

            if (wen[3]) mem[word_addr][31:24] <= w_lanes[31:24];
        end
    end
endmodule