# PiPER teleop systemd configuration (S100P)

These templates only configure the machine-dog side of the authenticated UDP
bridge. They do not replace `han_dog.service` or its existing policy drop-in.
Do not enable them until the S100P Wi-Fi address and the S100 allowlist have
been confirmed on the real network.

1. Generate and install a unique key on the S100P without printing it. The
   service runs as `bsrl1`, so use ownership `root:bsrl1` and mode `0640`; the
   directory must be traversable by that group:

   ```sh
   sudo install -d -o root -g bsrl1 -m 0750 /etc/han_dog
   openssl rand -hex 32 | sudo tee /etc/han_dog/arm-teleop.key >/dev/null
   sudo chown root:bsrl1 /etc/han_dog/arm-teleop.key
   sudo chmod 0640 /etc/han_dog/arm-teleop.key
   ```

   The file contains only the key followed by an optional newline—never an
   `NAME=value` assignment. `HAN_DOG_ARM_TELEOP_SECRET_FILE` is read once at
   process startup and whitespace is trimmed. A missing, unreadable, or empty
   configured file disables the bridge without falling back to another secret.

2. Copy `40-arm-teleop.conf.example` to
   `/etc/systemd/system/han_dog.service.d/40-arm-teleop.conf`. Keep the existing
   `30-policy1119.conf` unchanged. Adjust `HAN_DOG_ARM_TELEOP_HOST` only if the
   mechanical-arm S100 is no longer `192.168.66.65`.

3. After the mechanical arm is fixed to its base and both services have passed
   safe read-only tests, run `systemctl daemon-reload` and restart
   `han_dog.service`. The bridge binds UDP `14601` for signed status ACKs and
   sends signed controls to S100 UDP `14600`.

The bridge is fail-closed: missing, unreadable, empty, short, or obvious
placeholder secrets leave the arm bridge disabled while the original
machine-dog controller continues to start. No real secret or machine-dog IP is
stored in these templates. `HAN_DOG_ARM_TELEOP_SECRET` remains supported only
for compatibility when `HAN_DOG_ARM_TELEOP_SECRET_FILE` is not configured;
new deployments must use the key file.

Protocol v1 signs integer-only canonical JSON. Stick axes use signed
`lx_ppm`/`ly_ppm`/`rx_ppm`/`ry_ppm` millionths, and the gripper ACK uses
`gripper_width_um`; floating-point values are rejected before HMAC processing.
