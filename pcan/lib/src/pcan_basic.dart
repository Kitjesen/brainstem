import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'pcan_basic.g.dart';
import 'pcan_library.dart';

import 'utils.dart';

PcanStatus canInitialize(
  PcanChannel channel,
  PcanBaudRate baudRate,
  int hwType,
  int ioPort,
  int interrupt,
) => canInitializeRaw(
  channel.value,
  baudRate.value,
  hwType,
  ioPort,
  interrupt,
).asPcanStatus;

PcanStatus canInitializeFD(PcanChannel channel, String params) {
  final pStr = params.toNativeUtf8().cast<ffi.Char>();
  try {
    return canInitializeFDRaw(channel.value, pStr).asPcanStatus;
  } finally {
    calloc.free(pStr);
  }
}

PcanStatus canUninitialize(PcanChannel channel) =>
    canUninitializeRaw(channel.value).asPcanStatus;

PcanStatus canReset(PcanChannel channel) =>
    canResetRaw(channel.value).asPcanStatus;

PcanStatus canGetStatus(PcanChannel channel) =>
    canGetStatusRaw(channel.value).asPcanStatus;

(PcanMessage, PcanTimestamp, PcanStatus) canRead(PcanChannel channel) {
  final msgBuffer = calloc<tagTPCANMsg>();
  final timestampBuffer = calloc<tagTPCANTimestamp>();
  final status = canReadRaw(
    channel.value,
    msgBuffer,
    timestampBuffer,
  ).asPcanStatus;

  final length = msgBuffer.ref.LEN;
  final message = PcanMessage(
    id: msgBuffer.ref.ID,
    type: .fromValue(msgBuffer.ref.MSGTYPE),
    data: .fromList(.generate(length, (i) => msgBuffer.ref.DATA[i])),
  );

  final timestamp = PcanTimestamp(
    millis: timestampBuffer.ref.millis,
    millisOverflow: timestampBuffer.ref.millis_overflow,
    micros: timestampBuffer.ref.micros,
  );

  calloc.free(msgBuffer);
  calloc.free(timestampBuffer);
  return (message, timestamp, status);
}

(PcanMessageFD, PcanTimestamp, PcanStatus) canReadFD(PcanChannel channel) {
  final msgBuffer = calloc<tagTPCANMsgFD>();
  final timestampBuffer = calloc<tagTPCANTimestamp>();
  final status = canReadFDRaw(
    channel.value,
    msgBuffer,
    timestampBuffer.cast(),
  ).asPcanStatus;

  final length = dlcToLength(msgBuffer.ref.DLC);
  final message = PcanMessageFD(
    id: msgBuffer.ref.ID,
    type: .fromValue(msgBuffer.ref.MSGTYPE),
    data: .fromList(.generate(length, (i) => msgBuffer.ref.DATA[i])),
  );

  final timestamp = PcanTimestamp(
    millis: timestampBuffer.ref.millis,
    millisOverflow: timestampBuffer.ref.millis_overflow,
    micros: timestampBuffer.ref.micros,
  );

  calloc.free(msgBuffer);
  calloc.free(timestampBuffer);
  return (message, timestamp, status);
}

PcanStatus canWrite(PcanChannel channel, PcanMessage message) {
  final msgBuffer = calloc<tagTPCANMsg>();
  msgBuffer.ref.ID = message.id;
  msgBuffer.ref.LEN = message.length;
  msgBuffer.ref.MSGTYPE = message.type.value;

  for (var i = 0; i < message.length; i++) {
    msgBuffer.ref.DATA[i] = message.data[i];
  }

  final status = canWriteRaw(channel.value, msgBuffer).asPcanStatus;
  calloc.free(msgBuffer);
  return status;
}

PcanStatus canWriteFD(PcanChannel channel, PcanMessageFD message) {
  final msgBuffer = calloc<tagTPCANMsgFD>();
  msgBuffer.ref.ID = message.id;
  msgBuffer.ref.DLC = lengthToDlc(message.length);
  msgBuffer.ref.MSGTYPE = message.type.value;

  for (var i = 0; i < message.length; i++) {
    msgBuffer.ref.DATA[i] = message.data[i];
  }

  final status = canWriteFDRaw(channel.value, msgBuffer).asPcanStatus;
  calloc.free(msgBuffer);
  return status;
}

