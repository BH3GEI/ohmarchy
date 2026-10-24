cmake_minimum_required(VERSION 3.5.0)
project(vote120)
add_library(vote120 SHARED vote120.cpp)
target_link_libraries(vote120 PUBLIC libace_napi.z.so libace_ndk.z.so libnative_window.so libhilog_ndk.z.so)
