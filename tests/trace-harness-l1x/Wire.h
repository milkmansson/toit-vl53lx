#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <vector>
// Fake I2C bus + simple VL53L1X register model (16-bit register addresses).
struct TwoWire {
  uint8_t regs[0x200];
  uint16_t ptr = 0;
  std::vector<uint8_t> txbuf;
  std::vector<uint8_t> rxbuf;
  size_t rxpos = 0;
  FILE* trace = stdout;
  TwoWire() {
    memset(regs, 0, sizeof regs);
    // Preloaded result block (0x89..0x99): status 9 (valid), spads 10.0 (8.8),
    // ambient 0x0040, range 300 mm, signal 0x0100.
    regs[0x89] = 0x09;
    regs[0x8C] = 0x0A; regs[0x8D] = 0x00;
    regs[0x90] = 0x00; regs[0x91] = 0x40;
    regs[0x96] = 0x01; regs[0x97] = 0x2C;
    regs[0x98] = 0x01; regs[0x99] = 0x00;
    regs[0xDE] = 0x05; regs[0xDF] = 0x80;  // Oscillator calibration value.
  }
  uint8_t model(uint16_t r) {
    switch (r) {
      case 0x010F: return 0xEA;
      case 0x0110: return 0xCC;
      case 0x0111: return 0x10;
      case 0x00E5: return 0x03;
      case 0x0031: return ((regs[0x30] >> 4) & 1) ^ 1;  // Data ready.
      default: return regs[r & 0x1FF];
    }
  }
  void beginTransmission(uint8_t) { txbuf.clear(); }
  size_t write(uint8_t b) { txbuf.push_back(b); return 1; }
  size_t write(const uint8_t* b, size_t n) { for (size_t i = 0; i < n; i++) txbuf.push_back(b[i]); return n; }
  uint8_t endTransmission(bool = true) {
    if (txbuf.size() == 2) { ptr = (txbuf[0] << 8) | txbuf[1]; }
    else if (txbuf.size() > 2) {
      uint16_t reg = (txbuf[0] << 8) | txbuf[1];
      fprintf(trace, "W %04X", reg);
      for (size_t i = 2; i < txbuf.size(); i++) {
        fprintf(trace, " %02X", txbuf[i]);
        regs[(reg + i - 2) & 0x1FF] = txbuf[i];
      }
      fprintf(trace, "\n");
    }
    return 0;
  }
  uint8_t requestFrom(uint8_t, uint8_t n) {
    fprintf(trace, "R %04X %d\n", ptr, n);
    rxbuf.clear(); rxpos = 0;
    for (int i = 0; i < n; i++) rxbuf.push_back(model((uint16_t)(ptr + i)));
    return n;
  }
  int available() { return (int)(rxbuf.size() - rxpos); }
  int read() { return rxpos < rxbuf.size() ? rxbuf[rxpos++] : 0; }
  void begin() {}
  void end() {}
};
extern TwoWire Wire;
