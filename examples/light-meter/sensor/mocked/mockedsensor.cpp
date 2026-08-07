#include "mockedsensor.h"
#include <algorithm>
#include <random>

namespace {
class Random {
  public:
    Random() : m_rng(std::random_device{}()) {}
    int int_range(int min, int max) {
        std::uniform_int_distribution<int> dist(min, max);
        return dist(m_rng);
    }
  private:
    std::mt19937 m_rng;  // 引擎重用，避免重复初始化
};
}

struct LuxSource {
  public:
    LuxSource() : random_source(std::make_unique<Random>()){}
    void setPhase(double phase_) {
        phase = phase_;
    }
    // 契约: lux ∈ [50, 800]。正弦波 + 抖动, clamp 到契约区间。
    double fetch_lux() const {
        return std::clamp(400 + 350*std::sin(phase) +
                          random_source->int_range(-30, 30), 50.0, 800.0);
    }
  private:
    double phase {0.0};
    std::unique_ptr<Random> random_source;
};

struct PsSource {
  public:
    PsSource() : random_source(std::make_unique<Random>()){}
    void set_held(bool is_held_) {
        is_held = is_held_;
    }
    // 契约: ps 0~1023, >500 视为"有接近"(手靠近)。
    // 手靠近(held) → 高值; 手离开 → 低值, 以便 UI 据此 10s 后息屏。
    int fetch_ps() const {
        if (is_held)
            return 800 + random_source->int_range(0, 40);   // 800~840, >500 近
        return random_source->int_range(0, 40);             // 0~40, <500 远
    }
  private:
    bool is_held {false};
    std::unique_ptr<Random> random_source;
};

void LuxSourceDeleter::operator()(LuxSource* p) const {
    delete p;
}

void PsSourceDeleter::operator()(PsSource* p) const {
    delete p;
};


MockedSensor::MockedSensor() : Sensor() {}

std::expected<void, Sensor::InitError> MockedSensor::init(bool force_reinit)
{
    if(!lux_source || force_reinit) {
        lux_source = std::unique_ptr<LuxSource, LuxSourceDeleter>(new LuxSource);
    }

    if(!ps_source || force_reinit) {
        ps_source = std::unique_ptr<PsSource, PsSourceDeleter>(new PsSource);
    }
    return {};
}

std::expected<SensorData, Sensor::QueryError> MockedSensor::query_once()
{
    if(!lux_source || !ps_source){
        return std::unexpected {QueryError::NotInited};
    }

    return {
        SensorData {
            .luxury = lux_source->fetch_lux(),
            .ps = ps_source->fetch_ps()
        }
    };
}

void MockedSensor::set_held(bool is_held)
{
    if(!ps_source) {
        return;
    }

    ps_source->set_held(is_held);
}

void MockedSensor::set_phase(double phase)
{
    if(!lux_source) {
        return;
    }

    lux_source->setPhase(phase);
}



