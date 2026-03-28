from __future__ import annotations

import argparse
import csv
import math
import random
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
NAV_GATEWAY_SRC = REPO_ROOT / "products" / "nova-dog" / "runtime" / "services" / "nav-gateway" / "src"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
if str(NAV_GATEWAY_SRC) not in sys.path:
    sys.path.insert(0, str(NAV_GATEWAY_SRC))

from odor_cfd_turbulence_demo import (  # noqa: E402
    OdorSeekPolicy,
    SensorChannel,
    TurbulentPlumeCFD,
    Vec2,
    clamp,
    make_sensors,
    wrap_angle,
)
from nova_dog_nav_gateway.api import create_app  # noqa: E402
from nova_dog_nav_gateway.service import NavGatewayService  # noqa: E402


@dataclass
class RecordingLingTuBridge:
    mode_requests: list[int]
    navigation_requests: list[dict[str, Any]]
    cancel_requests: list[str]
    tracked_modes: dict[str, str]
    _task_counter: int = 0

    def __init__(self) -> None:
        self.mode_requests = []
        self.navigation_requests = []
        self.cancel_requests = []
        self.tracked_modes = {}
        self._task_counter = 0

    def ensure_mode(self, mode: int):
        self.mode_requests.append(mode)
        return True, "autonomous" if mode == 4 else "mapping"

    def start_navigation(self, mission_id: str, waypoints: list[dict[str, Any]], **kwargs):
        self._task_counter += 1
        task_id = f"task-{self._task_counter:03d}"
        self.navigation_requests.append(
            {
                "mission_id": mission_id,
                "task_id": task_id,
                "waypoints": waypoints,
                "kwargs": kwargs,
            }
        )
        return task_id

    def cancel_task(self, mission_id: str) -> bool:
        self.cancel_requests.append(mission_id)
        return True

    def pause_task(self, mission_id: str) -> bool:
        del mission_id
        return True

    def resume_task(self, mission_id: str) -> bool:
        del mission_id
        return True

    def set_tracked_mode(self, mission_id: str, provider_mode: str) -> None:
        self.tracked_modes[mission_id] = provider_mode


class RollingTargetPlanner:
    def __init__(self) -> None:
        self.policy = OdorSeekPolicy()

    def compute_goal(
        self,
        *,
        position: Vec2,
        yaw: float,
        sensors: list[SensorChannel],
        local_wind: Vec2,
        now_s: float,
        dt: float,
        width_m: float,
        height_m: float,
    ) -> tuple[dict[str, float], dict[str, float | str]]:
        speed, yaw_rate, strength, g_x, g_y = self.policy.step(
            sensors,
            now_s,
            dt,
            yaw=yaw,
            local_wind=local_wind,
        )
        horizon_s = 1.15 if self.policy.mode == "track" else 0.85
        goal_heading = yaw + yaw_rate * horizon_s
        goal_distance = clamp(speed * (2.0 if self.policy.mode == "track" else 1.6), 0.45, 0.95)
        goal = {
            "x": clamp(position.x + goal_distance * math.cos(goal_heading), 0.0, width_m),
            "y": clamp(position.y + goal_distance * math.sin(goal_heading), 0.0, height_m),
            "yaw": goal_heading,
            "arrival_radius": 0.28 if self.policy.mode == "track" else 0.38,
        }
        metrics = {
            "mode": self.policy.mode,
            "strength": strength,
            "g_x": g_x,
            "g_y": g_y,
            "speed": speed,
            "yaw_rate": yaw_rate,
        }
        return goal, metrics


