cmake_minimum_required(VERSION 3.13)
project(ucode-mod-pcp C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode_library NAMES ucode)
find_path(pcpnatpmp_include_dir NAMES pcpnatpmp/pcpnatpmp.h)

add_compile_options(-Wall -Werror -pedantic)

add_library(pcp_lib MODULE pcp.c)
set_target_properties(pcp_lib PROPERTIES OUTPUT_NAME pcp PREFIX "")
target_include_directories(pcp_lib PRIVATE ${ucode_include_dir} ${pcpnatpmp_include_dir})
target_link_libraries(pcp_lib ${ucode_library} pcpnatpmp)

install(TARGETS pcp_lib
	LIBRARY DESTINATION lib/ucode
)
