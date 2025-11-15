import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:icp_autorun/config/app_config.dart';

/// Manages wrangler processes for testing
class WranglerManager {
  static WranglerManager? _instance;
  final String projectRoot;
  final int port;
  Process? _process;
  bool _isReady = false;

  WranglerManager(this.projectRoot, this.port);

  /// Get current instance
  static WranglerManager get instance {
    if (_instance == null) {
      throw StateError('WranglerManager not initialized. Call initialize() first.');
    }
    return _instance!;
  }

  /// Get target endpoint URL
  String get endpoint => 'http://localhost:$port';
  
  /// Get API endpoint URL (alias for endpoint)
  String get endpointUrl => endpoint;

  /// Get API endpoint URL (static method)
  static String get apiEndpoint => instance.endpointUrl;

  /// Initialize wrangler process (static method)
  static Future<void> initialize() async {
    final projectRoot = _findProjectRoot();
    final port = await _findUnusedPort();
    _instance = WranglerManager(projectRoot, port);
    await _instance!.start();
    
    // Set the test endpoint in AppConfig so tests use the correct port
    AppConfig.setTestEndpoint(_instance!.endpoint);
  }

  /// Cleanup wrangler process (static method)
  static Future<void> cleanup() async {
    if (_instance != null) {
      await _instance!.stop();
      _instance = null;
    }
  }

  /// Find project root by looking for .git directory
  static String _findProjectRoot() {
    var current = Directory.current;
    while (current.parent.path != current.path) {
      if (Directory('${current.path}/.git').existsSync()) {
        return current.path;
      }
      current = current.parent;
    }
    return Directory.current.path;
  }

  /// Find an unused port
  static Future<int> _findUnusedPort() async {
    for (int port = 30000; port < 40000; port++) {
      try {
        final socket = await ServerSocket.bind('localhost', port);
        await socket.close();
        return port;
      } catch (e) {
        // Port is in use, try next
      }
    }
    throw Exception('Could not find unused port');
  }

  /// Start wrangler process
  Future<void> start() async {
    if (_process != null) {
      throw StateError('Wrangler already started');
    }

    print('=== Wrangler Manager: Initializing ===');
    print('Project root: $projectRoot');
    print('Found unused port: $port');
    print('Target endpoint: $endpoint');

    // Check if wrangler is already running on this port
    if (await _isWranglerRunningOnPort()) {
      print('Wrangler is already running on port $port');
      _isReady = true;
      return;
    }

    print('No processes found on port $port');
    print('Starting fresh wrangler process...');

    // Change to cloudflare-api directory
    final cloudflareApiDir = '$projectRoot/cloudflare-api';
    print('Changing to cloudflare-api directory: $cloudflareApiDir');

    // Start wrangler process
    _process = await Process.start(
      'wrangler',
      [
        'dev',
        '--port', '$port',
        '--persist-to', '.wrangler/state',
        '--var', 'ENVIRONMENT:development',
      ],
      workingDirectory: cloudflareApiDir,
      mode: ProcessStartMode.normal,
    );

    print('Wrangler process started with PID: ${_process!.pid}');
    
    // Wait for wrangler to be ready
    await _waitForWranglerReady();
  }

  /// Check if wrangler is already running on the specified port
  Future<bool> _isWranglerRunningOnPort() async {
    print('Checking if wrangler is already running on port $port...');
    
    try {
      // Use lsof to check if any process is using the port
      final result = await Process.run('lsof', ['-ti', ':$port']);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        final pids = result.stdout.toString().trim().split('\n');
        print('Found processes on port $port: $pids');
        
        // Check if any of these processes are wrangler
        for (final pid in pids) {
          if (await _isWranglerProcess(pid.trim())) {
            return true;
          }
        }
        print('No wrangler processes found on port $port');
        return false;
      }
    } catch (e) {
      print('Error checking port $port: $e');
    }
    
