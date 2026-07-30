#ifndef SENSOR_H
#define SENSOR_H

#include <expected>

struct SensorData {
    double luxury; // light luxury
    int ps; // how hand close to the sensor
};

/**
 * @brief   Sensor is the source data class, using in query
 *          within platfrom inrelatives
 */
class Sensor {
  public:
    enum class InitError {
        Ok, GeneralFailed, DeviceUnavailable
    };

    enum class QueryError {
        Ok, NotInited, DeviceUnavailable
    };

    Sensor() = default;
    virtual ~Sensor() = default;   // 多态基类: 经基类指针 delete 需 virtual 析构
    /**
     * @brief   manual_init calls for the init of getting sensor's data
     *          for linux platform, it calls for the open dev files
     * @param   force_reinit
     */
    virtual std::expected<void, InitError> init(bool force_reinit = false) = 0;

    /**
     * @brief sync read once data
     * @return sensor data we read, in windows, it is the mocked data
     */
    virtual std::expected<SensorData, QueryError> query_once() = 0;
};

#endif // SENSOR_H
