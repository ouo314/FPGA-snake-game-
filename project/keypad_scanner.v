module keypad_scanner (
    input wire clk,             // 50MHz Clock
    input wire rst_n,           // Reset (Active Low)
    input wire [3:0] col,       // Keypad Column Input
    output reg [3:0] row,       // Keypad Row Output
    output reg [3:0] key_val,   // Detected Key Value (0-F)
    output reg key_pressed      // Flag: 1 if any key is pressed
);

    // 掃描頻率設定 (50MHz / 500k = 100Hz)
    parameter SCAN_LIMIT = 500000; 
    reg [19:0] cnt;
    
    // 狀態機: 用來切換 Row
    reg [1:0] current_row_idx; 

    // 暫存掃描到的值
    reg [3:0] scan_val;
    reg valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
            row <= 4'b1110; // 初始掃描第 0 列
            current_row_idx <= 0;
            key_val <= 0;
            key_pressed <= 0;
        end else begin
            // 降低掃描速度
            if (cnt >= SCAN_LIMIT) begin
                cnt <= 0;
                
                // 1. 判斷當前 Row 偵測到的按鍵
                valid = 1'b0;
                case ({row, col})
                    // Row 0 (1110)
                    8'b1110_1110: begin scan_val = 4'h7; valid = 1; end
                    8'b1110_1101: begin scan_val = 4'h4; valid = 1; end
                    8'b1110_1011: begin scan_val = 4'h1; valid = 1; end
                    8'b1110_0111: begin scan_val = 4'h0; valid = 1; end
                    
                    // Row 1 (1101)
                    8'b1101_1110: begin scan_val = 4'h8; valid = 1; end
                    8'b1101_1101: begin scan_val = 4'h5; valid = 1; end
                    8'b1101_1011: begin scan_val = 4'h2; valid = 1; end
                    8'b1101_0111: begin scan_val = 4'hA; valid = 1; end
                    
                    // Row 2 (1011)
                    8'b1011_1110: begin scan_val = 4'h9; valid = 1; end
                    8'b1011_1101: begin scan_val = 4'h6; valid = 1; end
                    8'b1011_1011: begin scan_val = 4'h3; valid = 1; end
                    8'b1011_0111: begin scan_val = 4'hB; valid = 1; end
                    
                    // Row 3 (0111)
                    8'b0111_1110: begin scan_val = 4'hC; valid = 1; end
                    8'b0111_1101: begin scan_val = 4'hD; valid = 1; end
                    8'b0111_1011: begin scan_val = 4'hE; valid = 1; end
                    8'b0111_0111: begin scan_val = 4'hF; valid = 1; end
                    
                    default: begin 
								valid = 1'b0;
								key_pressed <= 1'b0; 
						  end
                endcase
						
                // 如果有偵測到按鍵，更新輸出
                if (valid) begin
                    key_val <= scan_val;
                    key_pressed <= 1'b1;
                end 
                
                // 2. 切換到下一個 Row
                current_row_idx <= current_row_idx + 1;
                case (current_row_idx)
                    0: row <= 4'b1101; // Next is 1
                    1: row <= 4'b1011; // Next is 2
                    2: row <= 4'b0111; // Next is 3
                    3: row <= 4'b1110; // Next is 0
                endcase

            end else begin
                cnt <= cnt + 1;
					 
            end
        end
    end
endmodule

module seven_segment (
    input wire [3:0] hex_in,   
    output reg [6:0] seg_out   
);
   
    always @(*) begin
        case (hex_in)
            4'h0: seg_out = 7'b1000000;
            4'h1: seg_out = 7'b1111001;
            4'h2: seg_out = 7'b0100100;
            4'h3: seg_out = 7'b0110000;
            4'h4: seg_out = 7'b0011001;
            4'h5: seg_out = 7'b0010010;
            4'h6: seg_out = 7'b0000010;
            4'h7: seg_out = 7'b1111000; 
            4'h8: seg_out = 7'b0000000;
            4'h9: seg_out = 7'b0010000; 
            4'hA: seg_out = 7'b0001000;
            4'hB: seg_out = 7'b0000011; 
            4'hC: seg_out = 7'b1000110; 
            4'hD: seg_out = 7'b0100001; 
            4'hE: seg_out = 7'b0000110;
            4'hF: seg_out = 7'b0001110;
            default: seg_out = 7'b1111111; // OFF
        endcase
    end
endmodule

