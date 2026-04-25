cmake_minimum_required(VERSION 3.16)
project(nacl_napi LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# DevEco's Hvigor passes NATIVERENDER_ROOT_PATH when building inside a HAP;
# fall back to CMAKE_CURRENT_SOURCE_DIR for standalone builds.
if(NOT DEFINED NATIVERENDER_ROOT_PATH)
  set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
endif()

include_directories(
  ${NATIVERENDER_ROOT_PATH}
  ${NATIVERENDER_ROOT_PATH}/tweetnacl
  ${NATIVERENDER_ROOT_PATH}/napi
)

add_library(nacl SHARED
  tweetnacl/tweetnacl.c
  tweetnacl/randombytes.c
  napi/nacl_napi.cpp
)

# TweetNaCl has deliberate sign-compare warnings from the original single-
# file port; suppress to keep the build output clean.
target_compile_options(nacl PRIVATE
  -fvisibility=hidden
  -Wno-sign-compare
)

# When built against the OH NDK, link libace_napi (NAPI runtime). Hvigor
# sets this automatically inside a HAP project; for the standalone smoke
# build driven by smoke-test.sh we link it manually.
find_library(libace_napi ace_napi.z)
if(libace_napi)
  target_link_libraries(nacl PRIVATE ${libace_napi})
endif()
