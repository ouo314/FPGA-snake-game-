module led_driver_snake_pwm (
    input wire clk,
    input wire rst_n,
    input wire [2:0] body_x [0:15], 
    input wire [2:0] body_y [0:15], 
    input wire [3:0] snake_len,
    input wire [2:0] food_x,
    input wire [2:0] food_y,
    input wire game_over,
    
    output reg [7:0] row_pins, 
    output reg [7:0] col_pins  
);

    // --- PWM 與 掃描控制 ---
    // 我們需要比原本更快的掃描速度來支援 PWM
    // 假設目標 Frame Rate = 1kHz (每秒掃描1000次畫面)
    // 每個 Frame 有 8 個 Row
    // 每個 Row 有 64 個 PWM 階層
    // 總共需要頻率：1000 * 8 * 64 = 512kHz
    // 50MHz / 512kHz ~= 97
    // 我們取 100 作為分頻係數
    parameter PWM_DIV = 100; 

    reg [7:0] div_cnt;
    reg [5:0] pwm_cnt;   // 0~63 亮度計數
    reg [2:0] scan_row;  // 0~7 掃描列

    // 每個 Column 的目標亮度 (0~63)
    reg [5:0] col_brightness [0:7];
    
    // 閃爍控制
    reg [23:0] blink_cnt;
    wire is_blink_on;
    always @(posedge clk) blink_cnt <= blink_cnt + 1;
    assign is_blink_on = blink_cnt[23]; 

    // 迴圈變數
    integer i, k;

    // Row 解碼 (Active Low)
    function [7:0] row_decode;
        input [2:0] r;
        case (r)
            3'd0: row_decode = 8'b01111111;
            3'd1: row_decode = 8'b10111111;
            3'd2: row_decode = 8'b11011111;
            3'd3: row_decode = 8'b11101111;
            3'd4: row_decode = 8'b11110111;
            3'd5: row_decode = 8'b11111011;
            3'd6: row_decode = 8'b11111101;
            3'd7: row_decode = 8'b11111110;
            default: row_decode = 8'b11111111;
        endcase
    endfunction

    // --- 1. 計算當前 Row 每個 Column 的亮度---
    always @(*) begin
        // 初始化亮度為 0
        for (i = 0; i < 8; i = i + 1) begin
            col_brightness[i] = 6'd0;
        end

        if (game_over) begin
            // Game Over: 顯示 X，亮度全開
            if (scan_row == scan_row) col_brightness[scan_row] = 63; // 防呆寫法，其實就是 current row 的對角
            col_brightness[scan_row] = 63;        // 正對角線 (0,0), (1,1)...
            col_brightness[7 - scan_row] = 63;    // 反對角線 (0,7), (1,6)...
        end else begin
            // 正常遊戲模式
            
            // A. 蛇身 (處理漸層)
            // 從尾巴開始設定，這樣頭部 (k=0) 會最後設定，覆蓋掉重疊的部分
            for (k = 15; k >= 0; k = k - 1) begin
                if (k < snake_len) begin
                    if (body_y[k] == scan_row) begin
                        // 計算漸層亮度
                        if (k == 0) begin
                            col_brightness[body_x[k]] = 20; // 頭最亮
                        end else begin
                            // 身體亮度遞減: 20 - k
                            // 確保最低亮度不低於 5 (避免看不見)
                            if (20 > (k * 2)) 
                                col_brightness[body_x[k]] = 6'd20 - (k[5:0]);
                            else 
                                col_brightness[body_x[k]] = 6'd5;
                        end
                    end
                end
            end

            // B. 食物 (最亮 + 閃爍)
            if (food_y == scan_row && is_blink_on) begin
                col_brightness[food_x] = 63;
            end
        end
    end

    // --- 2. PWM 掃描輸出邏輯 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 0;
            pwm_cnt <= 0;
            scan_row <= 0;
            row_pins <= 8'hFF;
            col_pins <= 8'h00;
        end else begin
            // 分頻計數
            if (div_cnt >= PWM_DIV) begin
                div_cnt <= 0;
                
                // 更新 PWM 計數
                if (pwm_cnt == 63) begin
                    pwm_cnt <= 0;
                    // 一個 PWM 週期結束，切換到下一個 Row
                    scan_row <= scan_row + 1;
                end else begin
                    pwm_cnt <= pwm_cnt + 1;
                end

            end else begin
                div_cnt <= div_cnt + 1;
            end

            // 更新輸出
            // Row: 永遠掃描當前列
            row_pins <= row_decode(scan_row);

            // Col: PWM 比較邏輯
            // 如果 "目標亮度" > "當前 PWM 計數"，則輸出 High (亮)
            col_pins[0] <= (col_brightness[0] > pwm_cnt);
            col_pins[1] <= (col_brightness[1] > pwm_cnt);
            col_pins[2] <= (col_brightness[2] > pwm_cnt);
            col_pins[3] <= (col_brightness[3] > pwm_cnt);
            col_pins[4] <= (col_brightness[4] > pwm_cnt);
            col_pins[5] <= (col_brightness[5] > pwm_cnt);
            col_pins[6] <= (col_brightness[6] > pwm_cnt);
            col_pins[7] <= (col_brightness[7] > pwm_cnt);
        end
    end

endmodule