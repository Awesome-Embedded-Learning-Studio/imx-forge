cmake_minimum_required(VERSION 3.16)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
project(ap3216c_app VERSION 1.0.0 LANGUAGES C)

add_executable(ap3216c_app ap3216c_app.c)

# Install target
install(TARGETS ap3216c_app
    RUNTIME DESTINATION usr/local/bin
)
