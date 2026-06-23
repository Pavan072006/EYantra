// t2c_maze_explorer_v5.v
//
// This version implements the user's "exit-blocking" strategy.
//
// 1. It adds a counter `dead_ends_found_count`.
// 2. It hardcodes a `TOTAL_DEAD_ENDS = 9` (for Maze 1).
// 3. It uses the `dead_end_visited` map to only count *new* dead ends.
// 4. If the bot tries to move to the exit [4,0] *before* its counter
//    reaches 9, it will temporarily treat the exit as a wall and be
//    forced to turn away and keep exploring.

module t2c_maze_explorer (
    input clk,
    input rst_n,
    input left, mid, right, // 0 - no wall, 1 - wall (relative to facing)
    output reg [2:0] move
);

// --- New parameter for the mission target ---
localparam TOTAL_DEAD_ENDS = 9;

// --- Declarations moved to module scope ---
reg next_cell_N_visited, next_cell_E_visited, next_cell_S_visited, next_cell_W_visited;
reg next_cell_L_visited, next_cell_M_visited, next_cell_R_visited;

// --- Current state ---
reg [3:0] bot_x, bot_y;
reg [1:0] bot_orient; // 0=N,1=E,2=S,3=W
reg is_done;
// --- New state: dead end counter ---
reg [3:0] dead_ends_found_count;

// --- Next state (combinational) ---
reg [3:0] bot_x_next, bot_y_next;
reg [1:0] bot_orient_next;
reg is_done_next;
reg [2:0] move_next;
// --- New next state for counter ---
reg [3:0] dead_ends_found_count_next;

// --- FIX: Declarations for modified sensors moved to module scope ---
reg mod_left, mod_mid, mod_right;

// --- Memory maps ---
reg [1:0] visited_map [8:0][8:0];      // For general pathfinding
reg [1:0] dead_end_visited [8:0][8:0]; // For counting unique dead ends

// Unused memories
reg wall_N [8:0][8:0];
reg wall_E [8:0][8:0];
reg wall_S [8:0][8:0];
reg wall_W [8:0][8:0];


integer i,j;

