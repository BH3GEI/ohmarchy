cmake_minimum_required(VERSION 3.5.0)
project(ohdisp C CXX)
set(CMAKE_CXX_STANDARD 17)

# The window provider the system virglrenderer dlopens by name (hwf_kits.c).
add_library(hwf_kits.z SHARED hwf_kits.c)
target_link_libraries(hwf_kits.z PUBLIC libnative_window.so)

# vtest from upstream virglrenderer 1.1.1, patched (../../../../vtest-inapp.patch);
# gpu-prep.sh puts it in gpu/ and the device's libraries in entry/libs/arm64-v8a.
set(GPU ${CMAKE_CURRENT_SOURCE_DIR}/gpu)
set(V ${GPU}/virglrenderer)
set(PREBUILT ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH})
set(VTEST_SOURCES
    ${V}/vtest/util.c ${V}/vtest/vtest_shm.c ${V}/vtest/vtest_server.c ${V}/vtest/vtest_renderer.c
    ${V}/src/mesa/util/ralloc.c ${V}/src/mesa/util/hash_table.c ${V}/src/gallium/auxiliary/util/u_hash_table.c)
# exit() in vtest ends its thread (gpu.cpp), not the app.
set_source_files_properties(${VTEST_SOURCES} PROPERTIES
    COMPILE_OPTIONS "-include;${GPU}/config.h;-Dexit=vtest_exit;-w")

add_library(ohdisp SHARED ohdisp.cpp gpu.cpp audio.cpp cursor.cpp ${VTEST_SOURCES})
target_include_directories(ohdisp PRIVATE ${GPU} ${V}/src ${V}/src/gallium/include ${V}/src/gallium/include/pipe
    ${V}/src/mesa/pipe ${V}/src/gallium/auxiliary ${V}/src/mesa ${V}/src/mesa/util ${V}/src/mesa/compat ${V}/vtest)
target_compile_options(ohdisp PRIVATE -O2)
target_link_libraries(ohdisp PUBLIC libace_napi.z.so libace_ndk.z.so libnative_window.so libhilog_ndk.z.so
    libohinputmethod.so libohaudio.so libohinput.so libpixelmap.so hwf_kits.z ${PREBUILT}/libvirglrenderer.so m)

# Route J (J+D) loader module, independent of the GPU libs
add_subdirectory(jl)
