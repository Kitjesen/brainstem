from __future__ import annotations

import argparse
import csv
import math
import random
from dataclasses import dataclass
from pathlib import Path

import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def wrap_angle(angle: float) -> float:
    return math.atan2(math.sin(angle), math.cos(angle))


@dataclass(frozen=True)
class Vec2:
    x: float
    y: float

    def rotated(self, yaw: float) -> "Vec2":
        c = math.cos(yaw)
        s = math.sin(yaw)
        return Vec2(c * self.x - s * self.y, s * self.x + c * self.y)


@dataclass
class SensorChannel:
    name: str
    offset_body_xy: Vec2
    gain: float
    bias: float
    tau_s: float
    noise_sigma: float
    baseline_tau_s: float
    raw_value: float = 0.0
    filtered_value: float = 0.0
    baseline_value: float = 0.0
    delta_value: float = 0.0
    slope_value: float = 0.0
    drift_value: float = 0.0
    _prev_delta: float = 0.0

    def step(self, concentration: float, dt: float, drift_sigma: float) -> None:
        self.drift_value += random.gauss(0.0, drift_sigma * math.sqrt(dt))
        target = self.bias + self.gain * concentration + self.drift_value
        self.raw_value += clamp(dt / self.tau_s, 0.0, 1.0) * (target - self.raw_value)
        self.raw_value += random.gauss(0.0, self.noise_sigma)
        self.filtered_value += 0.42 * (self.raw_value - self.filtered_value)

        baseline_alpha = clamp(dt / self.baseline_tau_s, 0.0, 1.0)
        if self.filtered_value > self.baseline_value + 0.8:
            baseline_alpha *= 0.18
        self.baseline_value += baseline_alpha * (self.filtered_value - self.baseline_value)

        self.delta_value = self.filtered_value - self.baseline_value
        self.slope_value = (self.delta_value - self._prev_delta) / max(dt, 1e-6)
        self._prev_delta = self.delta_value


