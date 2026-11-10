`timescale 1ns / 1ps

// Self-checking testbench for Control.
// Inputs change on the falling edge of clk, outputs are checked after the
// rising edge, so the same testbench also works on the synthesized netlist.
module tb_Control;

    logic        clk = 0;
    logic        rst_n;
    logic        S_Ain_c;
    logic [2:0]  Mode;
    logic        WL_Enable, WL_Zero, BL_Enable, BL_Zero;
    logic [31:0] WL_S;
    logic [63:0] BL_S;
    logic [31:0] LB_en;

    Control dut (.*);

    always #5 clk = ~clk;

    int errors = 0;
    int checks = 0;

    task automatic check(string what,
                         logic wl_en, logic wl_z, logic bl_en, logic bl_z,
                         logic [31:0] wl_s, logic [63:0] bl_s, logic [31:0] lb);
        checks++;
        if (WL_Enable !== wl_en || WL_Zero !== wl_z || BL_Enable !== bl_en ||
            BL_Zero !== bl_z || WL_S !== wl_s || BL_S !== bl_s || LB_en !== lb) begin
            errors++;
            $display("FAIL %s @%0t", what, $time);
            $display("  got  WL_En=%b WL_Z=%b BL_En=%b BL_Z=%b WL_S=%h BL_S=%h LB_en=%h",
                     WL_Enable, WL_Zero, BL_Enable, BL_Zero, WL_S, BL_S, LB_en);
            $display("  want WL_En=%b WL_Z=%b BL_En=%b BL_Z=%b WL_S=%h BL_S=%h LB_en=%h",
                     wl_en, wl_z, bl_en, bl_z, wl_s, bl_s, lb);
        end
    endtask

    // All outputs inactive
    task automatic check_off(string what);
        check(what, 0, 0, 0, 0, 32'h0, 64'h0, 32'h0);
    endtask

    // One clock with the given serial bit
    task automatic pulse(logic b);
        S_Ain_c = b;
        @(posedge clk); #1;
        @(negedge clk);
    endtask

    task automatic set_mode(logic [2:0] m);
        Mode = m;
        pulse(0);               // IDLE -> SHIFT_* (no bit is captured on this edge)
    endtask

    task automatic go_idle();
        Mode = 3'b000;
        pulse(0);               // any state -> IDLE
        pulse(0);               // IDLE clears the masks
    endtask

    // Shift a code MSB first; returns after the edge that captures the last bit
    task automatic send_code(int value, int nbits);
        for (int i = nbits - 1; i >= 0; i--)
            pulse(value[i]);
    endtask

    logic [31:0] wl_mask;
    logic [63:0] bl_mask;

    initial begin
        rst_n = 0; Mode = 0; S_Ain_c = 0;
        repeat (2) @(negedge clk);
        #1 check_off("reset");
        rst_n = 1;
        @(negedge clk);
        check_off("idle after reset");

        // ---------------- Program: all 32 codes, cumulative ----------------
        set_mode(3'b001);
        check_off("program: shifting first code, outputs off");
        wl_mask = '1;
        for (int n = 0; n < 32; n++) begin
            send_code(n, 5);
            wl_mask[n] = 0;
            check($sformatf("program code %0d applied", n), 1, 0, 1, 1, wl_mask, 64'h0, 32'h0);
            pulse(0);       // APPLY_PROG -> SHIFT_PROG_CONT (no bit captured)
            check($sformatf("program code %0d held", n), 1, 0, 1, 1, wl_mask, 64'h0, 32'h0);
        end

        go_idle();
        check_off("idle after program");

        // ---------------- Program: single code after IDLE starts fresh ----------------
        set_mode(3'b001);
        send_code(5, 5);
        check("program code 5 after idle (masks reset)", 1, 0, 1, 1, ~(32'h1 << 5), 64'h0, 32'h0);
        go_idle();

        // ---------------- Erase: all 64 codes, cumulative ----------------
        set_mode(3'b010);
        check_off("erase: shifting first code, outputs off");
        bl_mask = '1;
        for (int n = 0; n < 64; n++) begin
            send_code(n, 6);
            bl_mask[n] = 0;
            check($sformatf("erase code %0d applied", n), 1, 1, 1, 0, 32'h0, bl_mask, 32'h0);
            pulse(0);       // APPLY_ERASE -> SHIFT_ERASE_CONT
            check($sformatf("erase code %0d held", n), 1, 1, 1, 0, 32'h0, bl_mask, 32'h0);
        end
        go_idle();
        check_off("idle after erase");

        // ---------------- Loopback: all 32 codes, thermometer ----------------
        set_mode(3'b100);
        check_off("loopback: shifting first code, outputs off");
        for (int n = 0; n < 32; n++) begin
            logic [31:0] therm;
            therm = (n == 31) ? 32'hFFFF_FFFF : ((32'h1 << (n + 1)) - 1);
            send_code(n, 5);
            check($sformatf("loopback code %0d applied", n), 0, 0, 0, 0, 32'h0, 64'h0, therm);
            pulse(0);       // APPLY_LB -> SHIFT_LB_CONT
            check($sformatf("loopback code %0d held", n), 0, 0, 0, 0, 32'h0, 64'h0, therm);
        end
        // Loopback is not cumulative: a lower code shrinks the thermometer
        send_code(3, 5);
        check("loopback code 3 after 31", 0, 0, 0, 0, 32'h0, 64'h0, 32'h0000_000F);
        go_idle();
        check_off("idle after loopback");

        // ---------------- Inference ----------------
        set_mode(3'b011);
        for (int i = 0; i < 8; i++) begin
            pulse(i[0]);
            check_off("inference: all outputs off");
        end
        go_idle();

        // ---------------- Abort in the middle of a code ----------------
        set_mode(3'b001);
        pulse(1); pulse(1); pulse(1);       // 3 of 5 bits
        check_off("program: partial code, no output");
        go_idle();
        set_mode(3'b001);
        send_code(2, 5);                    // must decode as a fresh code 2
        check("program after abort decodes fresh code", 1, 0, 1, 1, ~(32'h1 << 2), 64'h0, 32'h0);

        // Leaving the mode during APPLY drops to IDLE and clears outputs
        Mode = 3'b010;
        pulse(0);
        check_off("mode change during program -> idle");
        go_idle();

        // ---------------- Undefined modes act like idle ----------------
        for (int m = 5; m <= 7; m++) begin
            Mode = m[2:0];
            repeat (7) pulse(1);
            check_off($sformatf("undefined mode %b", m[2:0]));
        end
        go_idle();

        // ---------------- Reset in the middle of operation ----------------
        set_mode(3'b010);
        send_code(10, 6);
        rst_n = 0; #1;
        check_off("async reset during erase");
        rst_n = 1;
        Mode = 0;
        @(negedge clk);
        check_off("idle after async reset");

        if (errors == 0)
            $display("=== ALL %0d CHECKS PASSED ===", checks);
        else
            $display("=== %0d OF %0d CHECKS FAILED ===", errors, checks);
        $finish;
    end

endmodule
