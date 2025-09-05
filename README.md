# ProcV Helium

ProcV Helium is designed as a minimalistic, performant, and extensible operating system targeting systems as old as 1999. It started as a hobby project to learn more about how hardware works, but it evolved into something serious once I realized how enjoyable writing it is.

ProcV is open-source, and its documentation is important. A goal of mine with ProcV is to not just help myself learn, but to help others learn through reading extensive yet helpful documentation, and to learn history out the reasonings behind why things are the way they are.

For those wishing to help improve code or documentation, please make an issue or contact me through Discord on what to improve.

# ! BEFORE CONTINUING !
Yes, there is no source code... or any code at all. I will publish it once I am comfortable with the state of the operating system. At the moment, ProcV is not exactly usable, and I want userspace, good documentation, and general improvements before
publishing it.

## Roadmap
ProcV is still in development. It is far from a full OS, but it is improving daily in terms of functionality.

- [X] BIOS Bootloader including:
  - VESA framebuffer loading
  - E820 memory map obtainment
  - Saving RSDP
  - Loading kernel into extended memory using Unreal Mode
- [X] Interrupt handling using:
  - LAPIC & I/O APIC
  - Dynamic callbacks
  - IRQ remapping & deprecation
  - LAPIC calibration
- [X] Timing
  - LAPIC timer for low accuracy and scheduling
  - TSC timer for high accuracy
  - RTC for wall clock and as a reference for variant timers
- [X] Memory Management
  - 4MB Paging
  - Page mapping
  - Physical memory allocator (bitmap)
- [X] Hardware Abstraction Layer
  - Interrupt abstraction
  - COM abstraction
  - I/O abstraction
  - TSC abstraction
  - Paging abstraction
  - PC speaker abstraction
  - ACPI abstraction
- [ ] Drivers
  - [X] ATA
  - [X] CMOS / RTC
  - [X] PCI
  - [X] PS/2
  - [X] VESA / VGA
  - [ ] NIC
  - [ ] AC'97
  - [ ] USB
  - [ ] NVMe
- [X] CLI w/ tokenizer
  - Direct disk reads / writes / partitioning
  - Direct RAM reads / writes
  - Help
  - Clear terminal
  - Current time
- [ ] Services
  - [X] CLK (abstraction over LAPIC, TSC, and RTC for low-precision and high-precision timing, scheduling, and sleeping
  - [ ] - [ ] HWD (abstraction over PCI)
  - [ ] DSK (abstraction over NVMe, ATA, USB)
  - [X] DEV (abstraction over human peripherals such as mouse and keyboard)
  - [ ] GUI (abstraction over GPU or framebuffer for rendering to screen)
  - [X] MEM (abstraction over RAM bitmap allocator)
  - [ ] VFS (abstraction over DSK for reads and write to and from a filesystem)
  - [ ] NET (abstraction over NIC driver for contacting the outside world)
- [ ] Standard Library
  - [X] Heap allocator and memory functions using SSE
  - [X] Standard definitions
  - [X] UTF-32 string manipulation
  - [ ] Math functions
  - [ ] Console output (through COM or something)
  - [ ] Algorithms (sorting, hashmaps, etc.)

## Building

To build ProcV, you only require 3 dependencies:
 - QEMU
 - NASM
 - i686 ELF GCC cross compiler

If you are on Windows, you may build directly using the provided `run32.bat` Batch script in the repository. It will automatically compile the source into a disk image and boot you into the operating system through `qemu-system-i386`. This project does not come with a Bash script or a Make script.
Make sure to place `src` and `run32.bat` in their own folder to prevent the script from dumping logs and temporary folders into your system.

## Licensing

ProcV is licensed under the GNU General Public License v3. I value free software and the modification of my work, and the GNU GPLv3 seemed like a best fit for this while restricting others from redistributing ProcV
under a proprietary license. In my eyes, all software should be free, and therefore, you are free to modify and redistribute ProcV as you wish.
