#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string>
typedef uint8_t byte;
typedef bool boolean;
#define HIGH 1
#define LOW 0
#define INPUT 0
#define OUTPUT 1
static inline uint32_t millis() { static uint32_t t = 0; return t += 1; }
static inline void delay(uint32_t) {}
static inline void delayMicroseconds(uint32_t) {}
static inline void pinMode(int, int) {}
static inline void digitalWrite(int, int) {}
static inline int digitalRead(int) { return 0; }
class String {
 public:
  std::string s;
  String() {}
  String(const char* c) : s(c) {}
  String(int v) : s(std::to_string(v)) {}
  String(unsigned v) : s(std::to_string(v)) {}
  String(long v) : s(std::to_string(v)) {}
  String(unsigned long v) : s(std::to_string(v)) {}
  String(float v) : s(std::to_string(v)) {}
  String(double v) : s(std::to_string(v)) {}
  String(unsigned char v, int = 10) : s(std::to_string((int)v)) {}
  String operator+(const String& o) const { String r; r.s = s + o.s; return r; }
};
static inline String operator+(const char* a, const String& b) { String r(a); return r + b; }
struct SerialShim {
  void begin(long) {}
  void print(const String&) {}
  void println(const String&) {}
  void println(const char*) {}
  void print(const char*) {}
  void println(int) {}
  void print(int) {}
  void println() {}
};
extern SerialShim Serial;
