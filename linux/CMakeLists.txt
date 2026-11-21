# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "cyberhex")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "com.gaboexperimetos.cyberhex")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# CyberHex native core (Zig + C23).
find_program(ZIG_EXECUTABLE zig)
if(NOT ZIG_EXECUTABLE)
  message(FATAL_ERROR "zig no está en PATH. Instala Zig 0.17+ o expórtalo antes de compilar.")
endif()

# Opcional: -DCYBERHEX_DECODER=miniaudio para no depender de FFmpeg en el PC.
set(CYBERHEX_DECODER "auto" CACHE STRING "Decodificador del núcleo: auto, ffmpeg o miniaudio")

set(CYBERHEX_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../core")
set(CYBERHEX_CORE_PREFIX "${CMAKE_BINARY_DIR}/cyberhex_core")
set(CYBERHEX_CORE_LIB "${CYBERHEX_CORE_PREFIX}/lib/libcyberhex_core.so")

# Se vigilan también las cabeceras y el C del núcleo: si cambia
# include/cyberhex_core.h y no se recompilase, la app cargaría un .so con el ABI
# antiguo (y las funciones nuevas saldrían como nulas).
file(GLOB_RECURSE CYBERHEX_CORE_SOURCES CONFIGURE_DEPENDS
  "${CYBERHEX_CORE_DIR}/src/*.zig"
  "${CYBERHEX_CORE_DIR}/src/*.c"
  "${CYBERHEX_CORE_DIR}/src/*.h"
  "${CYBERHEX_CORE_DIR}/include/*.h"
  "${CYBERHEX_CORE_DIR}/vendor/*.h"
  "${CYBERHEX_CORE_DIR}/build.zig"
  "${CYBERHEX_CORE_DIR}/build.zig.zon")

add_custom_command(
  OUTPUT "${CYBERHEX_CORE_LIB}"
  # -Drelease=true => ReleaseFast (preferred_optimize_mode del build.zig).
  COMMAND "${ZIG_EXECUTABLE}" build
    -Drelease=true
    -Ddecoder=${CYBERHEX_DECODER}
    --prefix "${CYBERHEX_CORE_PREFIX}"
  # zig conserva la fecha original al instalar: sin este touch el .so siempre
  # parecería más viejo que las fuentes y el núcleo se recompilaría en cada build.
  COMMAND ${CMAKE_COMMAND} -E touch "${CYBERHEX_CORE_LIB}"
  WORKING_DIRECTORY "${CYBERHEX_CORE_DIR}"
  DEPENDS ${CYBERHEX_CORE_SOURCES}
  COMMENT "Compilando el núcleo CyberHex con Zig"
  VERBATIM)

add_custom_target(cyberhex_core ALL DEPENDS "${CYBERHEX_CORE_LIB}")
add_dependencies(${BINARY_NAME} cyberhex_core)

install(FILES "${CYBERHEX_CORE_LIB}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Copy the native assets provided by the hook/build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
