/// SocketCAN backend for Linux — replaces PCAN Basic when chardev driver
/// (`/dev/pcan*`) is unavailable but SocketCAN interfaces (`can0`..`can3`) exist.
///
/// Maps PCAN_USBBUS1..4 → can0..can3 and uses raw AF_CAN sockets via FFI.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'pcan_basic.dart';

// ─── Linux CAN constants ─────────────────────────────────────────────────────

// ignore_for_file: constant_identifier_names, non_constant_identifier_names, unused_field

const int _AF_CAN = 29;
const int _SOCK_RAW = 3;
const int _CAN_RAW = 1;
const int _SIOCGIFINDEX = 0x8933;
const int _CAN_EFF_FLAG = 0x80000000;
const int _CAN_EFF_MASK = 0x1FFFFFFF;
const int _CAN_SFF_MASK = 0x000007FF;

// ─── Native structs ──────────────────────────────────────────────────────────

// struct ifreq { char ifr_name[16]; int ifr_ifindex; ... } (simplified, 40 bytes)
final class _Ifreq extends ffi.Struct {
  @ffi.Array(16)
  external ffi.Array<ffi.Char> ifr_name;
  @ffi.Int32()
  external int ifr_ifindex;
}

// struct sockaddr_can { sa_family_t can_family; int can_ifindex; ... }
final class _SockaddrCan extends ffi.Struct {
  @ffi.Uint16()
  external int can_family;

  @ffi.Int32()
  external int can_ifindex;

  // tp/addr union padding (8 bytes)
  @ffi.Uint32()
  external int rx_id;
  @ffi.Uint32()
  external int tx_id;
}

// struct can_frame { canid_t can_id; __u8 len; __u8 __pad; __u8 __res0; __u8 len8_dlc; __u8 data[8]; }
final class _CanFrame extends ffi.Struct {
  @ffi.Uint32()
  external int can_id;
  @ffi.Uint8()
  external int len;
  @ffi.Uint8()
  external int __pad;
  @ffi.Uint8()
  external int __res0;
  @ffi.Uint8()
  external int len8_dlc;
  @ffi.Array(8)
  external ffi.Array<ffi.Uint8> data;
}

// ─── libc bindings ───────────────────────────────────────────────────────────

final ffi.DynamicLibrary _libc = ffi.DynamicLibrary.open('libc.so.6');

final int Function(int, int, int) _socket =
    _libc.lookupFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32),
        int Function(int, int, int)>('socket');

final int Function(int, ffi.Pointer<_SockaddrCan>, int) _bind = _libc
    .lookupFunction<
        ffi.Int32 Function(ffi.Int32, ffi.Pointer<_SockaddrCan>, ffi.Uint32),
        int Function(int, ffi.Pointer<_SockaddrCan>, int)>('bind');

final int Function(int, int, ffi.Pointer<_Ifreq>) _ioctl =
    _libc.lookupFunction<
        ffi.Int32 Function(ffi.Int32, ffi.Uint64, ffi.Pointer<_Ifreq>),
        int Function(int, int, ffi.Pointer<_Ifreq>)>('ioctl');

final int Function(int, ffi.Pointer<_CanFrame>, int) _write =
    _libc.lookupFunction<
        ffi.IntPtr Function(ffi.Int32, ffi.Pointer<_CanFrame>, ffi.Size),
        int Function(int, ffi.Pointer<_CanFrame>, int)>('write');

final int Function(int, ffi.Pointer<_CanFrame>, int, int) _recv =
    _libc.lookupFunction<
        ffi.IntPtr Function(ffi.Int32, ffi.Pointer<_CanFrame>, ffi.Size, ffi.Int32),
        int Function(int, ffi.Pointer<_CanFrame>, int, int)>('recv');

const int _MSG_DONTWAIT = 0x40;

final int Function(int) _close =
    _libc.lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
        'close');


// ─── Channel mapping ─────────────────────────────────────────────────────────

/// Map PcanChannel enum to SocketCAN interface name.
/// usbbus1 → can0, usbbus2 → can1, ..., usbbus8 → can7
String? _channelToInterface(PcanChannel channel) {
  final index = switch (channel) {
    PcanChannel.usbbus1 => 0,
    PcanChannel.usbbus2 => 1,
    PcanChannel.usbbus3 => 2,
    PcanChannel.usbbus4 => 3,
    PcanChannel.usbbus5 => 4,
    PcanChannel.usbbus6 => 5,
    PcanChannel.usbbus7 => 6,
    PcanChannel.usbbus8 => 7,
    _ => null,
  };
  return index != null ? 'can$index' : null;
}

// ─── SocketCAN Pcan replacement ──────────────────────────────────────────────

/// Drop-in replacement for [Pcan] that uses Linux SocketCAN instead of
/// PCAN Basic chardev API. Same public interface.
class SocketCanPcan {
  final PcanChannel channel;
  int _fd = -1;

  // Reusable native buffers (allocated once, freed on close)
  ffi.Pointer<_CanFrame>? _frameBuf;