    return false;
  }

  /// Check if a process with given PID is a wrangler process
  Future<bool> _isWranglerProcess(String pid) async {
    try {
      final result = await Process.run('ps', ['-p', pid, '-o', 'command=']);
      if (result.exitCode == 0) {
        final command = result.stdout.toString().trim();
        print('Process $pid: $command');
        return command.contains('wrangler') && command.contains('dev');
      }
    } catch (e) {
      print('Error checking process $pid: $e');
    }
    return false;
  }

  /// Wait for wrangler to be ready
  Future<void> _waitForWranglerReady() async {
    print('Waiting for wrangler to fully start (this can take 10-20 seconds)...');
    
    final maxWaitTime = Duration(seconds: 45);
    final startTime = DateTime.now();
    int retryCount = 0;
    int delayMs = 500; // Start with 500ms
    
    while (DateTime.now().difference(startTime) < maxWaitTime) {
      try {
        final client = HttpClient();
        client.connectionTimeout = Duration(seconds: 5);
        final request = await client.getUrl(Uri.parse('$endpoint/health'));
        final response = await request.close().timeout(Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final responseData = await response.transform(utf8.decoder).join();
          print('✅ Wrangler process is running and responding');
          print('Checking health endpoint: $endpoint/health');
          print('✅ Wrangler became healthy in ${DateTime.now().difference(startTime).inMilliseconds}ms');
          print('Health check response: $responseData');
          print('✅ Wrangler is ready at $endpoint');
          _isReady = true;
          client.close();
          return;
        }
        client.close();
      } catch (e) {
        // Not ready yet, continue waiting with exponential backoff
        retryCount++;
        final elapsed = DateTime.now().difference(startTime);
        print('Health check attempt $retryCount failed (${elapsed.inSeconds}s/${maxWaitTime.inSeconds}s): $e');
      }
      
      // Exponential backoff with jitter
      await Future.delayed(Duration(milliseconds: delayMs));
      delayMs = (delayMs * 2).clamp(1000, 5000); // Between 1s and 5s
    }
    
    final elapsed = DateTime.now().difference(startTime);
    throw TimeoutException('Wrangler did not become ready within ${elapsed.inSeconds} seconds (tried $retryCount times)', maxWaitTime);
  }

  /// Stop wrangler process
  Future<void> stop() async {
    print('=== Wrangler Manager: Cleaning up ===');
    
    if (_process != null) {
      print('Attempting graceful wrangler shutdown...');
      try {
        _process!.kill();
        // Don't wait for exitCode on normal processes either - just give it time
        await Future.delayed(Duration(seconds: 2));
      } catch (e) {
        print('Error stopping wrangler process: $e');
      }
      _process = null;
    }

    // Also try to kill any remaining wrangler processes on this port
    await _killWranglerProcessesOnPort();
  }

  /// Kill any wrangler processes running on the specified port
  Future<void> _killWranglerProcessesOnPort() async {
    print('Attempting to stop wrangler processes...');
    
    try {
      final result = await Process.run('lsof', ['-ti', ':$port']);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        final pids = result.stdout.toString().trim().split('\n');
        print('Found processes on port $port to check: $pids');
        
        for (final pid in pids) {
          final pidTrim = pid.trim();
          if (pidTrim.isEmpty) continue;
          
          if (await _isWranglerProcess(pidTrim)) {
            print('Sending SIGTERM to wrangler process $pidTrim on port $port');
            final killResult = await Process.run('kill', ['-TERM', pidTrim]);
            if (killResult.exitCode == 0) {
              print('Successfully sent SIGTERM to wrangler process $pidTrim');
              // Give it a moment to terminate gracefully
              await Future.delayed(Duration(milliseconds: 500));
            } else {
              print('Failed to send SIGTERM to wrangler process $pidTrim: ${killResult.stderr}');
            }
          } else {
            print('Skipping non-wrangler process $pidTrim');
          }
        }
      }
    } catch (e) {
      print('Error stopping wrangler processes: $e');
    }
  }

  /// Check if wrangler is ready
  bool get isReady => _isReady;
}