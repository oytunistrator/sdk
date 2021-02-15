cmake_minimum_required(VERSION 3.16)
project(expidus-sdk VERSION "0.1.0" HOMEPAGE_URL "https://wiki.expidusos.com/index.php/SDK")

include(GNUInstallDirs)

add_subdirectory(dbuild)

install(PROGRAMS "${PROJECT_SOURCE_DIR}/bin/expidus-devify" DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(DIRECTORY "${PROJECT_SOURCE_DIR}/lib" DESTINATION "/opt/expidus-sdk")
