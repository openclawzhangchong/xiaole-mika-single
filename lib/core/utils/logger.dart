import 'package:logger/logger.dart';

import 'log_buffer.dart';

/// 日志工具类
///
/// v4.3.2：每个级别方法在输出前同步写一份进 [LogBuffer] 环形缓冲，
/// 使「开发者中心 → 📋 运行日志查看」也能复制到这里的日志。
/// 注：本项目当前实际主用 package:logging（汇聚于 main.dart 的
/// Logger.root.onRecord）；本类为既有封装，此处做增量补齐，
/// 避免将来调用它时日志漏采。
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
  );

  /// 把 [message] 与可选 [error] 合成一行写入缓冲区
  static void _buffer(String level, dynamic message, dynamic error) {
    final body = error == null ? '$message' : '$message | err=$error';
    LogBuffer.push(level, 'AppLogger', body);
  }

  /// Debug 日志
  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _buffer('D', message, error);
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Info 日志
  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _buffer('I', message, error);
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Warning 日志
  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _buffer('W', message, error);
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Error 日志
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _buffer('E', message, error);
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Fatal 日志
  static void f(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _buffer('F', message, error);
    _logger.f(message, error: error, stackTrace: stackTrace);
  }
}
