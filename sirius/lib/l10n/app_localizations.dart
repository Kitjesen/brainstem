import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en', ''),
    Locale('zh', ''),
  ];

  // Navigation
  String get navDashboard => locale.languageCode == 'zh' ? '仪表盘' : 'Dashboard';
  String get navMonitor => locale.languageCode == 'zh' ? '监控' : 'Monitor';
  String get navControl => locale.languageCode == 'zh' ? '控制' : 'Control';
  String get navParams => locale.languageCode == 'zh' ? '参数' : 'Params';
  String get navProtocol => locale.languageCode == 'zh' ? '协议' : 'Protocol';
  String get navImu     => locale.languageCode == 'zh' ? '姿态' : 'IMU';
  String get navHistory => locale.languageCode == 'zh' ? '记录' : 'History';
  String get navBrain   => locale.languageCode == 'zh' ? '智脑' : 'Brain';
  String get navOta     => locale.languageCode == 'zh' ? 'OTA' : 'OTA';

  // Theme
  String get themeColor => locale.languageCode == 'zh' ? '主题颜色' : 'Theme Color';
  String get colorPurple => locale.languageCode == 'zh' ? '紫色' : 'Purple';
  String get colorBlue => locale.languageCode == 'zh' ? '蓝色' : 'Blue';
  String get colorTeal => locale.languageCode == 'zh' ? '青色' : 'Teal';
  String get colorGreen => locale.languageCode == 'zh' ? '绿色' : 'Green';
  String get colorOrange => locale.languageCode == 'zh' ? '橙色' : 'Orange';
  String get colorPink => locale.languageCode == 'zh' ? '粉色' : 'Pink';

  // Common
  String get appTitle => locale.languageCode == 'zh' ? 'Sirius' : 'Sirius';
  String get connected => locale.languageCode == 'zh' ? '已连接' : 'Connected';
  String get disconnected => locale.languageCode == 'zh' ? '未连接' : 'Disconnected';

  // Error messages
  String get errorInvalidIP => locale.languageCode == 'zh' ? 'IP 地址格式错误' : 'Invalid IP address format';
  String get errorInvalidPort => locale.languageCode == 'zh' ? '端口号必须在 1-65535 之间' : 'Port must be between 1-65535';
  String get errorFileNotFound => locale.languageCode == 'zh' ? '文件不存在' : 'File not found';
  String get errorInvalidFileFormat => locale.languageCode == 'zh' ? '文件格式错误' : 'Invalid file format';
  String get errorFileTooLarge => locale.languageCode == 'zh' ? '文件过大' : 'File too large';
  String get errorInvalidPath => locale.languageCode == 'zh' ? '文件路径包含非法字符' : 'File path contains invalid characters';
  String get errorConnectionFailed => locale.languageCode == 'zh' ? '连接失败' : 'Connection failed';
  String get errorEmergencyStop => locale.languageCode == 'zh' ? '紧急停止已触发' : 'Emergency stop triggered';

  // Success messages
  String get successConnected => locale.languageCode == 'zh' ? '已连接' : 'Connected';
  String get successDisconnected => locale.languageCode == 'zh' ? '已断开' : 'Disconnected';
  String get successImported => locale.languageCode == 'zh' ? '导入成功' : 'Import successful';
  String get successExported => locale.languageCode == 'zh' ? '导出成功' : 'Export successful';
  String get successSaved => locale.languageCode == 'zh' ? '保存成功' : 'Saved successfully';
  String get successDeleted => locale.languageCode == 'zh' ? '删除成功' : 'Deleted successfully';
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'zh'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
