#include "VL53L0X.h"
TwoWire Wire;
#define STEP(s) fprintf(stdout, "# %s\n", s)
int main() {
  VL53L0X s;
  STEP("init");
  bool ok = s.init(true);
  fprintf(stdout, "# init-result %d\n", ok);
  STEP("get-budget");
  fprintf(stdout, "# budget %u\n", (unsigned) s.getMeasurementTimingBudget());
  STEP("single");
  fprintf(stdout, "# range %u\n", s.readRangeSingleMillimeters());
  STEP("continuous-b2b");
  s.startContinuous(0);
  fprintf(stdout, "# range %u\n", s.readRangeContinuousMillimeters());
  s.stopContinuous();
  STEP("continuous-timed-100");
  s.startContinuous(100);
  fprintf(stdout, "# range %u\n", s.readRangeContinuousMillimeters());
  s.stopContinuous();
  STEP("signal-rate-0.1");
  s.setSignalRateLimit(0.1);
  fprintf(stdout, "# limit-micro %d\n", (int)(s.getSignalRateLimit() * 1000000 + 0.5));
  STEP("vcsel-pre-18");
  fprintf(stdout, "# r %d\n", s.setVcselPulsePeriod(VL53L0X::VcselPeriodPreRange, 18));
  STEP("vcsel-final-14");
  fprintf(stdout, "# r %d\n", s.setVcselPulsePeriod(VL53L0X::VcselPeriodFinalRange, 14));
  STEP("budget-200ms");
  fprintf(stdout, "# r %d\n", s.setMeasurementTimingBudget(200000));
  fprintf(stdout, "# budget %u\n", (unsigned) s.getMeasurementTimingBudget());
  STEP("budget-20ms");
  fprintf(stdout, "# r %d\n", s.setMeasurementTimingBudget(20000));
  fprintf(stdout, "# budget %u\n", (unsigned) s.getMeasurementTimingBudget());
  STEP("get-vcsel");
  int pre = s.getVcselPulsePeriod(VL53L0X::VcselPeriodPreRange);
  int fin = s.getVcselPulsePeriod(VL53L0X::VcselPeriodFinalRange);
  fprintf(stdout, "# pre %d final %d\n", pre, fin);
  STEP("set-address");
  s.setAddress(0x30);
  return 0;
}
