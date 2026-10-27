cmake_minimum_required(VERSION 3.13)
project(ucode-mod-ubbf C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode_library NAMES ucode)

add_compile_options(-Wall -Werror -pedantic)
add_compile_definitions(_GNU_SOURCE)

option(UBBF_SCHEMA_TABLE "Build the TR-181 schema tables schema-*.so" ON)

if(UBBF_SCHEMA_TABLE)
	# The schema tables are compiled from the schema files with the build
	# host's ucode, so they cannot drift from the files developers edit.
	find_program(UCODE_HOST ucode)
	if(NOT UCODE_HOST)
		message(FATAL_ERROR "host ucode not found; it generates the schema tables")
	endif()

	set(UBBF_UCODE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../files/usr/share/ucode
	    CACHE PATH "Directory holding the ubbf ucode modules")
	set(UBBF_MODULES_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../modules
	    CACHE PATH "Directory holding the ubbf out-of-tree modules")
	file(GLOB UBBF_SCHEMA_SOURCES CONFIGURE_DEPENDS ${UBBF_UCODE_DIR}/ubbf/schemas/*.uc)
	file(GLOB UBBF_MODULE_SCHEMAS CONFIGURE_DEPENDS ${UBBF_MODULES_DIR}/*/schema.uc)

	# Builds schema-<name>.so from the core schemas, or, with a source, from
	# the schema.uc of the module <name>. A table holds only data, so it
	# links without libc.
	function(schema_table name)
		set(out ${CMAKE_CURRENT_BINARY_DIR}/schema-${name}.c)

		if(ARGN)
			set(gen_args ${name} ${ARGN})
			set(gen_depends ${ARGN})
		else()
			set(gen_args)
			set(gen_depends ${UBBF_SCHEMA_SOURCES})
		endif()

		add_custom_command(
			OUTPUT ${out}
			COMMAND ${UCODE_HOST} -L "${UBBF_UCODE_DIR}/*.uc"
				${CMAKE_CURRENT_SOURCE_DIR}/schema-gen.uc
				${CMAKE_CURRENT_SOURCE_DIR}/ubbf.h
				${UBBF_UCODE_DIR}/ubbf/schemas
				${out} ${gen_args}
			DEPENDS schema-gen.uc schema-table.h ubbf.h
				${UBBF_UCODE_DIR}/ubbf/utils/dm-version.uc ${gen_depends}
			VERBATIM
		)

		add_library(schema_${name} MODULE ${out})
		set_target_properties(schema_${name} PROPERTIES OUTPUT_NAME schema-${name} PREFIX "")
		target_include_directories(schema_${name} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
		target_link_options(schema_${name} PRIVATE -nostdlib)
		install(TARGETS schema_${name} LIBRARY DESTINATION lib/ubbf)
	endfunction()

	schema_table(core)

	foreach(source ${UBBF_MODULE_SCHEMAS})
		get_filename_component(dir ${source} DIRECTORY)
		get_filename_component(name ${dir} NAME)
		schema_table(${name} ${source})
	endforeach()
endif()

# The helpers the native libraries of the modules share with ubbf.so.
add_library(ubbf_util STATIC util.c)
set_target_properties(ubbf_util PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(ubbf_util INTERFACE ${CMAKE_CURRENT_SOURCE_DIR})

set(UBBF_LIB_SOURCES
	ubbf.c
	path.c
	coerce.c
	inet.c
	mac.c
	string.c
	firewall.c
	firewall_reconcile.c
	wifi.c
	wifi_dataelements.c
	wifi_phy.c
	wifi_psk.c
	time.c
	atomic.c
	sys.c
	proc.c
	dhcp.c
	diag.c
	tree.c
	instance.c
	sysfs.c
	dm.c
	dm_model.c
	dm_get.c
	dm_set.c
	dm_names.c
	schema.c
	schedule.c
	routing.c
	nptv6.c
	sfp.c
	ssh_keys.c
	curl.c
	dns.c
	hosts.c
	ifstats.c
	ipv6.c
	log.c
	protocol.c
	map.c
	config.c
	order.c
	gate.c
	cache.c
	netlink.c
	rtnl.c
	ethtool.c
	uci_track.c
	acl.c
	status.c
	vm.c
)

find_library(ubox_library NAMES ubox)
find_path(ubox_include_dir NAMES libubox/ulog.h)
find_library(nl_tiny_library NAMES nl-tiny)
find_path(nl_tiny_include_dir NAMES netlink/msg.h PATH_SUFFIXES libnl-tiny)
if(NOT nl_tiny_library OR NOT nl_tiny_include_dir)
	message(FATAL_ERROR "libnl-tiny not found; rtnl.c needs it")
endif()
find_library(md_library NAMES md)
find_path(md_include_dir NAMES sha2.h)
if(NOT md_library OR NOT md_include_dir)
	message(FATAL_ERROR "libmd not found; config.c needs it")
endif()

add_library(ubbf_lib MODULE ${UBBF_LIB_SOURCES})
set_target_properties(ubbf_lib PROPERTIES OUTPUT_NAME ubbf PREFIX "")
target_include_directories(ubbf_lib SYSTEM PRIVATE ${ucode_include_dir} ${ubox_include_dir} ${nl_tiny_include_dir} ${md_include_dir})
target_link_libraries(ubbf_lib ${ucode_library} ${ubox_library} ${nl_tiny_library} ${md_library} m ${CMAKE_DL_LIBS} ubbf_util)

install(TARGETS ubbf_lib
	LIBRARY DESTINATION lib/ucode
)

# Host only: the OpenWrt package build leaves this off.
option(UBBF_UNIT_TESTS "Build the cmocka unit tests of ubbf.so" OFF)

if(UBBF_UNIT_TESTS)
	enable_testing()
	add_subdirectory(tests)
endif()
