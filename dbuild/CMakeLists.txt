cmake_minimum_required(VERSION 3.16)
project(expidus-sdk-dbuild VERSION "0.1.0" LANGUAGES NONE)

install(PROGRAMS "${PROJECT_SOURCE_DIR}/bin/dbuild" DESTINATION "/opt/expidus-sdk/bin")
install(DIRECTORY "${PROJECT_SOURCE_DIR}/etc" DESTINATION "/opt/expidus-sdk")
install(DIRECTORY "${PROJECT_SOURCE_DIR}/lib/dbuild" DESTINATION "/opt/expidus-sdk/lib")
install(FILES "${PROJECT_SOURCE_DIR}/README.md" DESTINATION "/opt/expidus-sdk" RENAME "dbuild.md")
