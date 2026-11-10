`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Ruppin acadamic center final project
// Engineer: Yuval Nibar & Magen Nibar
// Project Supervisor: Ilan Oren
// Create Date: 09.09.2026 11:52:17
// Design Name: Control.sv
// Module Name: Control
// Project Name: SNN_MYN
// Description: Control block for SNN final project 
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module Control (
    input  logic        clk,
    input  logic        rst_n,
    
    // --- External Inputs ---
    input  logic        S_Ain_c,     
    input  logic [2:0]  Mode,        
    
    // --- Control Flags (Outputs to Tuning Blocks) ---
    output logic        WL_Enable,
    output logic        WL_Zero,
    output logic        BL_Enable,
    output logic        BL_Zero,

    // --- Tri-State Capable Select Busses ---
    output logic [31:0] WL_S,
    output logic [63:0] BL_S,

    // --- Loopback Enable Bus (Thermometer Encoded) ---
    output logic [31:0] LB_en
);

    // ---------------------------------------------------------
    // FSM State Definitions (4-bit encoding for 11 states)
    // ---------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE             = 4'b0000,
        SHIFT_PROG       = 4'b0001,
        APPLY_PROG       = 4'b0010,
        SHIFT_PROG_CONT  = 4'b0011,
        SHIFT_ERASE      = 4'b0100,
        APPLY_ERASE      = 4'b0101,
        SHIFT_ERASE_CONT = 4'b0110,
        INFERENCE        = 4'b0111,
        SHIFT_LB         = 4'b1000,
        APPLY_LB         = 4'b1001,
        SHIFT_LB_CONT    = 4'b1010
    } state_t;

    state_t current_state, next_state;

    // ---------------------------------------------------------
    // Shift Registers, Counters & Cumulative Mask Registers
    // ---------------------------------------------------------
    logic [4:0]  wl_shift_reg; // 5 bits for 32 WL addresses
    logic [5:0]  bl_shift_reg; // 6 bits for 64 BL addresses
    logic [4:0]  LB_SR;        // 5 bits for 32 Loopback threshold codes

    logic [2:0]  wl_cnt;
    logic [2:0]  bl_cnt;
    logic [2:0]  lb_cnt;

    // Registered cumulative masks
    logic [31:0] wl_decoded;
    logic [63:0] bl_decoded;
    logic [31:0] lb_en_reg;

    // Helper wires for the final bit shifted in on the terminal count clock
    logic [4:0] next_wl_addr;
    logic [5:0] next_bl_addr;
    logic [4:0] next_lb_code;

    assign next_wl_addr = {wl_shift_reg[3:0], S_Ain_c};
    assign next_bl_addr = {bl_shift_reg[4:0], S_Ain_c};
    assign next_lb_code = {LB_SR[3:0], S_Ain_c};

    // ---------------------------------------------------------
    // Sequential Datapath & Cumulative Memory Logic
    // ---------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            wl_shift_reg  <= 5'b0;
            bl_shift_reg  <= 6'b0;
            LB_SR         <= 5'b0;
            wl_cnt        <= 3'b0;
            bl_cnt        <= 3'b0;
            lb_cnt        <= 3'b0;
            wl_decoded    <= 32'hFFFF_FFFF;
            bl_decoded    <= 64'hFFFF_FFFF_FFFF_FFFF;
            lb_en_reg     <= 32'h0000_0000;
        end else begin
            current_state <= next_state;

            // Reset counters and initialize masks when in IDLE or INFERENCE
            if (current_state == IDLE || current_state == INFERENCE) begin
                wl_cnt     <= 3'b0;
                bl_cnt     <= 3'b0;
                lb_cnt     <= 3'b0;
                wl_decoded <= 32'hFFFF_FFFF;
                bl_decoded <= 64'hFFFF_FFFF_FFFF_FFFF;
                lb_en_reg  <= 32'h0000_0000;
            end

            // --- Program Mode Shifting & Cumulative Disconnect ---
            if (current_state == SHIFT_PROG || current_state == SHIFT_PROG_CONT) begin
                if (Mode == 3'b001) begin
                    wl_shift_reg <= next_wl_addr;
                    if (wl_cnt == 3'd4) begin
                        wl_cnt                   <= 3'b0;
                        wl_decoded[next_wl_addr] <= 1'b0; // Cumulative disconnect!
                    end else begin
                        wl_cnt <= wl_cnt + 3'd1;
                    end
                end else begin
                    wl_cnt <= 3'b0;
                end
            end else if (current_state == APPLY_PROG) begin
                wl_cnt <= 3'b0;
            end

            // --- Erase Mode Shifting & Cumulative Disconnect ---
            if (current_state == SHIFT_ERASE || current_state == SHIFT_ERASE_CONT) begin
                if (Mode == 3'b010) begin
                    bl_shift_reg <= next_bl_addr;
                    if (bl_cnt == 3'd5) begin
                        bl_cnt                   <= 3'b0;
                        bl_decoded[next_bl_addr] <= 1'b0; // Cumulative disconnect!
                    end else begin
                        bl_cnt <= bl_cnt + 3'd1;
                    end
                end else begin
                    bl_cnt <= 3'b0;
                end
            end else if (current_state == APPLY_ERASE) begin
                bl_cnt <= 3'b0;
            end

            // --- Loopback Mode Shifting ---
            if (current_state == SHIFT_LB || current_state == SHIFT_LB_CONT) begin
                if (Mode == 3'b100) begin
                    LB_SR <= next_lb_code;
                    if (lb_cnt == 3'd4) begin
                        lb_cnt <= 3'b0;
                        for (int i = 0; i < 32; i++) begin
                            if (i <= next_lb_code)
                                lb_en_reg[i] <= 1'b1;
                            else
                                lb_en_reg[i] <= 1'b0;
                        end
                    end else begin
                        lb_cnt <= lb_cnt + 3'd1;
                    end
                end else begin
                    lb_cnt <= 3'b0;
                end
            end else if (current_state == APPLY_LB) begin
                lb_cnt <= 3'b0;
            end
        end
    end

    // ---------------------------------------------------------
    // FSM Combinational Next-State Logic
    // ---------------------------------------------------------
    always_comb begin
        next_state = current_state; 
        
        case (current_state)
            IDLE: begin
                if (Mode == 3'b001)      next_state = SHIFT_PROG;
                else if (Mode == 3'b010) next_state = SHIFT_ERASE;
                else if (Mode == 3'b011) next_state = INFERENCE;
                else if (Mode == 3'b100) next_state = SHIFT_LB;
            end

            // --- Program ---
            SHIFT_PROG: begin
                if (Mode != 3'b001)      next_state = IDLE; // Abort
                else if (wl_cnt == 3'd4) next_state = APPLY_PROG;
            end
            APPLY_PROG: begin
                if (Mode != 3'b001)      next_state = IDLE;
                else                     next_state = SHIFT_PROG_CONT; // Stay active!
            end
            SHIFT_PROG_CONT: begin
                if (Mode != 3'b001)      next_state = IDLE;
                else if (wl_cnt == 3'd4) next_state = APPLY_PROG;
            end

            // --- Erase ---
            SHIFT_ERASE: begin
                if (Mode != 3'b010)      next_state = IDLE; // Abort
                else if (bl_cnt == 3'd5) next_state = APPLY_ERASE;
            end
            APPLY_ERASE: begin
                if (Mode != 3'b010)      next_state = IDLE;
                else                     next_state = SHIFT_ERASE_CONT; // Stay active!
            end
            SHIFT_ERASE_CONT: begin
                if (Mode != 3'b010)      next_state = IDLE;
                else if (bl_cnt == 3'd5) next_state = APPLY_ERASE;
            end

            // --- Inference ---
            INFERENCE: begin
                if (Mode != 3'b011)      next_state = IDLE;
            end

            // --- Loopback ---
            SHIFT_LB: begin
                if (Mode != 3'b100)      next_state = IDLE; // Abort
                else if (lb_cnt == 3'd4) next_state = APPLY_LB;
            end
            APPLY_LB: begin
                if (Mode != 3'b100)      next_state = IDLE;
                else                     next_state = SHIFT_LB_CONT;
            end
            SHIFT_LB_CONT: begin
                if (Mode != 3'b100)      next_state = IDLE;
                else if (lb_cnt == 3'd4) next_state = APPLY_LB;
            end

            default: next_state = IDLE;
        endcase
    end

    // ---------------------------------------------------------
    // Output Flags Logic (Continuous Enable during *_CONT states)
    // ---------------------------------------------------------
    always_comb begin
        WL_Enable = 1'b0; 
        WL_Zero   = 1'b0;
        BL_Enable = 1'b0; 
        BL_Zero   = 1'b0;

        if (current_state == APPLY_PROG || current_state == SHIFT_PROG_CONT) begin
            WL_Enable = 1'b1; WL_Zero = 1'b0; 
            BL_Enable = 1'b1; BL_Zero = 1'b1; 
        end
        else if (current_state == APPLY_ERASE || current_state == SHIFT_ERASE_CONT) begin
            BL_Enable = 1'b1; BL_Zero = 1'b0; 
            WL_Enable = 1'b1; WL_Zero = 1'b1; 
        end
    end

    // ---------------------------------------------------------
    // Tri-State Buffers & Loopback Bus Outputs
    // ---------------------------------------------------------
    assign WL_S  = (WL_Enable) ? ((WL_Zero) ? 32'h0000_0000 : wl_decoded) : 32'h0000_0000;
    assign BL_S  = (BL_Enable) ? ((BL_Zero) ? 64'h0000_0000_0000_0000 : bl_decoded) : 64'h0000_0000_0000_0000;
    assign LB_en = (current_state == APPLY_LB || current_state == SHIFT_LB_CONT) ? lb_en_reg : 32'h0000_0000;

endmodule