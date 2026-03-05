/// PCAN-Basic LookUpChannel Query Builder for Dart
///
/// This class provides a convenient way to build query strings for the
/// PCAN-Basic LookUpChannel function, similar to the Python implementation.
class PcanLookupQuery {
  static const String lookupDeviceType = 'devicetype';
  static const String lookupDeviceId = 'deviceid';
  static const String lookupControllerNumber = 'controllernumber';
  static const String lookupIpAddress = 'ipaddress';
  static const String lookupDeviceGuid = 'deviceguid';

  static const String pcanUsb = 'PCAN_USB';
  static const String pcanPci = 'PCAN_PCI';
  static const String pcanLan = 'PCAN_LAN';
  static const String pcanIsa = 'PCAN_ISA';
  static const String pcanDng = 'PCAN_DNG';
  static const String pcanPcc = 'PCAN_PCC';

  String? _deviceType;
  String? _deviceId;
  String? _controllerNumber;
  String? _ipAddress;
  String? _deviceGuid;

  PcanLookupQuery();

  PcanLookupQuery deviceType(String deviceType) {
    _deviceType = deviceType;
    return this;
  }

  PcanLookupQuery deviceId(String deviceId) {
    _deviceId = deviceId;
    return this;
  }

  PcanLookupQuery deviceIdInt(int deviceId) {
    _deviceId = deviceId.toString();
    return this;
  }

  PcanLookupQuery controllerNumber(String controllerNumber) {
    _controllerNumber = controllerNumber;
    return this;
  }

  PcanLookupQuery controllerNumberInt(int controllerNumber) {
    _controllerNumber = controllerNumber.toString();
    return this;
  }

  PcanLookupQuery ipAddress(String ipAddress) {
    _ipAddress = ipAddress;
    return this;
  }

  PcanLookupQuery deviceGuid(String deviceGuid) {
    _deviceGuid = deviceGuid;
    return this;
  }

  String build() {
    final parameters = <String>[];

    if (_deviceType != null && _deviceType!.isNotEmpty) {
      parameters.add('$lookupDeviceType=$_deviceType');
    }

    if (_deviceId != null && _deviceId!.isNotEmpty) {
      parameters.add('$lookupDeviceId=$_deviceId');
    }

    if (_controllerNumber != null && _controllerNumber!.isNotEmpty) {
      parameters.add('$lookupControllerNumber=$_controllerNumber');
    }

    if (_ipAddress != null && _ipAddress!.isNotEmpty) {
      parameters.add('$lookupIpAddress=$_ipAddress');
    }

    if (_deviceGuid != null && _deviceGuid!.isNotEmpty) {
      parameters.add('$lookupDeviceGuid=$_deviceGuid');
    }

    return parameters.join(', ');
  }

  List<int> buildAsBytes() => build().codeUnits;

  void clear() {
    _deviceType = null;
    _deviceId = null;
    _controllerNumber = null;
    _ipAddress = null;
    _deviceGuid = null;
  }

  static PcanLookupQuery forUsb({String? deviceId, int? controllerNumber}) {
    final query = PcanLookupQuery().deviceType(pcanUsb);
    if (deviceId != null) query.deviceId(deviceId);
    if (controllerNumber != null) query.controllerNumberInt(controllerNumber);
    return query;
  }

  static PcanLookupQuery forPci({String? deviceId, int? controllerNumber}) {
    final query = PcanLookupQuery().deviceType(pcanPci);
    if (deviceId != null) query.deviceId(deviceId);
    if (controllerNumber != null) query.controllerNumberInt(controllerNumber);
    return query;
  }

  static PcanLookupQuery forLan({String? ipAddress, String? deviceId}) {
    final query = PcanLookupQuery().deviceType(pcanLan);
    if (ipAddress != null) query.ipAddress(ipAddress);
    if (deviceId != null) query.deviceId(deviceId);
    return query;
  }

  static PcanLookupQuery custom() => PcanLookupQuery();

  @override
  String toString() => 'PCANLookupQuery{${build()}}';
}

class PCANLookupUtils {
  static String findFirstUsb() => PcanLookupQuery.forUsb().build();

  static String findUsbWithId(int deviceId) =>
      PcanLookupQuery.forUsb(deviceId: deviceId.toString()).build();

  static String findUsbWithController(int controllerNumber) =>
      PcanLookupQuery.forUsb(controllerNumber: controllerNumber).build();

  static String findPci() => PcanLookupQuery.forPci().build();

  static String findLanWithIp(String ipAddress) =>
      PcanLookupQuery.forLan(ipAddress: ipAddress).build();

  static String findByGuid(String guid) =>
      PcanLookupQuery.forUsb().deviceGuid(guid).build();

  static String findComplexUsb({
    String? deviceId,
    int? controllerNumber,
    String? guid,
  }) {
    final query = PcanLookupQuery.forUsb();
    if (deviceId != null) query.deviceId(deviceId);
    if (controllerNumber != null) query.controllerNumberInt(controllerNumber);
    if (guid != null) query.deviceGuid(guid);
    return query.build();
  }
}
