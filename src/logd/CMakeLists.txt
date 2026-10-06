cmake_minimum_required(VERSION 3.13)
project(ubbf-logd C)

find_library(ubox NAMES ubox REQUIRED)
find_library(ubus NAMES ubus REQUIRED)
find_library(blobmsg_json NAMES blobmsg_json REQUIRED)

add_executable(ubbf-logd
	main.c
	config.c
	input.c
	listen.c
	output.c
	tls.c
	ubus.c
	msg.c
	frame.c
	template.c
	filter.c
)

target_include_directories(ubbf-logd PRIVATE include)
target_compile_options(ubbf-logd PRIVATE -Wall -Werror)

target_link_libraries(ubbf-logd
	${ubus}
	${ubox}
	${blobmsg_json}
	${CMAKE_DL_LIBS}
)

install(TARGETS ubbf-logd RUNTIME DESTINATION sbin)

add_executable(ubbf-logd-test
	tests/test.c
	msg.c
	frame.c
	template.c
	filter.c
)

target_include_directories(ubbf-logd-test PRIVATE include)
target_compile_options(ubbf-logd-test PRIVATE -Wall -Werror)

enable_testing()
add_test(NAME ubbf-logd-test COMMAND ubbf-logd-test)
