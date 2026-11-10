`timescale 1ns / 1ps

// Prints the block's inputs and outputs clock by clock for a few example
// codes, so one can see how each code turns into WL_S / BL_S / LB_en.
module tb_demo;

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

    int cycle = 0;

    task automatic show(string note);
        $display("%4d | %b  |   %b    | WL_En=%b BL_En=%b | WL_S=%h | BL_S=%h | LB_en=%h | %s",
                 cycle, Mode, S_Ain_c, WL_Enable, BL_Enable, WL_S, BL_S, LB_en, note);
    endtask

    // One clock: drive S_Ain_c, clock it in, print the outputs after the edge
    task automatic pulse(logic b, string note);
        S_Ain_c = b;
        @(posedge clk); #1;
        cycle++;
        show(note);
        @(negedge clk);
    endtask

    task automatic send_code(int value, int nbits, string what);
        for (int i = nbits - 1; i >= 0; i--)
            pulse(value[i], $sformatf("%s bit %0d of %0d", what, nbits - i, nbits));
    endtask

    task automatic header(string title);
        $display("");
        $display("---- %s ----", title);
        $display("clk  | Mode | S_Ain_c | flags             | WL_S     | BL_S             | LB_en    | note");
    endtask

    initial begin
        rst_n = 0; Mode = 0; S_Ain_c = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;

        header("PROGRAM word line 5 (00101), then word line 9 (01001)");
        Mode = 3'b001;
        pulse(0, "IDLE -> SHIFT_PROG (no bit taken)");
        send_code(5, 5, "WL 5:");
        pulse(0, "APPLY_PROG -> SHIFT_PROG_CONT (bit ignored)");
        send_code(9, 5, "WL 9:");
        Mode = 3'b000;
        pulse(0, "Mode=000 -> IDLE, outputs off");
        pulse(0, "IDLE clears the masks");

        header("ERASE bit line 40 (101000)");
        Mode = 3'b010;
        pulse(0, "IDLE -> SHIFT_ERASE (no bit taken)");
        send_code(40, 6, "BL 40:");
        Mode = 3'b000;
        pulse(0, "Mode=000 -> IDLE");
        pulse(0, "IDLE clears the masks");

        header("LOOPBACK code 3 (00011) -> LB_en bits 0..3 on");
        Mode = 3'b100;
        pulse(0, "IDLE -> SHIFT_LB (no bit taken)");
        send_code(3, 5, "LB 3:");
        Mode = 3'b000;
        pulse(0, "Mode=000 -> IDLE");

        $display("");
        $finish;
    end

endmodule
