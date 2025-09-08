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
mov al, 0xD0 ; Some command
out 0x64, al ; Issue the command to the PS/2 controller
in al, 0x60  ; Read the response from the PS/2 controller
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

### Quick Note

The distinction between a Type 1 and a Type 2 controller is minor but important when proceeding. A Type 1 controller is the original, unmodified Intel i8042, which
supported solely a keyboard. IBM's extension of the i8042 is referred to as a Type 2 controller, which supported the auxiliary device. A few important distinctions
between these two controllers:

- Two commands (unspecified in the specs) are unavailable on Type 2 controllers.
- Only the Type 1 controller can translate keyboard scan codes when the Translate bit in the Controller Configuration byte is on.
- The Type 2 controller can only provide 7 of the 32 internal addresses present in the controller.
- Poll Input Port Low nor Poll Input Port High are supported by Type 2 controllers.
- Type 2 controllers only support writes to the A20 Gate bit in the output port.
- The only Pulse Output Port command variant supported by the Type 2 controller is command `0xFE`.

### Issuable i8042 Commands

The following commands can be sent to the status port to perform certain actions on either the controller or a PS/2 device:

**0x20 - 0x3F** - Read from Controller RAM<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Issuing any value in the specified range will return a byte from the controller's RAM. The only byte that is valuable to read from controller memory
is byte 0 (by issuing `0x20` to the controller through the status register), as it is guaranteed to be the Controller Configuration byte. Other bytes are
generally considered useless to software.

Upon issuing `0x20` to the status port, the data port will return the Controller Configuration byte, which can be read to obtain the following structure:

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
that maps to the command value. The only byte that is valuable to write to is the Controller Configuration byte by issuing command 0x60. Other bytes
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
Enables the keyboard password feature. This only works when there is a password currently present in the controller.

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

The following structure is returned in the data port upon issuing this command:

| Bit | Name            | Description                                                                                                         |
|-----|-----------------|---------------------------------------------------------------------------------------------------------------------|
| 7-2 | Reserved        | These bits are reserved (i.e. not used).                                                                            |
| 1   | Aux Data In     | Reflects the state of the data line driven by the auxiliary device.                                                 |
| 0   | Main Data In    | Reflects the state of the data line driven by the keyboard.                                                         |

**0xC1** - Poll Input Port Low<br>
&nbsp;&nbsp;&nbsp;&nbsp;
For Type 1 controllers exclusively, the 4 low bits of the input port are placed into the high 4 bits of the Controller Status byte.

**0xC2** - Poll Input Port High<br>
&nbsp;&nbsp;&nbsp;&nbsp;
For Type 1 controllers exclusively, the 4 high bits of the input port are placed into the high 4 bits of the Controller Status byte.

**0xD0** - Read Output Port<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Tells the controller to read its output port and place its contents in the data port, which can then be read by the software.

The following structure is returned in the data port upon issuing this command:

| Bit | Name            | Description                                                                                                         |
|-----|-----------------|---------------------------------------------------------------------------------------------------------------------|
| 7   | Main Data Out   | Reflects the state of the data line driven by the keyboard.                                                         |
| 6   | Main Clock Out  | Reflects the state of the clock line driven by the keyboard.                                                        |
| 5   | IRQ12 Data      | When on, indicates that the data present in the data port is issued by the auxiliary device.                        |
| 4   | IRQ1 Data       | When on, indicates that the data present in the data port is issued by the keyboard.                                |
| 3   | Aux Clock Out   | Reflects the state of the data line driven by the auxiliary device.                                                 |
| 2   | Aux Data Out    | Reflects the state of the clock line driven by the auxiliary device.                                                |
| 1   | A20 Gate        | When on, alongside the second bit in the System Control Port A port (0x92), the A20 gate is enabled.                |
| 0   | Reset CPU       | When off, resets the CPU until the bit is switched back to on.                                                      |

