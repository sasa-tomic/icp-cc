import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Configuration for HTTP request retry logic
class HttpRequestConfig {
  final Duration timeout;
  final Duration retryDelay;
  final int maxRetries;
  final int minSuccessCode;
  final int maxSuccessCode;
  final String? userMessage;

  const HttpRequestConfig({
    this.timeout = const Duration(seconds: 30),
    this.retryDelay = const Duration(milliseconds: 200),
    this.maxRetries = 10,
    this.minSuccessCode = 200,
    this.maxSuccessCode = 299,
    this.userMessage,
  });
}

/// Result of an HTTP request with retry logic
class HttpRequestResult {
  final http.Response response;
  final int attempts;
  final Duration totalTime;

  HttpRequestResult({
    required this.response,
    required this.attempts,
    required this.totalTime,
  });

  bool get isSuccess => response.statusCode >= 200 && response.statusCode <= 299;
}

/// Robust HTTP helper for tests with retry logic and detailed error reporting
/// 
/// IMPORTANT: TestWidgetsFlutterBinding HTTP Mocking Issue
/// =====================================================
/// When a test file contains ANY testWidgets, Flutter automatically:
/// 1. Sets up TestWidgetsFlutterBinding
/// 2. Mocks ALL HTTP requests via HttpClient  
/// 3. Returns HTTP 400 with empty response body for ALL requests
/// 4. Affects BOTH testWidgets AND regular test functions in same file
/// 
/// SOLUTION: Separate UI tests (testWidgets) from API tests (test) into different files
/// See: HTTP_TEST_DEBUGGING_ROOT_CAUSE.md for full analysis
class HttpTestHelper {
  static const HttpRequestConfig _defaultConfig = HttpRequestConfig();

  /// Execute HTTP GET request with retry logic
  static Future<HttpRequestResult> get(
    String url, {
    HttpRequestConfig? config,
    Map<String, String>? headers,
  }) async {
    // In Flutter test environment, use HttpClient to avoid networking issues
    if (kDebugMode && !kReleaseMode) {
      return _executeRequestWithClient(
        () async {
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse(url));
          if (headers != null) {
            headers.forEach((key, value) => request.headers.set(key, value));
          }
          final response = await request.close();
          final responseBody = await response.transform(utf8.decoder).join();
          return _convertHttpClientResponse(response, responseBody);
        },
        config: config,
        requestType: 'GET',
        url: url,
      );
    }
    