class TurbulentPlumeCFD:
    def __init__(
        self,
        *,
        width_m: float,
        height_m: float,
        nx: int,
        ny: int,
        dt: float,
        source_xy: Vec2,
        wind_heading_deg: float,
        wind_speed: float,
        diffusion: float,
        decay: float,
        source_rate: float,
        source_sigma: float,
    ) -> None:
        self.width_m = width_m
        self.height_m = height_m
        self.nx = nx
        self.ny = ny
        self.dt = dt
        self.dx = width_m / (nx - 1)
        self.dy = height_m / (ny - 1)
        self.source_xy = source_xy
        self.wind_heading_rad = math.radians(wind_heading_deg)
        self.wind_speed = wind_speed
        self.diffusion = diffusion
        self.decay = decay
        self.source_rate = source_rate
        self.source_sigma = source_sigma

        self.x = np.linspace(0.0, width_m, nx)
        self.y = np.linspace(0.0, height_m, ny)
        self.xx, self.yy = np.meshgrid(self.x, self.y)
        self.concentration = np.zeros((ny, nx), dtype=np.float64)

    def velocity_field(self, t_s: float) -> tuple[np.ndarray, np.ndarray]:
        base_u = self.wind_speed * math.cos(self.wind_heading_rad)
        base_v = self.wind_speed * math.sin(self.wind_heading_rad)

        kx1 = 2.0 * math.pi / self.width_m
        ky1 = 2.0 * math.pi / self.height_m
        kx2 = 3.2 * math.pi / self.width_m
        ky2 = 2.7 * math.pi / self.height_m

        psi1 = 0.065 * np.sin(kx1 * self.xx + 0.22 * t_s) * np.sin(1.8 * ky1 * self.yy - 0.15 * t_s)
        psi2 = 0.032 * np.sin(kx2 * self.xx - 0.12 * t_s + 0.6) * np.sin(1.35 * ky2 * self.yy + 0.18 * t_s)
        psi = psi1 + psi2

        u_turb = np.gradient(psi, self.dy, axis=0)
        v_turb = -np.gradient(psi, self.dx, axis=1)

        return base_u + u_turb, base_v + v_turb

    def _sample_grid(self, field: np.ndarray, x_world: np.ndarray, y_world: np.ndarray) -> np.ndarray:
        x_pos = np.clip(x_world / self.dx, 0.0, self.nx - 1.001)
        y_pos = np.clip(y_world / self.dy, 0.0, self.ny - 1.001)

        x0 = np.floor(x_pos).astype(np.int32)
        y0 = np.floor(y_pos).astype(np.int32)
        x1 = np.minimum(x0 + 1, self.nx - 1)
        y1 = np.minimum(y0 + 1, self.ny - 1)

        wx = x_pos - x0
        wy = y_pos - y0

        return (
            (1.0 - wx) * (1.0 - wy) * field[y0, x0]
            + wx * (1.0 - wy) * field[y0, x1]
            + (1.0 - wx) * wy * field[y1, x0]
            + wx * wy * field[y1, x1]
        )

    def sample(self, x_world: float, y_world: float) -> float:
        return float(self._sample_grid(self.concentration, np.array([x_world]), np.array([y_world]))[0])

    def sample_velocity(self, x_world: float, y_world: float, t_s: float) -> tuple[float, float]:
        u_field, v_field = self.velocity_field(t_s)
        u = self._sample_grid(u_field, np.array([x_world]), np.array([y_world]))[0]
        v = self._sample_grid(v_field, np.array([x_world]), np.array([y_world]))[0]
        return float(u), float(v)

    def step(self, t_s: float) -> tuple[np.ndarray, np.ndarray]:
        u_field, v_field = self.velocity_field(t_s)

        back_x = np.clip(self.xx - u_field * self.dt, 0.0, self.width_m)
        back_y = np.clip(self.yy - v_field * self.dt, 0.0, self.height_m)
        advected = self._sample_grid(self.concentration, back_x, back_y)

        laplace = (
            (np.roll(advected, -1, axis=1) - 2.0 * advected + np.roll(advected, 1, axis=1)) / (self.dx * self.dx)
            + (np.roll(advected, -1, axis=0) - 2.0 * advected + np.roll(advected, 1, axis=0)) / (self.dy * self.dy)
        )

        source_term = self.source_rate * np.exp(
            -(
                (self.xx - self.source_xy.x) ** 2 + (self.yy - self.source_xy.y) ** 2
            )
            / (2.0 * self.source_sigma * self.source_sigma)
        )

        updated = advected + self.dt * (self.diffusion * laplace + source_term - self.decay * advected)
        updated[0, :] = 0.0
        updated[-1, :] = 0.0
        updated[:, 0] = 0.0
        updated[:, -1] = 0.0
        self.concentration = np.clip(updated, 0.0, None)
        return u_field, v_field


