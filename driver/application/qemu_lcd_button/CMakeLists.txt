cmake_minimum_required(VERSION 3.16)
project(lcd_button LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)

# Qt6 lives in the buildroot staging sysroot; configure with
#   -DCMAKE_PREFIX_PATH=<buildroot>/staging/usr
#   -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,<buildroot>/staging/usr/lib"
find_package(Qt6 QUIET COMPONENTS Widgets)
if(NOT Qt6_FOUND)
    message(STATUS "lcd_button: Qt6 not found — skipping (needs buildroot staging sysroot)")
    return()
endif()

add_executable(lcd_button lcd_button.cpp)
target_link_libraries(lcd_button PRIVATE Qt6::Widgets)

install(TARGETS lcd_button RUNTIME DESTINATION usr/local/bin)
