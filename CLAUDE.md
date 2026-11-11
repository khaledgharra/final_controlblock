# CLAUDE.md - read this FIRST every time we continue work on this repo

Project: synthesis + gate-level verification of the SNN chip control block (module `Control`).
RTL by Yuval & Magen Nibar (Ruppin, supervisor Ilan Oren). `Control.sv` = `Control_block_Fixed.txt`,
never modified.

---------------------------------------------------------------------------
## RULES (always follow)

1. **Commits: one commit per step, with a useful message.**
   Format: `<area>: <what changed> - <key result>`
   e.g. `TS18PM: synthesis results - slack +7.15 ns, 730 cells`
2. **Bugs get their own commits:**
   - When a bug is found: commit the evidence (failing log) with
     `BUG <short-name>: <symptom>` (e.g. `BUG reset-check-1ns: real-delay gate sim fails 1/282`).
   - When fixed: separate commit `FIX <short-name>: <cause> -> <fix> - <result>`.
   - Add every bug to the **BUG LOG** below (name, symptom, cause, fix, commits).
3. Ask the user before changing synthesis/P&R scripts (`*.tcl`, `.synopsys_dc.setup`) on your own initiative.
4. Never commit `*.pptx` (supervisor slides). Never commit tool junk (command.log, default.svf,
   filenames.log, xcelium.d/, xrun.history, xrun.log, WORK/).
5. Keep this file and the work log `~/vlsi_worklog/final_controlblock_LOG.md` (Mac) updated
   after every step. Update "STATUS / NEXT STEPS" below before ending a session.
6. Lab shell is **tcsh**: no `2>&1` (use `>&` or wrap in `bash -c '...'`).
7. Keep `README.md` (the public explanation: status table, tests, files, problems) in sync with
   every new result or bug fix.
8. The Mac copy under ~/Desktop is iCloud-offloaded (`.git` unreadable). On the Mac, work in a fresh
   clone outside ~/Desktop. Real work runs on the lab.

---------------------------------------------------------------------------
## STATUS / NEXT STEPS (last update 2026-11-11)

- `main`  = old library tsl18fs120 (PDK_TS18SL): slack +6.09 ns, 819 cells, gate-level 282/282.
- `ts18pm` = new library requested by the supervisor: /tools/kits/tower/TS18PM_1/
  - Library: `tsl18fs190svt_tt_1p8v_25c.db` (typical, 1.8 V, 25 C)
  - Synthesis (with `set_load 0.05 [all_outputs]`): slack +4.60 ns @ 10 ns, 731 cells, cell area 12700,
    0 DRC violations (area units differ from fs120). Without set_load it was +7.15 ns / 730 cells / 129 DRC.
  - Gate-level: 282/282 with zero delay AND with real delays (`tb_Control_gl.sv`)
- Next:
  1. (done) DRC min_capacitance fixed with set_load - commit 06ea472.
  2. Open question: `assign BL_Enable = WL_Enable;` in netlist (VO-4) - optional
     `set_fix_multiple_port_nets -all -buffer_constants`, not approved yet.
  3. Questions for supervisor: WL_Enable == BL_Enable always? 1-clock gap between codes?
  4. Not looked at yet: `Control_block_HighZ_not_fixed.txt`.

---------------------------------------------------------------------------
## LAB ACCESS (Mac Terminal)

1. `ssh epkgms@132.68.59.71 vncserver -list` ; if empty: `ssh epkgms@132.68.59.71 vncserver`
   and note the display `:N` (on 2026-11-11 it was `:2` because `:1` was locked).
2. Tunnel in its own Mac window (prints nothing, leave open):
   `ssh -N -L 590N:localhost:590N epkgms@132.68.59.71`
3. Finder -> Cmd+K -> `vnc://localhost:590N`. Lab terminal: `setenv DISPLAY :N`.
4. Lab repo: `~/Desktop/khaled/final_controlblock`. Push password = GitHub Personal Access Token.
5. "Create a color profile" pop-up: never type a password, never kill processes.

---------------------------------------------------------------------------
## HOW TO RUN (lab, in the repo)

Synthesis (no GUI):
```
dc_shell -x "source control_syn.tcl; exit" | tee syn.log
grep -m1 slack reports/timing.rpt ; grep -i "cell area\|Number of cells" reports/area.rpt
```
DRC list: `dc_shell -x "source control_syn.tcl; report_constraint -all_violators; exit" > drc.log`

Gate-level sim, TS18PM library (branch ts18pm):
```
set K=/tools/kits/tower/TS18PM_1/tsl18fs190svt_Rev_2019.09/lib/verilog
xrun -sv -timescale 1ns/1ps Control_syn.v tb_Control_gl.sv -v $K/tsl18fs190svt.v -v $K/tsl18fs190svt_udp.v
```
(add `-delay_mode zero` for zero-delay; add `-access +r -gui` for SimVision)

Gate-level sim, old library (branch main):
```
xrun -sv Control_syn.v tb_Control.sv -v /tools/kits/tower/PDK_TS18SL/FS120_STD_Cells_0_18um_2005_12/DW_TOWER_tsl18fs120/2005.12/verilog/zero/all.v
```

---------------------------------------------------------------------------
## BUG LOG

| # | Name | Symptom | Cause | Fix |
|---|---|---|---|---|
| 1 | tcsh-redirect | `Ambiguous output redirect.` | lab shell is tcsh, `2>&1` is bash syntax | wrap in `bash -c '...'` |
| 2 | timescale-missing | xmelab `*F,CUMSTS: Timescale directive missing` with TS18PM cells | new cell models have `1ns/1ps`, netlist has none | add `-timescale 1ns/1ps` to xrun |
| 3 | reset-check-1ns | real-delay gate sim: `FAIL async reset during erase`, 281/282 | `tb_Control.sv:165` checks 1 ns after `rst_n=0`; new library models have real delays (old run used zero-delay models) | `tb_Control_gl.sv` waits 3 ns -> 282/282; zero-delay run with original tb also 282/282 |
| 5 | drc-min-cap (FIXED 06ea472) | DRC cost 88.4, 129 `min_capacitance` violations on output ports (report: reports/drc_violators.rpt) | no output load constraint -> ~0 pF on output nets; new lib has min_capacitance | `set_load 0.05 [all_outputs]` before compile -> 0 violations, slack 4.60 ns, 282/282 |
| 4 | xrun-unresolved-UDP | (old lib) `U_MUX_2_1 is unresolved` | UDPs in separate file | use `-v .../verilog/zero/all.v` |
