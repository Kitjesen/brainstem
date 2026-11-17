#!/bin/bash
set -euo pipefail
trap 'echo $? > build.exit' EXIT
export ONNXRUNTIME_DLL_PATH=/usr/local/lib/libonnxruntime.so
export LD_LIBRARY_PATH=/usr/local/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu
export THUNDER_ALLOW_MOTOR_ENABLE=false
export CMAKE_BUILD_PARALLEL_LEVEL=1
export CI=true
export DART_SUPPRESS_ANALYTICS=true
dart pub get --offline --enforce-lockfile
cd thunder
dart format lib/src/app/joint_transport.dart test/joint_transport_test.dart
dart analyze lib/src/app/joint_transport.dart test/joint_transport_test.dart
dart test test/joint_transport_test.dart test/operator_mode_slots_test.dart test/grpc_operator_slots_test.dart test/three_slot_grpc_web_test.dart --concurrency=2 --reporter expanded
cd ../thunder_brain
dart test test --concurrency=2 --reporter expanded
cd ..
dart build cli --target=thunder/bin/thunder.dart --output=build/w5-stairs
cp /home/sunrise/tri_slot_20261101_1937/build/tri-slot/bundle/lib/libcserialport.so build/w5-stairs/bundle/lib/
sha256sum build/w5-stairs/bundle/bin/thunder > binary.sha256
