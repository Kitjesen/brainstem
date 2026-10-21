# Unified YunZhuo dog controls — 2026-10-20

User approved the mapping and body-height right-stick-X deadzone of +/-15% travel.
This document covers dog controls, not the arm teleoperation mapping. Source files
are installed in the production and body-height checkouts; no service restart,
enable, stand-up, calibration, motion RPC or hardware acceptance was performed.
An already running Dart process continues using its loaded code until a separately
approved controlled restart. Do not operate two controller services concurrently.

| Input | Production dog service | Body-height service (V2/V5/E17K) |
| --- | --- | --- |
| Left stick Y | Forward/backward | Same |
| Left stick X | Lateral movement | Same |
| Right stick X | Yaw contribution, original 0.5 gain | Yaw contribution after central +/-0.15 deadzone, maximum 0.5 |
| Right stick Y | No dog-height command | Integrate height; centered holds commanded height |
| CH14 (`knob` in decoder) | Yaw | Yaw, unchanged |
| H / CH6 | Motor-enable request / disable | Same |
| L1 / CH11 | Stand up | Same |
| L2 / CH7 | Sit down | Same |
| R1 / CH15 | Return to standing | Same, no height-command reset |
| Red / CH13 | Disable and clear errors on press | Same |
| R2 / CH16 | Existing stationary-state profile switch | Ignored in body-height mode |
| LT / RT | Original left-stick translation gain 0.5 / 1.5 | Same; final profile limits still apply |

CH14 is a receiver channel, not a known panel label or a guaranteed physical knob
location. Confirm its transmitter assignment from the channel monitor or a photo;
do not identify it by moving unknown controls with motors enabled.

## Yaw and height

Body-height right-stick contribution is zero for `abs(x)<=0.15`; outside it,
`sign(x)*(min(abs(x),1)-0.15)/0.85*0.5`. The contribution is summed with CH14,
clamped to [-1,1], then uses the existing yaw sign and downstream command limits.
CH14 retains its standalone 0.02 noise deadzone, applied before summing in body-height
mode. The YunZhuo body-height path does not apply a second deadzone to the sum, so
right-stick yaw starts continuously after 15% (not an enlarged 18.4% threshold).
The neutral interlock also checks raw stick X and CH14 independently, so a held
small X input or cancellation between yaw sources cannot arm movement. Other
controller types keep their existing downstream deadzone. Both axes
remain usable together: deliberate or accidental X beyond the threshold can turn
while Y changes height. This deadzone reduces cross-axis contamination, not eliminates it.

E17K height bounds/default/rate remain 0.20–0.46m / 0.41m / 0.08m/s for the physical
height integrator. Velocity bounds remain vx +/-0.5m/s, vy +/-0.3m/s, yaw +/-0.3rad/s.
V2/V5 profiles, all model weights/gains, normal-service shaping and CH14 sign are
unchanged. Equal control meanings do NOT imply equal speed limits or state-transition
timing: production retains its settle-before-standing path; body-height retains its
existing policy takeover and safety gates.

## Enable and switches

H must be seen low before high. After 150ms loss of valid frames, enable is revoked;
returning H high is not enough. Hardware confirmation is still required. Motion
input must return neutral after each confirmed-enable generation; prior input is
discarded, not queued. Height input has its existing separate neutral interlock.

L1/L2/R1: after hardware enable confirmation, the first received switch level only
sets a baseline. Each later new change in either direction emits once; repeated
same-level frames do nothing. Changes while disabled/pending and the first frame
after a gap are not replayed. This is a switch-edge rule: if a physical control
springs back, both transitions count, so verify the actual transmitter assignment
with the hardware disabled. R1 cancels any pending height takeover before requesting
standUp; it does not set height back to 0.41m. The existing later policy-takeover
default initialization remains a separate operation and was not changed.

Red fires on a new pressed level, including a first frame already pressed; release
does not fire. This is software disabling, not an independent hardware emergency stop.
G/S, calibration combinations, arm-mode routing and the gRPC interface are unchanged.
Do not use calibration combinations as motion controls. Offline mock tests do not
certify real motors, transmitter polarity, balance or hardware stopping performance.
