cmake_minimum_required(VERSION 3.13)
project(testbed-aftr C)

add_executable(testbed-aftr aftr.c)

install(TARGETS testbed-aftr RUNTIME DESTINATION libexec/ubbf)
