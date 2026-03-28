"""
Room-scale odor source localization scenarios.

Runs 8 scenarios in an 8m x 6m room with varied source positions,
wind directions, and start locations to validate exploration and
local planning behavior.
"""

from __future__ import annotations

import math
import random
import sys
from pathlib import Path

import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from odor_cfd_turbulence_demo import (  # noqa: E402
    OdorSeekPolicy,
    TurbulentPlumeCFD,
    Vec2,
    clamp,
    make_sensors,
    render_gif,
    render_storyboard,
    render_summary,
    write_csv,
)

OUTPUT_DIR = SCRIPT_DIR / "output"

ROOM_NX = 240
ROOM_NY = 180
DT = 0.05
MAX_STEPS = 1200  # 60 seconds
SUCCESS_RADIUS = 0.55
GIF_EVERY = 8
SNAPSHOT_EVERY = 24

SCENARIOS = [
    {
        "id": "room_upwind",
        "label": "A. 正对上风",
        "subtitle": "Direct upwind — baseline success case",
        "width_m": 8.0,
        "height_m": 6.0,
        "source_x": 6.5,
        "source_y": 3.0,
        "start_x": 1.5,
        "start_y": 3.0,
        "start_yaw_deg": 0.0,
        "wind_heading_deg": 180.0,
        "wind_speed": 0.55,
        "seed": 42,
    },
    {
        "id": "room_cross",
        "label": "B. 横风偏置",
        "subtitle": "Cross-wind offset — explore then track",
        "width_m": 8.0,
        "height_m": 6.0,
        "source_x": 6.5,
        "source_y": 5.0,
        "start_x": 1.5,
        "start_y": 1.0,
        "start_yaw_deg": 0.0,
        "wind_heading_deg": 180.0,
        "wind_speed": 0.55,
        "seed": 42,
    },
    {
        "id": "room_diagonal",
        "label": "C. 对角风场",
        "subtitle": "Diagonal wind 225° — asymmetric plume",
        "width_m": 8.0,
        "height_m": 6.0,
        "source_x": 6.5,
        "source_y": 5.0,
        "start_x": 1.0,
        "start_y": 1.0,
        "start_yaw_deg": 45.0,
        "wind_heading_deg": 225.0,
        "wind_speed": 0.55,
        "seed": 42,
    },
    {
        "id": "room_headwind",
        "label": "D. 下风起步",
        "subtitle": "Downwind start — must explore blind",
        "width_m": 8.0,
        "height_m": 6.0,
        "source_x": 2.0,
        "source_y": 3.0,
        "start_x": 7.0,
        "start_y": 3.0,
        "start_yaw_deg": 180.0,
        "wind_heading_deg": 180.0,
        "wind_speed": 0.55,
        "seed": 42,
    },
    {
        "id": "room_sidewind",
        "label": "E. 侧风 270°",
        "subtitle": "Side wind — perpendicular plume geometry",
        "width_m": 8.0,
        "height_m": 6.0,
        "source_x": 4.0,
        "source_y": 5.5,
        "start_x": 4.0,
        "start_y": 0.5,
        "start_yaw_deg": 90.0,
        "wind_heading_deg": 270.0,
        "wind_speed": 0.55,
        "seed": 42,
    },
    {
        "id": "room_corner",
        "label": "F. 角落气源",
        "subtitle": "Corner source 210° wind — boundary effects",
        "width_m": 8.0,
        "height_m": 6.0,
        "source_x": 7.2,
        "source_y": 5.2,
        "start_x": 0.8,
        "start_y": 0.8,
        "start_yaw_deg": 45.0,
        "wind_heading_deg": 210.0,
        "wind_speed": 0.55,
        "seed": 42,
    },
    {
        "id": "room_weak",
        "label": "G. 微风 0.28 m/s",
        "subtitle": "Weak wind — wider plume, weaker gradient",
        "width_m": 8.0,
        "height_m": 6.0,
        "source_x": 6.5,
        "source_y": 3.0,
        "start_x": 1.5,
        "start_y": 3.0,
        "start_yaw_deg": 0.0,
        "wind_heading_deg": 180.0,
        "wind_speed": 0.28,
        "seed": 42,
    },
    {
        "id": "room_strong",
        "label": "H. 强风 0.90 m/s",
        "subtitle": "Strong wind — narrow plume, fast transport",
        "width_m": 8.0,
        "height_m": 6.0,
        "source_x": 6.5,
        "source_y": 3.0,
        "start_x": 1.5,
        "start_y": 3.0,
        "start_yaw_deg": 0.0,
        "wind_heading_deg": 180.0,
        "wind_speed": 0.90,
        "seed": 42,
    },
]


