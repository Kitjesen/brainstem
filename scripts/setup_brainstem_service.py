"""
SSH to sunrise robot and set up brainstem.service systemd unit.
Steps:
  1. Compile han_dog binary
  2. Create systemd service file
  3. daemon-reload
  4. Verify with systemd-analyze
"""

import paramiko
import sys
import time

HOST = "192.168.66.192"
PORT = 2020
USER = "sunrise"
PASSWORD = "sunrise"

def ssh_exec(client: paramiko.SSHClient, cmd: str, timeout: int = 300) -> tuple[int, str, str]:
    """Execute command and return (exit_code, stdout, stderr)."""
    print(f"\n>>> {cmd}")
    stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    if out.strip():
        print(out.rstrip())
    if err.strip():
        print(f"[stderr] {err.rstrip()}")
    print(f"[exit {exit_code}]")
    return exit_code, out, err


SERVICE_CONTENT = """\
[Unit]
Description=Brainstem Han Dog Control Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=sunrise
Group=sunrise

WorkingDirectory=/home/sunrise/Desktop/brainstem

# Wait for USB/CAN devices to be ready
ExecStartPre=/bin/sleep 30

ExecStart=/home/sunrise/Desktop/brainstem/build/han_dog

# PCAN native library
Environment="LD_PRELOAD=/usr/lib/libpcanbasic.so"
# Dart / ONNX model path
Environment="HAN_DOG_MODEL_PATH=/home/sunrise/Desktop/brainstem/model/policy_260106.onnx"
# Profiles directory
Environment="HAN_DOG_PROFILE_DIR=/home/sunrise/Desktop/brainstem/han_dog/profiles"

Restart=on-failure
RestartSec=5

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=brainstem

[Install]
WantedBy=multi-user.target
"""


def main():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    print(f"Connecting to {USER}@{HOST}:{PORT} ...")
    try:
        client.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=15)
    except Exception as e:
        print(f"SSH connection failed: {e}")
        sys.exit(1)
    print("Connected.\n")

    # ── Step 0: Check current state ──────────────────────────────
    print("=" * 60)
    print("Step 0: Check environment")
    print("=" * 60)
    ssh_exec(client, "/usr/local/dart-sdk/bin/dart --version")
    ssh_exec(client, "ls -la /home/sunrise/Desktop/brainstem/han_dog/bin/han_dog.dart")
    ssh_exec(client, "ls -la /usr/lib/libpcanbasic.so")
    ssh_exec(client, "ls -la /home/sunrise/Desktop/brainstem/model/policy_260106.onnx")

    # ── Step 1: Create build directory & compile ─────────────────
    print("\n" + "=" * 60)
    print("Step 1: Compile han_dog binary")
    print("=" * 60)
    ssh_exec(client, "mkdir -p /home/sunrise/Desktop/brainstem/build")

    exit_code, out, err = ssh_exec(
        client,
        "cd /home/sunrise/Desktop/brainstem && "
        "/usr/local/dart-sdk/bin/dart compile exe "
        "han_dog/bin/han_dog.dart "
        "-o /home/sunrise/Desktop/brainstem/build/han_dog",
        timeout=600,  # compilation can take a while on ARM
    )
    if exit_code != 0:
        print("\nERROR: Compilation failed. Aborting.")
        client.close()
        sys.exit(1)

    ssh_exec(client, "ls -lh /home/sunrise/Desktop/brainstem/build/han_dog")

    # ── Step 2: Write systemd service file ───────────────────────
    print("\n" + "=" * 60)
    print("Step 2: Create brainstem.service")
    print("=" * 60)

    # Write to a temp file first, then sudo mv
    escaped = SERVICE_CONTENT.replace("'", "'\\''")
    ssh_exec(
        client,
        f"cat > /tmp/brainstem.service << 'HEREDOC'\n{SERVICE_CONTENT}HEREDOC",
    )
    ssh_exec(client, "cat /tmp/brainstem.service")

    # Copy to systemd directory with sudo
    exit_code, _, _ = ssh_exec(
        client,
        f"echo '{PASSWORD}' | sudo -S cp /tmp/brainstem.service /etc/systemd/system/brainstem.service",
    )
    if exit_code != 0:
        print("ERROR: Failed to copy service file.")
        client.close()
        sys.exit(1)

    ssh_exec(
        client,
        f"echo '{PASSWORD}' | sudo -S chmod 644 /etc/systemd/system/brainstem.service",
    )

    # ── Step 3: daemon-reload ────────────────────────────────────
    print("\n" + "=" * 60)
    print("Step 3: systemctl daemon-reload")
    print("=" * 60)
    ssh_exec(
        client,
        f"echo '{PASSWORD}' | sudo -S systemctl daemon-reload",
    )

    # ── Step 4: Verify service file ──────────────────────────────
    print("\n" + "=" * 60)
    print("Step 4: Verify service file")
    print("=" * 60)
    ssh_exec(
        client,
        f"echo '{PASSWORD}' | sudo -S systemd-analyze verify /etc/systemd/system/brainstem.service",
    )

    # Show the installed service status (should be inactive/disabled)
    ssh_exec(client, "systemctl status brainstem.service || true")

    # Also confirm old service is still disabled
    ssh_exec(client, "systemctl is-enabled han_dog.service 2>/dev/null || echo 'han_dog.service not found or disabled'")

    # ── Done ─────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("DONE. brainstem.service is installed but NOT enabled/started.")
    print("When ready, run:")
    print("  sudo systemctl enable brainstem.service")
    print("  sudo systemctl start brainstem.service")
    print("=" * 60)

    client.close()


if __name__ == "__main__":
    main()
