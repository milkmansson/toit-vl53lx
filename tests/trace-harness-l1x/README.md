# VL53L1X trace harness

Compiles ST's Ultra Lite Driver (as shipped in SparkFun's library) against a
fake `Wire` that models a VL53L1X register file (the same model as
`tests/mock-vl53l1x.toit`) and prints every register access.  The output,
without the `# sensor-id` line, is `tests/golden-vl53l1x.toit`.

```
git clone https://github.com/sparkfun/SparkFun_VL53L1X_Arduino_Library
S=SparkFun_VL53L1X_Arduino_Library/src
g++ -std=c++14 -fpermissive -w -I. -I$S -I$S/st_src -o trace main.cpp $S/st_src/vl53l1x_class.cpp
./trace
```