def step_goal_follower(
    *,
    position: Vec2,
    yaw: float,
    goal: dict[str, float],
    dt: float,
    max_speed: float,
    width_m: float,
    height_m: float,
) -> tuple[Vec2, float]:
    dx = goal["x"] - position.x
    dy = goal["y"] - position.y
    distance = math.hypot(dx, dy)
    if distance < 1e-6:
        return position, yaw

    desired_heading = math.atan2(dy, dx)
    heading_error = wrap_angle(desired_heading - yaw)
    yaw_rate = clamp(2.3 * heading_error, -1.2, 1.2)
    yaw = wrap_angle(yaw + yaw_rate * dt)

    speed_scale = clamp(1.0 - abs(heading_error) / 1.8, 0.22, 1.0)
    speed = min(max_speed, distance * 1.2) * speed_scale
    new_position = Vec2(
        clamp(position.x + speed * math.cos(yaw) * dt, 0.0, width_m),
        clamp(position.y + speed * math.sin(yaw) * dt, 0.0, height_m),
    )
    return new_position, yaw


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def render_summary(
    *,
    cfd: TurbulentPlumeCFD,
    history_rows: list[dict[str, str]],
    retarget_rows: list[dict[str, str]],
    source_xy: Vec2,
    success_radius: float,
    output_path: Path,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    if not history_rows:
        return

    fig, (ax_field, ax_distance) = plt.subplots(1, 2, figsize=(12.5, 4.8), dpi=160)

    xs = [float(row["robot_x_m"]) for row in history_rows]
    ys = [float(row["robot_y_m"]) for row in history_rows]
    times = [float(row["time_s"]) for row in history_rows]
    distances = [float(row["distance_to_source_m"]) for row in history_rows]

    wind_u, wind_v = cfd.velocity_field(times[-1])
    image = ax_field.imshow(
        cfd.concentration,
        origin="lower",
        extent=[cfd.x[0], cfd.x[-1], cfd.y[0], cfd.y[-1]],
        cmap="YlOrRd",
        aspect="auto",
        alpha=0.9,
    )
    ax_field.quiver(
        cfd.x[::12],
        cfd.y[::10],
        wind_u[::10, ::12],
        wind_v[::10, ::12],
        color="#1c7ed6",
        alpha=0.52,
        scale=9.0,
        width=0.0035,
    )
    ax_field.plot(xs, ys, color="#0b7285", linewidth=2.4, label="robot path")
    ax_field.scatter([xs[0]], [ys[0]], color="#f08c00", s=32, label="start", zorder=4)
    ax_field.scatter([source_xy.x], [source_xy.y], color="#c92a2a", s=42, label="source", zorder=4)
    ax_field.add_patch(
        plt.Circle(
            (source_xy.x, source_xy.y),
            success_radius,
            fill=False,
            linestyle="--",
            color="#c92a2a",
            linewidth=1.1,
            alpha=0.72,
        )
    )

    for index, retarget in enumerate(retarget_rows, 1):
        goal_x = float(retarget["goal_x_m"])
        goal_y = float(retarget["goal_y_m"])
        ax_field.scatter([goal_x], [goal_y], color="#111111", s=18, zorder=5)
        if index <= 10:
            ax_field.text(goal_x + 0.03, goal_y + 0.03, str(index), fontsize=8, color="#111111")

    ax_field.set_title("Rolling odor targets sent through nav-gateway")
    ax_field.set_xlabel("x (m)")
    ax_field.set_ylabel("y (m)")
    ax_field.grid(True, alpha=0.12)
    ax_field.legend(loc="upper left")
    fig.colorbar(image, ax=ax_field, fraction=0.046, pad=0.04, label="odor concentration")

    ax_distance.plot(times, distances, color="#2b8a3e", linewidth=2.2)
    ax_distance.axhline(success_radius, color="#c92a2a", linestyle="--", linewidth=1.1)
    for retarget in retarget_rows:
        ax_distance.axvline(float(retarget["time_s"]), color="#495057", alpha=0.18, linewidth=0.9)
    ax_distance.set_title("Distance to source with retarget events")
    ax_distance.set_xlabel("time (s)")
    ax_distance.set_ylabel("distance (m)")
    ax_distance.grid(True, alpha=0.25)

    text_rows = retarget_rows[-6:]
    if text_rows:
        summary_lines = [
            f"retargets = {len(retarget_rows)}",
            f"last task = {text_rows[-1]['provider_task_id']}",
        ]
        for item in text_rows:
            summary_lines.append(
                f"t={float(item['time_s']):>4.1f}s -> {item['provider_task_id']} "
                f"({float(item['goal_x_m']):.2f},{float(item['goal_y_m']):.2f})"
            )
        ax_distance.text(
            0.03,
            0.97,
            "\n".join(summary_lines),
            transform=ax_distance.transAxes,
            va="top",
            ha="left",
            fontsize=9,
            bbox={"boxstyle": "round,pad=0.35", "facecolor": "white", "alpha": 0.86, "edgecolor": "#cccccc"},
        )

    fig.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path)
    plt.close(fig)


