import importlib.util
import json
import math
import os
import tempfile
import unittest
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "walk_ref", REPO_ROOT / "sim" / "scripts" / "walk_ref.py"
)
walk_ref = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(walk_ref)


def profile_dict(**overrides):
    profile = {
        "observationType": "bodyHeight",
        "bodyHeightCommand": 0.32,
        "minBodyHeightCommand": 0.20,
        "maxBodyHeightCommand": 0.54,
        "velocityCommandMin": [-2.5, -1.0, -1.0],
        "velocityCommandMax": [2.5, 1.0, 1.0],
        "standingPose": list(range(16)),
        "standUpPose": [100.0 + value for value in range(16)],
        "policyDefaultPose": [200.0 + value for value in range(16)],
        "actionScale": [0.125, 0.25, 0.25, 5.0],
        "inferKp": [100.0] * 16,
        "inferKd": [15.0] * 16,
        "standUpKp": [40.0] * 16,
        "standUpKd": [5.0] * 16,
        "modelPath": "model/policy.onnx",
    }
    profile.update(overrides)
    return profile


class ProfileContractTest(unittest.TestCase):
    def test_profile_resolves_model_from_repo_root(self):
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", encoding="utf-8", delete=False
        ) as stream:
            json.dump(profile_dict(), stream)
            profile_path = Path(stream.name)
        try:
            profile = walk_ref.load_profile(profile_path, REPO_ROOT)
        finally:
            os.unlink(profile_path)
        self.assertEqual(profile.observation_type, "bodyHeight")
        self.assertEqual(profile.frame_dim, 58)
        self.assertEqual(profile.model_path, REPO_ROOT / "model" / "policy.onnx")
        np.testing.assert_array_equal(profile.standing_pose, np.arange(16))
        np.testing.assert_array_equal(profile.stand_up_pose, np.arange(16) + 100.0)
        np.testing.assert_array_equal(
            profile.policy_default_pose, np.arange(16) + 200.0
        )
        np.testing.assert_array_equal(profile.stand_up_kp, np.full(16, 40.0))
        np.testing.assert_array_equal(profile.stand_up_kd, np.full(16, 5.0))

    def test_legacy_pose_feeds_both_explicit_roles(self):
        raw = profile_dict()
        del raw["standUpPose"]
        del raw["policyDefaultPose"]

        profile = walk_ref.parse_profile(raw, REPO_ROOT)

        np.testing.assert_array_equal(profile.stand_up_pose, profile.standing_pose)
        np.testing.assert_array_equal(
            profile.policy_default_pose, profile.standing_pose
        )

    def test_standard_profile_keeps_57_dimension(self):
        profile = walk_ref.parse_profile(
            profile_dict(
                observationType="standard",
                bodyHeightCommand=None,
                minBodyHeightCommand=None,
                maxBodyHeightCommand=None,
            ),
            REPO_ROOT,
        )
        self.assertEqual(profile.frame_dim, 57)

    def test_commands_are_finite_and_clamped(self):
        profile = walk_ref.parse_profile(profile_dict(), REPO_ROOT)
        command = walk_ref.resolve_commands(profile, height=0.9, vx=3.0, vy=-2.0, vyaw=0.25)
        self.assertEqual(command, (0.54, 2.5, -1.0, 0.25))
        with self.assertRaisesRegex(ValueError, "finite"):
            walk_ref.resolve_commands(profile, height=math.nan, vx=0, vy=0, vyaw=0)

    def test_invalid_profile_vector_length_fails(self):
        with self.assertRaisesRegex(ValueError, "standingPose"):
            walk_ref.parse_profile(profile_dict(standingPose=[0.0] * 15), REPO_ROOT)
        with self.assertRaisesRegex(ValueError, "standUpPose"):
            walk_ref.parse_profile(profile_dict(standUpPose=[0.0] * 15), REPO_ROOT)
        with self.assertRaisesRegex(ValueError, "policyDefaultPose"):
            walk_ref.parse_profile(
                profile_dict(policyDefaultPose=[0.0] * 15), REPO_ROOT
            )


