This file contains extensive and full documentation of all the APIs used by Procedure operating systems. Despite not being an official source, the numbers, recommendations, and
information have all been checked against official sources. If you would like to double-check the reliability of the numbers provided, each chapter will provide references used.

All code snippets present will use ISO C and Intel syntax Assembly.

**Table of Contents**

- [PS/2](#section-ps/2)
- [ATA](#section-ata)
- [PCI](#section-pci)
- [CMOS](#section-cmos)
- [VESA](#section-vesa)
- [VGA](#section-vga)

<a id="section-ps/2"></a>
# PS/2

PS/2 refers to the lineup of computers released by IBM in 1987. One of the two most recognized standards that IBM shipped with these computers is the PS/2 interface.
When people refer to PS/2, it is typically referring to the interface that is used to interact with the keyboard and mouse, which are plugged into the computer using
a PS/2 port. IBM extended Intel's i8042 chip to have an auxiliary interface to go alongside the keyboard interface, allowing the introduction of both a mouse and a
keyboard to your computer, which are still both the most prevalent devices present on any computer. The PS/2 is a colloquial term to refer to a modified version of the
Intel i8042 chip, which handles much more than PS/2 configuration.

## Implementation

These PS/2 devices are interacted with using a status port and a data port. Due to their age, these two ports are accessed using port-mapped I/O, contrary to the more
typical memory-mapped I/O seen in more modern device interfaces.

### PS/2 / i8042 Ports
| Hex  | Name        | Description                                                                                           |
|------|-------------|-------------------------------------------------------------------------------------------------------|
| 0x60 | Data Port   | Can be read as a response from the controller and<br>can be used to issue commands to a PS/2 device.  |
| 0x64 | Status Port | Can be read for the i8042 controller state and can be used<br>to issue commands to the controller.    |

On x86, these can be written to or read from using the `in` and `out` mnemonics:

```
mov al, 0x1234 ; Some command
out 0x64, al ; Issue the command to the PS/2 controller
in al, 0x60 ; Read the response from the PS/2 controller
```

### i8042 Controller Status Byte

Upon reading from the status port, you can obtain a structure providing the current state of the i8042 controller:

| Bit | Name          | Description                                                                                                         |
|-----|---------------|---------------------------------------------------------------------------------------------------------------------|
| 7   | Parity Error  | Indicates last byte of data received from the keyboard had odd parity. Places 0xFF in data port when parity is odd. |
| 6   | Timeout       | Indicates keyboard transmission or controller transmission did not conclude within its time limit.                  |
| 5   | Aux Response  | Indicates that the auxiliary PS/2 device was the responder to the command issued to the status port.                |
| 4   | Inhibited     | When off, indicates that the keyboard password is active and that the keyboard is inhibited.                        |
| 3   | Status Write  | Set by the controller when the software writes to the status port.                                                  |
| 2   | System Flag   | Set to the same value that is written to the System Flag bit in the Controller Command byte.                        |
| 1   | Input Pending | Indicates that data has been written to either the status or data port, but has not yet been processed.             |
| 0   | Main Response | Indicates that a PS/2 device has responded to the command issued to the status port.                                |

- Software should only write to the data or status port when the Main Response bit in the Controller Status byte is off.
- When both the Main Response and the Aux Response bits are set, it indicates that the responder to the sent data was the auxiliary device. If
Main Response is set and Aux Response is not, it indicates that the responder to the sent data was the keyboard.

### Issuable i8042 Commands

The following commands can be sent to the status port to perform certain actions on either the controller or a PS/2 device:

**0x20 - 0x3F** - Read from Controller RAM<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Issuing any value in the specified range will return a byte from the controller's RAM. The only byte that is valuable to read from controller memory
is byte 0 (by issuing 0x20 to the controller through the status register), as it is guaranteed to be the Controller Configuration byte. Other bytes are
generally considered useless to software.

Upon issuing 0x20 to the status port, the data port will return the Controller Configuration byte, which can be read to obtain the following structure:

| Bit | Name            | Description                                                                                                         |
|-----|-----------------|---------------------------------------------------------------------------------------------------------------------|
| 7   | Reserved        | This bit is reserved (i.e. not used).                                                                               |
| 6   | Translate       | If a Type 1 controller is present, the controller will translate keyboard scan codes to scan set 1.                 |
| 5   | Disable Aux     | When on, disables the auxiliary device by driving the clock line low. No data is received while disabled.           |
| 4   | Disable Main    | When on, disables the keyboard device by driving the clock line low. No data is received while disabled.            |
| 3   | Reserved        | This bit is reserved (i.e. not used).                                                                               |
| 2   | System Flag     | The value written here is forwarded to the Controller Status byte.                                                  |
| 1   | Enable Aux Int  | When on, will trigger an interrupt (IRQ12) every time the auxiliary device places a byte into the data port.        |
| 0   | Enable Main Int | When on, will trigger an interrupt (IRQ1) every time the keyboard device places a byte into the data port.          |

**0x60 - 0x7F** - Write to Controller RAM<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Issuing any value in the specified range will tell the controller to write the next value passed to the status port to the appropriate byte of RAM
that maps to the command value. The only byte that is value top write to is the Controller Configuration byte by issuing command 0x60. Other bytes
are generally considered useless to software.

**0xA4** - Test Password Installed<br>
&nbsp;&nbsp;&nbsp;&nbsp;
This tells the controller to check for a password currently installed in it. The result of the test is placed in the data port. When the data port
is read, a value of 0xFA indicates a password is installed, while 0xF1 indicates a password is not installed.

**0xA5** - Load Password<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Initiates the Password Load procedure, which will continue to take in writes to the data port as an ASCII-encoded string. Once a null sentinel of `\0` (i.e. a plain 0, or no bits set) is encountered, the password is stored in the controller.

**0xA6** - Enable Password<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Enables the controller password feature. This only works when there is a password currently present in the controller.

**0xA7** - Disable Auxiliary Device Interface<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Sets the Disable Aux byte of the Controller Configuration byte to on, which disables the auxiliary device interface. Data is not received while the interface is disabled.

**0xA8** - Enable Auxiliary Device Interface<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Sets the Disable Aux byte of the Controller Configuration byte to off, which enables the auxiliary device interface and allowing it to receive data.

**0xAD** - Disable Keyboard Interface<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Sets the Disable Main byte of the Controller Configuration byte to on, which disables the keyboard interface. Data is not received while the interface is disabled.

**0xAE** - Enable Keyboard Interface<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Sets the Disable Aux byte of the Controller Configuration byte to off, which enables the keyboard interface and allowing it to receive data.

**0xC0** - Read Input Port<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Tells the controller to read its input port and place its contents in the data port, which can then be read by the software.

**0xC1** - Poll Input Port Low<br>
&nbsp;&nbsp;&nbsp;&nbsp;
For Type 1 controllers exclusively, the 4 low bits of the input port are placed into the high 4 bits of the Controller Status byte.

**0xC2** - Poll Input Port High<br>
&nbsp;&nbsp;&nbsp;&nbsp;
For Type 1 controllers exclusively, the 4 high bits of the input port are placed into the high 4 bits of the Controller Status byte.

**0xD1** - Write Output Port<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Tells the controller to place the next byte written to the data port into the controller output port. Type 2 controllers can only write to the first bit (i.e. the A20 gate).

**0xD2** - Write Keyboard Output Buffer<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Forwards the next byte written to the data port back to the data port, and performing the appropriate actions such as firing the keyboard IRQ if it is enabled as if the keyboard invoked it.

**0xD3** - Write Auxiliary Device Output Buffer<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Forwards the next byte written to the data port back to the data port, and performing the appropriate actions such as firing the auxiliary IRQ if it is enabled as if the auxiliary device invoked it.

**0xD4** - Write to Auxiliary Device<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The next byte written to the data port is forwarded to the auxiliary device rather than the keyboard.

**0xE0** - Write Auxiliary Device Output Buffer<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Makes the controller reads its test inputs and place the result in the data port. Test 0 is connected to the keyboard clock, and Test 1 is connected to the auxiliary device clock. Data bit 0 represents Test 0, and data bit 1 represents Test 1.

**0xF0 - 0xFF** - Pulse Output Port<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Pulses the selected bits in the controller's output port for approximately 6 milliseconds. The low 4 bits select the respective bits in the controller output port. For example, if the first bit in the command is off, the first bit of the output port
is pulsed and the CPU is reset.

<a id="section-ata"></a>
# ATA

This chapter has not been written yet.

<a id="section-pci"></a>
# PCI

This chapter has not been written yet.

<a id="section-cmos"></a>
# CMOS

This chapter has not been written yet.

<a id="section-vesa"></a>
# VESA

This chapter has not been written yet.

<a id="section-vga"></a>
# VGA

This chapter has not been written yet.