def render_gif(
    *,
    gif_frames: list[dict[str, object]],
    history_rows: list[dict[str, str]],
    retarget_rows: list[dict[str, str]],
    source_xy: Vec2,
    success_radius: float,
    output_path: Path,
) -> bool:
    try:
        import imageio.v2 as imageio
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception:
        return False

    if not gif_frames or not history_rows:
        return False

    xs = [float(row["robot_x_m"]) for row in history_rows]
    ys = [float(row["robot_y_m"]) for row in history_rows]
    yaws = [math.radians(float(row["robot_yaw_deg"])) for row in history_rows]
    distances = [float(row["distance_to_source_m"]) for row in history_rows]
    times = [float(row["time_s"]) for row in history_rows]

    retarget_times = [float(row["time_s"]) for row in retarget_rows]
    retarget_xs = [float(row["goal_x_m"]) for row in retarget_rows]
    retarget_ys = [float(row["goal_y_m"]) for row in retarget_rows]

    x_coords = gif_frames[0]["x_coords"]
    y_coords = gif_frames[0]["y_coords"]
    max_concentration = max(float(np.max(frame["concentration"])) for frame in gif_frames)
    frames: list[np.ndarray] = []

    for frame in gif_frames:
        path_count = int(frame["path_count"])
        time_s = float(frame["time_s"])
        field = frame["concentration"]
        wind_u = frame["wind_u"]
        wind_v = frame["wind_v"]
        retarget_count = int(frame["retarget_count"])
        current = history_rows[path_count - 1]

        fig, (ax_field, ax_info) = plt.subplots(
            1,
            2,
            figsize=(10.8, 4.6),
            dpi=120,
            gridspec_kw={"width_ratios": [1.45, 1.0]},
        )

        ax_field.imshow(
            field,
            origin="lower",
            extent=[x_coords[0], x_coords[-1], y_coords[0], y_coords[-1]],
            cmap="YlOrRd",
            aspect="auto",
            alpha=0.92,
            vmin=0.0,
            vmax=max(max_concentration, 1e-6),
        )
        ax_field.quiver(
            x_coords[::12],
            y_coords[::10],
            wind_u[::10, ::12],
            wind_v[::10, ::12],
            color="#1c7ed6",
            alpha=0.52,
            scale=9.0,
            width=0.0035,
        )
        ax_field.plot(xs[:path_count], ys[:path_count], color="#0b7285", linewidth=2.5)
        ax_field.scatter([xs[0]], [ys[0]], color="#f08c00", s=34, zorder=4)
        ax_field.scatter([source_xy.x], [source_xy.y], color="#c92a2a", s=44, zorder=4)
        ax_field.add_patch(
            plt.Circle(
                (source_xy.x, source_xy.y),
                success_radius,
                fill=False,
                linestyle="--",
                color="#c92a2a",
                linewidth=1.2,
                alpha=0.72,
            )
        )

        # Plot rolling targets up to current time
        for rt_idx in range(retarget_count):
            ax_field.scatter(
                [retarget_xs[rt_idx]], [retarget_ys[rt_idx]],
                color="#111111", s=18, zorder=5,
            )
            # Label recent targets with index numbers
            if rt_idx >= max(0, retarget_count - 10):
                ax_field.text(
                    retarget_xs[rt_idx] + 0.03,
                    retarget_ys[rt_idx] + 0.03,
                    str(rt_idx + 1),
                    fontsize=7,
                    color="#111111",
                )

        robot_x = xs[path_count - 1]
        robot_y = ys[path_count - 1]
        robot_yaw = yaws[path_count - 1]
        ax_field.scatter(
            [robot_x], [robot_y], s=74, facecolors="none",
            edgecolors="#111111", linewidths=1.8, zorder=5,
        )
        ax_field.arrow(
            robot_x,
            robot_y,
            0.32 * math.cos(robot_yaw),
            0.32 * math.sin(robot_yaw),
            width=0.015,
            head_width=0.11,
            head_length=0.14,
            color="#111111",
            length_includes_head=True,
            zorder=5,
        )
        ax_field.set_title("Rolling odor targets through nav-gateway")
        ax_field.set_xlabel("x (m)")
        ax_field.set_ylabel("y (m)")
        ax_field.grid(True, alpha=0.12)

        # Right panel: distance curve
        ax_info.plot(times[:path_count], distances[:path_count], color="#2b8a3e", linewidth=2.2)
        ax_info.axhline(success_radius, color="#c92a2a", linestyle="--", linewidth=1.2)
        for rt_time in retarget_times[:retarget_count]:
            ax_info.axvline(rt_time, color="#495057", alpha=0.18, linewidth=0.9)
        ax_info.set_xlim(times[0], times[-1])
        ax_info.set_ylim(0.0, max(distances) * 1.05)
        ax_info.set_title("Distance to source")
        ax_info.set_xlabel("time (s)")
        ax_info.set_ylabel("distance (m)")
        ax_info.grid(True, alpha=0.24)

        info_text = (
            f"t = {time_s:.1f}s\n"
            f"mode = {current['odor_mode']}\n"
            f"distance = {current['distance_to_source_m']} m\n"
            f"FL/FR = {float(current['fl_delta']):.1f} / {float(current['fr_delta']):.1f}\n"
            f"RL/RR = {float(current['rl_delta']):.1f} / {float(current['rr_delta']):.1f}\n"
            f"retargets = {retarget_count}"
        )
        ax_info.text(
            0.04,
            0.96,
            info_text,
            transform=ax_info.transAxes,
            va="top",
            ha="left",
            fontsize=10,
            bbox={"boxstyle": "round,pad=0.35", "facecolor": "white", "alpha": 0.86, "edgecolor": "#cccccc"},
        )

        fig.tight_layout()
        fig.canvas.draw()
        width, height = fig.canvas.get_width_height()
        frame_rgb = np.frombuffer(fig.canvas.buffer_rgba(), dtype=np.uint8).reshape(height, width, 4)[..., :3].copy()
        frames.append(frame_rgb)
        plt.close(fig)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    imageio.mimsave(output_path, frames, duration=0.10, loop=0)
    return True