- Setting the A20 Gate bit is a method used to enable A20 on older motherboards. Typically, this bit is on, but some motherboards still require
explicitly setting the second bit in the System Control Port A port.
- The Pulse Output Port command can be used to reset the CPU by issuing a command with it where the Reset CPU bit is cleared, resetting the CPU.
It is also possible to directly write to the controller's output port using the Write Output Port command and submitting any 8-bit value where
the first bit is off to reset the CPU.

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

**0xE0** - Read Test Inputs<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Makes the controller reads its test inputs and place the result in the data port. Test 0 is connected to the keyboard clock, and Test 1 is connected to the auxiliary device clock. Data bit 0 represents Test 0, and data bit 1 represents Test 1.

**0xF0 - 0xFF** - Pulse Output Port<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Pulses the selected bits in the controller's output port for approximately 6 milliseconds. The low 4 bits select the respective bits in the controller output port. For example, if the first bit in the command is off, the first bit of the output port
is pulsed and the CPU is reset.

## Auxiliary Device Protocol

Before proceeding, it is important to note that sending commands to the auxiliary device requires issuing the Write to Auxiliary Device command to the status port
before issuing the auxiliary device command. Otherwise, the command will be forwarded to the keyboard, which is most likely unwanted.

Every auxiliary device generally follows the same protocol, and can be interfaced with or configured relatively similarly. The accuracy of the following information
may be dodgy as official sources from IBM and Microsoft have seemingly been purged.

From here, the auxiliary device will be referred to as the mouse, as it is the most common device that will be plugged into the computer.

The default PS/2 mouse sends its information in 3 separate 8-bit packets. The mouse will continue to issue these one by one, and each write will trigger IRQ12, assuming
that the software had set the Enable Aux Int bit in the Controller Configuration byte to on. Once 3 packets have been received, the section of info has been returned and
the next set of packets will come. For PS/2-compliant mice, the mouse will send the packets in the following order.

The first packet consists of mouse button state, along with overflow values for the mouse X and Y deltas. The first packet is structured like so:

| Bit | Name            | Description                                                                                                         |
|-----|-----------------|---------------------------------------------------------------------------------------------------------------------|
| 7   | Y Overflow      | The 9th overflow bit of the third packet (i.e. the Y delta).                                                        |
| 6   | X Overflow      | The 9th overflow bit of the second packet (i.e. the X delta).                                                       |
| 5   | Y Sign          | Indicates the signedness of the third packet (i.e. the Y delta).                                                    |
| 4   | X Sign          | Indicates the signedness of the second packet (i.e. the X delta).                                                   |
| 3   | Always On       | This bit is guaranteed to always be on.                                                                             |
| 2   | Middle Button   | When on, indicates that the middle mouse button is being pressed.                                                   |
| 1   | Right Button    | When on, indicates that the right mouse button is being pressed.                                                    |
| 0   | Left Button     | When on, indicates that the left mouse button is being pressed.                                                     |

The second packet consists of the low 8 bits of the X delta, and the third consists of the low 8 bits of the Y delta. Once all three packets have
been received, the software may perform whatever action it wishes with the information provided.

As seen above, the mouse's X and Y deltas are provided as signed 9-bit integers. This gives them a potential range of negative 255 to positive 255. If the
mouse delta exceeds this range, the appropriate overflow bit in the first packet will be set.

### Mouse Modes

The mouse can be put into multiple modes, which will be described below.

**Reset Mode**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse enters reset mode at boot, or in response to the Reset command. The mouse will perform a diagnostic test, referred to as BAT (Basic Assurance Test). This
sets the mouse to a few default values:

- 100 samples per second
- 5 counts per millimeter
- Scaling is 1:1
- Data reports are disabled

The mouse will then send either a `0xAA` indicating success, or a `0xFC` indicating failure to the data port. Once the BAT completion code is read by software, the mouse will provide
its device ID through the data port, which on standard PS/2 mice will return `0x00`. Once the mouse has sent its device ID to the software, it will enter stream mode. The mouse will not
send any packets to the software until the software enables Data Reporting, which was disabled by the Reset command or during boot.

