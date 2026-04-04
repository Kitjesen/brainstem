"""brainstem_sdk unit tests.

Tests the OrixClient against a mock gRPC server.
No real robot needed.
"""

import threading
import time
from concurrent import futures
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import grpc
import pytest
from google.protobuf.empty_pb2 import Empty
from google.protobuf.duration_pb2 import Duration

from brainstem_sdk import OrixClient, RobotState
from brainstem_sdk._proto import cms_pb2, cms_pb2_grpc, common_pb2


# ── Mock gRPC server ────────────────────────────────────────

class MockCmsServicer(cms_pb2_grpc.CmsServicer):
    """Fake CMS server that returns predictable responses."""

    def __init__(self):
        self.last_walk_cmd = None
        self.last_profile_req = None
        self.enabled = False
        self.state = cms_pb2.CMS_STATE_KIND_GROUNDED

    def Enable(self, request, context):
        self.enabled = True
        return Empty()

    def Disable(self, request, context):
        self.enabled = False
        return Empty()

    def Walk(self, request, context):
        self.last_walk_cmd = request
        return Empty()

    def StandUp(self, request, context):
        self.state = cms_pb2.CMS_STATE_KIND_STANDING
        return Empty()

    def SitDown(self, request, context):
        self.state = cms_pb2.CMS_STATE_KIND_GROUNDED
        return Empty()

    def GetCmsState(self, request, context):
        return cms_pb2.CmsState(kind=self.state)

    def GetVoltage(self, request, context):
        return cms_pb2.Voltage(values=[42.0] * 16)

    def GetMotorStatus(self, request, context):
        motors = [
            cms_pb2.MotorState(
                id=i, online=True, temperature=35.0,
                voltage=42.0, position=0.0, velocity=0.0,
                torque=0.0, errors=[],
            )
            for i in range(16)
        ]
        return cms_pb2.MotorStatusResponse(motors=motors)

    def GetProfile(self, request, context):
        return cms_pb2.ProfileInfo(
            current="default",
            available=["default", "mini"],
            descriptions=["Default profile", "Mini dog profile"],
        )

    def SwitchProfile(self, request, context):
        self.last_profile_req = request.name
        return cms_pb2.ProfileInfo(
            current=request.name,
            available=["default", "mini"],
            descriptions=["Default profile", "Mini dog profile"],
        )

    def ClearMotorFault(self, request, context):
        return Empty()

    def SetZero(self, request, context):
        return Empty()

    def ListenImu(self, request, context):
        for i in range(3):
            yield cms_pb2.Imu(
                gyroscope=common_pb2.Vector3(x=0.01 * i, y=0.0, z=0.0),
                quaternion=common_pb2.Quaternion(w=1.0, x=0.0, y=0.0, z=0.0),
                timestamp=Duration(seconds=0, nanos=i * 20_000_000),
            )

    def ListenJoint(self, request, context):
        for i in range(3):
            yield cms_pb2.Joint(
                single_joint=cms_pb2.SingleJoint(
                    id=i, position=0.1 * i, velocity=0.0, torque=0.0,
                ),
                timestamp=Duration(seconds=0, nanos=i * 20_000_000),
            )

    def ListenCmsState(self, request, context):
        for kind in [
            cms_pb2.CMS_STATE_KIND_GROUNDED,
            cms_pb2.CMS_STATE_KIND_STANDING,
            cms_pb2.CMS_STATE_KIND_WALKING,
        ]:
            yield cms_pb2.CmsState(kind=kind)


# ── Fixtures ────────────────────────────────────────────────

@pytest.fixture(scope="module")
def mock_server():
    """Start a mock gRPC server on a random port."""
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=2))
    servicer = MockCmsServicer()
    cms_pb2_grpc.add_CmsServicer_to_server(servicer, server)
    port = server.add_insecure_port("[::]:0")
    server.start()
    yield port, servicer
    server.stop(grace=1)


@pytest.fixture
def dog(mock_server):
    """Create a OrixClient connected to the mock server."""
    port, _ = mock_server
    client = OrixClient("localhost", port=port, timeout=5.0)
    yield client
    client.close()


@pytest.fixture
def servicer(mock_server):
    _, s = mock_server
    return s


# ── Tests ───────────────────────────────────────────────────

class TestMotorControl:
    def test_enable(self, dog, servicer):
        dog.enable()
        assert servicer.enabled is True

    def test_disable(self, dog, servicer):
        servicer.enabled = True
        dog.disable()
        assert servicer.enabled is False


class TestMotionCommands:
    def test_walk_forward(self, dog, servicer):
        dog.walk(vx=0.5)
        assert servicer.last_walk_cmd.x == pytest.approx(0.5)
        assert servicer.last_walk_cmd.y == pytest.approx(0.0)
        assert servicer.last_walk_cmd.z == pytest.approx(0.0)

    def test_walk_with_rotation(self, dog, servicer):
        dog.walk(vx=0.3, vy=-0.1, vyaw=0.2)
        assert servicer.last_walk_cmd.x == pytest.approx(0.3)
        assert servicer.last_walk_cmd.y == pytest.approx(-0.1)
        assert servicer.last_walk_cmd.z == pytest.approx(0.2)

    def test_walk_stop(self, dog, servicer):
        dog.walk()
        assert servicer.last_walk_cmd.x == pytest.approx(0.0)

    def test_stand_up(self, dog, servicer):
        dog.stand_up()
        assert servicer.state == cms_pb2.CMS_STATE_KIND_STANDING

    def test_sit_down(self, dog, servicer):
        dog.sit_down()
        assert servicer.state == cms_pb2.CMS_STATE_KIND_GROUNDED


