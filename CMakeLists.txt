cmake_minimum_required(VERSION 3.13)
project(ubbf C)

set(CMAKE_C_STANDARD 99)
add_compile_definitions(_GNU_SOURCE _POSIX_C_SOURCE=200809L)

add_subdirectory(src/usp-service)
add_subdirectory(src/ucode-mod-users)
add_subdirectory(src/ucode-mod-openssl)
add_subdirectory(src/mcast)
add_subdirectory(src/ucode-mod-ubbf)
add_subdirectory(src/ucode-mod-pcp)
add_subdirectory(src/dnsprobe)
add_subdirectory(src/testbed-aftr)
