cmake_minimum_required(VERSION 3.16)
project(orix_sdk_cpp VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ── 依赖：gRPC + Protobuf ─────────────────────────────────────
# 推荐用 vcpkg 安装：
#   vcpkg install grpc protobuf
# 或用 conan / 系统包管理器。
find_package(gRPC CONFIG REQUIRED)
find_package(Protobuf REQUIRED)

# ── Proto 代码生成 ────────────────────────────────────────────
# PROTO_IMPORT_ROOT 是 han_dog_message/ 的父目录（brainstem 根目录下的包目录）
# cms.proto 中写的是 import "han_dog_message/common.proto"
# 所以 -I 指向 han_dog_message/ 这个包目录的上一级
set(PROTO_IMPORT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../han_dog_message")
set(PROTO_OUT "${CMAKE_CURRENT_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${PROTO_OUT}/han_dog_message")

get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)

function(compile_proto PROTO_NAME OUT_SRCS)
    set(PROTO_FILE "${PROTO_IMPORT_ROOT}/han_dog_message/${PROTO_NAME}.proto")

    set(PB_CC  "${PROTO_OUT}/han_dog_message/${PROTO_NAME}.pb.cc")
    set(PB_H   "${PROTO_OUT}/han_dog_message/${PROTO_NAME}.pb.h")
    set(GR_CC  "${PROTO_OUT}/han_dog_message/${PROTO_NAME}.grpc.pb.cc")
    set(GR_H   "${PROTO_OUT}/han_dog_message/${PROTO_NAME}.grpc.pb.h")

    add_custom_command(
        OUTPUT  "${PB_CC}" "${PB_H}" "${GR_CC}" "${GR_H}"
        COMMAND "${Protobuf_PROTOC_EXECUTABLE}"
        ARGS
            "--cpp_out=${PROTO_OUT}"
            "--grpc_out=${PROTO_OUT}"
            "--plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN}"
            "-I${PROTO_IMPORT_ROOT}"
            "-I${Protobuf_INCLUDE_DIRS}"
            "han_dog_message/${PROTO_NAME}.proto"
        WORKING_DIRECTORY "${PROTO_IMPORT_ROOT}"
        DEPENDS "${PROTO_FILE}"
        COMMENT "Compiling proto: ${PROTO_NAME}.proto"
        VERBATIM
    )

    set(${OUT_SRCS} "${PB_CC}" "${GR_CC}" PARENT_SCOPE)
endfunction()

compile_proto(common COMMON_PROTO_SRCS)
compile_proto(cms    CMS_PROTO_SRCS)

# ── 静态库 ────────────────────────────────────────────────────
add_library(orix_sdk STATIC
    src/orix_client.cpp
    ${COMMON_PROTO_SRCS}
    ${CMS_PROTO_SRCS}
)

target_include_directories(orix_sdk
    PUBLIC  "${CMAKE_CURRENT_SOURCE_DIR}/include"
    PRIVATE "${PROTO_OUT}"
)

target_link_libraries(orix_sdk
    PUBLIC gRPC::grpc++
    PUBLIC protobuf::libprotobuf
)

# ── 示例可执行文件（不依赖 OpenCV）──────────────────────────
foreach(EXAMPLE IN ITEMS
    01_hello_walk
    02_read_imu
    03_motor_diagnostics
    04_keyboard_control
    05_gestures
    06_motor_control)
    add_executable(${EXAMPLE} "examples/${EXAMPLE}.cpp")
    target_link_libraries(${EXAMPLE} PRIVATE orix_sdk)
endforeach()

# ── 摄像头模块（可选，需要 OpenCV）───────────────────────────
find_package(OpenCV QUIET)
if(OpenCV_FOUND)
    message(STATUS "OpenCV ${OpenCV_VERSION} — 摄像头支持已启用")

    add_library(orix_camera STATIC
        src/orix_camera.cpp
    )
    target_include_directories(orix_camera
        PUBLIC  "${CMAKE_CURRENT_SOURCE_DIR}/include"
        PRIVATE "${OpenCV_INCLUDE_DIRS}"
    )
    target_link_libraries(orix_camera
        PUBLIC ${OpenCV_LIBS}
    )

    foreach(EXAMPLE IN ITEMS
        07_camera_basic
        08_camera_record
        09_camera_stream)
        add_executable(${EXAMPLE} "examples/${EXAMPLE}.cpp")
        target_link_libraries(${EXAMPLE} PRIVATE orix_camera)
    endforeach()

    install(TARGETS orix_camera ARCHIVE DESTINATION lib)
else()
    message(STATUS "OpenCV 未找到 — 跳过摄像头示例 (07/08/09)")
    message(STATUS "  安装 OpenCV: vcpkg install opencv4")
endif()

# ── 安装规则 ──────────────────────────────────────────────────
install(TARGETS orix_sdk
    ARCHIVE DESTINATION lib
)
install(DIRECTORY include/orix
    DESTINATION include
)
