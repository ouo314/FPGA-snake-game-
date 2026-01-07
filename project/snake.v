module snake (
    input wire MAX10_CLK1_50,
    input wire [1:0] KEY,      // KEY[0] = Reset
    
    input  wire [3:0] KEYPAD_COL,
    output wire [3:0] KEYPAD_ROW,
    
    output wire [7:0] LED_ROW,
    output wire [7:0] LED_COL,
    
    // 七段顯示器
    output wire [6:0] HEX0, // 分數 個位
    output wire [6:0] HEX1, // 分數 十位
    output wire [6:0] HEX4, // 時間 個位
    output wire [6:0] HEX5  // 時間 十位
);

    wire rst_n = KEY[0];
    wire [3:0] key_val;
    wire key_pressed;
    
    wire [2:0] snake_x [0:15];
    wire [2:0] snake_y [0:15];
    wire [3:0] snake_len;
    
    wire [2:0] food_x;
    wire [2:0] food_y;
    wire game_over;
    
    wire [6:0] current_score;
    wire [5:0] remaining_time; // 連接時間訊號

    // Keypad 掃描
    keypad_scanner u_keypad (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .col(KEYPAD_COL),
        .row(KEYPAD_ROW),
        .key_val(key_val),
        .key_pressed(key_pressed)
    );

    // 核心邏輯
    snake_core u_core (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .key_val(key_val),
        .key_pressed(key_pressed),
        .snake_x(snake_x), 
        .snake_y(snake_y),
        .snake_len(snake_len),
        .food_x(food_x),
        .food_y(food_y),
        .game_over(game_over),
        .score(current_score),
        .remaining_time(remaining_time) 
    );

    // 顯示驅動 (PWM)
    led_driver_snake_pwm u_display (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .body_x(snake_x), 
        .body_y(snake_y),
        .snake_len(snake_len),
        .food_x(food_x),
        .food_y(food_y),
        .game_over(game_over),
        .row_pins(LED_ROW),
        .col_pins(LED_COL)
    );
    
    // --- 七段顯示器邏輯 ---
    
    // 1. 分數顯示 (右邊)
    wire [3:0] score_units = current_score % 10;
    wire [3:0] score_tens  = current_score / 10;
    
    seven_segment u_hex0 (.hex_in(score_units), .seg_out(HEX0));
    seven_segment u_hex1 (.hex_in(score_tens),  .seg_out(HEX1));
    

    
    // 3. 時間顯示 (左邊)
    wire [3:0] time_units = remaining_time % 10;
    wire [3:0] time_tens  = remaining_time / 10;
    
    seven_segment u_hex4 (.hex_in(time_units), .seg_out(HEX4));
    seven_segment u_hex5 (.hex_in(time_tens),  .seg_out(HEX5));

endmodule