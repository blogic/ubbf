cmake_minimum_required(VERSION 3.13)
project(dm-host C)

add_compile_options(-Wall -Werror)

find_path(ubus_include_dir NAMES libubus.h)
find_library(ubus NAMES ubus)
find_library(ubox NAMES ubox)

add_executable(dm-host dm-host.c)
target_include_directories(dm-host PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} SYSTEM ${ubus_include_dir})
target_link_libraries(dm-host ${ubus} ${ubox} ${CMAKE_DL_LIBS})
# Modules call the ubbf_dm_* services, which the executable exports.
set_target_properties(dm-host PROPERTIES ENABLE_EXPORTS ON)

install(TARGETS dm-host RUNTIME DESTINATION libexec/ubbf)
install(FILES ubbf/dm-module.h DESTINATION include/ubbf)

option(UBBF_DM_TEST_MODULE "Build the dm-host test module" OFF)

if(UBBF_DM_TEST_MODULE)
	add_library(dm_test MODULE test/dm-test.c)
	set_target_properties(dm_test PROPERTIES OUTPUT_NAME dmtest PREFIX "")
	target_include_directories(dm_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
endif()
