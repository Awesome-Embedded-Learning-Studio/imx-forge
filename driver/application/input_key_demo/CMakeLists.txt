cmake_minimum_required(VERSION 3.16)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
project(input_key_demo VERSION 1.0.0 LANGUAGES C)

add_executable(input_key_demo input_key_demo.c)

# Install target
install(TARGETS input_key_demo
    RUNTIME DESTINATION usr/local/bin
)
