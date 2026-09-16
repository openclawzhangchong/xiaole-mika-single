import 'dart:io';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// 定位能力服务 —— v6.3.0
///
/// 把"设备定位"封装成纯 Dart 接口，供 MCP 工具 `self.location.get_current` 调用
/// （见 `chat_page._setupMcpResponder`）。
///
/// ## 设计原则（与 DeviceCapabilityService 一致）
/// 1. **只做能力封装**：不含任何 MCP 协议逻辑；
/// 2. **返回结构化结果**：统一 `{success, message, latitude, longitude,
///    accuracy, coordType, provider}`，**所有异常一律在内部消化**，绝不外抛；
/// 3. **绝不阻塞 UI**：全程异步 + 超时（8s）降级，失败即返回结构化错误；
/// 4. **坐标系**：Android/iOS 原生 GPS 为 WGS-84，国内地图（高德/腾讯/百度）用
///    GCJ-02，故内部完成 **WGS-84→GCJ-02 转换**，对外统一输出 GCJ-02；
/// 5. **隐私**：仅 AI 调用时按需取位，绝不后台采集。
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  static bool get _isAndroid => Platform.isAndroid;

  Map<String, dynamic> _fail(String msg) => {'success': false, 'message': msg};

  /// 获取当前位置。返回结构化结果，异常全部内部消化。
  ///
  /// 流程：权限检查/申请 → 定位服务开关检查 → 取位（高精 8s 超时降级最近已知）
  /// → WGS-84→GCJ-02 → 返回 GCJ-02 坐标。
  Future<Map<String, dynamic>> getCurrent() async {
    if (!_isAndroid) {
      // 桌面调试（Windows）无 GPS；iOS 走同一套 geolocator，此处不特殊排除。
      // 但为安全起见，非 Android/iOS 直接返回提示，避免无意义的原生崩溃。
      if (!Platform.isIOS) {
        return _fail('定位仅支持 Android / iOS（当前平台不支持）');
      }
    }

    // ① 权限
    try {
      final perm = await Permission.locationWhenInUse.status;
      if (perm.isPermanentlyDenied) {
        return _fail('定位权限已被永久拒绝，请到系统设置中开启「小乐」的定位权限');
      }
      if (perm.isDenied) {
        final req = await Permission.locationWhenInUse.request();
        if (!req.isGranted) {
          return _fail('定位权限被拒绝（请允许本应用使用定位后重试）');
        }
      }
    } catch (e) {
      return _fail('定位权限检查失败：$e');
    }

    // ② 定位服务是否开启
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        return _fail('定位服务未开启，请在系统设置中打开「位置信息」');
      }
    } catch (e) {
      return _fail('无法确认定位服务状态：$e');
    }

    // ③ 取位（高精，8s 超时降级最近已知位置）
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      // 高精超时/失败：降级到最近一次已知位置（网络/低精度）
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {
        pos = null;
      }
    }
    if (pos == null) {
      return _fail('获取定位超时或失败，请确认已开启 GPS 并在室外/窗边重试');
    }

    // ④ WGS-84 → GCJ-02（国内地图通用坐标系）
    final gcj = wgs84ToGcj02(pos.latitude, pos.longitude);

    // geolocator 4.x 的 Position 无 source 字段，按精度/是否模拟推断 provider
    final provider = pos.isMocked
        ? 'mock'
        : (pos.hasAccuracy && pos.accuracy <= 50 ? 'gps' : 'network');

    return {
      'success': true,
      'latitude': gcj['lat'],
      'longitude': gcj['lng'],
      'accuracy': pos.accuracy,
      'coordType': 'gcj02',
      'provider': provider,
      'mocked': pos.isMocked,
      'message': '已获取当前位置（GCJ-02，精度 ${pos.accuracy.toStringAsFixed(0)} 米）',
    };
  }
}

// ====================================================================
// WGS-84 → GCJ-02 坐标转换（标准算法，纯函数，可单测校验已知点）
// ====================================================================

const double _kA = 6378245.0;
const double _kEe = 0.00669342162296594323;
const double _kPi = math.pi;

double _transformLat(double x, double y) {
  double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y +
      0.2 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * _kPi) + 20.0 * math.sin(2.0 * x * _kPi)) *
      2.0 / 3.0;
  ret += (20.0 * math.sin(y * _kPi) + 40.0 * math.sin(y / 3.0 * _kPi)) *
      2.0 / 3.0;
  ret += (160.0 * math.sin(y / 12.0 * _kPi) + 320.0 * math.sin(y * _kPi / 30.0)) *
      2.0 / 3.0;
  return ret;
}

double _transformLng(double x, double y) {
  double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y +
      0.1 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * _kPi) + 20.0 * math.sin(2.0 * x * _kPi)) *
      2.0 / 3.0;
  ret += (20.0 * math.sin(x * _kPi) + 40.0 * math.sin(x / 3.0 * _kPi)) *
      2.0 / 3.0;
  ret += (150.0 * math.sin(x / 12.0 * _kPi) + 300.0 * math.sin(x / 30.0 * _kPi)) *
      2.0 / 3.0;
  return ret;
}

bool _outOfChina(double lat, double lng) {
  return lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;
}

/// WGS-84 → GCJ-02。中国境外坐标原样返回（GCJ-02 仅对中国境内有效）。
Map<String, double> wgs84ToGcj02(double lat, double lng) {
  if (_outOfChina(lat, lng)) {
    return {'lat': lat, 'lng': lng};
  }
  final dLat = _transformLat(lng - 105.0, lat - 35.0);
  final dLng = _transformLng(lng - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * _kPi;
  var magic = math.sin(radLat);
  magic = 1 - _kEe * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  final mgLat = lat +
      (dLat * 180.0) / ((_kA * (1 - _kEe)) / (magic * sqrtMagic) * _kPi);
  final mgLng =
      lng + (dLng * 180.0) / (_kA / sqrtMagic * math.cos(radLat) * _kPi);
  return {'lat': mgLat, 'lng': mgLng};
}