class ObservationContractTest(unittest.TestCase):
    def test_policy_zero_drives_observation_and_action_target(self):
        profile = walk_ref.parse_profile(profile_dict(), REPO_ROOT)
        measured = profile.policy_default_pose + 0.25

        relative = walk_ref.relative_joint_position(measured, profile)
        target = walk_ref.policy_target(np.zeros(16), profile)

        np.testing.assert_allclose(relative[:12], np.full(12, 0.25))
        np.testing.assert_array_equal(relative[12:], np.zeros(4))
        np.testing.assert_array_equal(target, profile.policy_default_pose)
        self.assertFalse(np.array_equal(target, profile.stand_up_pose))

    def test_handover_uses_101_smoothstep_samples_and_caps(self):
        profile = walk_ref.parse_profile(profile_dict(), REPO_ROOT)
        action = np.ones(16)
        policy = walk_ref.policy_target(action, profile)

        frame0 = walk_ref.handover_control(0, action, profile)
        frame50 = walk_ref.handover_control(50, action, profile)
        frame100 = walk_ref.handover_control(100, action, profile)
        capped = walk_ref.handover_control(101, action, profile)

        self.assertEqual(frame0.alpha, 0.0)
        np.testing.assert_array_equal(frame0.target, profile.stand_up_pose)
        np.testing.assert_array_equal(frame0.kp, profile.stand_up_kp)
        np.testing.assert_array_equal(frame0.kd, profile.stand_up_kd)

        self.assertEqual(frame50.alpha, 0.5)
        np.testing.assert_allclose(
            frame50.target, (profile.stand_up_pose + policy) / 2.0
        )
        np.testing.assert_allclose(
            frame50.kp, (profile.stand_up_kp + profile.infer_kp) / 2.0
        )
        np.testing.assert_allclose(
            frame50.kd, (profile.stand_up_kd + profile.infer_kd) / 2.0
        )

        for frame in (frame100, capped):
            self.assertEqual(frame.alpha, 1.0)
            np.testing.assert_allclose(frame.target, policy)
            np.testing.assert_array_equal(frame.kp, profile.infer_kp)
            np.testing.assert_array_equal(frame.kd, profile.infer_kd)
            np.testing.assert_allclose(frame.target[12:], policy[12:])

    def test_body_height_is_raw_final_scalar(self):
        groups = [
            np.arange(3),
            np.arange(10, 13),
            np.arange(20, 23),
            np.arange(30, 46),
            np.arange(50, 66),
            np.arange(70, 86),
        ]
        obs = walk_ref.compose_observation(*groups, height=0.37, observation_type="bodyHeight")
        self.assertEqual(obs.shape, (58,))
        np.testing.assert_array_equal(obs[:57], np.concatenate(groups).astype(np.float32))
        self.assertEqual(float(obs[-1]), np.float32(0.37))

    def test_standard_observation_has_no_height(self):
        groups = [np.zeros(3), np.zeros(3), np.zeros(3), np.zeros(16), np.zeros(16), np.zeros(16)]
        obs = walk_ref.compose_observation(*groups, height=0.37, observation_type="standard")
        self.assertEqual(obs.shape, (57,))

    def test_history_dimension_supports_h15_and_h18(self):
        self.assertEqual(walk_ref.infer_history_size(58, 58), 1)
        self.assertEqual(walk_ref.infer_history_size(580, 58), 10)
        with self.assertRaisesRegex(ValueError, "divisible"):
            walk_ref.infer_history_size(579, 58)

    def test_history_is_oldest_to_newest(self):
        history = walk_ref.initialize_history(np.array([2.0], dtype=np.float32), 3)
        history.append(np.array([3.0], dtype=np.float32))
        np.testing.assert_array_equal(walk_ref.flatten_history(history), [[2.0, 2.0, 3.0]])


class SafetyTest(unittest.TestCase):
    def test_nonfinite_and_low_trunk_fail(self):
        with self.assertRaisesRegex(RuntimeError, "non-finite"):
            walk_ref.validate_step(np.array([math.nan]), np.zeros(16), trunk_height=0.4, min_trunk_height=0.12)
        with self.assertRaisesRegex(RuntimeError, "fallen"):
            walk_ref.validate_step(np.zeros(3), np.zeros(16), trunk_height=0.1, min_trunk_height=0.12)


if __name__ == "__main__":
    unittest.main()