def render_storyboard(
    *,
    plume_snapshots: list[dict[str, object]],
    history_rows: list[dict[str, str]],
    retarget_rows: list[dict[str, str]],
    source_xy: Vec2,
    success_radius: float,
    output_path: Path,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    if len(plume_snapshots) < 4 or not history_rows:
        return

    xs = [float(row["robot_x_m"]) for row in history_rows]
    ys = [float(row["robot_y_m"]) for row in history_rows]
    yaws = [math.radians(float(row["robot_yaw_deg"])) for row in history_rows]

    retarget_xs = [float(row["goal_x_m"]) for row in retarget_rows]
    retarget_ys = [float(row["goal_y_m"]) for row in retarget_rows]

    stage_labels = [
        "1. Odor planner initializes",
        "2. First rolling targets sent",
        "3. Tracking and retargeting",
        "4. Reaching source area",
    ]

    fig, axes = plt.subplots(2, 2, figsize=(12, 8), dpi=160)
    for ax, snapshot, label in zip(axes.flat, plume_snapshots[:4], stage_labels):
        field = snapshot["concentration"]
        path_count = int(snapshot["path_count"])
        x_coords = snapshot["x_coords"]
        y_coords = snapshot["y_coords"]
        wind_u = snapshot["wind_u"]
        wind_v = snapshot["wind_v"]
        time_s = float(snapshot["time_s"])
        retarget_count = int(snapshot["retarget_count"])

        image = ax.imshow(
            field,
            origin="lower",
            extent=[x_coords[0], x_coords[-1], y_coords[0], y_coords[-1]],
            cmap="YlOrRd",
            aspect="auto",
            alpha=0.9,
        )
        ax.quiver(
            x_coords[::12],
            y_coords[::10],
            wind_u[::10, ::12],
            wind_v[::10, ::12],
            color="#1c7ed6",
            alpha=0.55,
            scale=9.0,
            width=0.0035,
        )
        ax.plot(xs[:path_count], ys[:path_count], color="#0b7285", linewidth=2.6)
        ax.scatter([xs[0]], [ys[0]], color="#f08c00", s=34, zorder=4)
        ax.scatter([source_xy.x], [source_xy.y], color="#c92a2a", s=42, zorder=4)
        ax.add_patch(
            plt.Circle(
                (source_xy.x, source_xy.y),
                success_radius,
                fill=False,
                linestyle="--",
                color="#c92a2a",
                linewidth=1.1,
                alpha=0.72,
            )
        )

        # Plot rolling targets up to this snapshot's time
        for rt_idx in range(retarget_count):
            ax.scatter(
                [retarget_xs[rt_idx]], [retarget_ys[rt_idx]],
                color="#111111", s=18, zorder=5,
            )
            if rt_idx >= max(0, retarget_count - 10):
                ax.text(
                    retarget_xs[rt_idx] + 0.03,
                    retarget_ys[rt_idx] + 0.03,
                    str(rt_idx + 1),
                    fontsize=7,
                    color="#111111",
                )

        robot_x = xs[path_count - 1]
        robot_y = ys[path_count - 1]
        robot_yaw = yaws[path_count - 1]
        ax.scatter(
            [robot_x], [robot_y], s=74, facecolors="none",
            edgecolors="#111111", linewidths=1.8, zorder=5,
        )
        ax.arrow(
            robot_x,
            robot_y,
            0.32 * math.cos(robot_yaw),
            0.32 * math.sin(robot_yaw),
            width=0.015,
            head_width=0.11,
            head_length=0.14,
            color="#111111",
            length_includes_head=True,
            zorder=5,
        )
        ax.text(
            0.03,
            0.96,
            f"{label}\nt = {time_s:.1f}s  retargets = {retarget_count}",
            transform=ax.transAxes,
            va="top",
            ha="left",
            fontsize=10,
            bbox={"boxstyle": "round,pad=0.28", "facecolor": "white", "alpha": 0.82, "edgecolor": "#cccccc"},
        )
        ax.set_xlabel("x (m)")
        ax.set_ylabel("y (m)")
        ax.grid(True, alpha=0.12)
        fig.colorbar(image, ax=ax, fraction=0.046, pad=0.04)

    fig.suptitle("Nav-gateway retarget storyboard: rolling odor-seek targets", fontsize=14)
    fig.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path)
    plt.close(fig)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Drive rolling odor-seek targets through nav-gateway into a LingTu bridge stub.")
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--steps", type=int, default=340)
    parser.add_argument("--dt", type=float, default=0.05)
    parser.add_argument("--width-m", type=float, default=6.0)
    parser.add_argument("--height-m", type=float, default=2.4)
    parser.add_argument("--grid-x", type=int, default=180)
    parser.add_argument("--grid-y", type=int, default=96)
    parser.add_argument("--start-x", type=float, default=0.75)
    parser.add_argument("--start-y", type=float, default=0.85)
    parser.add_argument("--start-yaw-deg", type=float, default=0.0)
    parser.add_argument("--source-x", type=float, default=5.0)
    parser.add_argument("--source-y", type=float, default=1.2)
    parser.add_argument("--wind-heading-deg", type=float, default=180.0)
    parser.add_argument("--wind-speed", type=float, default=0.62)
    parser.add_argument("--retarget-period-s", type=float, default=0.70)
    parser.add_argument("--success-radius", type=float, default=0.45)
    parser.add_argument("--summary", type=Path, default=SCRIPT_DIR / "output" / "odor_nav_gateway_retarget_demo.png")
    parser.add_argument("--gif", type=Path, default=SCRIPT_DIR / "output" / "odor_nav_gateway_retarget_demo.gif")
    parser.add_argument("--storyboard", type=Path, default=SCRIPT_DIR / "output" / "odor_nav_gateway_retarget_storyboard.png")
    parser.add_argument("--csv", type=Path, default=SCRIPT_DIR / "output" / "odor_nav_gateway_retarget_demo.csv")
    parser.add_argument("--retarget-csv", type=Path, default=SCRIPT_DIR / "output" / "odor_nav_gateway_retarget_events.csv")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    random.seed(args.seed)
    np.random.seed(args.seed)

    bridge = RecordingLingTuBridge()
    service = NavGatewayService(lingtu_bridge=bridge)
    app = create_app(service=service)
    client = app.test_client()

    source_xy = Vec2(args.source_x, args.source_y)
    cfd = TurbulentPlumeCFD(
        width_m=args.width_m,
        height_m=args.height_m,
        nx=args.grid_x,
        ny=args.grid_y,
        dt=args.dt,
        source_xy=source_xy,
        wind_heading_deg=args.wind_heading_deg,
        wind_speed=args.wind_speed,
        diffusion=0.0018,
        decay=0.030,
        source_rate=0.62,
        source_sigma=0.11,
    )
    sensors = make_sensors()
    planner = RollingTargetPlanner()

    position = Vec2(args.start_x, args.start_y)
    yaw = math.radians(args.start_yaw_deg)
    current_goal: dict[str, float] | None = None
    next_retarget_s = 0.0
    mission_id = "odor-demo-001"

    history_rows: list[dict[str, str]] = []
    retarget_rows: list[dict[str, str]] = []
    gif_frames: list[dict[str, object]] = []
    snapshot_candidates: list[dict[str, object]] = []
    reached_at: float | None = None
    min_distance = float("inf")

    for step in range(args.steps):
        now_s = step * args.dt
        cfd.step(now_s)
        local_u, local_v = cfd.sample_velocity(position.x, position.y, now_s)

        for sensor in sensors:
            offset_world = sensor.offset_body_xy.rotated(yaw)
            concentration = cfd.sample(
                clamp(position.x + offset_world.x, 0.0, args.width_m),
                clamp(position.y + offset_world.y, 0.0, args.height_m),
            )
            sensor.step(concentration, args.dt, planner.policy.drift_sigma)

        if now_s >= next_retarget_s:
            goal_pose, metrics = planner.compute_goal(
                position=position,
                yaw=yaw,
                sensors=sensors,
                local_wind=Vec2(local_u, local_v),
                now_s=now_s,
                dt=args.dt,
                width_m=args.width_m,
                height_m=args.height_m,
            )
            if current_goal is None:
                response = client.post(
                    "/api/v1/navigation/dispatch",
                    json={
                        "mission_id": mission_id,
                        "mission_type": "odor_seek",
                        "requested_capability": "nav.odor.seek",
                        "parameters": {
                            "goal_pose": goal_pose,
                            "max_speed": 0.45,
                        },
                    },
                    headers={"X-Service-Name": "odor-planner"},
                )
            else:
                response = client.patch(
                    f"/api/v1/navigation/sessions/{mission_id}/target",
                    json={
                        "goal_pose": goal_pose,
                        "parameters": {
                            "max_speed": 0.45,
                        },
                    },
                    headers={"X-Service-Name": "odor-planner"},
                )
            if response.status_code not in (200, 201):
                raise RuntimeError(f"nav-gateway request failed: {response.status_code} {response.json}")

            session = response.json["session"]
            current_goal = session["goal_pose"] or goal_pose
            provider_task_id = session.get("provider_task_id") or ""
            if provider_task_id:
                client.patch(
                    f"/api/v1/navigation/sessions/{mission_id}/provider",
                    json={
                        "provider": "lingtu",
                        "provider_task_id": provider_task_id,
                        "provider_status": "running",
                        "provider_mode": "autonomous",
                    },
                    headers={"X-Service-Name": "lingtu-sidecar"},
                )
            retarget_rows.append(
                {
                    "time_s": f"{now_s:.2f}",
                    "goal_x_m": f"{current_goal['x']:.4f}",
                    "goal_y_m": f"{current_goal['y']:.4f}",
                    "goal_yaw_rad": f"{current_goal['yaw']:.4f}",
                    "mode": str(metrics["mode"]),
                    "strength": f"{float(metrics['strength']):.4f}",
                    "provider_task_id": provider_task_id,
                }
            )
            next_retarget_s = now_s + args.retarget_period_s

        if current_goal is not None:
            position, yaw = step_goal_follower(
                position=position,
                yaw=yaw,
                goal=current_goal,
                dt=args.dt,
                max_speed=0.45,
                width_m=args.width_m,
                height_m=args.height_m,
            )

        distance = math.hypot(position.x - source_xy.x, position.y - source_xy.y)
        min_distance = min(min_distance, distance)
        if reached_at is None and distance <= args.success_radius:
            reached_at = now_s

        row = {
            "time_s": f"{now_s:.2f}",
            "robot_x_m": f"{position.x:.4f}",
            "robot_y_m": f"{position.y:.4f}",
            "robot_yaw_deg": f"{math.degrees(yaw):.2f}",
            "distance_to_source_m": f"{distance:.4f}",
            "goal_x_m": f"{current_goal['x']:.4f}" if current_goal is not None else "",
            "goal_y_m": f"{current_goal['y']:.4f}" if current_goal is not None else "",
            "provider_task_id": retarget_rows[-1]["provider_task_id"] if retarget_rows else "",
            "odor_mode": planner.policy.mode,
        }
        for sensor in sensors:
            row[f"{sensor.name}_delta"] = f"{sensor.delta_value:.4f}"
        history_rows.append(row)

        if step % 6 == 0 or step == args.steps - 1:
            wind_u, wind_v = cfd.velocity_field(now_s)
            gif_frames.append({
                "time_s": now_s,
                "path_count": len(history_rows),
                "concentration": cfd.concentration.astype(np.float32).copy(),
                "x_coords": cfd.x.copy(),
                "y_coords": cfd.y.copy(),
                "wind_u": wind_u.astype(np.float32).copy(),
                "wind_v": wind_v.astype(np.float32).copy(),
                "retarget_count": len(retarget_rows),
            })
        if step % 24 == 0 or step == args.steps - 1:
            wind_u_snap, wind_v_snap = cfd.velocity_field(now_s)
            snapshot_candidates.append({
                "time_s": now_s,
                "path_count": len(history_rows),
                "concentration": cfd.concentration.copy(),
                "x_coords": cfd.x.copy(),
                "y_coords": cfd.y.copy(),
                "wind_u": wind_u_snap.copy(),
                "wind_v": wind_v_snap.copy(),
                "retarget_count": len(retarget_rows),
            })

        if reached_at is not None and now_s >= reached_at + 1.2:
            break

    write_csv(args.csv, history_rows)
    write_csv(args.retarget_csv, retarget_rows)
    render_summary(
        cfd=cfd,
        history_rows=history_rows,
        retarget_rows=retarget_rows,
        source_xy=source_xy,
        success_radius=args.success_radius,
        output_path=args.summary,
    )

    # Select 4 storyboard snapshots
    if snapshot_candidates:
        sample_count = min(4, len(snapshot_candidates))
        sample_indices = np.linspace(0, len(snapshot_candidates) - 1, sample_count, dtype=int)
        plume_snapshots = [snapshot_candidates[int(i)] for i in sample_indices]
    else:
        plume_snapshots = []

    render_storyboard(
        plume_snapshots=plume_snapshots,
        history_rows=history_rows,
        retarget_rows=retarget_rows,
        source_xy=source_xy,
        success_radius=args.success_radius,
        output_path=args.storyboard,
    )

    gif_written = render_gif(
        gif_frames=gif_frames,
        history_rows=history_rows,
        retarget_rows=retarget_rows,
        source_xy=source_xy,
        success_radius=args.success_radius,
        output_path=args.gif,
    )

    print(f"summary={args.summary}")
    if gif_written:
        print(f"gif={args.gif}")
    print(f"storyboard={args.storyboard}")
    print(f"csv={args.csv}")
    print(f"retarget_csv={args.retarget_csv}")
    print(f"reached_source={str(reached_at is not None).lower()}")
    if reached_at is not None:
        print(f"reached_at_s={reached_at:.2f}")
    print(f"min_distance_m={min_distance:.3f}")
    print(f"retarget_count={len(retarget_rows)}")
    print(f"lingtu_start_count={len(bridge.navigation_requests)}")
    print(f"lingtu_cancel_count={len(bridge.cancel_requests)}")
    if bridge.navigation_requests:
        print(f"last_task_id={bridge.navigation_requests[-1]['task_id']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
