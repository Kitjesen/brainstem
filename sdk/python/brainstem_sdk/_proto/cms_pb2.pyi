import datetime

from google.protobuf import empty_pb2 as _empty_pb2
from han_dog_message import common_pb2 as _common_pb2
from google.protobuf import timestamp_pb2 as _timestamp_pb2
from google.protobuf import duration_pb2 as _duration_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class CmsStateKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CMS_STATE_KIND_ZERO: _ClassVar[CmsStateKind]
    CMS_STATE_KIND_GROUNDED: _ClassVar[CmsStateKind]
    CMS_STATE_KIND_STANDING: _ClassVar[CmsStateKind]
    CMS_STATE_KIND_WALKING: _ClassVar[CmsStateKind]
    CMS_STATE_KIND_TRANSITIONING: _ClassVar[CmsStateKind]

class CmsTransitionKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CMS_TRANSITION_KIND_NONE: _ClassVar[CmsTransitionKind]
    CMS_TRANSITION_KIND_STAND_UP: _ClassVar[CmsTransitionKind]
    CMS_TRANSITION_KIND_SIT_DOWN: _ClassVar[CmsTransitionKind]
    CMS_TRANSITION_KIND_GESTURE: _ClassVar[CmsTransitionKind]
CMS_STATE_KIND_ZERO: CmsStateKind
CMS_STATE_KIND_GROUNDED: CmsStateKind
CMS_STATE_KIND_STANDING: CmsStateKind
CMS_STATE_KIND_WALKING: CmsStateKind
CMS_STATE_KIND_TRANSITIONING: CmsStateKind
CMS_TRANSITION_KIND_NONE: CmsTransitionKind
CMS_TRANSITION_KIND_STAND_UP: CmsTransitionKind
CMS_TRANSITION_KIND_SIT_DOWN: CmsTransitionKind
CMS_TRANSITION_KIND_GESTURE: CmsTransitionKind

class History(_message.Message):
    __slots__ = ("gyroscope", "projected_gravity", "command", "joint_position", "joint_velocity", "action", "next_action", "timestamp", "kp", "kd")
    GYROSCOPE_FIELD_NUMBER: _ClassVar[int]
    PROJECTED_GRAVITY_FIELD_NUMBER: _ClassVar[int]
    COMMAND_FIELD_NUMBER: _ClassVar[int]
    JOINT_POSITION_FIELD_NUMBER: _ClassVar[int]
    JOINT_VELOCITY_FIELD_NUMBER: _ClassVar[int]
    ACTION_FIELD_NUMBER: _ClassVar[int]
    NEXT_ACTION_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_FIELD_NUMBER: _ClassVar[int]
    KP_FIELD_NUMBER: _ClassVar[int]
    KD_FIELD_NUMBER: _ClassVar[int]
    gyroscope: _common_pb2.Vector3
    projected_gravity: _common_pb2.Vector3
    command: Command
    joint_position: _common_pb2.Matrix4
    joint_velocity: _common_pb2.Matrix4
    action: _common_pb2.Matrix4
    next_action: _common_pb2.Matrix4
    timestamp: _duration_pb2.Duration
    kp: _common_pb2.Matrix4
    kd: _common_pb2.Matrix4
    def __init__(self, gyroscope: _Optional[_Union[_common_pb2.Vector3, _Mapping]] = ..., projected_gravity: _Optional[_Union[_common_pb2.Vector3, _Mapping]] = ..., command: _Optional[_Union[Command, _Mapping]] = ..., joint_position: _Optional[_Union[_common_pb2.Matrix4, _Mapping]] = ..., joint_velocity: _Optional[_Union[_common_pb2.Matrix4, _Mapping]] = ..., action: _Optional[_Union[_common_pb2.Matrix4, _Mapping]] = ..., next_action: _Optional[_Union[_common_pb2.Matrix4, _Mapping]] = ..., timestamp: _Optional[_Union[datetime.timedelta, _duration_pb2.Duration, _Mapping]] = ..., kp: _Optional[_Union[_common_pb2.Matrix4, _Mapping]] = ..., kd: _Optional[_Union[_common_pb2.Matrix4, _Mapping]] = ...) -> None: ...

class Imu(_message.Message):
    __slots__ = ("gyroscope", "quaternion", "timestamp")
    GYROSCOPE_FIELD_NUMBER: _ClassVar[int]
    QUATERNION_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_FIELD_NUMBER: _ClassVar[int]
    gyroscope: _common_pb2.Vector3
    quaternion: _common_pb2.Quaternion
    timestamp: _duration_pb2.Duration
    def __init__(self, gyroscope: _Optional[_Union[_common_pb2.Vector3, _Mapping]] = ..., quaternion: _Optional[_Union[_common_pb2.Quaternion, _Mapping]] = ..., timestamp: _Optional[_Union[datetime.timedelta, _duration_pb2.Duration, _Mapping]] = ...) -> None: ...

