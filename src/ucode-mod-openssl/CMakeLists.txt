cmake_minimum_required(VERSION 3.13)
project(ucode-mod-openssl C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode_library NAMES ucode)

add_library(openssl_lib MODULE openssl.c)
set_target_properties(openssl_lib PROPERTIES OUTPUT_NAME openssl PREFIX "")
target_include_directories(openssl_lib PRIVATE ${ucode_include_dir})
target_link_libraries(openssl_lib ${ucode_library} ssl crypto)

install(TARGETS openssl_lib
	LIBRARY DESTINATION lib/ucode
)
