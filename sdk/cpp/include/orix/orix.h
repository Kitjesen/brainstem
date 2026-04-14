// orix/orix.h — ORIX C++ SDK 单头文件入口
//
// 包含此文件即可使用所有机器人控制功能：
//   #include "orix/orix.h"
//
//   orix::OrixClient dog("192.168.66.190");
//   dog.enable();
//   dog.stand_up();
//   dog.walk(0.3);
//   dog.sit_down();
//   dog.disable();
//
// 摄像头模块需单独引用（依赖 OpenCV）：
//   #include "orix/orix_camera.h"
//
//   orix::OrixCamera cam;
//   cam.open();
//   cam.save_photo("photo.jpg");
#pragma once

#include "orix/types.h"
#include "orix/errors.h"
#include "orix/orix_client.h"
