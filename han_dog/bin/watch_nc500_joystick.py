#!/usr/bin/env python3
import json
import os
import select
import struct
import time
from pathlib import Path

ROOT = Path('/home/bsrl1/brainstem')
CFG = ROOT / 'han_dog/config/xbox.json'
JS = '/dev/input/js0'

def norm(v):
    return max(-1.0, min(1.0, v / 32767.0))

def dead(v, dz):
    return 0.0 if abs(v) < dz else v

def bar(v, width=16):
    n = int(round(v * width))
    if n > 0:
        return ' ' * width + '|' + '#' * n + ' ' * (width - n)
    if n < 0:
        return ' ' * (width + n) + '#' * (-n) + '|' + ' ' * width
    return ' ' * width + '|' + ' ' * width

def load_cfg():
    with CFG.open(encoding='utf-8') as f:
        return json.load(f)

def main():
    cfg = load_cfg()
    axes = cfg['axes']
    speed = cfg['speed']
    stick = cfg['stick']
    buttons = cfg['buttons']
    dz = cfg.get('deadzone', 0.08)
    axis = [0.0] * 8
    btn = {i: False for i in range(16)}

    fd = os.open(JS, os.O_RDONLY | os.O_NONBLOCK)
    try:
        while True:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                while True:
                    try:
                        data = os.read(fd, 8)
                    except BlockingIOError:
                        break
                    if len(data) != 8:
                        break
                    _t, value, typ, num = struct.unpack('IhBB', data)
                    if typ & 0x80:
                        continue
                    base = typ & 0x7f
                    if base == 2 and num < len(axis):
                        axis[num] = norm(value)
                    elif base == 1:
                        btn[num] = bool(value)

            ly = dead(axis[axes['left_stick_y']], dz)
            if stick.get('left_y_invert', False):
                ly = -ly
            lx = dead(axis[axes['left_stick_x']], dz)
            if stick.get('vy_from_lx_negate', False):
                lx = -lx
            rx = dead(axis[axes['right_stick_x']], dz)
            if stick.get('right_x_invert', False):
                rx = -rx

            vx = ly * speed['vx_scale']
            vy = lx * speed['vy_scale']
            wz = rx * speed['vyaw_scale']

            pressed = [name.upper() for name, idx in buttons.items() if btn.get(idx, False)]
            os.system('clear')
            print('NC500 joystick offline watcher - Ctrl+C to stop')
            print('READ ONLY: does not send enable/stand/walk commands')
            print(f'config: {CFG}')
            print(f'deadzone={dz} buttons={buttons}')
            print()
            print(f'raw LX={axis[axes["left_stick_x"]]:+6.2f}  LY={axis[axes["left_stick_y"]]:+6.2f}  RX={axis[axes["right_stick_x"]]:+6.2f}')
            print(f'cmd vx={vx:+6.2f}  vy={vy:+6.2f}  wz={wz:+6.2f}')
            print()
            print('vx forward/back : ' + bar(vx))
            print('vy left/right   : ' + bar(vy / max(speed['vy_scale'], 1e-9)))
            print('wz yaw          : ' + bar(wz / max(speed['vyaw_scale'], 1e-9)))
            print()
            print('pressed:', ', '.join(pressed) if pressed else 'none')
            time.sleep(0.05)
    finally:
        os.close(fd)

if __name__ == '__main__':
    main()