**Stream Mode**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
As described above, this is the mode that the mouse will be put into after reset and the device ID is read. The mouse will continuously provide data to the software upon detected change
at the specified sample rate. As specified above, this is defaulted to 100, but may be changed by using the Set Sample Rate command. Stream mode is the default mode of operation, and most
commonly seen in software.

**Remote Mode**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
In this mode, the mouse will only notify the host of the changes when the software explicitly requests it. The software can request the mouse updates by issuing the Read Data command
to the mouse. Once received by the mouse, it will provide the software the expected packets.

**Wrap Mode**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
Every byte that the mouse received in this mode is returned to software. The mouse will refuse to respond to any command other than the Reset command and the Reset Wrap Mode command.
Every command excluding these two will be echoed back to the software.

### Issuable Mouse Commands

The software may send any of the following commands to the mouse. When in Stream Mode, it is required that the software has Data Reporting disabled on the mouse.
It is also important to note that a majority of the following commands will return an acknowledge byte in the data port, which must be read before issuing any further
commands to the i8042 / PS/2 controller, let alone the mouse itself.

**0xFF - Reset**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will enter Reset Mode.

**0xFE - Resend**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The software may send this whenever it receives an invalid packet from the mouse. The mouse will resend the last packet it sent to the software in the data port. If the mouse
responds with another invalid packet, the software may respond with another Resend command, can issue an Error command, can issue a Reset command, or can disable mouse communication
by sending the Disable Auxiliary Device Interface command to the controller.

**0xF6 - Set Defaults**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will reset itself to the default values as if it were in Reset Mode. Contrary to Reset Mode, the mouse will not
perform a BAT on itself.

**0xF5 - Disable Data Reporting**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will disable data reporting and reset its internal counters. If the mouse is currently in Stream Mode, it will
behave the same as if it were in Remote Mode.

**0xF4 - Enable Data Reporting**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will enable data reporting and reset its internal counters. The command may be issued while the mouse is in
either Remote Mode or Stream Mode, but only affects data reporting in Stream Mode.

**0xF3 - Set Sample Rate**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will read the next byte passed to the data port as the new sample rate. The mouse will once again respond
with the acknowledge signal in the data port and will reset its internal counters. The only valid sample rates are `10`, `20`, `40`, `60`, `80`, `100`, and `200`.

**0xF2 - Get Device ID**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and its device ID will follow immediately after in the data port. The mouse will also reset its internal counters.

**0xF0 - Set Remote Mode**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will enter Remote Mode and reset its internal counters.

**0xEE - Set Wrap Mode**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will enter Wrap Mode and reset its internal counters.

**0xEC - Reset Wrap Mode**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will return itself to the previous mode it was in and reset its internal counters.

**0xEB - Read Data**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will then forward a packet through the data port. This is the only method to receive data while in Remote Mode.
Once the packet is read from the data port by the software, the mouse will reset its internal counters.

**0xEA - Set Stream Mode**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will enter Stream Mode and reset its internal counters.

**0xE9 - Status Request**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will then send three packets through the data port. The first packet consists of the following structure:

| Bit | Name            | Description                                                                                                         |
|-----|-----------------|---------------------------------------------------------------------------------------------------------------------|
| 7   | Always Off      | This bit is guaranteed to always be off.                                                                            |
| 6   | Current Mode    | If on, Remote Mode is enabled; if off, Stream Mode is enabled.                                                      |
| 5   | Data Reporting  | If on, data reporting is currently enabled.                                                                         |
| 4   | Current Scaling | If on, the current scaling is 2:1; if off, the current scaling is 1:1.                                              |
| 3   | Always Off      | This bit is guaranteed to always be off.                                                                            |
| 2   | Left Button     | When on, indicates that the left mouse button is being pressed.                                                     |
| 1   | Middle Button   | When on, indicates that the middle mouse button is being pressed.                                                   |
| 0   | Right Button    | When on, indicates that the right mouse button is being pressed.                                                    |

