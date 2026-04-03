"""Brainstem SDK — Python client for Thunder quadruped robot.

Quick start::

    from brainstem_sdk import ThunderClient

    dog = ThunderClient("192.168.66.190")
    dog.stand_up()
    dog.walk(vx=0.3)
    dog.sit_down()

摄像头::

    from brainstem_sdk import OrixCamera

    with OrixCamera() as cam:
        cam.save_photo("photo.jpg")
"""

from brainstem_sdk.client import (
    ThunderClient,
    ImuData,
    JointData,
    MotorInfo,
    ProfileInfo,
    RobotState,
    Vec3,
    Quat,
)

# 摄像头模块延迟导入 — opencv-python 是可选依赖
try:
    from brainstem_sdk.camera import OrixCamera
except ImportError:
    OrixCamera = None  # type: ignore[assignment,misc]

__version__ = "1.0.0"

__all__ = [
    "ThunderClient",
    "ImuData",
    "JointData",
    "MotorInfo",
    "ProfileInfo",
    "RobotState",
    "Vec3",
    "Quat",
    "OrixCamera",
]