@dataclass
class OdorSeekPolicy:
    detection_threshold: float = 6.0
    loss_threshold: float = 3.0
    search_speed: float = 0.24
    track_speed: float = 0.38
    cast_speed: float = 0.20
    drift_sigma: float = 0.02
    mode: str = "search"
    mode_elapsed_s: float = 0.0
    last_detect_time_s: float = -1e9
    cast_sign: float = 1.0

    def step(
        self,
        sensors: list[SensorChannel],
        now_s: float,
        dt: float,
        yaw: float,
        local_wind: Vec2,
    ) -> tuple[float, float, float, float, float]:
        values = {sensor.name: max(sensor.delta_value, 0.0) for sensor in sensors}
        g_x = ((values["fl"] + values["fr"]) - (values["rl"] + values["rr"])) / 2.0
        g_y = ((values["fl"] + values["rl"]) - (values["fr"] + values["rr"])) / 2.0
        strength = sum(values.values()) / 4.0
        detected = strength >= self.detection_threshold
        upwind_heading = math.atan2(-local_wind.y, -local_wind.x)
        heading_error = wrap_angle(upwind_heading - yaw)

        if detected:
            self.last_detect_time_s = now_s

        if self.mode == "search" and detected:
            self.mode = "track"
            self.mode_elapsed_s = 0.0
        elif self.mode == "track" and strength < self.loss_threshold and now_s - self.last_detect_time_s > 1.0:
            self.mode = "cast"
            self.mode_elapsed_s = 0.0
            self.cast_sign *= -1.0
        elif self.mode == "cast" and detected:
            self.mode = "track"
            self.mode_elapsed_s = 0.0
        elif self.mode == "cast" and self.mode_elapsed_s > 10.0:
            self.mode = "search"
            self.mode_elapsed_s = 0.0

        self.mode_elapsed_s += dt

        if self.mode == "search":
            st = self.mode_elapsed_s
            if st < 15.0:
                # Phase 1: upwind with mild oscillation (original behavior)
                # 15s gives enough time for easy upwind/sidewind cases
                speed = self.search_speed
                yaw_rate = clamp(
                    0.9 * heading_error + 0.35 * math.sin(now_s * 0.55),
                    -0.75, 0.75,
                )
            else:
                # Phase 2: cross-wind zigzag with upwind drift
                t2 = st - 15.0
                leg_dur = 8.0
                leg_idx = int(t2 / leg_dur)
                sign = 1.0 if leg_idx % 2 == 0 else -1.0
                # Sweep angle grows from 40° toward 70° from upwind
                angle = min(math.radians(40) + math.radians(1.5) * t2,
                            math.radians(70))
                target = upwind_heading + sign * angle
                err = wrap_angle(target - yaw)
                speed = self.search_speed * 1.15
                yaw_rate = clamp(1.6 * err, -0.85, 0.85)
            return speed, yaw_rate, strength, g_x, g_y

        if self.mode == "track":
            speed = self.track_speed if g_x > -2.5 else self.cast_speed
            yaw_rate = clamp(1.1 * heading_error + 0.020 * g_y, -0.90, 0.90)
            return speed, yaw_rate, strength, g_x, g_y

        speed = self.cast_speed
        yaw_rate = clamp(0.7 * heading_error + self.cast_sign * (0.55 + 0.25 * math.sin(self.mode_elapsed_s * 1.2)), -0.95, 0.95)
        return speed, yaw_rate, strength, g_x, g_y


