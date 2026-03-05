import 'package:ffi/ffi.dart';
import 'dart:ffi';

import 'pcan_basic.dart';
import 'pcan_basic.g.dart';
import 'utils.dart';

class Pcan {
  final PcanChannel channel;

  Pcan(this.channel);
  PcanStatus open([PcanBaudRate baudRate = .baud1M]) =>
      canInitialize(channel, baudRate, 0, 0, 0);
  PcanStatus close() => canUninitialize(channel);
  PcanStatus reset() => canReset(channel);
  PcanStatus get status => canGetStatus(channel);

  PcanStatus write(PcanMessage message) => canWrite(channel, message);
  (PcanMessage, PcanTimestamp, PcanStatus) read() => canRead(channel);

  static (String, PcanStatus) get apiVersion {
    final valuePtr = calloc<Char>(MAX_LENGTH_VERSION_STRING);
    try {
      final status = canGetValue(
        .nonebus,
        .apiVersion,
        valuePtr.cast(),
        MAX_LENGTH_VERSION_STRING,
      );
      final version = valuePtr.cast<Utf8>().toDartString();
      return (version, status);
    } finally {
      calloc.free(valuePtr);
    }
  }

  static (int, PcanStatus) get counts {
    final countsPtr = calloc<Uint32>();
    try {
      final status = canGetValue(
        .nonebus,
        .attachedChannelsCount,
        countsPtr.cast(),
        sizeOf<Uint32>(),
      );

      final count = countsPtr.value;
      return (count, status);
    } finally {
      calloc.free(countsPtr);
    }
  }

  static (List<PcanChannelInformation>, PcanStatus) getAttachedChannels(
    int count,
  ) {
    if (count <= 0) return ([], PcanStatus.ok);

    final buffer = calloc<tagTPCANChannelInformation>(count);

    try {
      // 传入 0 是会报错的
      final status = canGetValue(
        .nonebus,
        .attachedChannels,
        buffer.cast(),
        count * sizeOf<tagTPCANChannelInformation>(),
      );

      return (
        List.generate(count, (index) {
          final info = buffer[index];
          return PcanChannelInformation(
            channelHandle: PcanChannel.fromValue(info.channel_handle),
            deviceType: PcanDeviceType.fromValue(info.device_type),
            controllerNumber: info.controller_number,
            deviceFeatures: PcanFeature(info.device_features),
            deviceName: info.device_name.toDartString(),
            deviceId: info.device_id,
            channelCondition: PcanChannelCondition.fromValue(
              info.channel_condition,
            ),
          );
        }),
        status,
      );
    } finally {
      calloc.free(buffer);
    }
  }
}

extension PCanInfo on Pcan {
  (PcanChannelCondition, PcanStatus) get condition {
    final conditionPtr = calloc<Uint32>();
    try {
      final status = canGetValue(
        channel,
        .channelCondition,
        conditionPtr.cast(),
        sizeOf<Uint32>(),
      );
      return (PcanChannelCondition.fromValue(conditionPtr.value), status);
    } finally {
      calloc.free(conditionPtr);
    }
  }

  // set blink(bool on) {
  //   final valuePtr = calloc<Uint32>();
  //   valuePtr.value = on ? PCAN_PARAMETER_ON : PCAN_PARAMETER_OFF;
  //   try {
  //     CAN_SetValue(
  //       channel.value,
  //       PcanParameter.channelIdentifying.value,
  //       valuePtr.cast(),
  //       sizeOf<Uint32>(),
  //     ).guard();
  //   } finally {
  //     calloc.free(valuePtr);
  //   }
  // }

  // bool get blink {
  //   final valuePtr = calloc<Uint32>();
  //   try {
  //     CAN_GetValue(
  //       channel.value,
  //       PcanParameter.channelIdentifying.value,
  //       valuePtr.cast(),
  //       sizeOf<Uint32>(),
  //     ).guard();
  //     return valuePtr.value == PCAN_PARAMETER_ON;
  //   } finally {
  //     calloc.free(valuePtr);
  //   }
  // }

  // set deviceId(int id) {
  //   final deviceIdPtr = calloc<Uint8>();
  //   deviceIdPtr.value = id;
  //   try {
  //     CAN_SetValue(
  //       channel.value,
  //       PcanParameter.deviceId.value,
  //       deviceIdPtr.cast(),
  //       sizeOf<Uint8>(),
  //     ).guard();
  //   } finally {
  //     calloc.free(deviceIdPtr);
  //   }
  // }

  // int get deviceId {
  //   final deviceIdPtr = calloc<Uint32>();
  //   try {
  //     CAN_GetValue(
  //       channel.value,
  //       PcanParameter.deviceId.value,
  //       deviceIdPtr.cast(),
  //       sizeOf<Uint32>(),
  //     ).guard();
  //     return deviceIdPtr.value;
  //   } finally {
  //     calloc.free(deviceIdPtr);
  //   }
  // }

  // String get guid {
  //   final valuePtr = calloc<Char>(256);
  //   try {
  //     CAN_GetValue(
  //       channel.value,
  //       PcanParameter.deviceGuid.value,
  //       valuePtr.cast(),
  //       256,
  //     ).guard();
  //     final guid = valuePtr.cast<Utf8>().toDartString();
  //     return guid;
  //   } finally {
  //     calloc.free(valuePtr);
  //   }
  // }

  // String get firmwareVersion {
  //   final valuePtr = calloc<Char>(MAX_LENGTH_VERSION_STRING);
  //   try {
  //     CAN_GetValue(
  //       channel.value,
  //       PcanParameter.firmwareVersion.value,
  //       valuePtr.cast(),
  //       MAX_LENGTH_VERSION_STRING,
  //     ).guard();
  //     final version = valuePtr.cast<Utf8>().toDartString();
  //     return version;
  //   } finally {
  //     calloc.free(valuePtr);
  //   }
  // }
}
