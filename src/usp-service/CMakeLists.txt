cmake_minimum_required(VERSION 3.13)
project(ucode-mod-usp-service C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode NAMES ucode REQUIRED)
find_library(ubox NAMES ubox REQUIRED)
find_library(protobuf_c NAMES protobuf-c REQUIRED)

add_library(usp_service MODULE
	usp-service.c
	uds-transport.c
	usp-protocol.c
	usp-record.pb-c.c
	usp-msg.pb-c.c
)

target_include_directories(usp_service PRIVATE ${ucode_include_dir})

target_link_libraries(usp_service
	${ucode}
	${ubox}
	${protobuf_c}
)

set_target_properties(usp_service PROPERTIES
	PREFIX ""
	OUTPUT_NAME "usp_service"
)

install(TARGETS usp_service LIBRARY DESTINATION lib/ucode)
