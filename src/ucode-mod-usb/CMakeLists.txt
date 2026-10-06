cmake_minimum_required(VERSION 3.13)
project(ucode-mod-usb C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode_library NAMES ucode)

add_compile_options(-Wall -Werror -pedantic)
add_compile_definitions(_GNU_SOURCE)

add_library(usb_lib MODULE usb.c)
set_target_properties(usb_lib PROPERTIES OUTPUT_NAME usb PREFIX "")
target_include_directories(usb_lib SYSTEM PRIVATE ${ucode_include_dir})
target_link_libraries(usb_lib ${ucode_library} ubbf_util)

install(TARGETS usb_lib
	LIBRARY DESTINATION lib/ucode
)