class Joint(_message.Message):
    __slots__ = ("single_joint", "all_joints", "timestamp")
    SINGLE_JOINT_FIELD_NUMBER: _ClassVar[int]
    ALL_JOINTS_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_FIELD_NUMBER: _ClassVar[int]
    single_joint: SingleJoint
    all_joints: AllJoints
    timestamp: _duration_pb2.Duration
    def __init__(self, single_joint: _Optional[_Union[SingleJoint, _Mapping]] = ..., all_joints: _Optional[_Union[AllJoints, _Mapping]] = ..., timestamp: _Optional[_Union[datetime.timedelta, _duration_pb2.Duration, _Mapping]] = ...) -> None: ...

class SingleJoint(_message.Message):
    __slots__ = ("id", "position", "velocity", "torque", "status")
    ID_FIELD_NUMBER: _ClassVar[int]
    POSITION_FIELD_NUMBER: _ClassVar[int]
    VELOCITY_FIELD_NUMBER: _ClassVar[int]
    TORQUE_FIELD_NUMBER: _ClassVar[int]
    STATUS_FIELD_NUMBER: _ClassVar[int]
    id: int
    position: float
    velocity: float
    torque: float
    status: int
    def __init__(self, id: _Optional[int] = ..., position: _Optional[float] = ..., velocity: _Optional[float] = ..., torque: _Optional[float] = ..., status: _Optional[int] = ...) -> None: ...

class AllJoints(_message.Message):
    __slots__ = ("position", "velocity", "torque", "status")
    POSITION_FIELD_NUMBER: _ClassVar[int]
    VELOCITY_FIELD_NUMBER: _ClassVar[int]
    TORQUE_FIELD_NUMBER: _ClassVar[int]
    STATUS_FIELD_NUMBER: _ClassVar[int]
    position: _common_pb2.Matrix4
    velocity: _common_pb2.Matrix4
    torque: _common_pb2.Matrix4
    status: _common_pb2.Matrix4Int32
    def __init__(self, position: _Optional[_Union[_common_pb2.Matrix4, _Mapping]] = ..., velocity: _Optional[_Union[_common_pb2.Matrix4, _Mapping]] = ..., torque: _Optional[_Union[_common_pb2.Matrix4, _Mapping]] = ..., status: _Optional[_Union[_common_pb2.Matrix4Int32, _Mapping]] = ...) -> None: ...

class Params(_message.Message):
    __slots__ = ("robot",)
    ROBOT_FIELD_NUMBER: _ClassVar[int]
    robot: _common_pb2.RobotModel
    def __init__(self, robot: _Optional[_Union[_common_pb2.RobotModel, _Mapping]] = ...) -> None: ...

class ProfileRequest(_message.Message):
    __slots__ = ("name",)
    NAME_FIELD_NUMBER: _ClassVar[int]
    name: str
    def __init__(self, name: _Optional[str] = ...) -> None: ...

class ProfileInfo(_message.Message):
    __slots__ = ("current", "available", "descriptions", "current_description")
    CURRENT_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTIONS_FIELD_NUMBER: _ClassVar[int]
    CURRENT_DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    current: str
    available: _containers.RepeatedScalarFieldContainer[str]
    descriptions: _containers.RepeatedScalarFieldContainer[str]
    current_description: str
    def __init__(self, current: _Optional[str] = ..., available: _Optional[_Iterable[str]] = ..., descriptions: _Optional[_Iterable[str]] = ..., current_description: _Optional[str] = ...) -> None: ...

class CmsState(_message.Message):
    __slots__ = ("kind", "transition", "gesture_name")
    KIND_FIELD_NUMBER: _ClassVar[int]
    TRANSITION_FIELD_NUMBER: _ClassVar[int]
    GESTURE_NAME_FIELD_NUMBER: _ClassVar[int]
    kind: CmsStateKind
    transition: CmsTransitionKind
    gesture_name: str
    def __init__(self, kind: _Optional[_Union[CmsStateKind, str]] = ..., transition: _Optional[_Union[CmsTransitionKind, str]] = ..., gesture_name: _Optional[str] = ...) -> None: ...

class Command(_message.Message):
    __slots__ = ("idle", "stand_up", "sit_down", "walk")
    IDLE_FIELD_NUMBER: _ClassVar[int]
    STAND_UP_FIELD_NUMBER: _ClassVar[int]
    SIT_DOWN_FIELD_NUMBER: _ClassVar[int]
    WALK_FIELD_NUMBER: _ClassVar[int]
    idle: _empty_pb2.Empty
    stand_up: _empty_pb2.Empty
    sit_down: _empty_pb2.Empty
    walk: _common_pb2.Vector3
    def __init__(self, idle: _Optional[_Union[_empty_pb2.Empty, _Mapping]] = ..., stand_up: _Optional[_Union[_empty_pb2.Empty, _Mapping]] = ..., sit_down: _Optional[_Union[_empty_pb2.Empty, _Mapping]] = ..., walk: _Optional[_Union[_common_pb2.Vector3, _Mapping]] = ...) -> None: ...
