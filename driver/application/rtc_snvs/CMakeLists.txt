cmake_minimum_required(VERSION 3.16)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
project(rtc_alarm_demo VERSION 1.0.0 LANGUAGES C)

add_executable(rtc_alarm_demo rtc_alarm_demo.c)

# Install target
install(TARGETS rtc_alarm_demo
    RUNTIME DESTINATION usr/local/bin
)