class TestStateQuery:
    def test_get_state_grounded(self, dog, servicer):
        servicer.state = cms_pb2.CMS_STATE_KIND_GROUNDED
        assert dog.get_state() == "grounded"

    def test_get_state_walking(self, dog, servicer):
        servicer.state = cms_pb2.CMS_STATE_KIND_WALKING
        assert dog.get_state() == "walking"

    def test_get_voltage(self, dog):
        voltages = dog.get_voltage()
        assert len(voltages) == 16
        assert all(v == pytest.approx(42.0) for v in voltages)

    def test_get_motor_status(self, dog):
        motors = dog.get_motor_status()
        assert len(motors) == 16
        assert motors[0].online is True
        assert motors[0].temperature == pytest.approx(35.0)
        assert motors[15].id == 15


class TestProfileManagement:
    def test_get_profile(self, dog):
        profile = dog.get_profile()
        assert profile.current == "default"
        assert "default" in profile.available
        assert "mini" in profile.available

    def test_switch_profile(self, dog, servicer):
        profile = dog.switch_profile("mini")
        assert servicer.last_profile_req == "mini"
        assert profile.current == "mini"


class TestDiagnostics:
    def test_clear_motor_fault_all(self, dog):
        dog.clear_motor_fault()

    def test_clear_motor_fault_specific(self, dog):
        dog.clear_motor_fault([0, 1, 2])

    def test_set_zero(self, dog):
        dog.set_zero()


class TestStreaming:
    def test_listen_imu(self, dog):
        data = list(dog.listen_imu())
        assert len(data) == 3
        assert data[0].gyroscope.x == pytest.approx(0.0)
        assert data[1].gyroscope.x == pytest.approx(0.01)
        assert data[2].gyroscope.x == pytest.approx(0.02)
        assert data[0].quaternion.w == pytest.approx(1.0)

    def test_listen_joint(self, dog):
        data = list(dog.listen_joint())
        assert len(data) == 3
        assert data[0].id == 0
        assert data[1].position == pytest.approx(0.1)
        assert data[2].position == pytest.approx(0.2)

    def test_listen_state(self, dog):
        states = list(dog.listen_state())
        assert states == ["grounded", "standing", "walking"]


class TestContextManager:
    def test_with_statement(self, mock_server):
        port, _ = mock_server
        with OrixClient("localhost", port=port) as dog:
            state = dog.get_state()
            assert state in RobotState._MAP.values()


class TestConnectionFailure:
    def test_connect_bad_port(self):
        """Connecting to a port with no server should fail on ping."""
        client = OrixClient("localhost", port=1, timeout=1.0)
        try:
            assert client.ping() is False
        finally:
            client.close()

    def test_with_statement_bad_port(self):
        """Using 'with' on a dead target should raise ConnectionError."""
        from brainstem_sdk.client import ConnectionError as OrixConnectionError

        with pytest.raises(OrixConnectionError):
            with OrixClient("localhost", port=1, timeout=1.0) as dog:
                pass


class TestSpeedMode:
    """Test speed-mode RPCs via stub-level mocking.

    SetSpeedMode / GetSpeedMode are not yet in the proto definition,
    so we patch them directly on the stub.
    """

    def test_set_high_speed(self, dog):
        mock_set = MagicMock(return_value=Empty())
        with patch.object(dog._stub, "SetSpeedMode", mock_set, create=True):
            dog.set_high_speed(True)
        mock_set.assert_called_once()
        req = mock_set.call_args[0][0]
        assert req.mode == 1

    def test_set_normal_speed(self, dog):
        mock_set = MagicMock(return_value=Empty())
        with patch.object(dog._stub, "SetSpeedMode", mock_set, create=True):
            dog.set_high_speed(False)
        req = mock_set.call_args[0][0]
        assert req.mode == 0

    def test_get_speed_mode_normal(self, dog):
        mock_get = MagicMock(return_value=SimpleNamespace(mode=0))
        with patch.object(dog._stub, "GetSpeedMode", mock_get, create=True):
            assert dog.get_speed_mode() == "normal"

    def test_get_speed_mode_high(self, dog):
        mock_get = MagicMock(return_value=SimpleNamespace(mode=1))
        with patch.object(dog._stub, "GetSpeedMode", mock_get, create=True):
            assert dog.get_speed_mode() == "high_speed"


class TestGestures:
    """Test gesture RPCs via stub-level mocking.

    ListGestures / PlayGesture are not yet in the proto definition,
    so we patch them directly on the stub.
    """

    def test_list_gestures(self, dog):
        fake_resp = SimpleNamespace(gestures=[
            SimpleNamespace(name="bow", description="Bow", duration_ms=3000),
            SimpleNamespace(name="dance", description="Dance", duration_ms=5000),
        ])
        mock_list = MagicMock(return_value=fake_resp)
        with patch.object(dog._stub, "ListGestures", mock_list, create=True):
            gestures = dog.list_gestures()
        assert len(gestures) == 2
        assert gestures[0].name == "bow"
        assert gestures[1].name == "dance"
        assert gestures[0].duration_ms == 3000

    def test_play_gesture(self, dog):
        mock_play = MagicMock(return_value=Empty())
        with patch.object(dog._stub, "PlayGesture", mock_play, create=True):
            dog.play_gesture("bow")
        mock_play.assert_called_once()
        req = mock_play.call_args[0][0]
        assert req.name == "bow"


class TestPing:
    def test_ping_returns_true(self, dog):
        assert dog.ping() is True