  SocketCanPcan(this.channel);

  bool get isOpen => _fd >= 0;

  PcanStatus open([PcanBaudRate baudRate = PcanBaudRate.baud1M]) {
    final ifName = _channelToInterface(channel);
    if (ifName == null) return PcanStatus.illhw;

    // 1. Create raw CAN socket
    final fd = _socket(_AF_CAN, _SOCK_RAW, _CAN_RAW);
    if (fd < 0) return PcanStatus.nodriver;

    // 2. Get interface index via ioctl(SIOCGIFINDEX)
    final ifreq = calloc<_Ifreq>();
    try {
      final nameBytes = ifName.codeUnits;
      for (int i = 0; i < nameBytes.length && i < 15; i++) {
        ifreq.ref.ifr_name[i] = nameBytes[i];
      }
      ifreq.ref.ifr_name[nameBytes.length] = 0; // null terminator

      if (_ioctl(fd, _SIOCGIFINDEX, ifreq) < 0) {
        _close(fd);
        return PcanStatus.illhw; // interface not found
      }
      final ifindex = ifreq.ref.ifr_ifindex;

      // 3. Bind socket to CAN interface
      final addr = calloc<_SockaddrCan>();
      try {
        addr.ref.can_family = _AF_CAN;
        addr.ref.can_ifindex = ifindex;
        if (_bind(fd, addr, ffi.sizeOf<_SockaddrCan>()) < 0) {
          _close(fd);
          return PcanStatus.busoff;
        }
      } finally {
        calloc.free(addr);
      }
    } finally {
      calloc.free(ifreq);
    }

    // 4. Keep write BLOCKING (CAN tx queue is small; non-blocking bursts
    //    return EAGAIN).  Read uses poll/select externally so blocking
    //    write + non-blocking read is the practical combination.
    //    We only set O_NONBLOCK for read via a separate fcntl after open
    //    — but SocketCAN doesn't support mixed mode on one fd, so we
    //    leave the fd blocking and handle read-empty via MSG_DONTWAIT
    //    in the read path instead.

    _fd = fd;
    _frameBuf = calloc<_CanFrame>();
    return PcanStatus.ok;
  }

  PcanStatus close() {
    if (_fd >= 0) {
      _close(_fd);
      _fd = -1;
    }
    if (_frameBuf != null) {
      calloc.free(_frameBuf!);
      _frameBuf = null;
    }
    return PcanStatus.ok;
  }

  PcanStatus write(PcanMessage message) {
    if (_fd < 0) return PcanStatus.illhw;
    final frame = _frameBuf!;

    // Encode CAN ID with flags
    int canId = message.id;
    if (message.type == PcanMessageType.extended) {
      canId |= _CAN_EFF_FLAG;
    }
    frame.ref.can_id = canId;
    frame.ref.len = message.length;
    for (int i = 0; i < message.length && i < 8; i++) {
      frame.ref.data[i] = message.data[i];
    }

    final size = ffi.sizeOf<_CanFrame>();
    // Blocking write — kernel will wait until tx queue has space.
    final written = _write(_fd, frame, size);
    return written == size ? PcanStatus.ok : PcanStatus.xmtfull;
  }

  (PcanMessage, PcanTimestamp, PcanStatus) read() {
    if (_fd < 0) {
      return (
        PcanMessage(id: 0, type: PcanMessageType.standard, data: Uint8List(0)),
        PcanTimestamp(millis: 0, millisOverflow: 0, micros: 0),
        PcanStatus.illhw,
      );
    }
    final frame = _frameBuf!;
    final n = _recv(_fd, frame, ffi.sizeOf<_CanFrame>(), _MSG_DONTWAIT);
    if (n < ffi.sizeOf<_CanFrame>()) {
      return (
        PcanMessage(id: 0, type: PcanMessageType.standard, data: Uint8List(0)),
        PcanTimestamp(millis: 0, millisOverflow: 0, micros: 0),
        PcanStatus.qrcvempty,
      );
    }

    final rawId = frame.ref.can_id;
    final isExtended = (rawId & _CAN_EFF_FLAG) != 0;
    final id = isExtended ? (rawId & _CAN_EFF_MASK) : (rawId & _CAN_SFF_MASK);
    final len = frame.ref.len;
    final data = Uint8List(len);
    for (int i = 0; i < len; i++) {
      data[i] = frame.ref.data[i];
    }

    return (
      PcanMessage(
        id: id,
        type: isExtended ? PcanMessageType.extended : PcanMessageType.standard,
        data: data,
      ),
      PcanTimestamp(millis: 0, millisOverflow: 0, micros: 0),
      PcanStatus.ok,
    );
  }

  PcanStatus reset() {
    // SocketCAN doesn't have a direct reset — close+reopen
    if (_fd < 0) return PcanStatus.ok;
    close();
    return open();
  }

  PcanStatus get status => _fd >= 0 ? PcanStatus.ok : PcanStatus.illhw;
}
