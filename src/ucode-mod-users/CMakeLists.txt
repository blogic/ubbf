cmake_minimum_required(VERSION 3.13)
project(ucode-mod-users C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode_library NAMES ucode)

add_compile_options(-Wall -Werror -pedantic)
add_compile_definitions(_GNU_SOURCE)

add_library(users_lib MODULE users.c rate_limit.c)
set_target_properties(users_lib PROPERTIES OUTPUT_NAME users PREFIX "")
target_include_directories(users_lib SYSTEM PRIVATE ${ucode_include_dir})
target_link_libraries(users_lib ${ucode_library} crypt)

install(TARGETS users_lib
	LIBRARY DESTINATION lib/ucode
)
