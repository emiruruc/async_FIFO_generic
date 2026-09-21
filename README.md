# Generic Asynchronous FIFO (VHDL)

A fully parametrizable asynchronous FIFO for safely transferring data across two independent, unrelated clock domains, using Gray-code pointer synchronization. Includes three self-written testbenches and Vivado implementation constraints with verified timing closure.

## Features

- Fully generic: `data_width`, `addr_width` (depth = `2**addr_width`), `N` (synchronizer stages)
- Gray-code write/read pointers with MSB-based full/empty detection
- N-stage CDC synchronizer (array-based, `ASYNC_REG`-tagged) in both directions
- Verified in simulation and carried through synthesis + implementation with timing closure on a real Xilinx target

## Files

| File | Description |
|---|---|
| `async_FIFO_generic.vhd` | The FIFO design |
| `tb_async_FIFO_generic.vhd` | Testbench 1 — basic write/read functional test |
| `tb2_async_FIFO_generic.vhd` | Testbench 2 — full-flag overwrite protection test |
| `tb3_async_FIFO_generic.vhd` | Testbench 3 — simultaneous write + read stress test |
| `async_FIFO_generic.xdc` | Pin assignment and clock constraints |
| `Async_FIFO_Design_Verification_Report.pdf` | Full design, verification, and timing-closure writeup |

## Architecture

- Write/read pointers are `addr_width + 1` bits wide (extra MSB for full/empty disambiguation)
- Each pointer is Gray-coded before crossing into the opposite clock domain
- Crossing is done through an N-stage synchronizer, implemented as an array of registers with a `for`-loop shift (each stage holds one full Gray-coded pointer)
- `full` / `empty` are computed by comparing the local Gray pointer against the synchronized opposite-domain pointer (MSBs inverted for `full`, exact match for `empty`)

See the full report for details, waveforms, and the XDC/timing-closure writeup.

## Simulation

Two independent clocks are used throughout testing (`clk_wr` = 100 MHz, `clk_rd` = 133.3 MHz) to genuinely exercise the CDC paths. Run any of the three testbenches in Vivado's behavioral simulator:

```
tb_async_FIFO_generic   -- basic write-then-read, full/empty timing, data integrity
tb2_async_FIFO_generic  -- fills FIFO, confirms overwrite is rejected while full
tb3_async_FIFO_generic  -- concurrent write + read at mid-depth
```

## Implementation

`async_FIFO_generic.xdc` assigns I/O pins (via Vivado's auto-place I/O flow) and defines the two clocks. Because `clk_wr` and `clk_rd` are asynchronous, `set_clock_groups -asynchronous` is required to prevent Vivado's static timing analysis from treating the CDC path as synchronous — see the report for the timing failure this caused and how it was resolved (WNS -0.203 ns / 6 failing endpoints → +4.240 ns / 0 failing endpoints, with no RTL changes).

## References

Architecture based on the standard Gray-code CDC technique described in:

- C. E. Cummings, *"Simulation and Synthesis Techniques for Asynchronous FIFO Design,"* SNUG 2002.
- P. P. Chu, *RTL Hardware Design Using VHDL*, Wiley, 2006 (Ch. 16).
- P. P. Chu, *FPGA Prototyping by VHDL Examples*, Wiley, 2008.

## Author

Emir Uruç
