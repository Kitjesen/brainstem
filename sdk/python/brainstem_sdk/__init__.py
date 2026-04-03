"""Brainstem SDK — Python client for Thunder quadruped robot.

Quick start::

    from brainstem_sdk import ThunderClient

    dog = ThunderClient("192.168.66.190")
    dog.stand_up()
    dog.walk(vx=0.3)
    dog.sit_down()
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

__version__ = "0.1.0"

__all__ = [
    "ThunderClient",
    "ImuData",
    "JointData",
    "MotorInfo",
    "ProfileInfo",
    "RobotState",
    "Vec3",
    "Quat",
]
