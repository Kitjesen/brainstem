"""Brainstem SDK — Python client for Thunder quadruped robot.

Quick start::

    from brainstem_sdk import OrixClient

    dog = OrixClient("192.168.66.190")
    dog.stand_up()
    dog.walk(vx=0.3)
    dog.sit_down()

摄像头::

    from brainstem_sdk import OrixCamera

    with OrixCamera() as cam:
        cam.save_photo("photo.jpg")
"""

from brainstem_sdk.client import (
    OrixClient,
    OrixClient,
    ImuData,
    JointData,
    MotorInfo,
    ProfileInfo,
    GestureInfo,
    RobotState,
    Vec3,
    Quat,
    OrixError,
    ConnectionError as OrixConnectionError,
    InvalidStateError,
    TimeoutError as OrixTimeoutError,
)

# 摄像头模块延迟导入 — opencv-python 是可选依赖
try:
    from brainstem_sdk.camera import OrixCamera, CameraOpenError
except ImportError:
    class OrixCamera:  # type: ignore[no-redef]
        """Stub: opencv-python not installed."""
        def __init__(self, *args, **kwargs):
            raise ImportError(
                "OrixCamera requires opencv-python. "
                "Install with: pip install brainstem-sdk[camera]"
            )
    CameraOpenError = None  # type: ignore[assignment,misc]

__version__ = "1.0.0"

__all__ = [
    "OrixClient",
    "OrixClient",
    "ImuData",
    "JointData",
    "MotorInfo",
    "ProfileInfo",
    "GestureInfo",
    "RobotState",
    "Vec3",
    "Quat",
    "OrixError",
    "OrixConnectionError",
    "InvalidStateError",
    "OrixTimeoutError",
    "OrixCamera",
    "CameraOpenError",
]
