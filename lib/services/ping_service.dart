import 'dart:io';

class PingResult {
  const PingResult({
    required this.success,
    this.rttMs,
    this.ttl,
    this.rawOutput = '',
    this.errorMessage,
  });

  final bool success;
  final int? rttMs;
  final int? ttl;
  final String rawOutput;
  final String? errorMessage;
}

class PingService {
  const PingService();

  Future<PingResult> ping(String ip) async {
    try {
      final processResult = await Process.run('ping', <String>[
        '-n',
        '1',
        '-w',
        '800',
        ip,
      ]);

      final output = '${processResult.stdout}\n${processResult.stderr}';
      final normalizedOutput = output.toLowerCase();
      final parsedRtt = _parseRtt(output);
      final parsedTtl = _parseTtl(output);

      final hasReplyFrom = normalizedOutput.contains('reply from');
      final hasTtl = normalizedOutput.contains('ttl=');
      final hasTimeout = normalizedOutput.contains('request timed out');
      final hasUnreachable =
          normalizedOutput.contains('destination host unreachable');

      final isDown = hasTimeout || hasUnreachable || processResult.exitCode != 0;
      final isUp = (hasReplyFrom || hasTtl) && !isDown;

      return PingResult(
        success: isUp,
        rttMs: parsedRtt,
        ttl: parsedTtl,
        rawOutput: output,
        errorMessage: null,
      );
    } on ProcessException catch (error) {
      return PingResult(
        success: false,
        rawOutput: '',
        errorMessage: 'Could not execute ping command: $error',
      );
    } catch (error) {
      return PingResult(
        success: false,
        rawOutput: '',
        errorMessage: 'Unexpected ping error: $error',
      );
    }
  }

  int? _parseRtt(String output) {
    final regex = RegExp(r'time[=<]\s*(\d+)\s*ms', caseSensitive: false);
    final match = regex.firstMatch(output);
    if (match == null) {
      return null;
    }

    return int.tryParse(match.group(1)!);
  }

  int? _parseTtl(String output) {
    final regex = RegExp(r'ttl[=\s:]+(\d+)', caseSensitive: false);
    final match = regex.firstMatch(output);
    if (match == null) {
      return null;
    }

    return int.tryParse(match.group(1)!);
  }
}