PcanStatus canFilterMessages(
  PcanChannel channel,
  int fromId,
  int toId,
  PcanMode mode,
) => canFilterMessagesRaw(channel.value, fromId, toId, mode.value).asPcanStatus;

PcanStatus canGetValue(
  PcanChannel channel,
  PcanParameter parameter,
  ffi.Pointer<ffi.Void> buffer,
  int bufferLength,
) => canGetValueRaw(
  channel.value,
  parameter.value,
  buffer,
  bufferLength,
).asPcanStatus;

PcanStatus canSetValue(
  PcanChannel channel,
  PcanParameter parameter,
  ffi.Pointer<ffi.Void> buffer,
  int bufferLength,
) => canSetValueRaw(
  channel.value,
  parameter.value,
  buffer,
  bufferLength,
).asPcanStatus;

(String, PcanStatus) canGetErrorText(PcanStatus error, PcanLanguage language) {
  // https://documentation.help/PCAN-Basic/CAN_GetErrorText.html
  final textPtr = calloc<ffi.Char>(256);
  try {
    final status = canGetErrorTextRaw(
      error.value,
      language.value,
      textPtr.cast(),
    ).asPcanStatus;
    final errorText = textPtr.cast<Utf8>().toDartString();
    return (errorText, status);
  } finally {
    calloc.free(textPtr);
  }
}

(PcanChannel, PcanStatus) lookUpChannel(String parameters) {
  final foundChannelPtr = calloc<ffi.Uint16>();
  final parametersPtr = parameters.toNativeUtf8().cast<ffi.Char>();
  final statusCode = canLookUpChannelRaw(parametersPtr, foundChannelPtr);
  final status = statusCode.asPcanStatus;
  final channel = PcanChannel.fromValue(foundChannelPtr.value);
  calloc.free(foundChannelPtr);
  calloc.free(parametersPtr);
  return (channel, status);
}

class PcanMessage {
  int id;
  int get length => data.length;
  PcanMessageType type;
  Uint8List data;

  PcanMessage({required this.id, required this.type, required this.data})
    : assert(data.length <= 8, 'Data length must be <= 8 bytes');

  @override
  String toString() => '$type: 0x${id.toHex()} |$length| ${data.toHex()}';
}

class PcanTimestamp {
  final int millis;
  final int millisOverflow;
  final int micros;

  PcanTimestamp({
    required this.millis,
    required this.millisOverflow,
    required this.micros,
  });

  /// Total Microseconds = micros + (1000ULL * millis) + (0x100000000ULL * 1000ULL * millis_overflow)
  int get totalMicroseconds =>
      micros + (1000 * millis) + (0x100000000 * 1000 * millisOverflow);
  double get totalSeconds => totalMicroseconds / 1_000_000.0;
  double get totalMilliseconds => totalMicroseconds / 1000.0;
  @override
  String toString() => '$totalSeconds s';
}

class PcanMessageFD {
  int id;
  int get length => data.length;
  PcanMessageType type;
  Uint8List data;

  PcanMessageFD({required this.id, required this.type, required this.data})
    : assert(data.length <= 64, 'Data length must be <= 64 bytes');

  @override
  String toString() => '$type: 0x${id.toHex()} |$length| ${data.toHex()}';
}

class PcanChannelInformation {
  PcanChannel channelHandle;
  PcanDeviceType deviceType;
  int controllerNumber; // 0, 1, 2, ...
  PcanFeature deviceFeatures;
  String deviceName;
  int deviceId;
  PcanChannelCondition channelCondition;

  PcanChannelInformation({
    required this.channelHandle,
    required this.deviceType,
    required this.controllerNumber,
    required this.deviceFeatures,
    required this.deviceName,
    required this.deviceId,
    required this.channelCondition,
  });

