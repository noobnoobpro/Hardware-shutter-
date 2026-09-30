# FPGA Hardware Shutter for Timepix3

```{=html}
<p align="center">
```
`<strong>`{=html}Deterministic FPGA-based shutter timing for Timepix3 on
Xilinx Zynq UltraScale+ MPSoC`</strong>`{=html}
```{=html}
</p>
```
```{=html}
<p align="center">
```
`<img alt="Vivado" src="https://img.shields.io/badge/Vivado-2024.2-blue">`{=html}
`<img alt="HDL" src="https://img.shields.io/badge/HDL-Verilog-blue">`{=html}
`<img alt="FPGA" src="https://img.shields.io/badge/FPGA-XCZu7EV-blue">`{=html}
`<img alt="Status" src="https://img.shields.io/badge/status-hardware%20integration-yellow">`{=html}
```{=html}
</p>
```

------------------------------------------------------------------------

## What this project is about

The existing Timepix3 setup controls the shutter from Linux/Python
through an AXI-to-GPIO register. Software raises the shutter, waits, and
lowers it again.

That is convenient, but the timing-critical part still depends on
software scheduling.

This work moves the shutter pulse generation into FPGA logic so that
software only provides the configuration and trigger.

``` mermaid
flowchart LR
    A["Linux / Python"] -->|"AXI register writes"| B["AXI-to-GPIO"]
    B --> C["Clock-Domain Crossing"]
    C --> D["Hardware Shutter FSM"]
    D --> E["Shutter"]
    E --> F["Timepix3"]

    B -. "width / control" .-> D
```

### The change in one picture

  Software-controlled shutter    Hardware-controlled shutter
  ------------------------------ ----------------------------------
  Python opens shutter           Python configures width
  `sleep(t)` determines timing   FPGA counter determines timing
  Python closes shutter          FPGA closes shutter
  OS scheduling affects timing   Deterministic clock-based timing

The current hardware shutter uses a **40 MHz timing clock**, giving a
coarse timing step of:

\[ T = `\frac{1}{40\ \mathrm{MHz}}`{=tex} = 25 `\mathrm{ns}`{=tex} \]

------------------------------------------------------------------------

## Hardware

  Item                        Configuration
  --------------------------- -------------------------------
  Platform                    Enclustra Andromeda XZU65
  FPGA / SoC family           Xilinx Zynq UltraScale+ MPSoC
  Vivado target               `xczu7ev-ffvc1156-2-i`
  Detector                    Timepix3
  Toolchain                   Xilinx Vivado 2024.2
  Current shutter clock       40 MHz
  Current coarse resolution   25 ns

The shutter work is a **subset of a larger detector-control design**
containing AXI peripherals, detector interfaces, Linux/PetaLinux
software, board constraints, and additional Timepix3 logic.

------------------------------------------------------------------------

## Architecture

The hardware path currently under test is:

``` mermaid
flowchart TB
    CPU["Linux / Python"]

    subgraph AXI["AXI clock domain"]
        GPIO["axi_to_gpio"]
        WIDTH["Shutter Width Register"]
        CTRL["Control / START"]
    end

    subgraph CDC["Clock-Domain Crossing"]
        TOGGLE["Request Toggle + Synchronizer"]
        CAPTURE["Configuration Capture"]
    end

    subgraph TIMING["40 MHz shutter domain"]
        FSM["shutter_fsm"]
        OUT["Hardware Shutter"]
    end

    CPU --> GPIO
    GPIO --> WIDTH
    GPIO --> CTRL
    CTRL --> TOGGLE
    WIDTH --> CAPTURE
    TOGGLE --> CAPTURE
    CAPTURE --> FSM
    FSM --> OUT
    OUT --> TPX["Timepix3 Shutter"]
```

The original software shutter path is retained as a fallback while the
hardware implementation is brought up.

------------------------------------------------------------------------

## Hardware Shutter FSM

`shutter_fsm.v` generates the shutter pulse in hardware.

``` mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> WAIT_DELAY: trigger + delay > 0
    IDLE --> SHUTTER_OPEN: trigger + delay = 0
    WAIT_DELAY --> SHUTTER_OPEN: delay complete
    SHUTTER_OPEN --> IDLE: width complete
```

### Inputs

-   `trigger` --- starts a shutter operation
-   `delay_cycles` --- optional coarse delay before opening
-   `shutter_cycles` --- requested shutter width

### Debug / status

-   `shutter`
-   `busy`
-   `state`
-   `counter`

The timing configuration is latched when a trigger is accepted,
preventing later software writes from changing an active pulse.

### Example timing

``` text
40 MHz clock
       ┌───┐   ┌───┐   ┌───┐   ┌───┐
───────┘   └───┘   └───┘   └───┘   └──────
         25 ns   25 ns   25 ns   25 ns

width = 4
       ┌───────────────────────────────┐
───────┘            SHUTTER            └──────
              <------ 100 ns ------>

width = 8
       ┌───────────────────────────────────────────────┐
───────┘                    SHUTTER                    └──────
                       <------ 200 ns ------>
```

