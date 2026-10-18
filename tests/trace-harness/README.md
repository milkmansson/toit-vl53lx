# VL53L0X trace harness

Compiles Pololu's `VL53L0X.cpp` against a fake `Wire` that models a VL53L0X
register file (the same model as `tests/mock-vl53l0x.toit`) and prints every
register access.  The output is `tests/golden-vl53l0x.toit`.

```
git clone https://github.com/pololu/vl53l0x-arduino
g++ -std=c++14 -I. -Ivl53l0x-arduino -o trace vl53l0x-arduino/VL53L0X.cpp main.cpp
./trace
```
