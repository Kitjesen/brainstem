"""
Xbox 手柄配置加载器 — 所有 Xbox 脚本共用。
配置文件: han_dog/config/xbox.json
"""
import json
from pathlib import Path

_CONFIG_PATH = Path(__file__).resolve().parent.parent.parent / "han_dog" / "config" / "xbox.json"


def load_xbox_config(path=None):
    """加载 Xbox 配置，返回字典。"""
    p = Path(path) if path else _CONFIG_PATH
    with open(p, encoding="utf-8") as f:
        return json.load(f)


class XboxController:
    """封装 Xbox 手柄读取逻辑，基于配置文件。"""

    def __init__(self, joy, config=None):
        self.joy = joy
        self.cfg = config or load_xbox_config()
        self._last_btn = {}

    # ── 轴 ────────────────────────────────────────────────────

    @property
    def deadzone(self):
        return self.cfg["deadzone"]

    def _dz(self, val):
        return 0.0 if abs(val) < self.deadzone else val

    def _axis(self, name):
        idx = self.cfg["axes"].get(name, -1)
        if idx < 0 or idx >= self.joy.get_numaxes():
            return 0.0
        return self.joy.get_axis(idx)

    @property
    def vx(self):
        ly = self._dz(self._axis("left_stick_y"))
        if self.cfg["stick"]["left_y_invert"]:
            ly = -ly
        return ly * self.speed_scale * self.cfg["speed"]["vx_scale"]

    @property
    def vy(self):
        lx = self._dz(self._axis("left_stick_x"))
        if self.cfg["stick"]["vy_from_lx_negate"]:
            lx = -lx
        return lx * self.speed_scale * self.cfg["speed"]["vy_scale"]

    @property
    def vyaw(self):
        rx = self._dz(self._axis("right_stick_x"))
        if self.cfg["stick"]["right_x_invert"]:
            rx = -rx
        return rx * self.speed_scale * self.cfg["speed"]["vyaw_scale"]

    @property
    def speed_scale(self):
        lt = (self._axis("lt") + 1) / 2
        rt = (self._axis("rt") + 1) / 2
        if lt > self.cfg["speed"]["lt_threshold"]:
            return self.cfg["speed"]["lt_multiplier"]
        if rt > self.cfg["speed"]["rt_threshold"]:
            return self.cfg["speed"]["rt_multiplier"]
        return 1.0

    @property
    def stick_active(self):
        return abs(self.vx) > 0.01 or abs(self.vy) > 0.01 or abs(self.vyaw) > 0.01

    # ── 按钮 ──────────────────────────────────────────────────

    def _btn_idx(self, action):
        btn_name = self.cfg["actions"].get(action)
        if btn_name is None:
            return -1
        return self.cfg["buttons"].get(btn_name, -1)

    def btn_pressed(self, action):
        """边沿检测：按钮刚按下返回 True。"""
        idx = self._btn_idx(action)
        if idx < 0 or idx >= self.joy.get_numbuttons():
            return False
        cur = self.joy.get_button(idx)
        prev = self._last_btn.get(idx, 0)
        self._last_btn[idx] = cur
        return cur and not prev
