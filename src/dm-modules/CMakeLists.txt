cmake_minimum_required(VERSION 3.13)
project(dm-modules C)

add_compile_options(-Wall -Werror)

# Builds /usr/lib/ubbf/dm/<name>.so, a native data model module for dm-host.
function(dm_module name)
	add_library(dm_${name} MODULE ${ARGN})
	set_target_properties(dm_${name} PROPERTIES OUTPUT_NAME ${name} PREFIX "")
	target_include_directories(dm_${name} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../dm-host)
	target_link_libraries(dm_${name} ubbf_util)
	install(TARGETS dm_${name} LIBRARY DESTINATION lib/ubbf/dm)
endfunction()
