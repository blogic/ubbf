cmake_minimum_required(VERSION 3.13)
project(ucode-mod-led C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode_library NAMES ucode)

add_compile_options(-Wall -Werror -pedantic)
add_compile_definitions(_GNU_SOURCE)

add_library(led_lib MODULE led.c)
set_target_properties(led_lib PROPERTIES OUTPUT_NAME led PREFIX "")
target_include_directories(led_lib SYSTEM PRIVATE ${ucode_include_dir})
target_link_libraries(led_lib ${ucode_library} ubbf_util)

install(TARGETS led_lib
	LIBRARY DESTINATION lib/ucode
)
