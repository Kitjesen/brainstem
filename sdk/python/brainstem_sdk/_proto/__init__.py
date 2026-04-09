"""Thin shim that re-exports brainstem_api submodules.

Historically ``brainstem_sdk/_proto/`` vendored the generated protobuf files
from ``han_dog_message`` v1.0.0. Starting with ``brainstem_api`` v2.0.0 the
vendored files are gone: this package now re-exports from the
``brainstem_api`` pip package (installed via
``brain/brainstem/brainstem_api/python``).

Install brainstem_api in development mode::

    cd brain/brainstem/brainstem_api/python
    pip install -e .

Downstream code can keep using ``from brainstem_sdk._proto import cms_pb2,
cms_pb2_grpc, common_pb2`` — the names resolve to the same modules.

Note that the **service class name** has changed in v2.0.0:

    v1.0.0 (legacy):  cms_pb2_grpc.CmsStub / CmsServicer
    v2.0.0:           cms_pb2_grpc.RobotControlStub / RobotControlServicer

See ``shared/proto/PROTO_GOVERNANCE.md`` for the full contract governance
model and ``brain/brainstem/brainstem_api/CHANGELOG.md`` for migration notes.
"""

from brainstem_api import cms_pb2 as cms_pb2
from brainstem_api import cms_pb2_grpc as cms_pb2_grpc
from brainstem_api import common_pb2 as common_pb2
from brainstem_api import common_pb2_grpc as common_pb2_grpc
from brainstem_api import mujoco_pb2 as mujoco_pb2
from brainstem_api import mujoco_pb2_grpc as mujoco_pb2_grpc

__all__ = [
    "cms_pb2",
    "cms_pb2_grpc",
    "common_pb2",
    "common_pb2_grpc",
    "mujoco_pb2",
    "mujoco_pb2_grpc",
]
