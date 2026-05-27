cmake_minimum_required(VERSION 3.16)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
project(key_demo VERSION 1.0.0 LANGUAGES C)

add_executable(key_demo key_demo.c)

# Install target
install(TARGETS key_demo
    RUNTIME DESTINATION usr/local/bin
)
