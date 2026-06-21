cmake_minimum_required(VERSION 3.16)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
project(icm20608_app VERSION 1.0.0 LANGUAGES C)

add_executable(icm20608_app icm20608_app.c)

# Install target
install(TARGETS icm20608_app
    RUNTIME DESTINATION usr/local/bin
)
