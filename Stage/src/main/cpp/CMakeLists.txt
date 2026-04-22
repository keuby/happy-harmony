# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(happy_harmony)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include
                    ${NATIVERENDER_ROOT_PATH}/tweetnacl)

add_library(stage SHARED
    napi_init.cpp
    tweetnacl/tweetnacl.c
    tweetnacl/randombytes.c)

# TweetNaCl's FOR() macro generates sign-compare warnings in the upstream
# source that are benign; silence them so the build output stays focused.
target_compile_options(stage PRIVATE -Wno-sign-compare)

target_link_libraries(stage PUBLIC libace_napi.z.so)
