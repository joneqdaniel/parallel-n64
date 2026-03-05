cmake_minimum_required(VERSION 3.16)

project(parallel_n64_tests LANGUAGES C CXX)

option(PARALLEL_N64_ENABLE_TESTS "Enable local CTest-based test targets." ON)

if(PARALLEL_N64_ENABLE_TESTS)
  include(CTest)

  if(BUILD_TESTING)
    add_subdirectory(tests)
  endif()
endif()
