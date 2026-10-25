# Route J (J+D): busybox-as-signed-.so loader. Independent of the GPU/display libs.
add_library(bbload SHARED bbload.cpp)
target_link_libraries(bbload PUBLIC libace_napi.z.so libhilog_ndk.z.so)
