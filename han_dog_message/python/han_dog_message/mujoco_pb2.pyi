import datetime

from google.protobuf import empty_pb2 as _empty_pb2
from han_dog_message import common_pb2 as _common_pb2
from google.protobuf import duration_pb2 as _duration_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class ViewerFrame(_message.Message):
    __slots__ = ("qpos", "qvel", "timestamp")
    QPOS_FIELD_NUMBER: _ClassVar[int]
    QVEL_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_FIELD_NUMBER: _ClassVar[int]
    qpos: _common_pb2.ArrayFloat
    qvel: _common_pb2.ArrayFloat
    timestamp: _duration_pb2.Duration
    def __init__(self, qpos: _Optional[_Union[_common_pb2.ArrayFloat, _Mapping]] = ..., qvel: _Optional[_Union[_common_pb2.ArrayFloat, _Mapping]] = ..., timestamp: _Optional[_Union[datetime.timedelta, _duration_pb2.Duration, _Mapping]] = ...) -> None: ...
