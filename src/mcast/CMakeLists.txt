cmake_minimum_required(VERSION 3.13)
project(ubbf-mcast-tools C)

find_package(Threads REQUIRED)

add_executable(mcast_server mcast_server.c)
add_executable(mcast_client mcast_client.c)
add_executable(igmp_querier igmp_querier.c)

target_link_libraries(mcast_client Threads::Threads)

install(TARGETS mcast_server mcast_client igmp_querier
	RUNTIME DESTINATION bin
)