The second packet describes the mouse resolution, and the third one describes the mouse sample rate.

**0xE8 - Set Resolution**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will read the next byte passed to the data port to determine its new resolution. It will respond
with one more acknowledgement signal in the data port before resetting its internal counters. It uses the following lookup table to determine its new resolution:

| Byte | Resolution              |
|------|-------------------------|
| 0x00 | 1 count per millimeter  |
| 0x01 | 2 counts per millimeter |
| 0x02 | 4 counts per millimeter |
| 0x03 | 8 counts per millimeter |

**0xE7 - Set Scaling 2:1**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will then enable 2:1 scaling, which effectively doubles the mouse's delta sensitivity.

**0xE6 - Set Scaling 1:1**<br>
&nbsp;&nbsp;&nbsp;&nbsp;
The mouse will respond with the acknowledge signal in the data port, and will then enable 1:1 scaling.

### Notes

- PS/2 devices are not hot-pluggable. The system must be reset if a PS/2 device is removed. It is even possible to damage the motherboard when
inserting or removing a PS/2 device while the computer is still running.
- The standard PS/2 mouse will only ever send the Resend or Error commands back to software.
- It is generally recommended to reset the mouse before configuring it, as the firmware may have left it in a misconfigured state before handing control over to the software.

## Examples

One of the most common things that the PS/2 / i8042 controller is used for is to restart the CPU. A common misconception is that clearing the Reset CPU bit will shut down
the CPU. This is not true; the CPU will restart after this bit is cleared rather than fully shutting down the system.

There are two proper methods of resetting the CPU: you may pulse the Reset CPU bit to off by using the Pulse Output Port command, or by directly writing a byte with
the first bit off to the data port after issuing the Write Output Port command:

```
; Pulse the Reset CPU bit in the controller output port to reset the CPU
mov al, 0xFE ; Pulse Output Port command; all bits except the first are on
out 0x64, al ; Write the byte to the status port, pulsing the controller output port's bits and resetting the CPU
```

An important reminder: `0xFE` is the only variant of the Pulse Output Port command that is guaranteed to be supported by Type 2 controllers.

The next method is technically invalid on Type 2 controllers, as only the A20 Gate bit can legally be set. However, most controllers support
this regardless, and is still a potential fallback for Type 1 controllers if the pulse above did not work.

```
; Write a null byte to the controller output port to clear the Reset CPU bit and reset the CPU
mov al, 0xD1 ; Write Output Port command
out 0x64, al ; The controller will forward the next byte written to the data port to the controller output port
mov al, 0x00 ; Null byte; most importantly, the Reset CPU bit is off
out 0x60, al ; The output port has been written to, and the CPU will reset shortly
```

Some software decides to write to the A20 Gate bit in the controller's output port as a legacy fallback for motherboards that do not support the System Control Port A port. This is usually done like so:

```
; Read the output port byte
mov al, 0xD0 ; Read Output Port command
out 0x64, al ; The controller has placed the output port's state in the data port
in ah, 0x60  ; Read that byte into AH

; Enable A20 gate by setting the appropriate bit and writing it back to the output port
or ah, 0x02  ; Set the A20 Gate bit in AH to on
mov al, 0xD1 ; Write Output Port command
out 0x64, al ; The controller will replace the current contents of the output port with the next byte written to the data port
out 0x60, ah ; The output port has been written to and the A20 gate is now enabled 
```

## Sources Used

[Keyboard & Auxiliary Device Controller Specification](https://www.ardent-tool.com/docs/pdf/ibm_hitrc07.pdf)

[The PS/2 Mouse Interface](https://eaw.app/Downloads/PS2_Mouse.pdf)

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




