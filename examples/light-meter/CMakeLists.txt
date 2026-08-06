cmake_minimum_required(VERSION 3.19)
project(light-meter LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Widgets)

qt_standard_project_setup()

qt_add_executable(light-meter
    WIN32 MACOSX_BUNDLE
    main.cpp
    mainwindow.cpp
    mainwindow.h
    ui/breathing_overlay.cpp
    ui/breathing_overlay.h
    ui/chart_view.cpp
    ui/chart_view.h
    sensor/sensor.h sensor/sensor.cpp
    sensor/mocked/mockedsensor.h sensor/mocked/mockedsensor.cpp
)

target_include_directories(light-meter PUBLIC sensor/)

# 真机后端(可选): /dev/ap3216c 桥接, 仅 Linux/板子(POSIX)。默认 OFF = Mock 后端。
option(USE_REAL_SENSOR "真机后端 /dev/ap3216c(仅 Linux/板子)" OFF)
if(USE_REAL_SENSOR)
    if(WIN32 OR NOT UNIX)
        message(FATAL_ERROR "USE_REAL_SENSOR 仅 Linux/板子可用(POSIX open/read/close)")
    endif()
    target_sources(light-meter PRIVATE
        sensor/ap3216c/ap3216c_sensor.h sensor/ap3216c/ap3216c_sensor.cpp)
    target_compile_definitions(light-meter PRIVATE USE_REAL_SENSOR=1)
endif()

# 源文件为 UTF-8(无 BOM), 含中文; 告知 MSVC 以 UTF-8 解释源与执行字符集。
if(MSVC)
    target_compile_options(light-meter PRIVATE /utf-8)
endif()

target_link_libraries(light-meter
    PRIVATE
        Qt::Core
        Qt::Widgets
)

install(TARGETS light-meter
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

qt_generate_deploy_app_script(
    TARGET light-meter
    OUTPUT_SCRIPT deploy_script
    NO_UNSUPPORTED_PLATFORM_ERROR
)
install(SCRIPT ${deploy_script})
