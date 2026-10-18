// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import serial

/**
A very small simulation of a VL53L1X register file with 16-bit addresses.

It exists to check the order and the content of the register accesses of the
  driver, not to simulate the optics.  The same model is implemented in
  tests/trace-harness-l1x/Wire.h, so that traces recorded with ST's Ultra Lite
  Driver can be compared with traces recorded with this one.

Behaviour:
- Writes are stored and reads return the stored value, except for the
  registers listed in $model_.
- The preloaded result block describes a valid measurement of 300 mm.
- Every access is recorded in $trace, one line per access: "R reg count" for
  reads and "W reg byte byte ..." for writes.  A write of only the two address
  bytes sets the read pointer and is not recorded.
*/
class MockVl53l1xDevice implements serial.Device:
  regs_/ByteArray := ByteArray 0x200
  pointer_/int := 0
  /** The recorded register accesses and the markers added with $mark. */
  trace/List := []

  constructor:
    // Result block 0x89..0x99: status 9 (valid), 10.0 SPADs (8.8), ambient,
    // range 300 mm and signal.
    regs_[0x89] = 0x09
    regs_[0x8C] = 0x0A
    regs_[0x8D] = 0x00
    regs_[0x90] = 0x00
    regs_[0x91] = 0x40
    regs_[0x96] = 0x01
    regs_[0x97] = 0x2C
    regs_[0x98] = 0x01
    regs_[0x99] = 0x00
    // Oscillator calibration value.
    regs_[0xDE] = 0x05
    regs_[0xDF] = 0x80

  /** Adds a marker line to the $trace. */
  mark text/string -> none:
    trace.add "# $text"

  /** Sets the preloaded range result, in millimetres. */
  set-range mm/int -> none:
    regs_[0x96] = mm >> 8
    regs_[0x97] = mm & 0xFF

  /** Sets the raw status byte in the preloaded result block. */
  set-raw-status value/int -> none:
    regs_[0x89] = value

  model_ register/int -> int:
    if register == 0x010F: return 0xEA
    if register == 0x0110: return 0xCC
    if register == 0x0111: return 0x10
    if register == 0x00E5: return 0x03  // Booted.
    if register == 0x0031: return ((regs_[0x30] >> 4) & 1) ^ 1  // Data ready.
    return regs_[register & 0x1FF]

  registers -> serial.Registers:
    throw "UNIMPLEMENTED"

  write bytes/ByteArray -> none:
    if bytes.size < 2: throw "short write"
    register := (bytes[0] << 8) | bytes[1]
    if bytes.size == 2:
      pointer_ = register
      return
    line := "W $(%04X register)"
    (bytes.size - 2).repeat:
      line += " $(%02X bytes[2 + it])"
      regs_[(register + it) & 0x1FF] = bytes[2 + it]
    trace.add line

  read amount/int -> ByteArray:
    trace.add "R $(%04X pointer_) $amount"
    return ByteArray amount: model_ ((pointer_ + it) & 0xFFFF)
