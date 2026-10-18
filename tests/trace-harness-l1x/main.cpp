#include "Arduino.h"
#include "Wire.h"
#include "st_src/vl53l1x_class.h"
SerialShim Serial;
TwoWire Wire;
#define STEP(s) fprintf(stdout, "# %s\n", s)
#define VAL(name, v) fprintf(stdout, "# %s %d\n", name, (int)(v))
int main() {
  VL53L1X d(&Wire, -1, -1);
  uint16_t u16 = 0;
  uint8_t u8 = 0;
  STEP("init");
  d.VL53L1X_GetSensorId(&u16);
  VAL("sensor-id", u16);
  d.VL53L1X_SensorInit();
  // The Toit constructor applies its defaults (long mode, 100 ms) after init.
  d.VL53L1X_SetDistanceMode(2);
  d.VL53L1X_SetTimingBudgetInMs(100);
  STEP("timing-100");
  d.VL53L1X_SetTimingBudgetInMs(100);
  STEP("get-timing");
  d.VL53L1X_GetTimingBudgetInMs(&u16); VAL("timing", u16);
  STEP("mode-short");
  d.VL53L1X_SetDistanceMode(1);
  STEP("get-mode");
  d.VL53L1X_GetDistanceMode(&u16); VAL("mode", u16);
  STEP("timing-33");
  d.VL53L1X_SetTimingBudgetInMs(33);
  STEP("mode-long");
  d.VL53L1X_SetDistanceMode(2);
  STEP("timing-200");
  d.VL53L1X_SetTimingBudgetInMs(200);
  d.VL53L1X_GetTimingBudgetInMs(&u16); VAL("timing", u16);
  STEP("inter-measurement-120");
  d.VL53L1X_SetInterMeasurementInMs(120);
  d.VL53L1X_GetInterMeasurementInMs(&u16); VAL("inter-measurement", u16);
  STEP("roi-8x8");
  d.VL53L1X_SetROI(8, 8, 150);
  uint16_t rx, ry;
  d.VL53L1X_GetROI_XY(&rx, &ry); VAL("roi-x", rx); VAL("roi-y", ry);
  STEP("roi-16x16");
  d.VL53L1X_SetROI(16, 16, 100);
  d.VL53L1X_GetROI_XY(&rx, &ry); VAL("roi-x", rx); VAL("roi-y", ry);
  STEP("offset");
  d.VL53L1X_SetOffset(-12);
  STEP("xtalk");
  d.VL53L1X_SetXtalk(500);
  d.VL53L1X_GetXtalk(&u16); VAL("xtalk", u16);
  STEP("thresholds");
  d.VL53L1X_SetDistanceThreshold(100, 300, 2, 0);
  d.VL53L1X_GetDistanceThresholdWindow(&u16); VAL("window", u16);
  d.VL53L1X_GetDistanceThresholdLow(&u16); VAL("low", u16);
  d.VL53L1X_GetDistanceThresholdHigh(&u16); VAL("high", u16);
  STEP("thresholds-no-target");
  d.VL53L1X_SetDistanceThreshold(50, 400, 3, 1);
  STEP("signal-sigma");
  d.VL53L1X_SetSignalThreshold(1024);
  d.VL53L1X_GetSignalThreshold(&u16); VAL("signal", u16);
  d.VL53L1X_SetSigmaThreshold(90);
  d.VL53L1X_GetSigmaThreshold(&u16); VAL("sigma", u16);
  STEP("polarity-low");
  d.VL53L1X_SetInterruptPolarity(0);
  d.VL53L1X_GetInterruptPolarity(&u8); VAL("polarity", u8);
  STEP("polarity-high");
  d.VL53L1X_SetInterruptPolarity(1);
  d.VL53L1X_GetInterruptPolarity(&u8); VAL("polarity", u8);
  STEP("ranging");
  d.VL53L1X_StartRanging();
  d.VL53L1X_CheckForDataReady(&u8); VAL("ready", u8);
  d.VL53L1X_GetDistance(&u16); VAL("distance", u16);
  d.VL53L1X_ClearInterrupt();
  d.VL53L1X_StopRanging();
  STEP("oneshot");
  d.VL53L1X_StartOneshotRanging();
  STEP("temperature");
  d.VL53L1X_StartTemperatureUpdate();
  STEP("set-address");
  d.VL53L1X_SetI2CAddress(0x60);
  return 0;
}
