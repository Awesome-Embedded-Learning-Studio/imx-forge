#ifndef MOCKEDSENSOR_H
#define MOCKEDSENSOR_H

#include <memory>

#include "sensor.h"

struct LuxSource;
struct PsSource;
struct LuxSourceDeleter {
    void operator()(LuxSource* p) const;
};
struct PsSourceDeleter {
    void operator()(PsSource *p) const;
};

class MockedSensor : public Sensor {
  public:
    MockedSensor();
    std::expected<void, InitError> init(bool force_reinit) override;
    std::expected<SensorData, QueryError> query_once() override;

    /* Interfaces using mocked datas */
    void set_held(bool is_held) override;
    void set_phase(double phase) override;
  private:
    std::unique_ptr<LuxSource, LuxSourceDeleter> lux_source;
    std::unique_ptr<PsSource, PsSourceDeleter> ps_source;
};

#endif // MOCKEDSENSOR_H