  @override
  String toString() =>
      'channelHandle: $channelHandle, '
      'deviceType: $deviceType, '
      'controllerNumber: $controllerNumber, '
      'deviceFeatures: ${deviceFeatures.str}, '
      'deviceName: $deviceName, '
      'deviceId: $deviceId, '
      'channelCondition: $channelCondition';
}

enum PcanChannel {
  nonebus(PCAN_NONEBUS),
  isabus1(PCAN_ISABUS1),
  isabus2(PCAN_ISABUS2),
  isabus3(PCAN_ISABUS3),
  isabus4(PCAN_ISABUS4),
  isabus5(PCAN_ISABUS5),
  isabus6(PCAN_ISABUS6),
  isabus7(PCAN_ISABUS7),
  isabus8(PCAN_ISABUS8),
  dngbus1(PCAN_DNGBUS1),
  pcibus1(PCAN_PCIBUS1),
  pcibus2(PCAN_PCIBUS2),
  pcibus3(PCAN_PCIBUS3),
  pcibus4(PCAN_PCIBUS4),
  pcibus5(PCAN_PCIBUS5),
  pcibus6(PCAN_PCIBUS6),
  pcibus7(PCAN_PCIBUS7),
  pcibus8(PCAN_PCIBUS8),
  pcibus9(PCAN_PCIBUS9),
  pcibus10(PCAN_PCIBUS10),
  pcibus11(PCAN_PCIBUS11),
  pcibus12(PCAN_PCIBUS12),
  pcibus13(PCAN_PCIBUS13),
  pcibus14(PCAN_PCIBUS14),
  pcibus15(PCAN_PCIBUS15),
  pcibus16(PCAN_PCIBUS16),
  usbbus1(PCAN_USBBUS1),
  usbbus2(PCAN_USBBUS2),
  usbbus3(PCAN_USBBUS3),
  usbbus4(PCAN_USBBUS4),
  usbbus5(PCAN_USBBUS5),
  usbbus6(PCAN_USBBUS6),
  usbbus7(PCAN_USBBUS7),
  usbbus8(PCAN_USBBUS8),
  usbbus9(PCAN_USBBUS9),
  usbbus10(PCAN_USBBUS10),
  usbbus11(PCAN_USBBUS11),
  usbbus12(PCAN_USBBUS12),
  usbbus13(PCAN_USBBUS13),
  usbbus14(PCAN_USBBUS14),
  usbbus15(PCAN_USBBUS15),
  usbbus16(PCAN_USBBUS16),
  pccbus1(PCAN_PCCBUS1),
  pccbus2(PCAN_PCCBUS2),
  lanbus1(PCAN_LANBUS1),
  lanbus2(PCAN_LANBUS2),
  lanbus3(PCAN_LANBUS3),
  lanbus4(PCAN_LANBUS4),
  lanbus5(PCAN_LANBUS5),
  lanbus6(PCAN_LANBUS6),
  lanbus7(PCAN_LANBUS7),
  lanbus8(PCAN_LANBUS8),
  lanbus9(PCAN_LANBUS9),
  lanbus10(PCAN_LANBUS10),
  lanbus11(PCAN_LANBUS11),
  lanbus12(PCAN_LANBUS12),
  lanbus13(PCAN_LANBUS13),
  lanbus14(PCAN_LANBUS14),
  lanbus15(PCAN_LANBUS15),
  lanbus16(PCAN_LANBUS16);

  const PcanChannel(this.value);

  final int value;

  static PcanChannel fromValue(int value) {
    return values.firstWhere(
      (channel) => channel.value == value,
      orElse: () => throw ArgumentError('Invalid PcanChannel value: $value'),
    );
  }

  static const usbChannels = [
    usbbus1,
    usbbus2,
    usbbus3,
    usbbus4,
    usbbus5,
    usbbus6,
    usbbus7,
    usbbus8,
    usbbus9,
    usbbus10,
    usbbus11,
    usbbus12,
    usbbus13,
    usbbus14,
    usbbus15,
    usbbus16,
  ];

