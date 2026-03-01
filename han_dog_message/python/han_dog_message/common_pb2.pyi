import datetime

from google.protobuf import duration_pb2 as _duration_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class RobotType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SKINNY: _ClassVar[RobotType]
    HAN: _ClassVar[RobotType]
    MINI: _ClassVar[RobotType]
    MINI2: _ClassVar[RobotType]
SKINNY: RobotType
HAN: RobotType
MINI: RobotType
MINI2: RobotType

class Vector3(_message.Message):
    __slots__ = ("x", "y", "z")
    X_FIELD_NUMBER: _ClassVar[int]
    Y_FIELD_NUMBER: _ClassVar[int]
    Z_FIELD_NUMBER: _ClassVar[int]
    x: float
    y: float
    z: float
    def __init__(self, x: _Optional[float] = ..., y: _Optional[float] = ..., z: _Optional[float] = ...) -> None: ...

class ArrayFloat(_message.Message):
    __slots__ = ("values",)
    VALUES_FIELD_NUMBER: _ClassVar[int]
    values: _containers.RepeatedScalarFieldContainer[float]
    def __init__(self, values: _Optional[_Iterable[float]] = ...) -> None: ...

class Matrix4(_message.Message):
    __slots__ = ("values",)
    VALUES_FIELD_NUMBER: _ClassVar[int]
    values: _containers.RepeatedScalarFieldContainer[float]
    def __init__(self, values: _Optional[_Iterable[float]] = ...) -> None: ...

class Matrix4Int32(_message.Message):
    __slots__ = ("values",)
    VALUES_FIELD_NUMBER: _ClassVar[int]
    values: _containers.RepeatedScalarFieldContainer[int]
    def __init__(self, values: _Optional[_Iterable[int]] = ...) -> None: ...

class Quaternion(_message.Message):
    __slots__ = ("w", "x", "y", "z")
    W_FIELD_NUMBER: _ClassVar[int]
    X_FIELD_NUMBER: _ClassVar[int]
    Y_FIELD_NUMBER: _ClassVar[int]
    Z_FIELD_NUMBER: _ClassVar[int]
    w: float
    x: float
    y: float
    z: float
    def __init__(self, w: _Optional[float] = ..., x: _Optional[float] = ..., y: _Optional[float] = ..., z: _Optional[float] = ...) -> None: ...

class Action(_message.Message):
    __slots__ = ("data", "timestamp")
    DATA_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_FIELD_NUMBER: _ClassVar[int]
    data: Matrix4
    timestamp: _duration_pb2.Duration
    def __init__(self, data: _Optional[_Union[Matrix4, _Mapping]] = ..., timestamp: _Optional[_Union[datetime.timedelta, _duration_pb2.Duration, _Mapping]] = ...) -> None: ...

class RobotModel(_message.Message):
    __slots__ = ("type", "initial_joint_position", "initial_joint_velocity")
    TYPE_FIELD_NUMBER: _ClassVar[int]
    INITIAL_JOINT_POSITION_FIELD_NUMBER: _ClassVar[int]
    INITIAL_JOINT_VELOCITY_FIELD_NUMBER: _ClassVar[int]
    type: RobotType
    initial_joint_position: Matrix4
    initial_joint_velocity: Matrix4
    def __init__(self, type: _Optional[_Union[RobotType, str]] = ..., initial_joint_position: _Optional[_Union[Matrix4, _Mapping]] = ..., initial_joint_velocity: _Optional[_Union[Matrix4, _Mapping]] = ...) -> None: ...

class SimState(_message.Message):
    __slots__ = ("gyroscope", "quaternion", "joint_position", "joint_velocity", "timestamp")
    GYROSCOPE_FIELD_NUMBER: _ClassVar[int]
    QUATERNION_FIELD_NUMBER: _ClassVar[int]
    JOINT_POSITION_FIELD_NUMBER: _ClassVar[int]
    JOINT_VELOCITY_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_FIELD_NUMBER: _ClassVar[int]
    gyroscope: Vector3
    quaternion: Quaternion
    joint_position: Matrix4
    joint_velocity: Matrix4
    timestamp: _duration_pb2.Duration
    def __init__(self, gyroscope: _Optional[_Union[Vector3, _Mapping]] = ..., quaternion: _Optional[_Union[Quaternion, _Mapping]] = ..., joint_position: _Optional[_Union[Matrix4, _Mapping]] = ..., joint_velocity: _Optional[_Union[Matrix4, _Mapping]] = ..., timestamp: _Optional[_Union[datetime.timedelta, _duration_pb2.Duration, _Mapping]] = ...) -> None: ...
