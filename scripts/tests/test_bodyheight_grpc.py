import math
import sys
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import patch

from scripts import bodyheight_grpc


def message(**kwargs):
    return SimpleNamespace(**kwargs)


def history(height, walk=None):
    if walk is None:
        command = message(WhichOneof=lambda _: None)
    else:
        command = message(
            WhichOneof=lambda _: "walk",
            walk=message(x=walk[0], y=walk[1], z=walk[2]),
        )
    return message(body_height_command=height, command=command)


class FakeStub:
    forbidden = (
        "Enable",
        "Disable",
        "StandUp",
        "SitDown",
        "SwitchProfile",
        "GetMotorStatus",
        "ClearMotorFault",
        "SetZero",
    )

    def __init__(self, *, profile="thunder_h15", state=2, histories=()):
        self.profile = profile
        self.state = state
        self.histories = list(histories)
        self.calls = []

    def GetProfile(self, request, timeout=None):
        self.calls.append(("GetProfile", request, timeout))
        return message(current=self.profile)

    def GetCmsState(self, request, timeout=None):
        self.calls.append(("GetCmsState", request, timeout))
        return message(kind=self.state)

    def ListenHistory(self, request, timeout=None):
        self.calls.append(("ListenHistory", request, timeout))
        return iter(self.histories)

    def SetBodyHeight(self, request, timeout=None):
        self.calls.append(("SetBodyHeight", request, timeout))
        return message()

    def Walk(self, request, timeout=None):
        self.calls.append(("Walk", request, timeout))
        return message()

    def __getattr__(self, name):
        if name in self.forbidden:
            def fail(*args, **kwargs):
                raise AssertionError(f"forbidden RPC invoked: {name}")
            return fail
        raise AttributeError(name)


class FailingHistoryStub(FakeStub):
    def ListenHistory(self, request, timeout=None):
        self.calls.append(("ListenHistory", request, timeout))

        def stream():
            yield history(0.3)
            raise RuntimeError("deadline exceeded")

        return stream()


class OrderingStub(FakeStub):
    def ListenHistory(self, request, timeout=None):
        self.calls.append(("ListenHistory", request, timeout))

        def stream():
            for item in self.histories:
                self.calls.append(("History", item, None))
                yield item

        return stream()