def run_scenario(scenario: dict) -> dict:
    """Run one CFD + odor-seek scenario and return results dict."""
    sid = scenario["id"]
    print(f"\n{'=' * 60}")
    print(f"  {sid}: {scenario['label']}")
    print(f"  {scenario['subtitle']}")
    print(f"{'=' * 60}")

    random.seed(scenario["seed"])
    np.random.seed(scenario["seed"])

    source_xy = Vec2(scenario["source_x"], scenario["source_y"])
    width_m = scenario["width_m"]
    height_m = scenario["height_m"]

    cfd = TurbulentPlumeCFD(
        width_m=width_m,
        height_m=height_m,
        nx=ROOM_NX,
        ny=ROOM_NY,
        dt=DT,
        source_xy=source_xy,
        wind_heading_deg=scenario["wind_heading_deg"],
        wind_speed=scenario["wind_speed"],
        diffusion=0.0018,
        decay=0.030,
        source_rate=0.62,
        source_sigma=0.11,
    )

    sensors = make_sensors()
    policy = OdorSeekPolicy()

    x_pos = scenario["start_x"]
    y_pos = scenario["start_y"]
    yaw = math.radians(scenario["start_yaw_deg"])

    history_rows: list[dict[str, str]] = []
    snapshot_candidates: list[dict[str, object]] = []
    gif_frames: list[dict[str, object]] = []
    mode_transitions: list[dict[str, object]] = []
    prev_mode = "search"

    reached_at: float | None = None
    min_distance = float("inf")

    for step in range(MAX_STEPS):
        now_s = step * DT
        wind_u, wind_v = cfd.step(now_s)
        local_u, local_v = cfd.sample_velocity(x_pos, y_pos, now_s)

        for sensor in sensors:
            offset_world = sensor.offset_body_xy.rotated(yaw)
            sample_x = clamp(x_pos + offset_world.x, 0.0, width_m)
            sample_y = clamp(y_pos + offset_world.y, 0.0, height_m)
            concentration = cfd.sample(sample_x, sample_y)
            sensor.step(concentration, DT, policy.drift_sigma)

        speed, yaw_rate, strength, g_x, g_y = policy.step(
            sensors,
            now_s,
            DT,
            yaw=yaw,
            local_wind=Vec2(local_u, local_v),
        )

        if policy.mode != prev_mode:
            mode_transitions.append(
                {"time_s": now_s, "from": prev_mode, "to": policy.mode}
            )
            prev_mode = policy.mode

        yaw += yaw_rate * DT
        x_pos = clamp(x_pos + speed * math.cos(yaw) * DT, 0.0, width_m)
        y_pos = clamp(y_pos + speed * math.sin(yaw) * DT, 0.0, height_m)

        distance = math.hypot(x_pos - source_xy.x, y_pos - source_xy.y)
        min_distance = min(min_distance, distance)
        if reached_at is None and distance <= SUCCESS_RADIUS:
            reached_at = now_s

        row: dict[str, str] = {
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

        if step % SNAPSHOT_EVERY == 0 or step == MAX_STEPS - 1:
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
        if step % GIF_EVERY == 0 or step == MAX_STEPS - 1:
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

    # Select 4 storyboard snapshots
    if snapshot_candidates:
        n = min(4, len(snapshot_candidates))
        indices = np.linspace(0, len(snapshot_candidates) - 1, n, dtype=int)
        plume_snapshots = [snapshot_candidates[int(i)] for i in indices]
    else:
        plume_snapshots = []

    # Output paths
    prefix = f"odor_{sid}"
    csv_path = OUTPUT_DIR / f"{prefix}_demo.csv"
    png_path = OUTPUT_DIR / f"{prefix}_demo.png"
    gif_path = OUTPUT_DIR / f"{prefix}_demo.gif"
    storyboard_path = OUTPUT_DIR / f"{prefix}_storyboard.png"

    write_csv(csv_path, history_rows)
    render_summary(
        plume_snapshots=plume_snapshots,
        history_rows=history_rows,
        source_xy=source_xy,
        success_radius=SUCCESS_RADIUS,
        output_path=png_path,
    )
    render_storyboard(
        plume_snapshots=plume_snapshots,
        history_rows=history_rows,
        source_xy=source_xy,
        success_radius=SUCCESS_RADIUS,
        output_path=storyboard_path,
    )
    gif_ok = render_gif(
        gif_frames=gif_frames,
        history_rows=history_rows,
        source_xy=source_xy,
        success_radius=SUCCESS_RADIUS,
        output_path=gif_path,
    )

    reached = reached_at is not None
    status = "SUCCESS" if reached else "CHALLENGE"
    reach_str = f"{reached_at:.2f}s" if reached_at else "N/A"
    print(f"  {status} | reach={reach_str} | min_dist={min_distance:.3f}m | transitions={len(mode_transitions)}")
    for t in mode_transitions:
        print(f"    t={t['time_s']:.1f}s: {t['from']} -> {t['to']}")

    return {
        "id": sid,
        "label": scenario["label"],
        "subtitle": scenario["subtitle"],
        "reached": reached,
        "reached_at": reached_at,
        "min_distance": min_distance,
        "mode_transitions": len(mode_transitions),
        "transitions_detail": mode_transitions,
        "final_mode": policy.mode,
        "steps": len(history_rows),
        "csv": csv_path,
        "png": png_path,
        "gif": gif_path if gif_ok else None,
        "storyboard": storyboard_path,
    }


def build_casebook(results: list[dict]) -> Path:
    """Build combined 4x2 casebook image from all scenario results."""
    from PIL import Image, ImageDraw, ImageFont

    def load_font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
        candidates = [
            r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc",
            r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
        ]
        for c in candidates:
            p = Path(c)
            if p.exists():
                try:
                    return ImageFont.truetype(str(p), size)
                except OSError:
                    continue
        return ImageFont.load_default()

    cols = 4
    rows = 2
    panel_w = 820
    panel_h = 600
    margin = 28
    header_h = 100

    canvas_w = margin + cols * (panel_w + margin)
    canvas_h = header_h + rows * (panel_h + margin) + margin

    canvas = Image.new("RGB", (canvas_w, canvas_h), (240, 243, 247))
    draw = ImageDraw.Draw(canvas, "RGBA")

    title_font = load_font(38, bold=True)
    subtitle_font = load_font(20)
    label_font = load_font(24, bold=True)
    metric_font = load_font(18, bold=True)
    body_font = load_font(16)

    draw.text(
        (margin, 22),
        "Room-Scale Odor Navigation Casebook",
        fill=(16, 36, 68),
        font=title_font,
    )
    draw.text(
        (margin, 66),
        "8m × 6m room — varied source positions, wind directions, and start locations",
        fill=(86, 96, 112),
        font=subtitle_font,
    )

    for idx, result in enumerate(results[: cols * rows]):
        col = idx % cols
        row_idx = idx // cols
        left = margin + col * (panel_w + margin)
        top = header_h + row_idx * (panel_h + margin)

        draw.rounded_rectangle(
            (left, top, left + panel_w, top + panel_h),
            radius=18,
            fill=(250, 251, 253),
            outline=(220, 226, 232),
            width=2,
        )

        draw.text(
            (left + 16, top + 10),
            result["label"],
            fill=(19, 37, 68),
            font=label_font,
        )
        draw.text(
            (left + 16, top + 40),
            result["subtitle"],
            fill=(92, 102, 118),
            font=body_font,
        )

        badge_y = top + 66
        if result["reached"]:
            draw.rounded_rectangle(
                (left + 16, badge_y, left + 120, badge_y + 26),
                radius=12,
                fill=(43, 138, 62, 230),
            )
            draw.text(
                (left + 28, badge_y + 3),
                "SUCCESS",
                fill=(255, 255, 255),
                font=body_font,
            )
        else:
            draw.rounded_rectangle(
                (left + 16, badge_y, left + 140, badge_y + 26),
                radius=12,
                fill=(201, 42, 42, 230),
            )
            draw.text(
                (left + 28, badge_y + 3),
                "CHALLENGE",
                fill=(255, 255, 255),
                font=body_font,
            )

        if result["reached_at"] is not None:
            metric_text = f"reach={result['reached_at']:.2f}s  min={result['min_distance']:.3f}m"
        else:
            metric_text = f"closest={result['min_distance']:.3f}m"
        draw.text(
            (left + 160, badge_y + 2),
            metric_text,
            fill=(31, 41, 55),
            font=metric_font,
        )

        if result["png"].exists():
            img = Image.open(result["png"]).convert("RGB")
            img.thumbnail((panel_w - 32, panel_h - 110))
            img_left = left + (panel_w - img.width) // 2
            img_top = top + 100
            canvas.paste(img, (img_left, img_top))

    output = OUTPUT_DIR / "odor_room_casebook.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, quality=95)
    print(f"\ncasebook={output}")
    return output


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    results: list[dict] = []
    for scenario in SCENARIOS:
        result = run_scenario(scenario)
        results.append(result)

    casebook_path = build_casebook(results)

    print(f"\n{'=' * 80}")
    print(f"{'ID':<20} {'Status':<12} {'Reach':<10} {'Min Dist':<12} {'Transitions'}")
    print(f"{'-' * 80}")
    for r in results:
        status = "SUCCESS" if r["reached"] else "CHALLENGE"
        reach = f"{r['reached_at']:.2f}s" if r["reached_at"] else "N/A"
        print(f"{r['id']:<20} {status:<12} {reach:<10} {r['min_distance']:<12.3f} {r['mode_transitions']}")

    successes = sum(1 for r in results if r["reached"])
    print(f"\nTotal: {successes}/{len(results)} succeeded")
    print(f"Casebook: {casebook_path}")


if __name__ == "__main__":
    main()
