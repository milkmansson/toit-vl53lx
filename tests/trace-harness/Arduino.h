#pragma once
#include <stdint.h>
#include <stddef.h>
typedef bool boolean;
static inline uint32_t millis() { static uint32_t t = 0; return t++; }
static inline void delay(uint32_t) {}
static inline void delayMicroseconds(uint32_t) {}