  static const pciChannels = [
    pcibus1,
    pcibus2,
    pcibus3,
    pcibus4,
    pcibus5,
    pcibus6,
    pcibus7,
    pcibus8,
    pcibus9,
    pcibus10,
    pcibus11,
    pcibus12,
    pcibus13,
    pcibus14,
    pcibus15,
    pcibus16,
  ];
}

enum PcanStatus {
  ok(PCAN_ERROR_OK),
  xmtfull(PCAN_ERROR_XMTFULL),
  overrun(PCAN_ERROR_OVERRUN),
  buslight(PCAN_ERROR_BUSLIGHT),
  busheavy(PCAN_ERROR_BUSHEAVY),
  buswarning(PCAN_ERROR_BUSWARNING),
  buspassive(PCAN_ERROR_BUSPASSIVE),
  busoff(PCAN_ERROR_BUSOFF),
  anybuserr(PCAN_ERROR_ANYBUSERR),
  qrcvempty(PCAN_ERROR_QRCVEMPTY),
  qoverrun(PCAN_ERROR_QOVERRUN),
  qxmtfull(PCAN_ERROR_QXMTFULL),
  regtest(PCAN_ERROR_REGTEST),
  nodriver(PCAN_ERROR_NODRIVER),
  hwinuse(PCAN_ERROR_HWINUSE),
  netinuse(PCAN_ERROR_NETINUSE),
  illhw(PCAN_ERROR_ILLHW),
  illnet(PCAN_ERROR_ILLNET),
  illclient(PCAN_ERROR_ILLCLIENT),
  illhandle(PCAN_ERROR_ILLHANDLE),
  resource(PCAN_ERROR_RESOURCE),
  illparamtype(PCAN_ERROR_ILLPARAMTYPE),
  illparamval(PCAN_ERROR_ILLPARAMVAL),
  unknown(PCAN_ERROR_UNKNOWN),
  illdata(PCAN_ERROR_ILLDATA),
  illmode(PCAN_ERROR_ILLMODE),
  caution(PCAN_ERROR_CAUTION),
  initialize(PCAN_ERROR_INITIALIZE),
  illoperation(PCAN_ERROR_ILLOPERATION);

  const PcanStatus(this.value);

  final int value;

  static PcanStatus fromValue(int value) {
    return values.firstWhere(
      (status) => status.value == value,
      orElse: () => throw ArgumentError('Invalid PcanStatus value: $value'),
    );
  }

  bool get isOk => this == ok;
  bool get isError => this != ok;
}

enum PcanDeviceType {
  none(PCAN_NONE),
  peakcan(PCAN_PEAKCAN),
  isa(PCAN_ISA),
  dongle(PCAN_DNG),
  pci(PCAN_PCI),
  usb(PCAN_USB),
  pcCard(PCAN_PCC),
  virtual(PCAN_VIRTUAL),
  lan(PCAN_LAN);

  const PcanDeviceType(this.value);
  final int value;

  static PcanDeviceType fromValue(int value) {
    return values.firstWhere(
      (deviceType) => deviceType.value == value,
      orElse: () => throw ArgumentError('Invalid PcanDeviceType value: $value'),
    );
  }

  static List<PcanDeviceType> get availableDeviceTypes => PcanDeviceType.values;

  static const commonDeviceTypes = <PcanDeviceType>[
    usb,
    pci,
    lan,
    isa,
    dongle,
    pcCard,
  ];

  static const physicalDeviceTypes = <PcanDeviceType>[
    isa,
    dongle,
    pci,
    usb,
    pcCard,
    lan,
  ];

  bool get isPhysical => physicalDeviceTypes.contains(this);
}

