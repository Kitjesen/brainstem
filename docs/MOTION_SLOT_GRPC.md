# Select robot-managed motion slots over gRPC

## Contract and ownership

Clients select a stable motion slot (`flat`, `stairs`, or configured
`high_platform`). The robot resolves the slot against its startup-frozen
`operator_modes.json` and selects the corresponding preloaded model/profile.
Replacing a model in a robot slot does not require changing the App's mapping.

This is already supported by the hardware operator-slot implementation of
`brainstem.api.v1.RobotControl.SwitchProfile`. There is no new RPC, service,
or automatic posture/power sequence. This change makes motion slots discoverable
using existing `ProfileInfo.mode_capabilities` and `active_mode_id` fields.

Example robot configuration (profile names are deployment-specific):

```json
{"flat":"flat_model_v2","stairs":"stairs_model_v3"}
```

Install, validate and preload compatible profiles using the existing deployment
procedure, then restart to load the frozen configuration. Editing JSON is not a
live model switch. The deployment/configuration owner maintains these bindings;
the App does not.

## Discover available slots

Call `GetProfile(google.protobuf.Empty)` and select `mode_capabilities` entries
whose kind is `ROBOT_MODE_KIND_LOCOMOTION_PROFILE`. Configured hardware slots are
returned in flat/stairs/high_platform order. Unassigned optional slots and
historical profiles are not advertised as motion capabilities.

Illustrative protobuf JSON response, omitting unrelated fields:

```json
{
  "current": "flat_model_v2",
  "available": ["flat_model_v2", "stairs_model_v3"],
  "activeModeId": "flat",
  "modeCapabilities": [
    {
      "id": "flat",
      "kind": "ROBOT_MODE_KIND_LOCOMOTION_PROFILE",
      "availability": "ROBOT_MODE_AVAILABILITY_AVAILABLE",
      "profileId": "flat_model_v2"
    },
    {
      "id": "stairs",
      "kind": "ROBOT_MODE_KIND_LOCOMOTION_PROFILE",
      "availability": "ROBOT_MODE_AVAILABILITY_AVAILABLE",
      "profileId": "stairs_model_v3"
    }
  ]
}
```

`AVAILABLE` for a motion slot means it is configured, not that the robot may
switch in its current physical/control state. The existing live switch checks
still apply. `profile_id` is diagnostic metadata, not the value the App must
send. Legacy `current`, `available` and descriptions retain their profile-name
semantics; do not replace them with slot strings.

Recovery retains its separate action capability and API. If recovery is selected,
`active_mode_id` is `recovery`, even though `current` still names the normal
locomotion profile. Switching locomotion while recovery is selected is rejected.
Without hardware operator slots, this API does not invent flat/stairs bindings.

## Switch by slot

Use the generated gRPC client and existing `ProfileRequest.name` field:

```text
service: brainstem.api.v1.RobotControl
method:  SwitchProfile
request: {"name":"stairs"}
```

Send `{"name":"flat"}` to return to flat. The examples are protobuf JSON
representations, not HTTP JSON POST endpoints. Full bound profile names remain
accepted for compatibility with existing clients. Unknown or unassigned slots
return `INVALID_ARGUMENT`.

After success, check the response's `active_mode_id` against the requested slot,
or read `GetProfile` again. Do not compare `current` to `flat`: it remains the
actual profile name. For an older server without motion capability metadata,
report that slot discovery is unsupported rather than parsing descriptions or
guessing model names.

## App integration

An optional App-local wrapper can expose:

```ts
switchMotionPolicy('flat');
switchMotionPolicy('stairs');
```

It sends the target string unchanged to `SwitchProfile`; it must not contain a
W5/CTS model-name table. Preserve the existing connection/session checks,
operator confirmation and action serialization. Use the slot capability list
instead of the legacy `available` model-name list to validate a slot request;
update both TypeScript and native Android validation if necessary. The inspected
DOSO App currently rejects IDs absent from `available`, so merely changing its
button argument to `flat` is insufficient. Use bindings generated from the
robot's pinned protocol version to expose the existing capability fields.

The current App requires Grounded, disabled motors and no motion lease for
profile selection. The hardware operator-slot server also supports idle
Standing under its existing checks. This change does not widen either side's
conditions or add automatic sit/disable/stand/enable actions. During walking,
transitions, local takeover, active motion leases or faults, show the actual
rejection reason. A timed-out request has an uncertain result: refresh status
before retrying rather than automatically repeating the switch.

## Validation and rollout

Local tests use mocked robot state and a loopback gRPC server. They cover slot
discovery, unchanged legacy fields, flat/stairs wire calls, replacement model
names, the optional high platform, failed commits, recovery selection and
non-operator catalogs. Existing authorization, lease, transition and rollback
tests continue to apply.

No App APK or robot deployment is included. No physical enable, posture,
profile-switch or motion command is required to run these tests. Deploy the
updated robot runtime and update the App's capability handling before claiming
end-to-end acceptance. Verify catalog reads first, then have the onsite operator
validate both directions of switching under the existing operating procedure.