    return _executeRequest(
      () => http.get(Uri.parse(url), headers: headers),
      config: config,
      requestType: 'GET',
      url: url,
    );
  }

  /// Execute HTTP POST request with retry logic
  static Future<HttpRequestResult> post(
    String url, {
    required Object body,
    HttpRequestConfig? config,
    Map<String, String>? headers,
  }) async {
    // In Flutter test environment, use HttpClient to avoid networking issues
    if (kDebugMode && !kReleaseMode) {
      return _executeRequestWithClient(
        () async {
          final client = HttpClient();
          final request = await client.postUrl(Uri.parse(url));
          if (headers != null) {
            headers.forEach((key, value) => request.headers.set(key, value));
          }
          request.write(body);
          final response = await request.close();
          final responseBody = await response.transform(utf8.decoder).join();
          return _convertHttpClientResponse(response, responseBody);
        },
        config: config,
        requestType: 'POST',
        url: url,
      );
    }
    
    return _executeRequest(
      () => http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      ),
      config: config,
      requestType: 'POST',
      url: url,
      body: body,
    );
  }

  /// Execute HTTP PUT request with retry logic
  static Future<HttpRequestResult> put(
    String url, {
    required Object body,
    HttpRequestConfig? config,
    Map<String, String>? headers,
  }) async {
    // In Flutter test environment, use HttpClient to avoid networking issues
    if (kDebugMode && !kReleaseMode) {
      return _executeRequestWithClient(
        () async {
          final client = HttpClient();
          final request = await client.putUrl(Uri.parse(url));
          if (headers != null) {
            headers.forEach((key, value) => request.headers.set(key, value));
          }
          request.write(body);
          final response = await request.close();
          final responseBody = await response.transform(utf8.decoder).join();
          return _convertHttpClientResponse(response, responseBody);
        },
        config: config,
        requestType: 'PUT',
        url: url,
      );
    }
    
    return _executeRequest(
      () => http.put(
        Uri.parse(url),
        headers: headers,
        body: body,
      ),
      config: config,
      requestType: 'PUT',
      url: url,
      body: body,
    );
  }

  /// Execute HTTP DELETE request with retry logic
  static Future<HttpRequestResult> delete(
    String url, {
    HttpRequestConfig? config,
    Map<String, String>? headers,
  }) async {
    // In Flutter test environment, use HttpClient to avoid networking issues
    if (kDebugMode && !kReleaseMode) {
      return _executeRequestWithClient(
        () async {
          final client = HttpClient();
          final request = await client.deleteUrl(Uri.parse(url));
          if (headers != null) {
            headers.forEach((key, value) => request.headers.set(key, value));
          }
          final response = await request.close();
          final responseBody = await response.transform(utf8.decoder).join();
          return _convertHttpClientResponse(response, responseBody);
        },
        config: config,
        requestType: 'DELETE',
        url: url,
      );
    }
    
    return _executeRequest(
      () => http.delete(Uri.parse(url), headers: headers),
      config: config,
      requestType: 'DELETE',
      url: url,
    );
  }

  /// Execute HTTP request with retry logic and detailed error reporting
  static Future<HttpRequestResult> _executeRequest(
    Future<http.Response> Function() requestFunction, {
    HttpRequestConfig? config,
    required String requestType,
    required String url,
    Object? body,
  }) async {
    final effectiveConfig = config ?? _defaultConfig;
    final stopwatch = Stopwatch()..start();
    
    if (kDebugMode) {
      debugPrint('🔄 HTTP $requestType $url - Starting request with retry logic');
      if (body != null) {
        debugPrint('📤 Request body: $body');
      }
    }

    http.Response? lastResponse;
    String? lastError;

    for (int attempt = 1; attempt <= effectiveConfig.maxRetries; attempt++) {
      try {
        lastResponse = await requestFunction().timeout(effectiveConfig.timeout);
        
        if (kDebugMode) {
          debugPrint('📥 Attempt $attempt/${effectiveConfig.maxRetries}: HTTP ${lastResponse.statusCode}');
          debugPrint('📄 Response body: "${lastResponse.body}"');
          debugPrint('📋 Response headers: ${lastResponse.headers}');
        }

        // Check if response code is in success range
        if (lastResponse.statusCode >= effectiveConfig.minSuccessCode && 
            lastResponse.statusCode <= effectiveConfig.maxSuccessCode) {
          stopwatch.stop();
          final result = HttpRequestResult(
            response: lastResponse,
            attempts: attempt,
            totalTime: stopwatch.elapsed,
          );
          
          if (kDebugMode) {
            debugPrint('✅ HTTP $requestType $url - Success after $attempt attempt(s) in ${result.totalTime.inMilliseconds}ms');
          }
          
          return result;
        }

        // If we get a client error (4xx), don't retry - these are typically validation errors
        if (lastResponse.statusCode >= 400 && lastResponse.statusCode < 500) {
          stopwatch.stop();
          final result = HttpRequestResult(
            response: lastResponse,
            attempts: attempt,
            totalTime: stopwatch.elapsed,
          );
          
          if (kDebugMode) {
            debugPrint('❌ HTTP $requestType $url - Client error ${lastResponse.statusCode}, not retrying');
            debugPrint('🚨 ERROR RESPONSE BODY: "${lastResponse.body}"');
            if (lastResponse.body.isNotEmpty) {
              try {
                final parsedBody = jsonDecode(lastResponse.body);
                debugPrint('📋 PARSED ERROR: ${const JsonEncoder.withIndent('  ').convert(parsedBody)}');
              } catch (e) {
                debugPrint('📋 RAW ERROR (not JSON): ${lastResponse.body}');
              }
            }
          }
          
          return result;
        }

        lastError = 'HTTP ${lastResponse.statusCode}: ${lastResponse.reasonPhrase}';

      } catch (e) {
        lastError = e.toString();
        if (kDebugMode) {
          debugPrint('⚠️ Attempt $attempt/${effectiveConfig.maxRetries}: $e');
        }
      }

      // If this is not the last attempt, wait before retrying
      if (attempt < effectiveConfig.maxRetries) {
        await Future.delayed(effectiveConfig.retryDelay);
      }
    }

    // All attempts failed
    stopwatch.stop();
    
    // If we have a last response, use it (even if it's an error)
    if (lastResponse != null) {
      final result = HttpRequestResult(
        response: lastResponse,
        attempts: effectiveConfig.maxRetries,
        totalTime: stopwatch.elapsed,
      );
      
      if (kDebugMode) {
        debugPrint('❌ HTTP $requestType $url - Failed after ${effectiveConfig.maxRetries} attempt(s) in ${result.totalTime.inMilliseconds}ms');
      }
      
      return result;
    }

    // No response received, throw an exception
    final errorMessage = effectiveConfig.userMessage ?? 
        'HTTP $requestType $url failed after ${effectiveConfig.maxRetries} attempts: $lastError';
    
    if (kDebugMode) {
      debugPrint('💥 HTTP $requestType $url - No response after ${effectiveConfig.maxRetries} attempts in ${stopwatch.elapsed.inMilliseconds}ms');
    }
    
    throw Exception(errorMessage);
  }

  /// Execute HTTP request using HttpClient (for Flutter test environment)
  static Future<HttpRequestResult> _executeRequestWithClient(
    Future<http.Response> Function() requestFunction, {
    HttpRequestConfig? config,
    required String requestType,
    required String url,
  }) async {
    final effectiveConfig = config ?? _defaultConfig;
    final stopwatch = Stopwatch()..start();
    
    if (kDebugMode) {
      debugPrint('🔄 HTTP $requestType $url - Using HttpClient for Flutter test environment');
    }

    http.Response? lastResponse;
    String? lastError;

    for (int attempt = 1; attempt <= effectiveConfig.maxRetries; attempt++) {
      try {
        lastResponse = await requestFunction().timeout(effectiveConfig.timeout);
        
        if (kDebugMode) {
          debugPrint('📥 Attempt $attempt/${effectiveConfig.maxRetries}: HTTP ${lastResponse.statusCode}');
          debugPrint('📄 Response body: "${lastResponse.body}"');
          debugPrint('📋 Response headers: ${lastResponse.headers}');
        }

        // Check if response code is in success range
        if (lastResponse.statusCode >= effectiveConfig.minSuccessCode && 
            lastResponse.statusCode <= effectiveConfig.maxSuccessCode) {
          stopwatch.stop();
          final result = HttpRequestResult(
            response: lastResponse,
            attempts: attempt,
            totalTime: stopwatch.elapsed,
          );
          
          if (kDebugMode) {
            debugPrint('✅ HTTP $requestType $url - Success after $attempt attempt(s) in ${result.totalTime.inMilliseconds}ms');
          }
          
          return result;
        }

        // If we get a client error (4xx), don't retry - these are typically validation errors
        if (lastResponse.statusCode >= 400 && lastResponse.statusCode < 500) {
          stopwatch.stop();
          final result = HttpRequestResult(
            response: lastResponse,
            attempts: attempt,
            totalTime: stopwatch.elapsed,
          );
          
          if (kDebugMode) {
            debugPrint('❌ HTTP $requestType $url - Client error ${lastResponse.statusCode}, not retrying');
            debugPrint('🚨 ERROR RESPONSE BODY: "${lastResponse.body}"');
            if (lastResponse.body.isNotEmpty) {
              try {
                final parsedBody = jsonDecode(lastResponse.body);
                debugPrint('📋 PARSED ERROR: ${const JsonEncoder.withIndent('  ').convert(parsedBody)}');
              } catch (e) {
                debugPrint('📋 RAW ERROR (not JSON): ${lastResponse.body}');
              }
            }
          }
          
          return result;
        }

        lastError = 'HTTP ${lastResponse.statusCode}: ${lastResponse.reasonPhrase}';

      } catch (e) {
        lastError = e.toString();
        if (kDebugMode) {
          debugPrint('⚠️ Attempt $attempt/${effectiveConfig.maxRetries}: $e');
        }
      }

      // If this is not the last attempt, wait before retrying
      if (attempt < effectiveConfig.maxRetries) {
        await Future.delayed(effectiveConfig.retryDelay);
      }
    }

    // All attempts failed
    stopwatch.stop();
    
    // If we have a last response, use it (even if it's an error)
    if (lastResponse != null) {
      final result = HttpRequestResult(
        response: lastResponse,
        attempts: effectiveConfig.maxRetries,
        totalTime: stopwatch.elapsed,
      );
      
      if (kDebugMode) {
        debugPrint('❌ HTTP $requestType $url - Failed after ${effectiveConfig.maxRetries} attempt(s) in ${result.totalTime.inMilliseconds}ms');
      }
      
      return result;
    }

    // No response received, throw an exception
    final errorMessage = effectiveConfig.userMessage ?? 
        'HTTP $requestType $url failed after ${effectiveConfig.maxRetries} attempts: $lastError';
    
    if (kDebugMode) {
      debugPrint('💥 HTTP $requestType $url - No response after ${effectiveConfig.maxRetries} attempts in ${stopwatch.elapsed.inMilliseconds}ms');
    }
    
    throw Exception(errorMessage);
  }

  /// Convert HttpClient response to http.Response format
  static http.Response _convertHttpClientResponse(
    HttpClientResponse response,
    String responseBody,
  ) {
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.isNotEmpty ? values.first : '';
    });
    
    return http.Response(
      responseBody,
      response.statusCode,
      reasonPhrase: response.reasonPhrase,
      headers: headers,
    );
  }

  /// Wait for a condition to be true with retry logic
  static Future<T> waitForCondition<T>(
    Future<T> Function() condition, {
    Duration timeout = const Duration(seconds: 10),
    Duration retryDelay = const Duration(milliseconds: 200),
    String? errorMessage,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    while (stopwatch.elapsed < timeout) {
      try {
        final result = await condition();
        stopwatch.stop();
        return result;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⏳ Condition not met yet, retrying... ($e)');
        }
        await Future.delayed(retryDelay);
      }
    }
    
    stopwatch.stop();
    throw Exception(errorMessage ?? 'Condition not met after ${timeout.inSeconds} seconds');
  }
}