enum PcanParameter {
  deviceId(PCAN_DEVICE_ID),
  power5Volts(PCAN_5VOLTS_POWER),
  receiveEvent(PCAN_RECEIVE_EVENT),
  messageFilter(PCAN_MESSAGE_FILTER),
  apiVersion(PCAN_API_VERSION),
  channelVersion(PCAN_CHANNEL_VERSION),
  busOffAutoReset(PCAN_BUSOFF_AUTORESET),
  listenOnly(PCAN_LISTEN_ONLY),
  logLocation(PCAN_LOG_LOCATION),
  logStatus(PCAN_LOG_STATUS),
  logConfigure(PCAN_LOG_CONFIGURE),
  logText(PCAN_LOG_TEXT),
  channelCondition(PCAN_CHANNEL_CONDITION),
  hardwareName(PCAN_HARDWARE_NAME),
  receiveStatus(PCAN_RECEIVE_STATUS),
  controllerNumber(PCAN_CONTROLLER_NUMBER),
  traceLocation(PCAN_TRACE_LOCATION),
  traceStatus(PCAN_TRACE_STATUS),
  traceSize(PCAN_TRACE_SIZE),
  traceConfigure(PCAN_TRACE_CONFIGURE),
  channelIdentifying(PCAN_CHANNEL_IDENTIFYING),
  channelFeatures(PCAN_CHANNEL_FEATURES),
  bitrateAdapting(PCAN_BITRATE_ADAPTING),
  bitrateInfo(PCAN_BITRATE_INFO),
  bitrateInfoFd(PCAN_BITRATE_INFO_FD),
  busSpeedNominal(PCAN_BUSSPEED_NOMINAL),
  busSpeedData(PCAN_BUSSPEED_DATA),
  ipAddress(PCAN_IP_ADDRESS),
  lanServiceStatus(PCAN_LAN_SERVICE_STATUS),
  allowStatusFrames(PCAN_ALLOW_STATUS_FRAMES),
  allowRtrFrames(PCAN_ALLOW_RTR_FRAMES),
  allowErrorFrames(PCAN_ALLOW_ERROR_FRAMES),
  interframeDelay(PCAN_INTERFRAME_DELAY),
  acceptanceFilter11Bit(PCAN_ACCEPTANCE_FILTER_11BIT),
  acceptanceFilter29Bit(PCAN_ACCEPTANCE_FILTER_29BIT),
  ioDigitalConfiguration(PCAN_IO_DIGITAL_CONFIGURATION),
  ioDigitalValue(PCAN_IO_DIGITAL_VALUE),
  ioDigitalSet(PCAN_IO_DIGITAL_SET),
  ioDigitalClear(PCAN_IO_DIGITAL_CLEAR),
  ioAnalogValue(PCAN_IO_ANALOG_VALUE),
  firmwareVersion(PCAN_FIRMWARE_VERSION),
  attachedChannelsCount(PCAN_ATTACHED_CHANNELS_COUNT),
  attachedChannels(PCAN_ATTACHED_CHANNELS),
  allowEchoFrames(PCAN_ALLOW_ECHO_FRAMES),
  devicePartNumber(PCAN_DEVICE_PART_NUMBER),
  hardResetStatus(PCAN_HARD_RESET_STATUS),
  lanChannelDirection(PCAN_LAN_CHANNEL_DIRECTION),
  deviceGuid(PCAN_DEVICE_GUID);

  const PcanParameter(this.value);

  final int value;

  static PcanParameter fromValue(int value) {
    return values.firstWhere(
      (param) => param.value == value,
      orElse: () {
        throw ArgumentError('Invalid PCANParameter value: $value');
      },
    );
  }
}

enum PcanChannelCondition {
  unavailable(PCAN_CHANNEL_UNAVAILABLE),
  available(PCAN_CHANNEL_AVAILABLE),
  occupied(PCAN_CHANNEL_OCCUPIED),
  pcanView(PCAN_CHANNEL_PCANVIEW); // 被PCAN-View应用程序使用，但可用于连接

  const PcanChannelCondition(this.value);
  final int value;

  static PcanChannelCondition fromValue(int value) {
    return values.firstWhere(
      (condition) => condition.value == value,
      orElse: () =>
          throw ArgumentError('Invalid PCANChannelCondition value: $value'),
    );
  }
}

