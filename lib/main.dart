import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models/ping_row.dart';
import 'services/ping_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    minimumSize: Size(1000, 600),
    center: true,
    title: 'IoT Ping Dashboard',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const IotPingApp());
}

class IotPingApp extends StatelessWidget {
  const IotPingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IoT Ping Dashboard',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const PingDashboardPage(),
    );
  }
}

class PingDashboardPage extends StatefulWidget {
  const PingDashboardPage({super.key});

  @override
  State<PingDashboardPage> createState() => _PingDashboardPageState();
}

class _PingDashboardPageState extends State<PingDashboardPage> {
  final PingService _pingService = const PingService();
  final TextEditingController _startIpController = TextEditingController(
    text: '192.168.55.20',
  );
  final TextEditingController _countController = TextEditingController(
    text: '10',
  );

  List<PingRow> _rows = const <PingRow>[];
  bool _isRunning = false;
  String? _lastError;
  int _runToken = 0;

  @override
  void initState() {
    super.initState();
    _rows = _buildRowsFromInput();
  }

  @override
  void dispose() {
    _isRunning = false;
    _runToken++;
    _startIpController.dispose();
    _countController.dispose();
    super.dispose();
  }

  List<PingRow> _buildRowsFromInput() {
    final parsed = _parseNetworkConfig(
      _startIpController.text.trim(),
      _countController.text.trim(),
    );

    if (!parsed.isValid) {
      return _rows;
    }

    final List<PingRow> rows = <PingRow>[];
    for (var i = 0; i < parsed.count; i++) {
      final octet = parsed.startLastOctet + i;
      final ip = '${parsed.prefix}.$octet';
      rows.add(PingRow(host: 'Device ${i + 1}', ip: ip));
    }
    return rows;
  }

  _NetworkConfig _parseNetworkConfig(String startIp, String countText) {
    final count = int.tryParse(countText);
    if (count == null || count <= 0) {
      return const _NetworkConfig.invalid('Count must be a positive integer.');
    }

    final parts = startIp.split('.');
    if (parts.length != 4) {
      return const _NetworkConfig.invalid(
        'Start IP must be a valid IPv4 address.',
      );
    }

    final octets = parts.map(int.tryParse).toList();
    if (octets.any((value) => value == null)) {
      return const _NetworkConfig.invalid(
        'Start IP must contain numeric octets.',
      );
    }

    final values = octets.cast<int>();
    final allOctetsValid = values.every((part) => part >= 0 && part <= 255);
    if (!allOctetsValid) {
      return const _NetworkConfig.invalid(
        'IPv4 octets must be between 0 and 255.',
      );
    }

    final startLastOctet = values[3];
    if (startLastOctet + count - 1 > 254) {
      return const _NetworkConfig.invalid(
        'Last octet range exceeds 254. Lower count or start IP.',
      );
    }

    final prefix = '${values[0]}.${values[1]}.${values[2]}';
    return _NetworkConfig.valid(
      prefix: prefix,
      startLastOctet: startLastOctet,
      count: count,
    );
  }

  void _applyConfig() {
    final parsed = _parseNetworkConfig(
      _startIpController.text.trim(),
      _countController.text.trim(),
    );

    if (!parsed.isValid) {
      setState(() {
        _lastError = parsed.error;
      });
      return;
    }

    setState(() {
      _lastError = null;
      _rows = _buildRowsFromInput();
    });
  }