class BodyHeightGrpcTests(unittest.TestCase):
    def setUp(self):
        self.profile_dir = bodyheight_grpc.DEFAULT_PROFILE_DIR

    def make_client(self, stub, timeout=0.1):
        return bodyheight_grpc.BodyHeightClient(
            stub,
            empty_factory=lambda: message(),
            vector_factory=lambda **values: message(**values),
            body_height_factory=lambda **values: message(**values),
            timeout=timeout,
        )

    def test_parser_defaults(self):
        args = bodyheight_grpc.build_parser().parse_args(["status"])
        self.assertEqual(args.target, "192.168.66.190:13145")
        self.assertEqual(args.timeout, 5.0)
        self.assertEqual(
            args.profile_dir,
            Path(bodyheight_grpc.__file__).resolve().parents[1]
            / "han_dog"
            / "profiles",
        )
        self.assertEqual(args.command, "status")

    def test_velocity_omitted_axes_become_zero(self):
        args = bodyheight_grpc.build_parser().parse_args(
            ["set-velocity", "--vx", "0.4"]
        )
        self.assertEqual(bodyheight_grpc.resolve_velocity(args), (0.4, 0.0, 0.0))

    def test_bare_velocity_is_rejected(self):
        args = bodyheight_grpc.build_parser().parse_args(["set-velocity"])
        with self.assertRaisesRegex(bodyheight_grpc.CommandError, "at least one"):
            bodyheight_grpc.resolve_velocity(args)

    def test_velocity_help_warns_that_enabled_motors_may_move(self):
        help_text = bodyheight_grpc.build_parser().format_help().lower()
        self.assertIn("motors are enabled", help_text)
        self.assertIn("may move", help_text)

    def test_profile_ranges_are_loaded(self):
        profile = bodyheight_grpc.load_profile(self.profile_dir, "thunder_h18")
        self.assertEqual(profile.name, "thunder_h18")
        self.assertEqual((profile.height_min, profile.height_max), (0.2, 0.54))
        self.assertEqual(profile.velocity_min, (-2.5, -1.0, -1.0))
        self.assertEqual(profile.velocity_max, (2.5, 1.0, 1.0))

    def test_profile_loading_fails_closed_on_malformed_config(self):
        malformed = '{"name":"thunder_h15","minBodyHeightCommand":0.2}'
        with patch.object(Path, "read_text", return_value=malformed):
            with self.assertRaises(bodyheight_grpc.ConfigError):
                bodyheight_grpc.load_profile(self.profile_dir, "thunder_h15")

    def test_height_rejects_nonfinite_and_out_of_range(self):
        for value in (math.nan, math.inf, 0.19, 0.55):
            stub = FakeStub(histories=[history(0.3)])
            client = self.make_client(stub)
            with self.subTest(value=value), self.assertRaises(bodyheight_grpc.CommandError):
                client.set_height(value, self.profile_dir)
            self.assertFalse(any(call[0] == "SetBodyHeight" for call in stub.calls))

    def test_velocity_rejects_nonfinite_and_out_of_range(self):
        for vector in ((math.nan, 0, 0), (2.6, 0, 0), (0, -1.1, 0)):
            stub = FakeStub(histories=[history(0.3, (0, 0, 0))])
            client = self.make_client(stub)
            with self.subTest(vector=vector), self.assertRaises(bodyheight_grpc.CommandError):
                client.set_velocity(vector, self.profile_dir)
            self.assertFalse(any(call[0] == "Walk" for call in stub.calls))

    def test_wrong_profile_is_rejected_before_command_rpc(self):
        stub = FakeStub(profile="default", histories=[history(0.3)])
        client = self.make_client(stub)
        with self.assertRaisesRegex(bodyheight_grpc.CommandError, "active profile"):
            client.set_height(0.3, self.profile_dir)
        self.assertFalse(any(call[0] == "SetBodyHeight" for call in stub.calls))

    def test_height_command_is_confirmed_by_telemetry(self):
        stub = FakeStub(histories=[history(0.3), history(0.3504)])
        client = self.make_client(stub)
        result = client.set_height(0.35, self.profile_dir, tolerance=0.001)
        self.assertEqual(result.state, "confirmed")
        self.assertAlmostEqual(result.history.body_height_command, 0.3504)
        sent = next(call[1] for call in stub.calls if call[0] == "SetBodyHeight")
        self.assertEqual(sent.meters, 0.35)

    def test_same_height_is_already_active_without_command_rpc(self):
        stub = FakeStub(histories=[history(0.3504)])
        result = self.make_client(stub).set_height(
            0.35, self.profile_dir, tolerance=0.001
        )
        self.assertEqual(result.state, "already_active")
        self.assertFalse(any(call[0] == "SetBodyHeight" for call in stub.calls))

    def test_missing_height_baseline_fails_before_command_rpc(self):
        missing_height = message(command=message(WhichOneof=lambda _: None))
        stub = FakeStub(histories=[missing_height, history(0.35)])
        with self.assertRaisesRegex(bodyheight_grpc.TelemetryError, "baseline"):
            self.make_client(stub).set_height(0.35, self.profile_dir)
        self.assertFalse(any(call[0] == "SetBodyHeight" for call in stub.calls))

    def test_height_baseline_is_consumed_before_command(self):
        stub = OrderingStub(histories=[history(0.3), history(0.35)])
        result = self.make_client(stub).set_height(0.35, self.profile_dir)
        names = [call[0] for call in stub.calls]
        self.assertEqual(result.state, "confirmed")
        self.assertLess(names.index("ListenHistory"), names.index("History"))
        self.assertLess(names.index("History"), names.index("SetBodyHeight"))
        self.assertLess(names.index("SetBodyHeight"), len(names) - 1)
        self.assertEqual(names[-1], "History")

    def test_silent_height_rejection_is_reported(self):
        stub = FakeStub(histories=[history(0.3), history(0.3)])
        client = self.make_client(stub)
        with self.assertRaisesRegex(bodyheight_grpc.TelemetryError, "not confirmed"):
            client.set_height(0.35, self.profile_dir)

    def test_height_stream_error_still_reports_missing_confirmation(self):
        client = self.make_client(FailingHistoryStub())
        with self.assertRaisesRegex(bodyheight_grpc.TelemetryError, "not confirmed"):
            client.set_height(0.35, self.profile_dir)

    def test_velocity_requires_standing_or_walking_state(self):
        stub = FakeStub(state=1, histories=[history(0.3, (0.2, 0, 0))])
        client = self.make_client(stub)
        with self.assertRaisesRegex(bodyheight_grpc.CommandError, "Standing or Walking"):
            client.set_velocity((0.2, 0, 0), self.profile_dir)
        self.assertFalse(any(call[0] == "Walk" for call in stub.calls))

    def test_velocity_command_is_confirmed_by_telemetry(self):
        stub = FakeStub(histories=[history(0.3), history(0.3, (0.2, -0.1, 0.3))])
        client = self.make_client(stub)
        result = client.set_velocity(
            (0.2, -0.1, 0.3), self.profile_dir, tolerance=0.001
        )
        self.assertEqual(result.state, "confirmed")
        self.assertEqual(result.history.command.WhichOneof("data"), "walk")
        sent = next(call[1] for call in stub.calls if call[0] == "Walk")
        self.assertEqual((sent.x, sent.y, sent.z), (0.2, -0.1, 0.3))

    def test_same_velocity_is_already_active_without_command_rpc(self):
        stub = FakeStub(histories=[history(0.3, (0.2, -0.1, 0.3))])
        result = self.make_client(stub).set_velocity(
            (0.2, -0.1, 0.3), self.profile_dir
        )
        self.assertEqual(result.state, "already_active")
        self.assertFalse(any(call[0] == "Walk" for call in stub.calls))

    def test_velocity_baseline_is_consumed_before_command(self):
        stub = OrderingStub(
            histories=[history(0.3, (0.0, 0.0, 0.0)), history(0.3, (0.2, 0, 0))]
        )
        result = self.make_client(stub).set_velocity((0.2, 0, 0), self.profile_dir)
        names = [call[0] for call in stub.calls]
        self.assertEqual(result.state, "confirmed")
        self.assertLess(names.index("ListenHistory"), names.index("History"))
        self.assertLess(names.index("History"), names.index("Walk"))
        self.assertEqual(names[-1], "History")

    def test_silent_velocity_rejection_is_reported(self):
        stub = FakeStub(histories=[history(0.3), history(0.3, (0.0, 0.0, 0.0))])
        client = self.make_client(stub)
        with self.assertRaisesRegex(bodyheight_grpc.TelemetryError, "not confirmed"):
            client.set_velocity((0.2, 0, 0), self.profile_dir)

    def test_only_allowed_command_methods_are_invoked(self):
        stub = FakeStub(histories=[history(0.35), history(0.35, (0.2, 0, 0))])
        client = self.make_client(stub)
        client.set_height(0.35, self.profile_dir)
        stub.histories = [history(0.35, (0.2, 0, 0))]
        client.set_velocity((0.2, 0, 0), self.profile_dir)
        invoked = {call[0] for call in stub.calls}
        self.assertTrue(invoked <= {
            "GetProfile", "GetCmsState", "ListenHistory", "SetBodyHeight", "Walk"
        })
        self.assertFalse(invoked.intersection(FakeStub.forbidden))

    def test_watch_history_stream_has_no_deadline(self):
        stub = FakeStub(histories=[history(0.35)])
        client = self.make_client(stub)
        self.assertEqual(len(list(client.histories(bounded=False))), 1)
        listen_call = next(call for call in stub.calls if call[0] == "ListenHistory")
        self.assertIsNone(listen_call[2])

    def test_runtime_loader_prepends_repo_generated_api_path(self):
        expected = (
            Path(bodyheight_grpc.__file__).resolve().parents[1]
            / "brainstem_api"
            / "python"
        )
        fake_grpc = ModuleType("grpc")
        fake_api = ModuleType("brainstem_api")
        fake_api.__path__ = []
        fake_api.Empty = object()
        fake_api.RobotControlStub = object()
        fake_api.Vector3 = object()
        fake_cms = ModuleType("brainstem_api.cms_pb2")
        fake_cms.BodyHeightCommand = object()
        modules = {
            "grpc": fake_grpc,
            "brainstem_api": fake_api,
            "brainstem_api.cms_pb2": fake_cms,
        }
        original_path = list(sys.path)
        try:
            with patch.object(Path, "is_dir", return_value=True):
                with patch.dict(sys.modules, modules):
                    runtime = bodyheight_grpc._load_runtime_api()
            self.assertEqual(Path(sys.path[0]), expected)
            self.assertIs(runtime.grpc, fake_grpc)
            self.assertIs(runtime.body_height_factory, fake_cms.BodyHeightCommand)
        finally:
            sys.path[:] = original_path


if __name__ == "__main__":
    unittest.main()
