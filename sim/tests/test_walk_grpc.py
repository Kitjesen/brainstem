import importlib.util
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "sim" / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("walk_grpc", SCRIPTS / "walk_grpc.py")
walk_grpc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(walk_grpc)


class FakeData:
    def __init__(self):
        self.qpos = np.zeros(23)
        self.qvel = np.zeros(22)
        self._sensors = {
            "orientation": SimpleNamespace(data=np.array([0.5, 0.1, 0.2, 0.3])),
            "angular-velocity": SimpleNamespace(data=np.array([1.0, 2.0, 3.0])),
        }

    def sensor(self, name):
        return self._sensors[name]


class FakeStub:
    def __init__(self):
        self.height_requests = []
        self.walk_requests = []

    def SetBodyHeight(self, request, timeout=None):
        self.height_requests.append((request, timeout))

    def Walk(self, request, timeout=None):
        self.walk_requests.append((request, timeout))


class GrpcContractTest(unittest.TestCase):
    def test_build_sim_state_conjugates_body_to_world_quaternion(self):
        data = FakeData()
        data.qpos[walk_grpc.DOF_IDS] = np.arange(16)
        data.qvel[walk_grpc.DOF_VEL] = np.arange(16) + 20
        state = walk_grpc.build_sim_state(data, 1.25)

        self.assertEqual((state.quaternion.w, state.quaternion.x,
                          state.quaternion.y, state.quaternion.z),
                         (0.5, -0.1, -0.2, -0.3))
        self.assertEqual(list(state.joint_position.values), list(range(16)))
        self.assertEqual(list(state.joint_velocity.values), list(range(20, 36)))
        self.assertEqual((state.timestamp.seconds, state.timestamp.nanos),
                         (1, 250_000_000))

    def test_start_walking_sends_height_then_velocity(self):
        stub = FakeStub()
        walk_grpc.start_walking(stub, height=0.32, velocity=(0.3, -0.1, 0.2),
                                timeout=2.0)
        self.assertAlmostEqual(stub.height_requests[0][0].meters, 0.32)
        request = stub.walk_requests[0][0]
        self.assertEqual((request.x, request.y, request.z), (0.3, -0.1, 0.2))
        self.assertEqual(stub.height_requests[0][1], 2.0)

    def test_history_requires_16_actions_gains_and_expected_observation(self):
        history = walk_grpc.cms_pb2.History(
            next_action=walk_grpc.common_pb2.Matrix4(values=[0.0] * 16),
            kp=walk_grpc.common_pb2.Matrix4(values=[1.0] * 16),
            kd=walk_grpc.common_pb2.Matrix4(values=[2.0] * 16),
            observation=[0.0] * 580,
            body_height_command=0.32,
        )
        walk_grpc.validate_history(history, expected_observation_dim=580,
                                   expected_height=0.32)
        history.observation.pop()
        with self.assertRaisesRegex(RuntimeError, "observation"):
            walk_grpc.validate_history(history, expected_observation_dim=580,
                                       expected_height=0.32)

    def test_profile_pd_torque_uses_leg_position_and_wheel_velocity(self):
        target = np.arange(16, dtype=float)
        q = np.ones(16)
        dq = np.full(16, 2.0)
        kp = np.arange(16, dtype=float) + 1
        kd = np.arange(16, dtype=float) + 2
        torque = walk_grpc.compute_torque(target, q, dq, kp, kd)
        np.testing.assert_allclose(
            torque[:12], kp[:12] * (target[:12] - q[:12]) - kd[:12] * dq[:12])
        np.testing.assert_allclose(
            torque[12:], kp[12:] * (target[12:] - q[12:])
            + kd[12:] * (target[12:] - dq[12:]))

    def test_fall_threshold_activates_only_after_standup(self):
        self.assertEqual(
            walk_grpc.active_min_trunk_height(walk_grpc.CMS_GROUNDED, 0.10), 0.0)
        self.assertEqual(
            walk_grpc.active_min_trunk_height(walk_grpc.CMS_WALKING, 0.10), 0.10)


    def test_nonfinite_target_fails_before_control(self):
        with self.assertRaisesRegex(RuntimeError, "non-finite"):
            walk_grpc.compute_torque(
                np.array([float("nan")] + [0.0] * 15),
                np.zeros(16), np.zeros(16), np.ones(16), np.ones(16))


if __name__ == "__main__":
    unittest.main()