def make_sensors() -> list[SensorChannel]:
    offsets = {
        "fl": Vec2(+0.16, +0.11),
        "fr": Vec2(+0.16, -0.11),
        "rl": Vec2(-0.12, +0.10),
        "rr": Vec2(-0.12, -0.10),
    }
    sensors: list[SensorChannel] = []
    for index, (name, offset) in enumerate(offsets.items()):
        sensors.append(
            SensorChannel(
                name=name,
                offset_body_xy=offset,
                gain=145.0 * (1.0 + 0.03 * (index - 1.5)),
                bias=3.2 + 0.18 * index,
                tau_s=0.55 + 0.07 * index,
                noise_sigma=0.16,
                baseline_tau_s=7.5,
            )
        )
    return sensors


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
    plume_snapshots: list[dict[str, object]],
    history_rows: list[dict[str, str]],
    source_xy: Vec2,
    success_radius: float,
    output_path: Path,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    if not history_rows or not plume_snapshots:
        return

    times = [float(row["time_s"]) for row in history_rows]
    xs = [float(row["robot_x_m"]) for row in history_rows]
    ys = [float(row["robot_y_m"]) for row in history_rows]
    distances = [float(row["distance_to_source_m"]) for row in history_rows]

    fig, axes = plt.subplots(2, 3, figsize=(15, 8), dpi=150)
    plume_axes = [axes[0, 0], axes[0, 1], axes[0, 2], axes[1, 0]]

    for ax, snapshot in zip(plume_axes, plume_snapshots):
        field = snapshot["concentration"]
        path_count = int(snapshot["path_count"])
        x_coords = snapshot["x_coords"]
        y_coords = snapshot["y_coords"]
        wind_u = snapshot["wind_u"]
        wind_v = snapshot["wind_v"]
        time_s = float(snapshot["time_s"])

        image = ax.imshow(
            field,
            origin="lower",
            extent=[x_coords[0], x_coords[-1], y_coords[0], y_coords[-1]],
            cmap="YlOrRd",
            aspect="auto",
            alpha=0.88,
        )
        skip_y = slice(None, None, 10)
        skip_x = slice(None, None, 12)
        ax.quiver(
            x_coords[skip_x],
            y_coords[skip_y],
            wind_u[skip_y, skip_x],
            wind_v[skip_y, skip_x],
            color="#1c7ed6",
            alpha=0.55,
            scale=9.0,
            width=0.0035,
        )
        ax.plot(xs[:path_count], ys[:path_count], color="#0b7285", linewidth=2.0)
        ax.scatter([xs[0]], [ys[0]], color="#f08c00", s=28, zorder=3)
        ax.scatter([source_xy.x], [source_xy.y], color="#c92a2a", s=36, zorder=3)
        ax.add_patch(
            plt.Circle(
                (source_xy.x, source_xy.y),
                success_radius,
                fill=False,
                linestyle="--",
                color="#c92a2a",
                linewidth=1.0,
                alpha=0.7,
            )
        )
        ax.set_title(f"Plume snapshot t={time_s:.1f}s")
        ax.set_xlabel("x (m)")
        ax.set_ylabel("y (m)")
        ax.grid(True, alpha=0.14)
        fig.colorbar(image, ax=ax, fraction=0.046, pad=0.04)

    for ax in plume_axes[len(plume_snapshots) :]:
        ax.axis("off")

    sensor_ax = axes[1, 1]
    distance_ax = axes[1, 2]
    sensor_colors = {
        "fl": "#d9480f",
        "fr": "#c2255c",
        "rl": "#2b8a3e",
        "rr": "#1c7ed6",
    }
    for sensor_name, color in sensor_colors.items():
        series = [float(row[f"{sensor_name}_delta"]) for row in history_rows]
        sensor_ax.plot(times, series, label=sensor_name.upper(), color=color, linewidth=1.8)
    sensor_ax.set_title("Sensor delta traces")
    sensor_ax.set_xlabel("time (s)")
    sensor_ax.set_ylabel("delta")
    sensor_ax.grid(True, alpha=0.25)
    sensor_ax.legend(loc="upper left")

    distance_ax.plot(times, distances, color="#2b8a3e", linewidth=2.1)
    distance_ax.axhline(success_radius, color="#c92a2a", linestyle="--", linewidth=1.2)
    distance_ax.set_title("Distance to source")
    distance_ax.set_xlabel("time (s)")
    distance_ax.set_ylabel("distance (m)")
    distance_ax.grid(True, alpha=0.25)

    fig.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path)
    plt.close(fig)


