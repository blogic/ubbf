cmake_minimum_required(VERSION 3.13)
project(ucode-mod-wde C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode_library NAMES ucode)

add_compile_options(-Wall -Werror -pedantic)
add_compile_definitions(_GNU_SOURCE)

add_library(wde_lib MODULE wde.c)
set_target_properties(wde_lib PROPERTIES OUTPUT_NAME wde PREFIX "")
target_include_directories(wde_lib SYSTEM PRIVATE ${ucode_include_dir})
target_link_libraries(wde_lib ${ucode_library} ubbf_util)

install(TARGETS wde_lib
	LIBRARY DESTINATION lib/ucode
)
