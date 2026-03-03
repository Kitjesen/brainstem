import 'package:flutter/material.dart';

/// 将大喵 G6620 电机状态码解码为中文描述
String decodeMotorStatus(int status) => switch (status) {
  0 => '禁用',
  1 => '正常',
  8 => '过压',
  9 => '欠压',
  10 => '过流',
  11 => 'MOS过温',
  12 => '转子过温',
  13 => '通信丢失',
  14 => '过载',
  _ => '未知($status)',
};

/// 返回对应状态码的颜色：正常→绿，禁用→灰，其余→红
Color motorStatusColor(int status) => switch (status) {
  1 => Colors.green,
  0 => Colors.grey,
  _ => Colors.red,
};