// --- Synchronous Block (1-stage pipeline) ---
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Reset current state
        bot_x <= 4;
        bot_y <= 8;
        bot_orient <= 2'b00; // NORTH
        is_done <= 1'b0;
        move <= 3'b000;
        dead_ends_found_count <= 0; // Reset counter

        // clear all memories
        for (i=0;i<9;i=i+1) begin
            for (j=0;j<9;j=j+1) begin
                visited_map[i][j] <= 2'b00;
                dead_end_visited[i][j] <= 2'b00;
                wall_N[i][j] <= 1'b0;
                wall_E[i][j] <= 1'b0;
                wall_S[i][j] <= 1'b0;
                wall_W[i][j] <= 1'b0;
            end
        end
        
        visited_map[4][8] <= 2'b01; // Mark start as visited

    end else begin
        // Standard FSM state update
        if (!is_done) begin
            bot_x <= bot_x_next;
            bot_y <= bot_y_next;
            bot_orient <= bot_orient_next;
            dead_ends_found_count <= dead_ends_found_count_next;
            
            // Mark new cell as visited (for pathfinding)
            if (move_next != 3'b000) begin
                 visited_map[bot_x_next][bot_y_next][0] <= 1'b1;
            end
            
            // --- Mark new *dead end* as visited (for counting) ---
            // We check if the *next* move is a U-TURN. If so, we
            // mark the *current* cell as a dead end.
            if (move_next == 3'b100 && !dead_end_visited[bot_x][bot_y][0]) begin
                 dead_end_visited[bot_x][bot_y][0] <= 1'b1;
            end
        end
        
        is_done <= is_done_next;
        move <= move_next;
    end
end

// --- Combinational Block ---
always @(*) begin
    // Default: state holds
    bot_x_next = bot_x;
    bot_y_next = bot_y;
    bot_orient_next = bot_orient;
    is_done_next = is_done;
    move_next = 3'b000;
    dead_ends_found_count_next = dead_ends_found_count;

    // --- Sensor preprocessing ---
    // --- FIX: Declaration was moved to module scope ---
    mod_left = left;
    mod_mid = mid;
    mod_right = right;
    
    // --- Logic for checking visited status of adjacent cells ---
    next_cell_N_visited = (bot_y == 0) ? 1'b1 : visited_map[bot_x][bot_y-1][0];
    next_cell_E_visited = (bot_x == 8) ? 1'b1 : visited_map[bot_x+1][bot_y][0];
    next_cell_S_visited = (bot_y == 8) ? 1'b1 : visited_map[bot_x][bot_y+1][0];
    next_cell_W_visited = (bot_x == 0) ? 1'b1 : visited_map[bot_x-1][bot_y][0];

    case (bot_orient)
        2'b00: begin // Facing N
            next_cell_L_visited = next_cell_W_visited;
            next_cell_M_visited = next_cell_N_visited;
            next_cell_R_visited = next_cell_E_visited;
        end
        2'b01: begin // Facing E
            next_cell_L_visited = next_cell_N_visited;
            next_cell_M_visited = next_cell_E_visited;
            next_cell_R_visited = next_cell_S_visited;
        end
        2'b10: begin // Facing S
            next_cell_L_visited = next_cell_E_visited;
            next_cell_M_visited = next_cell_S_visited;
            next_cell_R_visited = next_cell_W_visited;
        end
        default: begin // 2'b11: Facing W
            next_cell_L_visited = next_cell_S_visited;
            next_cell_M_visited = next_cell_W_visited;
            next_cell_R_visited = next_cell_N_visited;
        end
    endcase

    // If already done, stay idle (emit STOP)
    if (is_done) begin
        move_next = 3'b000;
    end else begin
        
        // --- NEW: Exit-Blocking Logic ---
        // If mission is not complete, check for exit-adjacent moves
        // and pretend there is a wall.
        if (dead_ends_found_count < TOTAL_DEAD_ENDS) begin
            // Check for [4,1] facing N (moving to [4,0])
            if (bot_x == 4 && bot_y == 1 && bot_orient == 2'b00) mod_mid = 1'b1;
            
            // Check for [3,0] facing E (moving to [4,0])
            if (bot_x == 3 && bot_y == 0 && bot_orient == 2'b01) mod_mid = 1'b1;
            
            // Check for [5,0] facing W (moving to [4,0])
            if (bot_x == 5 && bot_y == 0 && bot_orient == 2'b11) mod_mid = 1'b1;
        end
        
        // --- Main Decision Logic (uses MODIFIED sensors) ---
        if (mod_left == 1'b0 && !next_cell_L_visited) begin
            move_next = 3'b010; // 1. Turn LEFT (unvisited)
        end
        else if (mod_mid == 1'b0 && !next_cell_M_visited) begin
            move_next = 3'b001; // 2. Go FORWARD (unvisited)
        end
        else if (mod_right == 1'b0 && !next_cell_R_visited) begin
            move_next = 3'b011; // 3. Turn RIGHT (unvisited)
        end
        else if (mod_left == 1'b0) begin
            move_next = 3'b010; // 4. Turn LEFT (visited)
        end
        else if (mod_mid == 1'b0) begin
            move_next = 3'b001; // 5. Go FORWARD (visited)
        end
        else if (mod_right == 1'b0) begin
            move_next = 3'b011; // 6. Turn RIGHT (visited)
        end
        else begin
            move_next = 3'b100; // 7. U-TURN
        end
        
        // --- NEW: Dead End Counter Logic ---
        // If we decided to U-TURN *and* it's a new dead end...
        if (move_next == 3'b100 && !dead_end_visited[bot_x][bot_y][0]) begin
            // ...increment the counter for the *next* cycle.
            dead_ends_found_count_next = dead_ends_found_count + 1;
        end

        // --- Final Exit Check (TB-stopping condition) ---
        // This check is *not* blocked by the logic above.
        // The logic above prevents move_next from being 3'b001
        // if the conditions are met.
        if (bot_x == 4 && bot_y == 0 && bot_orient == 2'b00 && move_next == 3'b001) begin
            is_done_next = 1'b1;
            // Don't update position/orientation, just stop
            bot_x_next = bot_x;
            bot_y_next = bot_y;
            bot_orient_next = bot_orient;
        end else begin
            // Compute orientation change
            case (move_next)
                3'b001: bot_orient_next = bot_orient;
                3'b010: bot_orient_next = bot_orient - 1;
                3'b011: bot_orient_next = bot_orient + 1;
                3'b100: bot_orient_next = bot_orient + 2;
                default: bot_orient_next = bot_orient;
            endcase

            // Compute position change (if not stopping)
            if (move_next != 3'b000) begin
                case (bot_orient_next) // Use the *new* orientation
                    2'b00: begin // North -> decrease y
                        if (bot_y > 0) bot_y_next = bot_y - 1;
                    end
                    2'b01: begin // East -> increase x
                        if (bot_x < 8) bot_x_next = bot_x + 1;
                    end
                    2'b10: begin // South -> increase y
                        if (bot_y < 8) bot_y_next = bot_y + 1;
                    end
                    default: begin // 2'b11: West -> decrease x
                        if (bot_x > 0) bot_x_next = bot_x - 1;
                    end
                endcase
            end
        end
    end
end

endmodule