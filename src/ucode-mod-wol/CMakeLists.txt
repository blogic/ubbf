cmake_minimum_required(VERSION 3.13)
project(ucode-mod-wol C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode_library NAMES ucode)

add_compile_options(-Wall -Werror -pedantic)
add_compile_definitions(_GNU_SOURCE)

add_library(wol_lib MODULE wol.c)
set_target_properties(wol_lib PROPERTIES OUTPUT_NAME wol PREFIX "")
target_include_directories(wol_lib SYSTEM PRIVATE ${ucode_include_dir})
target_link_libraries(wol_lib ${ucode_library} ubbf_util)

install(TARGETS wol_lib
	LIBRARY DESTINATION lib/ucode
)
