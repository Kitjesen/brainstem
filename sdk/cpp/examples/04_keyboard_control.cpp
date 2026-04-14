// 04_keyboard_control.cpp — 键盘实时控制行走
//
// 按键映射：
//   W / ↑   前进       S / ↓   后退
//   A / ←   左移       D / →   右移
//   Q        左转       E        右转
//   空格     停止       U        站起
//   J        坐下       H        高速模式切换
//   ESC / X  退出
#include "orix/orix.h"

#include <atomic>
#include <chrono>
#include <iostream>
#include <thread>

// ── 平台键盘输入 ──────────────────────────────────────────────
#ifdef _WIN32
#  include <conio.h>
   static bool kb_hit()  { return _kbhit() != 0; }
   static int  kb_read() { return _getch(); }
#else
#  include <termios.h>
#  include <unistd.h>
#  include <fcntl.h>
   static struct termios _orig_termios;
   static void  raw_mode_on() {
       tcgetattr(STDIN_FILENO, &_orig_termios);
       struct termios t = _orig_termios;
       t.c_lflag &= ~(ICANON | ECHO);
       t.c_cc[VMIN] = 0; t.c_cc[VTIME] = 0;
       tcsetattr(STDIN_FILENO, TCSANOW, &t);
   }
   static void  raw_mode_off() { tcsetattr(STDIN_FILENO, TCSANOW, &_orig_termios); }
   static bool  kb_hit()  {
       unsigned char c; return read(STDIN_FILENO, &c, 1) == 1
           ? (ungetc(c, stdin), true) : false;
   }
   static int   kb_read() { unsigned char c; read(STDIN_FILENO, &c, 1); return c; }
#endif

int main() {
    orix::OrixClient dog("192.168.66.190");

    if (!dog.ping()) {
        std::cerr << "无法连接到机器人。\n";
        return 1;
    }

#ifndef _WIN32
    raw_mode_on();
#endif

    std::cout <<
        "=== 键盘控制模式 ===\n"
        "W/S/A/D  前/后/左/右    Q/E 左/右转\n"
        "空格 停止   U 站起   J 坐下   H 高速切换\n"
        "ESC/X 退出\n\n";

    try {
        dog.enable();
        dog.stand_up();
        std::cout << "机器人已站立，开始控制...\n";
    } catch (const orix::OrixError& e) {
        std::cerr << "初始化失败: " << e.what() << "\n";
#ifndef _WIN32
        raw_mode_off();
#endif
        return 1;
    }

    static constexpr double SPEED = 0.4;
    static constexpr double YAW   = 0.5;
    bool high_speed = false;

    while (true) {
        if (!kb_hit()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
            continue;
        }

        int key = kb_read();
        // Windows 方向键为 0x00/0xE0 + 方向码；统一转成小写字母处理
#ifdef _WIN32
        if (key == 0 || key == 0xE0) {
            key = kb_read();
            switch (key) {
                case 72: key = 'w'; break; // ↑
                case 80: key = 's'; break; // ↓
                case 75: key = 'a'; break; // ←
                case 77: key = 'd'; break; // →
            }
        }
#endif
        if (key >= 'A' && key <= 'Z') key += 32; // 转小写

        try {
            if (key == 27 || key == 'x') {        // ESC / X
                break;
            } else if (key == 'w') {
                dog.walk( SPEED, 0,  0);
            } else if (key == 's') {
                dog.walk(-SPEED, 0,  0);
            } else if (key == 'a') {
                dog.walk(0,  SPEED,  0);
            } else if (key == 'd') {
                dog.walk(0, -SPEED,  0);
            } else if (key == 'q') {
                dog.walk(0, 0,  YAW);
            } else if (key == 'e') {
                dog.walk(0, 0, -YAW);
            } else if (key == ' ') {
                dog.walk(0, 0, 0);
                std::cout << "停止\n";
            } else if (key == 'u') {
                dog.stand_up();
                std::cout << "站起\n";
            } else if (key == 'j') {
                dog.sit_down();
                std::cout << "坐下\n";
            } else if (key == 'h') {
                high_speed = !high_speed;
                dog.set_high_speed(high_speed);
                std::cout << (high_speed ? "高速模式 ON\n" : "高速模式 OFF\n");
            }
        } catch (const orix::OrixError& e) {
            std::cerr << "指令失败: " << e.what() << "\n";
        }
    }

    try { dog.walk(0, 0, 0); } catch (...) {}
    try { dog.sit_down();    } catch (...) {}
    try { dog.disable();     } catch (...) {}

#ifndef _WIN32
    raw_mode_off();
#endif
    std::cout << "\n退出。\n";
    return 0;
}
