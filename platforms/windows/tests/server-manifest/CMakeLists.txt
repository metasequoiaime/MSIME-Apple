cmake_minimum_required(VERSION 3.25)
project(ServerManifestProbe LANGUAGES CXX)
add_executable(msime-client-server main.cpp)
include(../../ServerManifest.cmake)
