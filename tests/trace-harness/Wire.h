#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <vector>
// Fake I2C bus + simple VL53L0X register model.  Records register-level ops.
struct TwoWire {
  uint8_t regs[256];
  uint8_t ptr = 0;
  std::vector<uint8_t> txbuf;
  std::vector<uint8_t> rxbuf;
  size_t rxpos = 0;
  FILE* trace = stdout;
  TwoWire() {
    memset(regs, 0, sizeof regs);
    // Preloaded result block (0x14..0x1F): status valid(11<<3), spads 8.8=0x0A00,
    // signal 9.7=0x0100, ambient 9.7=0x0040, range=300 mm.
    regs[0x14] = 0x58; regs[0x16] = 0x0A; regs[0x17] = 0x00;
    regs[0x1A] = 0x01; regs[0x1B] = 0x00; regs[0x1C] = 0x00; regs[0x1D] = 0x40;
    regs[0x1E] = 0x01; regs[0x1F] = 0x2C;
    regs[0xF8] = 0x0C; regs[0xF9] = 0x80;  // osc calibrate value.
    for (int i = 0xB0; i <= 0xB5; i++) regs[i] = 0xFF;
  }
  uint8_t model(uint8_t r) {
    switch (r) {
      case 0xC0: return 0xEE;
      case 0xC1: return 0xAA;
      case 0xC2: return 0x10;
      case 0x83: return 0x01;
      case 0x92: return 0x8C;   // aperture, count 12.
      case 0x13: return 0x07;   // interrupt status: always ready.
      case 0x91: return 0x3C;   // stop variable.
      case 0x00: return 0x00;   // start bit always clear.
      default: return regs[r];
    }
  }
  void beginTransmission(uint8_t) { txbuf.clear(); }
  void write(uint8_t b) { txbuf.push_back(b); }
  uint8_t endTransmission(uint8_t = 1) {
    if (txbuf.size() == 1) { ptr = txbuf[0]; }
    else if (txbuf.size() > 1) {
      fprintf(trace, "W %02X", txbuf[0]);
      for (size_t i = 1; i < txbuf.size(); i++) {
        fprintf(trace, " %02X", txbuf[i]);
        regs[(uint8_t)(txbuf[0] + i - 1)] = txbuf[i];
      }
      fprintf(trace, "\n");
    }
    return 0;
  }
  uint8_t requestFrom(uint8_t, uint8_t n) {
    fprintf(trace, "R %02X %d\n", ptr, n);
    rxbuf.clear(); rxpos = 0;
    for (int i = 0; i < n; i++) rxbuf.push_back(model((uint8_t)(ptr + i)));
    return n;
  }
  int read() { return rxpos < rxbuf.size() ? rxbuf[rxpos++] : 0; }
};
extern TwoWire Wire;
