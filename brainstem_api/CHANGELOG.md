# brainstem_api CHANGELOG

This file records the version history of the brainstem ↔ client gRPC contract
(`brainstem.api.v1` package). Consumers include `lingtu` navigation stack,
brainstem Python SDK, and the Dart services inside brainstem itself.

Versioning follows [Semantic Versioning](https://semver.org/).

**Field numbers, once published, are frozen forever.** Deprecated fields are
marked but their tag numbers are never reused. Breaking changes only happen on
a MAJOR bump.

See `../../shared/proto/PROTO_GOVERNANCE.md` for the full governance rules.

---

## [2.0.0] — 2026-04-09

First release under the `brainstem_api` name. Breaking rename from the legacy
`han_dog_message` package used during prototype development.

### Breaking changes

| Dimension | 1.0.0 (legacy) | 2.0.0 |
|-----------|---------------|-------|
| Dart package name | `han_dog_message` | `brainstem_api` |
| Python package name | `han-dog-message` / `han_dog_message` | `brainstem-api` / `brainstem_api` |
| Proto package | `han_dog` | `brainstem.api.v1` |
| Service name | `Cms` | `RobotControl` |
| gRPC method path | `/han_dog.Cms/Walk` | `/brainstem.api.v1.RobotControl/Walk` |
| Generated Dart client | `CmsClient` | `RobotControlClient` |
| Generated Python stub | `CmsStub` | `RobotControlStub` |
| Servicer base class | `CmsServicer` | `RobotControlServicer` |
| Server registration | `add_CmsServicer_to_server` | `add_RobotControlServicer_to_server` |
| Directory name | `brainstem/han_dog_message/` | `brainstem/brainstem_api/` |

Old 1.0.0 clients will **not** interop with 2.0.0 servers, and vice versa. The
service path component changed on the wire, so the rename is fully breaking.

### Non-breaking

All RPC signatures, message definitions, and field numbers are preserved from
1.0.0. Nothing in the payload wire format changed — only naming. This means
hand-migrating a client is mechanical (rename the import + the stub class).

### RPCs exposed (unchanged from 1.0.0)

| Category | RPCs | Notes |
|----------|------|-------|
| Motion control (arbitrated) | `Walk`, `StandUp`, `SitDown`, `SetSpeedMode`, `GetSpeedMode`, `PlayGesture` | Subject to ControlArbiter; teleop > gRPC; 3 s teleop timeout |
| Hardware (bypass arbiter) | `Enable`, `Disable`, `ClearMotorFault`, `SetZero` | Direct motor control |
| Telemetry (read-only) | `ListenHistory`, `ListenCmsState`, `ListenImu`, `ListenJoint`, `GetStartTime`, `GetCmsState`, `GetVoltage`, `GetMotorStatus`, `GetParams`, `ListGestures`, `SwitchProfile`, `GetProfile` | Streams at ~50 Hz (imu/joint), event-driven (state) |
| Simulation only | `Tick`, `Step` | Only valid in sim mode |

### Rationale

`han_dog_message` was the prototype naming from the early Han Dog robot. Now
that brainstem is the canonical control stack for Thunder (and future Nova
Dog / AXION humanoid platforms), the API name should reflect the implementer
(`brainstem`), use explicit versioning (`api.v1`), and use a self-documenting
service name (`RobotControl`) instead of the historical `Cms` acronym.

### Consumer migration checklist

| Consumer | Path | Status |
|----------|------|--------|
| lingtu `ThunderDriver` | `brain/lingtu/src/drivers/thunder/han_dog_module.py` | ⏳ pending |
| lingtu legacy bridge | `brain/lingtu/src/drivers/thunder/connection.py` | ⏳ pending |
| lingtu legacy handler | `brain/lingtu/src/drivers/thunder/legacy/han_dog_bridge.py` | ⏳ pending |
| lingtu integration test | `brain/lingtu/tests/integration/test_dog_bridge.py` | ⏳ pending |
| lingtu manager.py | `brain/lingtu/scripts/manager/manager.py` | ⏳ pending |
| brainstem Python SDK | `brain/brainstem/sdk/python/brainstem_sdk/_proto/` | ⏳ pending |
| brainstem Dart han_dog | `brain/brainstem/han_dog/**/*.dart` | ⏳ pending |
| brainstem Dart sirius | `brain/brainstem/sirius/**/*.dart` | ⏳ pending |
| sim xbox_remote | `brain/brainstem/sim/scripts/xbox_remote.py` | ⏳ pending |

### Mirrors

- `shared/proto/brainstem_api/` — maintained by `shared/proto/tools/sync_brainstem_api.sh`

---

## [1.0.0] — 2026-04-04 (legacy: `han_dog_message`)

Historical freeze under the previous `han_dog_message` / `package han_dog`
name. This baseline is preserved in git history but is superseded by 2.0.0.

First version to introduce formal version management and compatibility
guarantees (RPC signatures stable, field numbers locked, additive-only within
MAJOR). All of those guarantees carry over into 2.0.0 — only the naming
changed.
