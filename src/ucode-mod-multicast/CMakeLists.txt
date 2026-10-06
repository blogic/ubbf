cmake_minimum_required(VERSION 3.13)
project(ucode-mod-multicast C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode_library NAMES ucode)

add_compile_options(-Wall -Werror -pedantic)
add_compile_definitions(_GNU_SOURCE)

add_library(multicast_lib MODULE multicast.c)
set_target_properties(multicast_lib PROPERTIES OUTPUT_NAME multicast PREFIX "")
target_include_directories(multicast_lib SYSTEM PRIVATE ${ucode_include_dir})
target_link_libraries(multicast_lib ${ucode_library})

install(TARGETS multicast_lib
	LIBRARY DESTINATION lib/ucode
)