def render_storyboard(
    *,
    plume_snapshots: list[dict[str, object]],
    history_rows: list[dict[str, str]],
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

    stage_labels = [
        "1. Source releases odor",
        "2. Plume moves downwind",
        "3. Robot detects plume",
        "4. Robot reaches source area",
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

        robot_x = xs[path_count - 1]
        robot_y = ys[path_count - 1]
        robot_yaw = yaws[path_count - 1]
        ax.scatter([robot_x], [robot_y], s=74, facecolors="none", edgecolors="#111111", linewidths=1.8, zorder=5)
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
            f"{label}\nt = {time_s:.1f}s",
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

    fig.suptitle("Odor-seek storyboard: plume transport and robot response", fontsize=14)
    fig.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path)
    plt.close(fig)


def render_gif(
    *,
    gif_frames: list[dict[str, object]],
    history_rows: list[dict[str, str]],
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

    x_coords = gif_frames[0]["x_coords"]
    y_coords = gif_frames[0]["y_coords"]
    max_concentration = max(float(np.max(frame["concentration"])) for frame in gif_frames)
    max_delta = max(
        max(float(row[f"{sensor}_delta"]) for sensor in ("fl", "fr", "rl", "rr"))
        for row in history_rows
    )
    frames: list[np.ndarray] = []

    for frame in gif_frames:
        path_count = int(frame["path_count"])
        time_s = float(frame["time_s"])
        field = frame["concentration"]
        wind_u = frame["wind_u"]
        wind_v = frame["wind_v"]
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
        robot_x = xs[path_count - 1]
        robot_y = ys[path_count - 1]
        robot_yaw = yaws[path_count - 1]
        ax_field.scatter([robot_x], [robot_y], s=74, facecolors="none", edgecolors="#111111", linewidths=1.8, zorder=5)
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
        ax_field.set_title("CFD-style odor plume and robot path")
        ax_field.set_xlabel("x (m)")
        ax_field.set_ylabel("y (m)")
        ax_field.grid(True, alpha=0.12)

        ax_info.plot(times[:path_count], distances[:path_count], color="#2b8a3e", linewidth=2.2)
        ax_info.axhline(success_radius, color="#c92a2a", linestyle="--", linewidth=1.2)
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
            f"RL/RR = {float(current['rl_delta']):.1f} / {float(current['rr_delta']):.1f}"
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

        mini = ax_info.inset_axes([0.60, 0.08, 0.35, 0.32])
        sensor_colors = {
            "fl": "#d9480f",
            "fr": "#c2255c",
            "rl": "#2b8a3e",
            "rr": "#1c7ed6",
        }
        for sensor, color in sensor_colors.items():
            series = [float(row[f"{sensor}_delta"]) for row in history_rows[:path_count]]
            mini.plot(times[:path_count], series, color=color, linewidth=1.4)
        mini.set_xlim(times[0], times[-1])
        mini.set_ylim(min(0.0, min(float(row["fl_delta"]) for row in history_rows) - 1.0), max_delta * 1.08)
        mini.set_title("sensor delta", fontsize=8)
        mini.tick_params(labelsize=7)
        mini.grid(True, alpha=0.18)

        fig.tight_layout()
        fig.canvas.draw()
        width, height = fig.canvas.get_width_height()
        frame_rgb = np.frombuffer(fig.canvas.buffer_rgba(), dtype=np.uint8).reshape(height, width, 4)[..., :3].copy()
        frames.append(frame_rgb)
        plt.close(fig)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    imageio.mimsave(output_path, frames, duration=0.10, loop=0)
    return True


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render a CFD-style turbulent odor plume demo with four-sensor navigation.")
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--steps", type=int, default=560)
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
    parser.add_argument("--success-radius", type=float, default=0.45)
    parser.add_argument("--summary", type=Path, default=SCRIPT_DIR / "output" / "odor_cfd_turbulence_demo.png")
    parser.add_argument("--storyboard", type=Path, default=SCRIPT_DIR / "output" / "odor_cfd_turbulence_storyboard.png")
    parser.add_argument("--gif", type=Path, default=SCRIPT_DIR / "output" / "odor_cfd_turbulence_demo.gif")
    parser.add_argument("--csv", type=Path, default=SCRIPT_DIR / "output" / "odor_cfd_turbulence_demo.csv")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    random.seed(args.seed)
    np.random.seed(args.seed)

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
    policy = OdorSeekPolicy()

    x_pos = args.start_x
    y_pos = args.start_y
    yaw = math.radians(args.start_yaw_deg)

    history_rows: list[dict[str, str]] = []
    snapshot_candidates: list[dict[str, object]] = []
    gif_frames: list[dict[str, object]] = []

    reached_at: float | None = None
    min_distance = float("inf")

    for step in range(args.steps):
        now_s = step * args.dt
        wind_u, wind_v = cfd.step(now_s)
        local_u, local_v = cfd.sample_velocity(x_pos, y_pos, now_s)

        for sensor in sensors:
            offset_world = sensor.offset_body_xy.rotated(yaw)
            sample_x = clamp(x_pos + offset_world.x, 0.0, args.width_m)
            sample_y = clamp(y_pos + offset_world.y, 0.0, args.height_m)
            concentration = cfd.sample(sample_x, sample_y)
            sensor.step(concentration, args.dt, policy.drift_sigma)

        speed, yaw_rate, strength, g_x, g_y = policy.step(
            sensors,
            now_s,
            args.dt,
            yaw=yaw,
            local_wind=Vec2(local_u, local_v),
        )
        yaw += yaw_rate * args.dt
        x_pos = clamp(x_pos + speed * math.cos(yaw) * args.dt, 0.0, args.width_m)
        y_pos = clamp(y_pos + speed * math.sin(yaw) * args.dt, 0.0, args.height_m)

        distance = math.hypot(x_pos - source_xy.x, y_pos - source_xy.y)
        min_distance = min(min_distance, distance)
        if reached_at is None and distance <= args.success_radius:
            reached_at = now_s

        row = {
            "time_s": f"{now_s:.2f}",
            "robot_x_m": f"{x_pos:.4f}",
            "robot_y_m": f"{y_pos:.4f}",
            "robot_yaw_deg": f"{math.degrees(yaw):.2f}",
            "distance_to_source_m": f"{distance:.4f}",
            "odor_mode": policy.mode,
            "speed_mps": f"{speed:.4f}",
            "yaw_rate_rps": f"{yaw_rate:.4f}",
            "strength": f"{strength:.4f}",
            "g_x": f"{g_x:.4f}",
            "g_y": f"{g_y:.4f}",
        }
        for sensor in sensors:
            row[f"{sensor.name}_raw"] = f"{sensor.raw_value:.4f}"
            row[f"{sensor.name}_baseline"] = f"{sensor.baseline_value:.4f}"
            row[f"{sensor.name}_delta"] = f"{sensor.delta_value:.4f}"
            row[f"{sensor.name}_slope"] = f"{sensor.slope_value:.4f}"
        history_rows.append(row)

        if step % 24 == 0 or step == args.steps - 1:
            snapshot_candidates.append(
                {
                    "time_s": now_s,
                    "path_count": len(history_rows),
                    "concentration": cfd.concentration.copy(),
                    "x_coords": cfd.x.copy(),
                    "y_coords": cfd.y.copy(),
                    "wind_u": wind_u.copy(),
                    "wind_v": wind_v.copy(),
                }
            )
        if step % 6 == 0 or step == args.steps - 1:
            gif_frames.append(
                {
                    "time_s": now_s,
                    "path_count": len(history_rows),
                    "concentration": cfd.concentration.astype(np.float32).copy(),
                    "x_coords": cfd.x.copy(),
                    "y_coords": cfd.y.copy(),
                    "wind_u": wind_u.astype(np.float32).copy(),
                    "wind_v": wind_v.astype(np.float32).copy(),
                }
            )

        if reached_at is not None and now_s >= reached_at + 1.6:
            break

    if snapshot_candidates:
        sample_count = min(4, len(snapshot_candidates))
        sample_indices = np.linspace(0, len(snapshot_candidates) - 1, sample_count, dtype=int)
        plume_snapshots = [snapshot_candidates[index] for index in sample_indices]
    else:
        plume_snapshots = []

    write_csv(args.csv, history_rows)
    render_summary(
        plume_snapshots=plume_snapshots,
        history_rows=history_rows,
        source_xy=source_xy,
        success_radius=args.success_radius,
        output_path=args.summary,
    )
    render_storyboard(
        plume_snapshots=plume_snapshots,
        history_rows=history_rows,
        source_xy=source_xy,
        success_radius=args.success_radius,
        output_path=args.storyboard,
    )
    gif_written = render_gif(
        gif_frames=gif_frames,
        history_rows=history_rows,
        source_xy=source_xy,
        success_radius=args.success_radius,
        output_path=args.gif,
    )

    print(f"seed={args.seed}")
    print(f"summary={args.summary}")
    print(f"storyboard={args.storyboard}")
    if gif_written:
        print(f"gif={args.gif}")
    print(f"csv={args.csv}")
    print(f"start=({args.start_x:.2f},{args.start_y:.2f}) yaw_deg={args.start_yaw_deg:.1f}")
    print(f"source=({args.source_x:.2f},{args.source_y:.2f})")
    print(f"wind_heading_deg={args.wind_heading_deg:.1f}")
    print(f"reached_source={str(reached_at is not None).lower()}")
    if reached_at is not None:
        print(f"reached_at_s={reached_at:.2f}")
    print(f"min_distance_m={min_distance:.3f}")
    print(f"steps_recorded={len(history_rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
