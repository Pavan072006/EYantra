//=====================================================================
// t2c_maze_explorer.v  -- CORRECTED
//
// Depth-first maze explorer for a 9x9 grid with cell-visit memory.
// Explores every dead end before being allowed to leave via the exit.
//
// Interface protocol (ONE maze step per clock):
//   - Testbench drives {left,mid,right} for the CURRENT cell/orientation
//   - On the rising edge the FSM registers `move` AND updates its own
//     position, so after the edge `move` and the internal position agree.
//
// Move encoding:  000 STOP   001 FORWARD   010 LEFT   011 RIGHT   100 U-TURN
// Orientation:    00 N   01 E   10 S   11 W        Grid: x = column, y = row
//                 North decreases y.
//=====================================================================
module t2c_maze_explorer #(
    parameter TOTAL_DEAD_ENDS = 9,
    parameter START_X = 4, parameter START_Y = 8,
    parameter EXIT_X  = 4, parameter EXIT_Y  = 0
)(
    input             clk,
    input             rst_n,
    input             left, mid, right,   // 1 = wall, relative to facing
    output reg [2:0]  move,
    output reg        done,               // exit reached
    output reg [3:0]  dead_ends_found     // observability for verification
);

    localparam MOVE_STOP = 3'b000, MOVE_FWD = 3'b001,
               MOVE_LEFT = 3'b010, MOVE_RIGHT = 3'b011, MOVE_UTURN = 3'b100;
    localparam N = 2'b00, E = 2'b01, S = 2'b10, W = 2'b11;

    // ---------------- state ----------------
    reg [3:0] bot_x, bot_y;
    reg [1:0] bot_orient;

    reg [3:0] bot_x_n, bot_y_n;
    reg [1:0] bot_orient_n;
    reg [2:0] move_n;
    reg       done_n;
    reg [3:0] dead_ends_found_n;

    // 1 bit per cell (was [1:0] with only bit 0 used)
    reg visited   [0:8][0:8];
    reg de_counted[0:8][0:8];

    integer i, j;

    // ---------------- combinational ----------------
    reg oob_N, oob_E, oob_S, oob_W;          // move would leave the grid
    reg vis_N, vis_E, vis_S, vis_W;
    reg oob_L, oob_M, oob_R;
    reg vis_L, vis_M, vis_R;
    reg blk_L, blk_M, blk_R;                 // effective "wall" seen by the FSM
    reg at_exit_facing_out, mission_complete, is_dead_end;

    always @(*) begin
        // defaults
        bot_x_n           = bot_x;
        bot_y_n           = bot_y;
        bot_orient_n      = bot_orient;
        move_n            = MOVE_STOP;
        done_n            = done;
        dead_ends_found_n = dead_ends_found;

        mission_complete  = (dead_ends_found >= TOTAL_DEAD_ENDS);

        // --- out-of-grid detection ---
        oob_N = (bot_y == 0);
        oob_S = (bot_y == 8);
        oob_W = (bot_x == 0);
        oob_E = (bot_x == 8);

        // --- visited status of the four neighbours (out-of-grid counts as visited) ---
        vis_N = oob_N ? 1'b1 : visited[bot_x][bot_y-1];
        vis_S = oob_S ? 1'b1 : visited[bot_x][bot_y+1];
        vis_W = oob_W ? 1'b1 : visited[bot_x-1][bot_y];
        vis_E = oob_E ? 1'b1 : visited[bot_x+1][bot_y];

        // --- rotate absolute -> relative (left / mid / right) ---
        case (bot_orient)
            N:       begin vis_L=vis_W; vis_M=vis_N; vis_R=vis_E;
                           oob_L=oob_W; oob_M=oob_N; oob_R=oob_E; end
            E:       begin vis_L=vis_N; vis_M=vis_E; vis_R=vis_S;
                           oob_L=oob_N; oob_M=oob_E; oob_R=oob_S; end
            S:       begin vis_L=vis_E; vis_M=vis_S; vis_R=vis_W;
                           oob_L=oob_E; oob_M=oob_S; oob_R=oob_W; end
            default: begin vis_L=vis_S; vis_M=vis_W; vis_R=vis_N;
                           oob_L=oob_S; oob_M=oob_W; oob_R=oob_N; end
        endcase

        // --- FIX 1: the grid boundary is a wall ---
        // Without this the bot walks out through the entrance, because the
        // start cell has no physical south wall.
        blk_L = left  | oob_L;
        blk_M = mid   | oob_M;
        blk_R = right | oob_R;

        // --- FIX 2: single unified exit rule ---
        // The exit is the north edge of [EXIT_X,EXIT_Y]. It is only passable
        // once every dead end has been found. This replaces the three
        // hard-coded "pretend there's a wall" coordinates in the original.
        at_exit_facing_out = (bot_x == EXIT_X) && (bot_y == EXIT_Y) && (bot_orient == N);
        if (at_exit_facing_out && !mid && mission_complete) blk_M = 1'b0;

        // --- FIX 3: dead end detected from RAW sensors, not from the move choice ---
        // A cell with walls on all three sides is a dead end by definition.
        // The original inferred it from "I decided to U-turn", which also
        // fires at non-dead-end cells once neighbours are marked visited.
        is_dead_end = left & mid & right;

        if (done) begin
            move_n = MOVE_STOP;
        end else begin
            // decision ladder: prefer unvisited, left-hand bias
            if      (!blk_L && !vis_L) move_n = MOVE_LEFT;
            else if (!blk_M && !vis_M) move_n = MOVE_FWD;
            else if (!blk_R && !vis_R) move_n = MOVE_RIGHT;
            else if (!blk_L)           move_n = MOVE_LEFT;
            else if (!blk_M)           move_n = MOVE_FWD;
            else if (!blk_R)           move_n = MOVE_RIGHT;
            else                       move_n = MOVE_UTURN;

            if (is_dead_end && !de_counted[bot_x][bot_y])
                dead_ends_found_n = dead_ends_found + 1'b1;

            if (at_exit_facing_out && move_n == MOVE_FWD && mission_complete) begin
                done_n = 1'b1;                  // leave the maze, freeze position
            end else begin
                case (move_n)
                    MOVE_LEFT:  bot_orient_n = bot_orient - 2'd1;
                    MOVE_RIGHT: bot_orient_n = bot_orient + 2'd1;
                    MOVE_UTURN: bot_orient_n = bot_orient + 2'd2;
                    default:    bot_orient_n = bot_orient;
                endcase
                if (move_n != MOVE_STOP) begin
                    case (bot_orient_n)         // step using the NEW orientation
                        N:       if (bot_y > 0) bot_y_n = bot_y - 4'd1;
                        E:       if (bot_x < 8) bot_x_n = bot_x + 4'd1;
                        S:       if (bot_y < 8) bot_y_n = bot_y + 4'd1;
                        default: if (bot_x > 0) bot_x_n = bot_x - 4'd1;
                    endcase
                end
            end
        end
    end

    // ---------------- sequential ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bot_x           <= START_X;
            bot_y           <= START_Y;
            bot_orient      <= N;
            move            <= MOVE_STOP;
            done            <= 1'b0;
            dead_ends_found <= 4'd0;
            for (i = 0; i < 9; i = i + 1)
                for (j = 0; j < 9; j = j + 1) begin
                    visited[i][j]    <= 1'b0;
                    de_counted[i][j] <= 1'b0;
                end
            visited[START_X][START_Y] <= 1'b1;
        end else begin
            move            <= move_n;
            done            <= done_n;
            dead_ends_found <= dead_ends_found_n;
            if (!done) begin
                bot_x      <= bot_x_n;
                bot_y      <= bot_y_n;
                bot_orient <= bot_orient_n;
                if (move_n != MOVE_STOP) visited[bot_x_n][bot_y_n] <= 1'b1;
                if (is_dead_end)         de_counted[bot_x][bot_y]  <= 1'b1;
            end
        end
    end

endmodule