extension type const PcanFeature(int value) {
  static const fdCapable = PcanFeature(FEATURE_FD_CAPABLE);
  static const delayCapable = PcanFeature(FEATURE_DELAY_CAPABLE);
  static const ioCapable = PcanFeature(FEATURE_IO_CAPABLE);

  static const values = [fdCapable, delayCapable, ioCapable];

  Set<PcanFeature> get flags =>
      PcanFeature.values.where((f) => (value & f.value) != 0).toSet();

  bool has(PcanFeature f) => (value & f.value) != 0;
  PcanFeature add(PcanFeature f) => PcanFeature(value | f.value);
  PcanFeature remove(PcanFeature f) => PcanFeature(value & ~f.value);
  PcanFeature operator &(PcanFeature other) => PcanFeature(value & other.value);
  PcanFeature operator |(PcanFeature other) => PcanFeature(value | other.value);

  String get str => flags
      .map(
        (f) => switch (f) {
          fdCapable => 'FD',
          delayCapable => 'Delay',
          ioCapable => 'IO',
          _ => 'Unknown',
        },
      )
      .join(' | ');
}

enum PcanMode {
  standard(PCAN_MODE_STANDARD),
  extended(PCAN_MODE_EXTENDED);

  const PcanMode(this.value);

  final int value;

  static PcanMode fromValue(int value) {
    return PcanMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => throw ArgumentError('Invalid PCANMode value: $value'),
    );
  }
}

enum PcanMessageType {
  standard(PCAN_MESSAGE_STANDARD),
  rtr(PCAN_MESSAGE_RTR),
  extended(PCAN_MESSAGE_EXTENDED),
  fd(PCAN_MESSAGE_FD),
  brs(PCAN_MESSAGE_BRS),
  esi(PCAN_MESSAGE_ESI),
  echo(PCAN_MESSAGE_ECHO),
  errframe(PCAN_MESSAGE_ERRFRAME),
  status(PCAN_MESSAGE_STATUS);

  const PcanMessageType(this.value);

  final int value;

  static PcanMessageType fromValue(int value) {
    return values.firstWhere(
      (type) => type.value == value,
      orElse: () =>
          throw ArgumentError('Invalid PCANMessageType value: $value'),
    );
  }

  @override
  String toString() => switch (this) {
    standard => 'Standard',
    rtr => 'Remote Transmission Request',
    extended => 'Extended',
    fd => 'CAN FD',
    brs => 'Bit Rate Switch',
    esi => 'Error State Indicator',
    echo => 'Echo',
    errframe => 'Error Frame',
    status => 'Status',
  };
}

enum PcanBaudRate {
  baud1M(PCAN_BAUD_1M),
  baud800K(PCAN_BAUD_800K),
  baud500K(PCAN_BAUD_500K),
  baud250K(PCAN_BAUD_250K),
  baud125K(PCAN_BAUD_125K),
  baud100K(PCAN_BAUD_100K),
  baud95K(PCAN_BAUD_95K),
  baud83K(PCAN_BAUD_83K),
  baud50K(PCAN_BAUD_50K),
  baud47K(PCAN_BAUD_47K),
  baud33K(PCAN_BAUD_33K),
  baud20K(PCAN_BAUD_20K),
  baud10K(PCAN_BAUD_10K),
  baud5K(PCAN_BAUD_5K);

  const PcanBaudRate(this.value);

  final int value;

  static PcanBaudRate fromValue(int value) {
    return values.firstWhere(
      (baudRate) => baudRate.value == value,
      orElse: () => throw ArgumentError('Invalid PCANBaudRate value: $value'),
    );
  }
}

enum PcanLanguage {
  neutral(0x00),
  german(0x07),
  english(0x09),
  spanish(0x0A),
  italian(0x10),
  french(0x0C);

  const PcanLanguage(this.value);

  final int value;

  static PcanLanguage fromValue(int value) {
    return values.firstWhere(
      (lang) => lang.value == value,
      orElse: () => throw ArgumentError('Invalid PCANLanguage value: $value'),
    );
  }
}