------------------------------------------------------------------------

## AXI Register Interface

The development register map extends the existing GPIO interface without
removing the legacy control path.

    Offset Register               Purpose
  -------- ---------------------- ----------------------------------------
    `0x00` GPIO                   Existing GPIO control / legacy shutter
    `0x04` Shutter Width          Hardware shutter width in clock cycles
    `0x08` Timing Configuration   Reserved for future fine timing
    `0x0C` Control / Status       Hardware enable, START and status

A START request is transferred from the AXI clock domain into the
shutter clock domain using a toggle-based CDC mechanism. The shutter
configuration is captured before the FSM trigger is issued.

------------------------------------------------------------------------

## Simulation Results

The integration testbench verifies both the legacy and hardware shutter
paths.

### Hardware shutter: 4 cycles

``` text
shutter_width = 4

gpio_clk     ↑      ↑      ↑      ↑      ↑
             │      │      │      │      │
hw_shutter   ┌─────────────────────┐
─────────────┘                     └──────────
             <------ 100 ns ------->
```

### Hardware shutter: 8 cycles

``` text
shutter_width = 8

gpio_clk     ↑      ↑      ↑      ↑      ↑      ↑      ↑      ↑      ↑
             │      │      │      │      │      │      │      │      │
hw_shutter   ┌───────────────────────────────────────────────┐
─────────────┘                                               └──────
             <-------------------- 200 ns ------------------->
```

## Fine Timing Investigation

The 40 MHz FSM provides deterministic timing, but only in **25 ns
increments**.

The detector work also requires investigation of **nanosecond-scale
alignment** between the shutter and the relevant detector clock. A
separate Xilinx Clocking Wizard/MMCM experiment is therefore included.

``` mermaid
flowchart LR
    REF["Reference Clock"] --> MMCM["Clocking Wizard / MMCM"]
    MMCM --> SHIFT["Phase-adjusted Clock"]
    SHIFT --> ALIGN["Future ns-scale alignment"]

    CTRL["Phase-control experiment"] -->|"PSEN / PSINCDEC"| MMCM
    MMCM -->|"PSDONE"| CTRL
```

The experiment exercises:

-   `PSCLK`
-   `PSEN`
-   `PSINCDEC`
-   `PSDONE`

and verifies repeated phase-shift requests using the MMCM handshake.

> **Important:** dynamic phase shifting is currently an investigation,
> not the final shutter architecture.

Only the relevant part of this experiment will be integrated once the
required ns-scale timing mechanism and the exact clock to be delayed are
fixed. The current shutter pulse width does **not** depend on the
Clocking Wizard phase-shift experiment.

This separation is intentional:

``` text
                SHUTTER TIMING
                      │
          ┌───────────┴───────────┐
          │                       │
          ▼                       ▼
   Coarse pulse timing       Fine alignment
      shutter_fsm          Clock / delay logic
          │                       │
       25 ns steps             ns scale
          │                       │
          └───────────┬───────────┘
                      ▼
                 Final timing
```

------------------------------------------------------------------------

## Repository Contents

``` text
hardware_shutter/
│
├── README.md
│
├── shutter_fsm.v
├── tb_shutter_fsm.v
│
├── tb_axi_to_gpio.v
│
├── phase_controller.v          # if included in this branch
└── tb_clk_wiz.v
```

### `shutter_fsm.v`

Deterministic hardware shutter generator.

### `tb_shutter_fsm.v`

Standalone FSM verification.

### `tb_axi_to_gpio.v`

Integration test for AXI configuration, CDC and hardware shutter
generation.

### `phase_controller.v`

Experimental controller for repeated MMCM dynamic phase-shift requests.

### `tb_clk_wiz.v`

Clocking Wizard / dynamic phase-shift simulation.

------------------------------------------------------------------------

## Development Status

``` mermaid
flowchart LR
    A["RTL"] --> B["Behavioral Simulation"]
    B --> C["Andromeda Integration"]
    C --> D["Synthesis"]
    D --> E["Implementation"]
    E --> F["Bitstream"]
    F --> G["Ethernet Transfer"]
    G --> H["FPGA Hardware Test"]
    H --> I["Timing Measurement"]
    I --> J["ns-scale Alignment"]

    style A stroke-width:3px
    style B stroke-width:3px
    style C stroke-width:3px
    style D stroke-width:3px
```

**Current stage:** integration, synthesis and implementation in the
complete Andromeda XZU65 design.

The target system is currently programmed through the embedded Linux
environment over Ethernet rather than through the normal JTAG
development path.

------------------------------------------------------------------------

## Current Scope

This repository is **not a complete Timepix3 firmware release**.

It contains the hardware-shutter RTL, integration testbenches, and
selected clock-timing experiments used during development. The complete
Andromeda/Timepix3 system includes additional
proprietary/project-specific RTL, generated Vivado IP, constraints,
detector-control logic and Linux/PetaLinux components that are outside
this repository.

------------------------------------------------------------------------


### Design principle

> **Software configures the shutter. Hardware owns the timing.**
