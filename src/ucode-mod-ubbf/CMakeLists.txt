cmake_minimum_required(VERSION 3.13)
project(ucode-mod-ubbf C)

find_path(ucode_include_dir NAMES ucode/module.h)
find_library(ucode_library NAMES ucode)

add_compile_options(-Wall -Werror -pedantic)
add_compile_definitions(_GNU_SOURCE)

add_library(ubbf_lib MODULE
	ubbf.c
	path.c
	coerce.c
	inet.c
	mac.c
	string.c
	firewall.c
	wifi.c
	time.c
	atomic.c
	rate_limit.c
	wol.c
	sys.c
	wde.c
	led.c
	proc.c
	dhcp.c
	diag.c
	usb.c
	tree.c
	instance.c
	sysfs.c
	dm.c
)
set_target_properties(ubbf_lib PROPERTIES OUTPUT_NAME ubbf PREFIX "")
target_include_directories(ubbf_lib PRIVATE ${ucode_include_dir})
target_link_libraries(ubbf_lib ${ucode_library} m)

install(TARGETS ubbf_lib
	LIBRARY DESTINATION lib/ucode
)
