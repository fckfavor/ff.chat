import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sandbox_config.dart';
import 'sandbox_service.dart';

/// Shell calistirma sonucu.
class ShellResult {
  ShellResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.combined,
    required this.duration,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final String combined;
  final Duration duration;
  final bool timedOut;

  bool get success => exitCode == 0;

  Map<String, dynamic> toJson() => {
        'exitCode': exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'success': success,
        'timedOut': timedOut,
      };

  @override
  String toString() => combined.isEmpty ? '(no output)' : combined;
}

/// Android Linux sandbox icinde shell komutu calistirir.
///
/// MVP: `/system/bin/sh -c "cmd"` + workspace workingDirectory
/// V2:  proot -r rootfs -b workspace:/workspace sh -c "cmd"
class ShellExecutor {
  ShellExecutor._();
  static final ShellExecutor instance = ShellExecutor._();

  static const Duration defaultTimeout = Duration(seconds: 30);
  static const int maxOutputBytes = 1024 * 1024; // 1MB

  /// Verilen komutu calistir ve sonucu dondur.
  /// [command] shell komutu (or: "ls -la", "cat main.dart", "npm install")
  /// [workingDir] workspace'e gore relative (or: "project", ".")
  /// [timeout] default 30s
  Future<ShellResult> run(
    String command, {
    String workingDir = '.',
    Duration timeout = defaultTimeout,
    Map<String, String>? env,
  }) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'empty command',
        combined: 'empty command',
        duration: Duration.zero,
      );
    }
    if (SandboxConfig.isBlocked(trimmed)) {
      return ShellResult(
        exitCode: 126,
        stdout: '',
        stderr: 'blocked command (security policy): $trimmed',
        combined: 'blocked command',
        duration: Duration.zero,
      );
    }

    final sw = Stopwatch()..start();
    final workspaceRoot = await SandboxConfig.getWorkspaceRoot();
    final absoluteWorkDir = await SandboxConfig.resolve(workingDir);

    // workingDir yoksa olustur
    await Directory(absoluteWorkDir).create(recursive: true);

    // Proot sandbox check — varsa proot ile sarmala
    final prootWrap = await SandboxService.instance.wrapCommand(trimmed, absoluteWorkDir);
    final bool useProot = prootWrap['useProot'] == true;
    final String shell;
    final List<String> args;
    final String spawnWorkDir;
    if (useProot) {
      shell = prootWrap['executable'] as String;
      args = List<String>.from(prootWrap['args'] as List);
      spawnWorkDir = workspaceRoot; // proot -w ile icerde ayarlar
    } else {
      shell = _detectShell();
      args = _shellArgs(shell, trimmed);
      spawnWorkDir = absoluteWorkDir;
    }

    try {
      final process = await Process.start(
        shell,
        args,
        workingDirectory: spawnWorkDir,
        environment: useProot ? _buildProotEnv(env, workspaceRoot) : _buildEnv(env, workspaceRoot),
        runInShell: false,
      );

      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();
      var outputBytes = 0;
      var truncated = false;

      // stdout/stderr'i dinle, 1MB'i gecerse truncate et
      final stdoutSub = process.stdout.transform(utf8.decoder).listen((chunk) {
        if (truncated) return;
        outputBytes += chunk.length;
        if (outputBytes > maxOutputBytes) {
          truncated = true;
          stdoutBuf.write('\n[output truncated at 1MB]');
          return;
        }
        stdoutBuf.write(chunk);
      });
      final stderrSub = process.stderr.transform(utf8.decoder).listen((chunk) {
        if (truncated) return;
        outputBytes += chunk.length;
        if (outputBytes > maxOutputBytes) {
          truncated = true;
          stderrBuf.write('\n[output truncated]');
          return;
        }
        stderrBuf.write(chunk);
      });

      int exitCode;
      bool timedOut = false;
      try {
        exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
          timedOut = true;
          process.kill(ProcessSignal.sigkill);
          return 124; // timeout exit code (like GNU timeout)
        });
      } finally {
        await stdoutSub.cancel();
        await stderrSub.cancel();
      }

      sw.stop();
      final stdoutStr = stdoutBuf.toString();
      final stderrStr = stderrBuf.toString();
      final combined = [
        if (stdoutStr.isNotEmpty) stdoutStr,
        if (stderrStr.isNotEmpty) stderrStr,
      ].join('\n');

      // Proses hala yasiyorsa oldur
      if (timedOut) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }

      return ShellResult(
        exitCode: exitCode,
        stdout: stdoutStr,
        stderr: stderrStr,
        combined: timedOut ? '[timed out after ${timeout.inSeconds}s]\n$combined' : combined,
        duration: sw.elapsed,
        timedOut: timedOut,
      );
    } catch (e) {
      sw.stop();
      return ShellResult(
        exitCode: 127,
        stdout: '',
        stderr: 'failed to spawn shell ($shell): $e',
        combined: 'failed to spawn: $e',
        duration: sw.elapsed,
      );
    }
  }

  /// Komutu stream olarak calistir — her cikti chunk'ini yield eder.
  /// Uzun sureli komutlar (npm install, python train.py) icin.
  Stream<String> runStreaming(
    String command, {
    String workingDir = '.',
    Duration timeout = const Duration(minutes: 5),
  }) async* {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      yield 'empty command';
      return;
    }
    if (SandboxConfig.isBlocked(trimmed)) {
      yield 'blocked command: $trimmed';
      return;
    }
    final absoluteWorkDir = await SandboxConfig.resolve(workingDir);
    await Directory(absoluteWorkDir).create(recursive: true);
    final workspaceRoot = await SandboxConfig.getWorkspaceRoot();
    final prootWrap = await SandboxService.instance.wrapCommand(trimmed, absoluteWorkDir);
    final bool useProot = prootWrap['useProot'] == true;
    final String shell;
    final List<String> args;
    final String spawnWorkDir;
    if (useProot) {
      shell = prootWrap['executable'] as String;
      args = List<String>.from(prootWrap['args'] as List);
      spawnWorkDir = workspaceRoot;
    } else {
      shell = _detectShell();
      args = _shellArgs(shell, trimmed);
      spawnWorkDir = absoluteWorkDir;
    }

    final process = await Process.start(
      shell,
      args,
      workingDirectory: spawnWorkDir,
      environment: useProot ? _buildProotEnv(null, workspaceRoot) : _buildEnv(null, workspaceRoot),
      runInShell: false,
    );

    // Timeout guard
    Timer? timer;
    timer = Timer(timeout, () {
      process.kill(ProcessSignal.sigkill);
    });

    final stdoutStream = process.stdout.transform(utf8.decoder);
    final stderrStream = process.stderr.transform(utf8.decoder);

    // stdout ve stderr'i merge et
    final controller = StreamController<String>();
    var doneCount = 0;
    void checkDone() {
      doneCount++;
      if (doneCount == 2) controller.close();
    }

    stdoutStream.listen(
      (d) => controller.add(d),
      onDone: checkDone,
      onError: (e) => controller.addError(e),
    );
    stderrStream.listen(
      (d) => controller.add(d),
      onDone: checkDone,
      onError: (e) => controller.addError(e),
    );

    await for (final chunk in controller.stream) {
      yield chunk;
    }

    final exitCode = await process.exitCode;
    timer.cancel();
    yield '\n[exit $exitCode]';
  }

  String _detectShell() {
    if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
      // Android'de /system/bin/sh her zaman var
      if (File('/system/bin/sh').existsSync()) return '/system/bin/sh';
      if (File('/bin/sh').existsSync()) return '/bin/sh';
      return 'sh';
    }
    if (Platform.isWindows) return 'cmd';
    return 'sh';
  }

  List<String> _shellArgs(String shell, String command) {
    if (shell == 'cmd') return ['/c', command];
    return ['-c', command];
  }

  Map<String, String> _buildEnv(Map<String, String>? extra, String workspaceRoot) {
    final env = <String, String>{
      'TERM': 'xterm-256color',
      'HOME': workspaceRoot,
      'WORKSPACE': workspaceRoot,
      'PATH': '/system/bin:/system/xbin:/vendor/bin:${Platform.environment['PATH'] ?? ''}',
    };
    if (extra != null) env.addAll(extra);
    // API key gibi hassas seyleri env'e koyma — DynamicHttpClient zaten ayri yonetiyor
    return env;
  }

  /// Proot icinde rootfs PATH kullan (busybox /usr/bin:/bin)
  Map<String, String> _buildProotEnv(Map<String, String>? extra, String workspaceRoot) {
    final env = <String, String>{
      'TERM': 'xterm-256color',
      'HOME': '/root',
      'LANG': 'C.UTF-8',
      'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
    };
    if (extra != null) env.addAll(extra);
    return env;
  }

  /// Hizli health check: shell calisiyor mu?
  Future<bool> checkHealth() async {
    final result = await run('echo ok', timeout: const Duration(seconds: 5));
    return result.success && result.stdout.contains('ok');
  }
}
