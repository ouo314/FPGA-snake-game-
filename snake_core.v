module snake_core (
    input wire clk,             // 50MHz
    input wire rst_n,
    input wire [3:0] key_val,
    input wire key_pressed,     
    
    output reg [2:0] snake_x [0:15],     
    output reg [2:0] snake_y [0:15],
    output reg [3:0] snake_len, 
    
    output reg [2:0] food_x,
    output reg [2:0] food_y,
    
    output reg game_over,
    output reg [6:0] score,
    
    // 新增：剩餘時間輸出
    output reg [5:0] remaining_time
);

    // 參數設定
    parameter TIME_LIMIT = 25000000; // 蛇移動速度 (0.5秒)
    parameter ONE_SEC_LIMIT = 50000000; // 1秒的 Clock 數
    parameter INITIAL_TIME = 30; // 倒數 30 秒

    parameter [1:0] DIR_UP=0, DIR_DOWN=1, DIR_LEFT=2, DIR_RIGHT=3;

    reg [24:0] timer;   
    reg [25:0] sec_cnt; // 用來計算 1 秒
    
    reg [1:0] cur_dir, next_dir; 
    reg [15:0] lfsr; 
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lfsr <= 16'hACE1;
        else lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // -food generate
    reg [63:0] occupied_mask;
    integer k_mask;
    always @(*) begin
        occupied_mask = 64'd0; 
        for (k_mask = 0; k_mask < 16; k_mask = k_mask + 1) begin
            if (k_mask < snake_len) occupied_mask[{snake_y[k_mask], snake_x[k_mask]}] = 1'b1;
        end
    end

    reg [5:0] next_safe_food_pos; 
    reg [5:0] seed_pos;
    reg [5:0] check_pos;
    reg found;
    integer offset;
    always @(*) begin
        seed_pos = lfsr[5:0];
        next_safe_food_pos = seed_pos; 
        found = 0;
        for (offset = 0; offset < 64; offset = offset + 1) begin
            if (!found) begin
                check_pos = seed_pos + offset[5:0];
                if (occupied_mask[check_pos] == 1'b0) begin
                    next_safe_food_pos = check_pos;
                    found = 1'b1; 
                end
            end
        end
    end
    // ----------------------------------------

    integer i, k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snake_len <= 4'd5;
            snake_x[0] <= 3'd4; snake_y[0] <= 3'd3;
            snake_x[1] <= 3'd3; snake_y[1] <= 3'd3;
            snake_x[2] <= 3'd2; snake_y[2] <= 3'd3;
            snake_x[3] <= 3'd1; snake_y[3] <= 3'd3;
            snake_x[4] <= 3'd0; snake_y[4] <= 3'd3;
            for (i = 5; i < 16; i = i + 1) begin snake_x[i] <= 0; snake_y[i] <= 0; end

            food_x <= 3'd6; food_y <= 3'd6;
            
            timer   <= 0;
            cur_dir <= DIR_RIGHT; 
            next_dir <= DIR_RIGHT;
            game_over <= 0;
            score <= 0;
            
            // 初始化時間
            sec_cnt <= 0;
            remaining_time <= INITIAL_TIME;
            
        end else begin
            
            // 只有在遊戲進行中才倒數
            if (!game_over) begin
                
                // --- 1. 倒數計時邏輯 ---
                if (sec_cnt >= ONE_SEC_LIMIT) begin
                    sec_cnt <= 0;
                    if (remaining_time > 0) begin
                        remaining_time <= remaining_time - 1;
                    end else begin
                        // 時間到！觸發 Game Over (定格)
                        game_over <= 1;
                    end
                end else begin
                    sec_cnt <= sec_cnt + 1;
                end

                // --- 2. 方向控制 ---
                if (key_pressed) begin
                    case (key_val)
                        4'h6: if (cur_dir != DIR_DOWN) next_dir <= DIR_UP;    
                        4'h4: if (cur_dir != DIR_UP)   next_dir <= DIR_DOWN;  
                        4'h8: if (cur_dir != DIR_RIGHT) next_dir <= DIR_LEFT;  
                        4'h2: if (cur_dir != DIR_LEFT)  next_dir <= DIR_RIGHT; 
                        default: ; 
                    endcase
                end

                // --- 3. 移動邏輯 ---
                if (timer >= TIME_LIMIT) begin
                    
                    // 撞牆檢測
                    if ( (next_dir == DIR_UP    && snake_y[0] == 3'd0) ||
                         (next_dir == DIR_DOWN  && snake_y[0] == 3'd7) ||
                         (next_dir == DIR_LEFT  && snake_x[0] == 3'd0) ||
                         (next_dir == DIR_RIGHT && snake_x[0] == 3'd7) ) begin
                         game_over <= 1;
                    end else begin
                        // 正常移動
                        timer <= 0;
                        cur_dir <= next_dir;

                        for (i = 15; i > 0; i = i - 1) begin
                            snake_x[i] <= snake_x[i-1];
                            snake_y[i] <= snake_y[i-1];
                        end

                        case (next_dir)
                            DIR_UP:    snake_y[0] <= snake_y[0] - 3'd1;
                            DIR_DOWN:  snake_y[0] <= snake_y[0] + 3'd1;
                            DIR_LEFT:  snake_x[0] <= snake_x[0] - 3'd1;
                            DIR_RIGHT: snake_x[0] <= snake_x[0] + 3'd1;
                        endcase
                        
                        // 撞身體檢測
                        for (k = 1; k < 15; k = k + 1) begin
                            if (k < snake_len) begin
                                if (snake_x[0] == snake_x[k] && snake_y[0] == snake_y[k]) begin
                                    game_over <= 1;
                                end
                            end
                        end

                        // 吃食物
                        if (snake_x[0] == food_x && snake_y[0] == food_y) begin
                            food_x <= next_safe_food_pos[2:0]; 
                            food_y <= next_safe_food_pos[5:3]; 
                            if (snake_len < 15) snake_len <= snake_len + 1;
                            if (score < 99) score <= score + 1;
                            
                            // 吃到食物增加時間
                            remaining_time <= remaining_time + 5; 
                        end
                    end 

                end else begin
                    timer <= timer + 1;
                end
            end
        end
    end

endmodule