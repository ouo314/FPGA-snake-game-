

### 1. 系統概要

基於 Altera MAX10 (DE10-Lite) FPGA 開發板，結合 **4x4 Keypad** 與 **8x8 LED Dot Matrix** 的經典貪吃蛇遊戲。具備進階的 PWM 視覺效果、無重疊食物生成演算法以及計分/計時系統。

---

### 2. 遊戲規則與機制 (Gameplay)

* **移動機制**：
* 蛇每 **0.5 秒** 自動移動一格。
* **禁止回頭**：正在向右時，無法直接轉向左，反之亦然。


* **控制方式 (Keypad)**：
* `2`：上 (UP)
* `8`：下 (DOWN)
* `4`：左 (LEFT)
* `6`：右 (RIGHT)


* **得分與成長**：
* 吃到食物：長度 +1 (最大長度 15)，分數 +1 (上限 99)。
* 食物重生：保證出現在空白處。


* **遊戲結束條件 (Game Over)**：
1. **撞牆**：蛇頭觸碰邊界且試圖移出邊界。
2. **自噬**：蛇頭撞到自己的身體。
3. **時間到**：30 秒倒數歸零。


* *狀態*：遊戲結束時，蛇停止移動，畫面顯示X。



---

### 3. 顯示與視覺效果 (Visuals)

* **8x8 LED 矩陣 (PWM 驅動)**：
* **蛇頭**：最高亮度 (Highlight)。
* **蛇身**：**漸層亮度 (Gradient)**，越靠近尾巴越暗，產生漸層視覺效果。
* **食物**：**呼吸/閃爍 (Blinking)** 效果，全亮顯示。
* **Game Over**：顯示一個高亮度的 **大「X」圖案**。


* **七段顯示器 (7-Segment)**：
* **HEX5, HEX4 (左)**：顯示 **剩餘時間** (30秒倒數)。
* **HEX1, HEX0 (右)**：顯示 **當前分數** (00~99)。



### 5. 模組架構 (Module Architecture)

* **`snake.v` (Top Module)**：
* 系統整合，連接 Keypad、LED Matrix、七段顯示器。


* **`snake_core.v` (Game Logic)**：
* 處理狀態機、移動邏輯、撞牆/撞身檢測、時間計數、分數計算。
* 內含**食物生成**。


* **`led_driver_snake_pwm.v` (Display Driver)**：
* 負責高速掃描 LED Matrix。
* 計算每個像素的 **PWM 亮度** (蛇頭亮、蛇身漸暗、X圖案)。


* **`keypad_scanner.v`**：
* 負責掃描 4x4 鍵盤。


* **`seven_segment.v`**：
* BCD 解碼，將分數與時間轉為七段顯示碼。


---

# v2針對setup_time超時問題嘗試優化
下面整理「第一版（你剛貼的 occupied_mask + 64 格掃描）」到「最終版（mask + rotate/onehot）」的差異，並把你為了改善 setup time 做的設計思路與觀察結果寫成可直接放進報告的內容。

## 版本差異總表
| 面向 | 第一版（occupied_mask + 線性掃描） | 最終版（mask + rotate/onehot） |
|---|---|---|
| 蛇身佔用資訊 | 每個 combinational 週期用 `for` 依 `snake_x/y` + `snake_len` 重建 `occupied_mask`。[1] | 維持一個 64-bit `mask` 做狀態，移動時 set 新頭、必要時 clear 舊尾。[2] |
| 撞身體判斷 | 每次移動後用 `for (k=1..)` 逐段比較座標（O(n) 比較）。[1] | `hit_body = mask[head_next_idx]` 的 O(1) 判斷，並加上「走到舊尾巴但沒吃到不算撞」的特判。[2] |
| 食物生成 | 用 `seed_pos=lfsr[5:0]` 從起點掃 0..63 找第一個空格（線性 64 次檢查）。[1] | 用 `mask_for_food` 先把「新頭/尾巴變化」納入，再 rotate、onehot、encoder 找第一個 0-bit 的位置。[2] |
| 時序壓力來源 | `occupied_mask[{snake_y, snake_x}]` 的可變索引寫入 + 64 次掃描，工具展開後容易造成很長的組合路徑。[1] | 線性掃描移除後，時序壓力可能轉移到 64-bit rotate/adder/encoder（barrel shift + `+1` + reduction OR）這條組合鏈。[2] |

## 你改善 setup 的核心思路
- 把「每拍重建蛇身佔用」改成「維護狀態 mask」，讓撞身體從 O(n) 比較變成 O(1) 查表，縮短 `snake_len/snake_x/y → hit_body` 的組合路徑。[2]
- 把「吃到/撞到」判斷從使用更新後的 `snake_x[0]` 改成使用 `head_next_x/y`，避免 nonblocking 更新造成同一拍判斷用到舊值，讓邏輯更同步可預期。[2]
- 嘗試用演算法優化食物生成：把「64 次線性掃描」改成位元運算快速找空位（rotate + onehot + encoder），目標是減少迴圈展開的比較深度。[2]
- 在整體架構上，你也嘗試把「慢動作（0.5s 移動/1s 倒數/掃描）」改成以 tick/enable 控制，而不是讓遊戲每個 50MHz 週期都做重計算；早期也出現過帶 `tick` 輸入的版本作為探索方向。[3][1]

## 結果與觀察（為什麼還可能卡）
- 最終版確實把「撞身體」與「佔用資訊」的主要路徑縮短成 64-bit mask 的索引操作，通常比第一版的座標逐段比較更有利於時序。[2]
- 但最終版的 `food generate (combinational)` 變成一段很集中的 64-bit 組合鏈（rotate/shift、加法 `rotated_mask + 1`、再做多層 reduction OR encoder），這在 50MHz（20ns）下仍可能是新的 critical path。[2]
---
## V1
```verilog
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
```
<img width="724" height="215" alt="螢幕擷取畫面 2026-01-03 230447" src="https://github.com/user-attachments/assets/8a56b147-e8c1-4220-82dd-af3d32b16484" />  


- 很長的串聯電路

  
<img width="934" height="380" alt="螢幕擷取畫面 2026-01-04 210803" src="https://github.com/user-attachments/assets/846f9d18-09b4-4d61-91df-ceb30c4b962b" />


- 串聯電路的放大(由found導致)

  
<img width="919" height="645" alt="螢幕擷取畫面 2026-01-04 210823" src="https://github.com/user-attachments/assets/a5542014-30a9-4f46-a84e-9fdc460b7721" />  

---
## V2

```verilog
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
```
<img width="652" height="152" alt="螢幕擷取畫面 2026-01-05 013906" src="https://github.com/user-attachments/assets/5ad0895b-78b4-48b8-9c6d-1c64319c33df" />
