// v6.3.0：WGS-84 → GCJ-02 坐标转换单测
//
// 期望值来自标准 GCJ-02 算法（与本项目 location_service.dart 中实现的同一套公式），
// 用独立 Python 脚本按标准算法算出后硬编码为基准。测试断言本项目的纯函数
// `wgs84ToGcj02` 与标准算法输出一致（偏差 < 1e-6°，即 < 0.1m），
// 从而保证「对标准算法偏差 < 1m」这一验收要求。
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaozhi_client_flutter/core/mcp/location_service.dart';

void main() {
  // 已知 WGS-84 点 → 标准算法算出的 GCJ-02 基准（lat, lng）
  // （由独立 Python 实现的标准算法得出，作为权威基准）
  const cases = <Map<String, double>>[
    // 天安门
    {
      'wlat': 39.908823, 'wlng': 116.397470,
      'glat': 39.9102264981, 'glng': 116.4037135824,
    },
    // 上海人民广场
    {
      'wlat': 31.230416, 'wlng': 121.473701,
      'glat': 31.2284737422, 'glng': 121.4782240574,
    },
    // 昆明
    {
      'wlat': 25.045, 'wlng': 102.707,
      'glat': 25.0420205254, 'glng': 102.7084313176,
    },
    // 香港
    {
      'wlat': 22.3193, 'wlng': 114.1694,
      'glat': 22.3165507994, 'glng': 114.1743670663,
    },
  ];

  group('wgs84ToGcj02 与标准算法一致', () {
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      test('已知点 #$i', () {
        final out = wgs84ToGcj02(c['wlat']!, c['wlng']!);
        // 偏差 < 1e-6°（约 0.1m），确认与标准算法逐字节一致
        expect((out['lat']! - c['glat']!).abs(), lessThan(1e-6));
        expect((out['lng']! - c['glng']!).abs(), lessThan(1e-6));
      });
    }
  });

  test('境外坐标原样返回（GCJ-02 仅对中国境内有效）', () {
    // 纽约：应原样返回，不做偏移
    final out = wgs84ToGcj02(40.7128, -74.0060);
    expect(out['lat'], 40.7128);
    expect(out['lng'], -74.0060);
  });

  test('偏移量级合理（境内点偏移约数百米，非公里级）', () {
    final out = wgs84ToGcj02(39.908823, 116.397470);
    final dLatM = (out['lat']! - 39.908823) * 111320;
    final dLngM =
        (out['lng']! - 116.397470) * 111320 * math.cos(39.908823 * math.pi / 180);
    // 北京地区 GCJ-02 偏移典型为数百米
    expect(dLatM.abs(), greaterThan(50));
    expect(dLatM.abs(), lessThan(1000));
    expect(dLngM.abs(), greaterThan(50));
    expect(dLngM.abs(), lessThan(1000));
  });
}
