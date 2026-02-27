class PingRow {
  const PingRow({
    required this.host,
    required this.ip,
    this.rttMs,
    this.ttl,
    this.successCount = 0,
    this.failCount = 0,
    this.isUp = false,
    this.lastChecked,
  });

  final String host;
  final String ip;
  final int? rttMs;
  final int? ttl;
  final int successCount;
  final int failCount;
  final bool isUp;
  final DateTime? lastChecked;

  PingRow copyWith({
    String? host,
    String? ip,
    int? rttMs,
    bool clearRtt = false,
    int? ttl,
    bool clearTtl = false,
    int? successCount,
    int? failCount,
    bool? isUp,
    DateTime? lastChecked,
  }) {
    return PingRow(
      host: host ?? this.host,
      ip: ip ?? this.ip,
      rttMs: clearRtt ? null : (rttMs ?? this.rttMs),
      ttl: clearTtl ? null : (ttl ?? this.ttl),
      successCount: successCount ?? this.successCount,
      failCount: failCount ?? this.failCount,
      isUp: isUp ?? this.isUp,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}
