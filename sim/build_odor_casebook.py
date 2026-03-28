from __future__ import annotations

import csv
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[3]
SIM_OUTPUT = ROOT / "brain" / "brainstem" / "sim" / "output"
OUTPUT_PATH = SIM_OUTPUT / "odor_go2w_casebook.png"


def load_font(size: int, *, bold: bool = False):
    candidates = [
        r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size)
            except OSError:
                continue
    return ImageFont.load_default()


def load_metrics(csv_path: Path) -> tuple[bool, float | None, float]:
    rows = list(csv.DictReader(csv_path.open("r", encoding="utf-8")))
    distances = [float(row["distance_to_source_m"]) for row in rows]
    reached_at = next((float(row["time_s"]) for row in rows if float(row["distance_to_source_m"]) <= 0.65), None)
    return reached_at is not None, reached_at, min(distances)


def add_case_panel(
    canvas: Image.Image,
    *,
    image_path: Path,
    label: str,
    subtitle: str,
    reached: bool,
    reached_at: float | None,
    min_distance: float,
    left: int,
    top: int,
    width: int,
    height: int,
) -> None:
    draw = ImageDraw.Draw(canvas, "RGBA")
    card = (left, top, left + width, top + height)
    draw.rounded_rectangle(card, radius=24, fill=(250, 251, 253, 255), outline=(220, 226, 232, 255), width=2)

    title_font = load_font(30, bold=True)
    subtitle_font = load_font(18)
    metric_font = load_font(20, bold=True)
    body_font = load_font(18)

    draw.text((left + 24, top + 18), label, fill=(19, 37, 68, 255), font=title_font)
    draw.text((left + 24, top + 56), subtitle, fill=(92, 102, 118, 255), font=subtitle_font)

    metric_y = top + 92
    badge_text = "SUCCESS" if reached else "CHALLENGE"
    badge_fill = (43, 138, 62, 230) if reached else (201, 42, 42, 230)
    badge_w = 126 if reached else 146
    draw.rounded_rectangle((left + 24, metric_y, left + 24 + badge_w, metric_y + 34), radius=14, fill=badge_fill)
    draw.text((left + 40, metric_y + 7), badge_text, fill=(255, 255, 255, 255), font=body_font)

    if reached_at is None:
        summary = f"closest = {min_distance:.3f} m"
    else:
        summary = f"reach = {reached_at:.2f} s   min = {min_distance:.3f} m"
    draw.text((left + 190, metric_y + 5), summary, fill=(31, 41, 55, 255), font=metric_font)

    image = Image.open(image_path).convert("RGB")
    image.thumbnail((width - 48, height - 150))
    image_left = left + (width - image.width) // 2
    image_top = top + 138
    canvas.paste(image, (image_left, image_top))


def main() -> None:
    cases = [
        {
            "label": "Case A: Default Corridor v3",
            "subtitle": "Default start and source under the polished v3 scene",
            "plot": SIM_OUTPUT / "odor_mujoco_go2w_v3_demo.png",
            "csv": SIM_OUTPUT / "odor_mujoco_go2w_v3_demo.csv",
        },
        {
            "label": "Case B: Inline Plume Start",
            "subtitle": "Robot starts on the main plume centerline",
            "plot": SIM_OUTPUT / "odor_mujoco_go2w_v3_inline_demo.png",
            "csv": SIM_OUTPUT / "odor_mujoco_go2w_v3_inline_demo.csv",
        },
        {
            "label": "Case C: Slower Wind Variant",
            "subtitle": "Same geometry with a reduced airflow speed",
            "plot": SIM_OUTPUT / "odor_mujoco_go2w_v3_slowwind_demo.png",
            "csv": SIM_OUTPUT / "odor_mujoco_go2w_v3_slowwind_demo.csv",
        },
        {
            "label": "Case D: Offset Source Challenge",
            "subtitle": "Source and start are shifted together off the easy lane",
            "plot": SIM_OUTPUT / "odor_mujoco_go2w_v3_offset_demo.png",
            "csv": SIM_OUTPUT / "odor_mujoco_go2w_v3_offset_demo.csv",
        },
        {
            "label": "Case E: Midlane Start Challenge",
            "subtitle": "Start nudged toward the corridor center but still misses",
            "plot": SIM_OUTPUT / "odor_mujoco_go2w_v3_midlane_demo.png",
            "csv": SIM_OUTPUT / "odor_mujoco_go2w_v3_midlane_demo.csv",
        },
        {
            "label": "Case F: Wind Heading 176 deg",
            "subtitle": "A mild heading rotation exposes controller brittleness",
            "plot": SIM_OUTPUT / "odor_mujoco_go2w_v3_heading176_demo.png",
            "csv": SIM_OUTPUT / "odor_mujoco_go2w_v3_heading176_demo.csv",
        },
    ]

    canvas = Image.new("RGB", (2400, 2350), (240, 243, 247))
    draw = ImageDraw.Draw(canvas, "RGBA")
    title_font = load_font(42, bold=True)
    subtitle_font = load_font(22)
    draw.text((60, 36), "Odor Navigation Casebook", fill=(16, 36, 68, 255), font=title_font)
    draw.text(
        (60, 88),
        "Go2W MuJoCo odor-seek examples: three success cases plus three boundary and failure cases",
        fill=(86, 96, 112, 255),
        font=subtitle_font,
    )

    panel_w = 1120
    panel_h = 700
    positions = [
        (60, 150),
        (1220, 150),
        (60, 885),
        (1220, 885),
        (60, 1620),
        (1220, 1620),
    ]

    for case, (left, top) in zip(cases, positions):
        reached, reached_at, min_distance = load_metrics(case["csv"])
        add_case_panel(
            canvas,
            image_path=case["plot"],
            label=case["label"],
            subtitle=case["subtitle"],
            reached=reached,
            reached_at=reached_at,
            min_distance=min_distance,
            left=left,
            top=top,
            width=panel_w,
            height=panel_h,
        )

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUTPUT_PATH, quality=95)
    print(OUTPUT_PATH)


if __name__ == "__main__":
    main()
