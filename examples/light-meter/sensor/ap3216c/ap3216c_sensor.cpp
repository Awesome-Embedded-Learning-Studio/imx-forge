#include "ap3216c_sensor.h"

#include <fcntl.h>
#include <unistd.h>

Ap3216cSensor::Ap3216cSensor(std::string dev, double lux_coeff)
    : m_dev(std::move(dev)), m_lux_coeff(lux_coeff) {}

std::expected<void, Sensor::InitError>
Ap3216cSensor::init(bool force_reinit) {
    if (m_fd >= 0) {
        if (!force_reinit) return {};     // 已 init, 不重复打开
        ::close(m_fd);
        m_fd = -1;
    }
    m_fd = ::open(m_dev.c_str(), O_RDWR);
    if (m_fd < 0) return std::unexpected{InitError::DeviceUnavailable};
    return {};
}

std::expected<SensorData, Sensor::QueryError>
Ap3216cSensor::query_once() {
    if (m_fd < 0) return std::unexpected{QueryError::NotInited};

    unsigned short db[3] = {0, 0, 0};   // {ir, als, ps}, 与驱动 copy_to_user 顺序一致
    const ssize_t n = ::read(m_fd, db, sizeof(db));
    if (n != static_cast<ssize_t>(sizeof(db)))
        return std::unexpected{QueryError::DeviceUnavailable};

    return SensorData{
        .luxury = db[1] * m_lux_coeff,             // als → luxury(lux)
        .ps     = static_cast<int>(db[2])          // ps raw 直传, 不换算
    };
}