  Future<void> _startMonitoring() async {
    if (!Platform.isWindows || _isRunning) {
      return;
    }

    final parsed = _parseNetworkConfig(
      _startIpController.text.trim(),
      _countController.text.trim(),
    );
    if (!parsed.isValid) {
      setState(() {
        _lastError = parsed.error;
      });
      return;
    }

    setState(() {
      _lastError = null;
      _rows = _buildRowsFromInput();
      _isRunning = true;
    });

    final activeToken = ++_runToken;
    while (_isRunning && activeToken == _runToken) {
      for (var index = 0; index < _rows.length; index++) {
        if (!_isRunning || activeToken != _runToken) {
          break;
        }

        final currentRow = _rows[index];
        final result = await _pingService.ping(currentRow.ip);
        if (!mounted || activeToken != _runToken) {
          return;
        }

        setState(() {
          final now = DateTime.now();
          final updatedRow = result.success
              ? currentRow.copyWith(
                  rttMs: result.rttMs,
                  ttl: result.ttl,
                  successCount: currentRow.successCount + 1,
                  isUp: true,
                  lastChecked: now,
                )
              : currentRow.copyWith(
                  clearRtt: true,
                  clearTtl: true,
                  failCount: currentRow.failCount + 1,
                  isUp: false,
                  lastChecked: now,
                );

          _rows[index] = updatedRow;
          if (result.errorMessage != null) {
            _lastError = result.errorMessage;
          } else if (result.success) {
            _lastError = null;
          }
        });

        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  void _stopMonitoring() {
    setState(() {
      _isRunning = false;
      _runToken++;
    });
  }

  Future<void> _closeApp() async {
    _stopMonitoring();
    await windowManager.close();
  }

  String _formatLastChecked(DateTime? value) {
    if (value == null) {
      return '-';
    }

    String twoDigits(int input) => input.toString().padLeft(2, '0');
    return '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
  }

  Widget _buildStatusIndicator(PingRow row) {
    final color = row.isUp ? Colors.green : Colors.red;
    final label = row.isUp ? 'UP' : 'DOWN';
    return Tooltip(
      message: '$label - Last check: ${_formatLastChecked(row.lastChecked)}',
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWindows = Platform.isWindows;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.f10): const _ExitIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ExitIntent: CallbackAction<_ExitIntent>(
            onInvoke: (intent) {
              _closeApp();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('IoT Ping Dashboard'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _startIpController,
                          enabled: !_isRunning,
                          decoration: const InputDecoration(
                            labelText: 'Start IP',
                            hintText: '192.168.55.20',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _applyConfig(),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _countController,
                          enabled: !_isRunning,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Count',
                            hintText: '10',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _applyConfig(),
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: _isRunning ? null : _applyConfig,
                        child: const Text('Apply'),
                      ),
                      FilledButton(
                        onPressed: !isWindows
                            ? null
                            : (_isRunning ? _stopMonitoring : _startMonitoring),
                        child: Text(_isRunning ? 'Stop' : 'Start'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _closeApp,
                        icon: const Icon(Icons.close),
                        label: const Text('Exit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!isWindows)
                    const Text(
                      'This dashboard is designed for Windows ping command execution.',
                      style: TextStyle(color: Colors.red),
                    ),
                  if (_lastError != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _lastError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const minW = 1000.0;
                        final effectiveW = constraints.maxWidth < minW
                            ? minW
                            : constraints.maxWidth;

                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: effectiveW),
                            child: SingleChildScrollView(
                              child: DataTable(
                                dataRowMinHeight: 56,
                                dataRowMaxHeight: 56,
                                columns: const <DataColumn>[
                                  DataColumn(label: Text('Host / IP')),
                                  DataColumn(label: Text('RTT (ms)')),
                                  DataColumn(label: Text('TTL')),
                                  DataColumn(label: Text('Success')),
                                  DataColumn(label: Text('Fail')),
                                  DataColumn(label: Text('Status')),
                                ],
                                rows: _rows
                                    .map(
                                      (row) => DataRow(
                                        cells: <DataCell>[
                                          DataCell(
                                            SizedBox(
                                              width: 250,
                                              child: Text(
                                                '${row.host} - ${row.ip}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(row.rttMs?.toString() ?? '-'),
                                          ),
                                          DataCell(
                                            Text(row.ttl?.toString() ?? '-'),
                                          ),
                                          DataCell(
                                            Text(row.successCount.toString()),
                                          ),
                                          DataCell(
                                            Text(row.failCount.toString()),
                                          ),
                                          DataCell(_buildStatusIndicator(row)),
                                        ],
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExitIntent extends Intent {
  const _ExitIntent();
}

class _NetworkConfig {
  const _NetworkConfig.valid({
    required this.prefix,
    required this.startLastOctet,
    required this.count,
  })  : isValid = true,
        error = null;

  const _NetworkConfig.invalid(this.error)
      : isValid = false,
        prefix = '',
        startLastOctet = 0,
        count = 0;

  final bool isValid;
  final String? error;
  final String prefix;
  final int startLastOctet;
  final int count;
}
