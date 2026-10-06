cmake_minimum_required(VERSION 3.13)
project(ubbf-dnsprobe C)

find_library(ubox NAMES ubox REQUIRED)
find_library(ubus NAMES ubus REQUIRED)
find_library(blobmsg_json NAMES blobmsg_json REQUIRED)
find_library(uci NAMES uci REQUIRED)
find_library(resolv NAMES resolv)

add_executable(dnsprobe dnsprobe.c)

target_link_libraries(dnsprobe
	${ubus}
	${ubox}
	${blobmsg_json}
	${uci}
)

if(resolv)
	target_link_libraries(dnsprobe ${resolv})
endif()

install(TARGETS dnsprobe RUNTIME DESTINATION bin)
