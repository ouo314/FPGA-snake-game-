module snake_core (
    input  wire        clk,             // 50MHz
    input  wire        rst_n,
    input  wire [3:0]  key_val,
    input  wire        key_pressed,

    output reg  [2:0]  snake_x [0:15],
    output reg  [2:0]  snake_y [0:15],
    output reg  [3:0]  snake_len,

    output reg  [2:0]  food_x,
    output reg  [2:0]  food_y,

    output reg         game_over,
    output reg  [6:0]  score,

    output reg  [5:0]  remaining_time
);

    // 參數設定
    parameter TIME_LIMIT     = 25000000;  // 蛇移動速度 (0.5秒)
    parameter ONE_SEC_LIMIT  = 50000000;  // 1秒的 Clock 數
    parameter INITIAL_TIME   = 30;        // 倒數 30 秒

    parameter [1:0] DIR_UP=0, DIR_DOWN=1, DIR_LEFT=2, DIR_RIGHT=3;

    reg [24:0] timer;
    reg [25:0] sec_cnt;

    reg [1:0]  cur_dir, next_dir;
    reg [15:0] lfsr;

    // 盤面佔用 mask: index = {y[2:0], x[2:0]}，共 64 格
    reg [63:0] mask;

    integer i;

    // ------------------------------------------------------------
    // LFSR
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lfsr <= 16'hACE1;
        else        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // ------------------------------------------------------------
    // next head / collision (combinational)
    // ------------------------------------------------------------
    reg [2:0] head_next_x, head_next_y;
    reg [5:0] head_next_idx, tail_idx;
    reg       ate_next;
    reg       hit_wall, hit_body;
    reg [63:0] mask_for_food; // 用來確保「吃到後生成新食物」不會落在新蛇頭

    always @(*) begin
        // 預設
        head_next_x  = snake_x[0];
        head_next_y  = snake_y[0];

        // next head
        case (next_dir)
            DIR_UP:    head_next_y = snake_y[0] - 3'd1;
            DIR_DOWN:  head_next_y = snake_y[0] + 3'd1;
            DIR_LEFT:  head_next_x = snake_x[0] - 3'd1;
            default:   head_next_x = snake_x[0] + 3'd1; // DIR_RIGHT
        endcase

        head_next_idx = {head_next_y, head_next_x};
        tail_idx      = {snake_y[snake_len-1], snake_x[snake_len-1]};

        // 撞牆
        hit_wall = ((next_dir == DIR_UP    && snake_y[0] == 3'd0) ||
                    (next_dir == DIR_DOWN  && snake_y[0] == 3'd7) ||
                    (next_dir == DIR_LEFT  && snake_x[0] == 3'd0) ||
                    (next_dir == DIR_RIGHT && snake_x[0] == 3'd7));

        // 這一步是否吃到：用 next head 判斷
        ate_next = (head_next_x == food_x) && (head_next_y == food_y);

        // 撞身體：O(1) 用 mask 判斷
        // 特判：若「沒吃到」且 next head 剛好走到舊尾巴位置，這拍尾巴會被清掉，因此不算撞
        hit_body = mask[head_next_idx] && !((!ate_next) && (head_next_idx == tail_idx));

        // 給 food 生成用的 mask（包含新頭、若沒吃到則尾巴會離開）
        mask_for_food = mask;
        if (!ate_next) mask_for_food[tail_idx] = 1'b0;
        mask_for_food[head_next_idx] = 1'b1;
    end

    // ------------------------------------------------------------
    // food generate (combinational)
    // ------------------------------------------------------------
    reg [5:0]  next_safe_food_pos;
    reg [63:0] rotated_mask;
    reg [63:0] onehot;
    reg [5:0]  found_index;

    wire [5:0] sh = lfsr[5:0];

    always @(*) begin
        // rotate：sh==0 特判避免 <<64 / >>64
        if (sh == 6'd0) begin
            rotated_mask = mask_for_food;
        end else begin
            rotated_mask = (mask_for_food >> sh) | (mask_for_food << (7'd64 - {1'b0, sh}));
        end

        // 找第一個空位（onehot）
        onehot = ~rotated_mask & (rotated_mask + 64'd1);

        // onehot -> index (6-bit)
        found_index    = 6'd0;
        found_index[0] = |(onehot & 64'hAAAAAAAAAAAAAAAA);
        found_index[1] = |(onehot & 64'hCCCCCCCCCCCCCCCC);
        found_index[2] = |(onehot & 64'hF0F0F0F0F0F0F0F0);
        found_index[3] = |(onehot & 64'hFF00FF00FF00FF00);
        found_index[4] = |(onehot & 64'hFFFF0000FFFF0000);
        found_index[5] = |(onehot & 64'hFFFFFFFF00000000);

        // rotate 回原座標
        next_safe_food_pos = (found_index + sh) & 6'h3F;
    end

    // ------------------------------------------------------------
    // Main sequential
    // ------------------------------------------------------------
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snake_len <= 4'd5;

            snake_x[0] <= 3'd4; snake_y[0] <= 3'd3;
            snake_x[1] <= 3'd3; snake_y[1] <= 3'd3;
            snake_x[2] <= 3'd2; snake_y[2] <= 3'd3;
            snake_x[3] <= 3'd1; snake_y[3] <= 3'd3;
            snake_x[4] <= 3'd0; snake_y[4] <= 3'd3;

            for (i = 5; i < 16; i = i + 1) begin
                snake_x[i] <= 3'd0;
                snake_y[i] <= 3'd0;
            end

            // mask reset（不要用 snake_x/y 推，直接用常數座標 set）
            mask <= 64'd0;
            mask[{3'd3,3'd4}] <= 1'b1;
            mask[{3'd3,3'd3}] <= 1'b1;
            mask[{3'd3,3'd2}] <= 1'b1;
            mask[{3'd3,3'd1}] <= 1'b1;
            mask[{3'd3,3'd0}] <= 1'b1;

            food_x <= 3'd6;
            food_y <= 3'd6;

            timer    <= 25'd0;
            cur_dir  <= DIR_RIGHT;
            next_dir <= DIR_RIGHT;

            game_over <= 1'b0;
            score     <= 7'd0;

            sec_cnt        <= 26'd0;
            remaining_time <= INITIAL_TIME;
        end else begin
            if (!game_over) begin
                // 1) 倒數計時
                if (sec_cnt >= ONE_SEC_LIMIT - 1) begin
                    sec_cnt <= 26'd0;
                    if (remaining_time > 0) remaining_time <= remaining_time - 1'b1;
                    else game_over <= 1'b1;
                end else begin
                    sec_cnt <= sec_cnt + 1'b1;
                end

                // 2) 方向控制
                if (key_pressed) begin
                    case (key_val)
                        4'h6: if (cur_dir != DIR_DOWN)  next_dir <= DIR_UP;
                        4'h4: if (cur_dir != DIR_UP)    next_dir <= DIR_DOWN;
                        4'h8: if (cur_dir != DIR_RIGHT) next_dir <= DIR_LEFT;
                        4'h2: if (cur_dir != DIR_LEFT)  next_dir <= DIR_RIGHT;
                        default: ;
                    endcase
                end

                // 3) 移動
                if (timer >= TIME_LIMIT) begin
                    if (hit_wall || hit_body) begin
                        game_over <= 1'b1;
                    end else begin
                        timer   <= 25'd0;
                        cur_dir <= next_dir;

                        // 身體平移
                        for (i = 15; i > 0; i = i - 1) begin
                            snake_x[i] <= snake_x[i-1];
                            snake_y[i] <= snake_y[i-1];
                        end

                        // 更新蛇頭
                        snake_x[0] <= head_next_x;
                        snake_y[0] <= head_next_y;

                        // 更新 mask：先 set 新頭；沒吃到才 clear 舊尾
                        mask[head_next_idx] <= 1'b1;
                        if (!ate_next) mask[tail_idx] <= 1'b0;

                        // 吃到食物：更新食物、長度、分數、時間（用 next head 判斷）
                        if (ate_next) begin
                            food_x <= next_safe_food_pos[2:0];
                            food_y <= next_safe_food_pos[5:3];

                            if (snake_len < 4'd15) snake_len <= snake_len + 1'b1;
                            if (score < 7'd99)     score     <= score + 1'b1;

                            remaining_time <= remaining_time + 6'd5;
                        end
                    end
                end else begin
                    timer <= timer + 1'b1;
                end
            end
        end
    end

endmodule
