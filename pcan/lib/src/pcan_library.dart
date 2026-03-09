// ignore_for_file: camel_case_types

import 'dart:ffi' as ffi;
import 'dart:io';

import 'pcan_basic.g.dart';

/// Loads the PCAN-Basic native library via [ffi.DynamicLibrary.open].
///
/// This bypasses the `@ffi.Native` / native-assets hook mechanism, which may
/// not work in all deployment scenarios (e.g. `dart compile exe` on some
/// platforms does not invoke hooks, leading to
/// "No available native assets" errors at runtime).
///
/// Usage: all CAN_* wrapper functions in `pcan_basic.dart` call through the
/// typed function pointers exposed here instead of the generated top-level
/// `external` symbols in `pcan_basic.g.dart`.
final ffi.DynamicLibrary _lib = ffi.DynamicLibrary.open(
  switch (Platform.operatingSystem) {
    'linux' => 'libpcanbasic.so',
    'windows' => 'PCANBasic.dll',
    _ => throw UnsupportedError(
      'PCAN: unsupported platform ${Platform.operatingSystem}',
    ),
  },
);

// -- CAN_Initialize -----------------------------------------------------------

typedef _InitN = ffi.Uint32 Function(
  ffi.Uint16,
  ffi.Uint16,
  ffi.Uint8,
  ffi.Uint32,
  ffi.Uint16,
);
typedef _InitD = int Function(int, int, int, int, int);

final int Function(int, int, int, int, int) canInitializeRaw =
    _lib.lookupFunction<_InitN, _InitD>('CAN_Initialize');

// -- CAN_InitializeFD ---------------------------------------------------------

typedef _InitFdN = ffi.Uint32 Function(ffi.Uint16, ffi.Pointer<ffi.Char>);
typedef _InitFdD = int Function(int, ffi.Pointer<ffi.Char>);

final int Function(int, ffi.Pointer<ffi.Char>) canInitializeFDRaw =
    _lib.lookupFunction<_InitFdN, _InitFdD>('CAN_InitializeFD');

// -- CAN_Uninitialize ---------------------------------------------------------

typedef _UninitN = ffi.Uint32 Function(ffi.Uint16);
typedef _UninitD = int Function(int);

final int Function(int) canUninitializeRaw =
    _lib.lookupFunction<_UninitN, _UninitD>('CAN_Uninitialize');

// -- CAN_Reset ----------------------------------------------------------------

final int Function(int) canResetRaw =
    _lib.lookupFunction<ffi.Uint32 Function(ffi.Uint16), int Function(int)>(
      'CAN_Reset',
    );

// -- CAN_GetStatus ------------------------------------------------------------

final int Function(int) canGetStatusRaw =
    _lib.lookupFunction<ffi.Uint32 Function(ffi.Uint16), int Function(int)>(
      'CAN_GetStatus',
    );

// -- CAN_Read -----------------------------------------------------------------

typedef _ReadN = ffi.Uint32 Function(
  ffi.Uint16,
  ffi.Pointer<tagTPCANMsg>,
  ffi.Pointer<tagTPCANTimestamp>,
);
typedef _ReadD = int Function(
  int,
  ffi.Pointer<tagTPCANMsg>,
  ffi.Pointer<tagTPCANTimestamp>,
);

final int Function(
  int,
  ffi.Pointer<tagTPCANMsg>,
  ffi.Pointer<tagTPCANTimestamp>,
)
canReadRaw = _lib.lookupFunction<_ReadN, _ReadD>('CAN_Read');

// -- CAN_ReadFD ---------------------------------------------------------------

typedef _ReadFdN = ffi.Uint32 Function(
  ffi.Uint16,
  ffi.Pointer<tagTPCANMsgFD>,
  ffi.Pointer<ffi.Uint64>,
);
typedef _ReadFdD = int Function(
  int,
  ffi.Pointer<tagTPCANMsgFD>,
  ffi.Pointer<ffi.Uint64>,
);

final int Function(
  int,
  ffi.Pointer<tagTPCANMsgFD>,
  ffi.Pointer<ffi.Uint64>,
)
canReadFDRaw = _lib.lookupFunction<_ReadFdN, _ReadFdD>('CAN_ReadFD');

// -- CAN_Write ----------------------------------------------------------------

typedef _WriteN = ffi.Uint32 Function(ffi.Uint16, ffi.Pointer<tagTPCANMsg>);
typedef _WriteD = int Function(int, ffi.Pointer<tagTPCANMsg>);

final int Function(int, ffi.Pointer<tagTPCANMsg>) canWriteRaw =
    _lib.lookupFunction<_WriteN, _WriteD>('CAN_Write');

// -- CAN_WriteFD --------------------------------------------------------------

typedef _WriteFdN = ffi.Uint32 Function(
  ffi.Uint16,
  ffi.Pointer<tagTPCANMsgFD>,
);
typedef _WriteFdD = int Function(int, ffi.Pointer<tagTPCANMsgFD>);

final int Function(int, ffi.Pointer<tagTPCANMsgFD>) canWriteFDRaw =
    _lib.lookupFunction<_WriteFdN, _WriteFdD>('CAN_WriteFD');

// -- CAN_FilterMessages -------------------------------------------------------

typedef _FilterN = ffi.Uint32 Function(
  ffi.Uint16,
  ffi.Uint32,
  ffi.Uint32,
  ffi.Uint8,
);
typedef _FilterD = int Function(int, int, int, int);

final int Function(int, int, int, int) canFilterMessagesRaw =
    _lib.lookupFunction<_FilterN, _FilterD>('CAN_FilterMessages');

// -- CAN_GetValue -------------------------------------------------------------

typedef _GetValN = ffi.Uint32 Function(
  ffi.Uint16,
  ffi.Uint8,
  ffi.Pointer<ffi.Void>,
  ffi.Uint32,
);
typedef _GetValD = int Function(int, int, ffi.Pointer<ffi.Void>, int);

final int Function(int, int, ffi.Pointer<ffi.Void>, int) canGetValueRaw =
    _lib.lookupFunction<_GetValN, _GetValD>('CAN_GetValue');

// -- CAN_SetValue -------------------------------------------------------------

typedef _SetValN = ffi.Uint32 Function(
  ffi.Uint16,
  ffi.Uint8,
  ffi.Pointer<ffi.Void>,
  ffi.Uint32,
);
typedef _SetValD = int Function(int, int, ffi.Pointer<ffi.Void>, int);

final int Function(int, int, ffi.Pointer<ffi.Void>, int) canSetValueRaw =
    _lib.lookupFunction<_SetValN, _SetValD>('CAN_SetValue');

// -- CAN_GetErrorText ---------------------------------------------------------

typedef _ErrTxtN = ffi.Uint32 Function(
  ffi.Uint32,
  ffi.Uint16,
  ffi.Pointer<ffi.Char>,
);
typedef _ErrTxtD = int Function(int, int, ffi.Pointer<ffi.Char>);

final int Function(int, int, ffi.Pointer<ffi.Char>) canGetErrorTextRaw =
    _lib.lookupFunction<_ErrTxtN, _ErrTxtD>('CAN_GetErrorText');

// -- CAN_LookUpChannel --------------------------------------------------------

typedef _LookUpN = ffi.Uint32 Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Uint16>,
);
typedef _LookUpD = int Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Uint16>,
);

final int Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Uint16>)
canLookUpChannelRaw =
    _lib.lookupFunction<_LookUpN, _LookUpD>('CAN_LookUpChannel');
