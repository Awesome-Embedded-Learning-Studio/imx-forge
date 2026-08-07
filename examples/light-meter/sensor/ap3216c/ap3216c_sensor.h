#ifndef AP3216C_SENSOR_H
#define AP3216C_SENSOR_H

#include <string>

#include "sensor.h"

// Ap3216cSensor —— Sensor 的真机后端, 桥接 /dev/ap3216c 字符设备驱动。
//
// 契约对齐(驱动 ap3216c_read): 每次同步读 IR/ALS/PS 三路寄存器, 填
// unsigned short[3] = {ir, als, ps}, 立即返回(无等待队列)。
// query_once() 读一次 → als × lux_coeff 得 luxury, ps 直传。
//
// 平台: 仅 Linux/板子(POSIX open/read)。Windows 不参与编译
//      (由 CMakeLists 的 USE_REAL_SENSOR 选项 + 平台判断隔离)。
//
// 注: set_phase / set_held 是 MockedSensor 的"测试数据注入"口, 真机无意义。
//     本类不 override 它们 —— 若后续把它们作为 Sensor 基类的默认空实现虚方法,
//     则对真机自动 no-op;否则切换后端时 UI 层应避免对真机调用这两个口。
class Ap3216cSensor : public Sensor {
  public:
    // dev:       设备节点, 默认 /dev/ap3216c
    // lux_coeff: als_raw → luxury(lux) 换算系数, 占位 1.0, 上板标定后回填
    explicit Ap3216cSensor(std::string dev = "/dev/ap3216c", double lux_coeff = 1.0);

    std::expected<void, InitError> init(bool force_reinit) override;
    std::expected<SensorData, QueryError> query_once() override;

  private:
    std::string m_dev;
    int         m_fd = -1;        // < 0 表示未 init
    double      m_lux_coeff;
};

#endif // AP3216C_SENSOR_H
