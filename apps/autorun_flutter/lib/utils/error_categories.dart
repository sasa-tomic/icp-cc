import 'package:flutter/material.dart';

enum ErrorCategoryType {
  network,
  authentication,
  validation,
  notFound,
  server,
  rateLimit,
  unknown,
}

class ErrorInfo {
  final String title;
  final String userMessage;
  final String suggestedAction;
  final IconData icon;

  const ErrorInfo({
    required this.title,
    required this.userMessage,
    required this.suggestedAction,
    required this.icon,
  });
}

const Map<ErrorCategoryType, ErrorInfo> _errorInfoMap = {
  ErrorCategoryType.network: ErrorInfo(
    title: 'Connection Failed',
    userMessage: 'Could not connect to the server',
    suggestedAction: 'Check your internet connection and try again',
    icon: Icons.wifi_off,
  ),
  ErrorCategoryType.authentication: ErrorInfo(
    title: 'Authentication Required',
    userMessage: 'Your session has expired or is invalid',
    suggestedAction: 'Sign in again to continue',
    icon: Icons.lock_outline,
  ),
  ErrorCategoryType.validation: ErrorInfo(
    title: 'Invalid Input',
    userMessage: 'The data provided is not valid',
    suggestedAction: 'Check your input and try again',
    icon: Icons.edit_note,
  ),
  ErrorCategoryType.notFound: ErrorInfo(
    title: 'Not Found',
    userMessage: 'The requested resource does not exist',
    suggestedAction: 'This may have been deleted or moved',
    icon: Icons.search_off,
  ),
  ErrorCategoryType.server: ErrorInfo(
    title: 'Server Error',
    userMessage: 'Something went wrong on our end',
    suggestedAction: 'Try again in a few minutes',
    icon: Icons.cloud_off,
  ),
  ErrorCategoryType.rateLimit: ErrorInfo(
    title: 'Too Many Requests',
    userMessage: 'You\'ve made too many requests',
    suggestedAction: 'Wait a moment and try again',
    icon: Icons.hourglass_empty,
  ),
  ErrorCategoryType.unknown: ErrorInfo(
    title: 'Unexpected Error',
    userMessage: 'An unexpected error occurred',
    suggestedAction: 'Try again or contact support if the problem persists',
    icon: Icons.error_outline,
  ),
};

ErrorInfo getErrorInfo(ErrorCategoryType type) {
  return _errorInfoMap[type] ?? _errorInfoMap[ErrorCategoryType.unknown]!;
}

ErrorCategoryType categorizeError(Object? error) {
  if (error == null) return ErrorCategoryType.unknown;

  final errorString = error.toString().toLowerCase();

  if (_isNetworkError(errorString)) return ErrorCategoryType.network;
  if (_isAuthenticationError(errorString)) {
    return ErrorCategoryType.authentication;
  }
  if (_isValidationError(errorString)) return ErrorCategoryType.validation;
  if (_isNotFoundError(errorString)) return ErrorCategoryType.notFound;
  if (_isRateLimitError(errorString)) return ErrorCategoryType.rateLimit;
  if (_isServerError(errorString)) return ErrorCategoryType.server;

  return ErrorCategoryType.unknown;
}

bool _isNetworkError(String error) {
  const patterns = [
    'socketexception',
    'connection refused',
    'connection failed',
    'network unreachable',
    'timeoutexception',
    'timed out',
    'timeout',
    'connection reset',
    'connection closed',
    'no address associated',
    'failed host lookup',
    'network error',
  ];
  return patterns.any((p) => error.contains(p));
}

bool _isAuthenticationError(String error) {
  const patterns = [
    '401',
    'unauthorized',
    'authentication failed',
    'not authenticated',
    'invalid token',
    'token expired',
    'session expired',
    'access denied',
    'forbidden',
    '403',
  ];
  return patterns.any((p) => error.contains(p));
}

bool _isValidationError(String error) {
  const patterns = [
    'validation',
    'invalid input',
    'invalid argument',
    'invalid parameter',
    'required field',
    'field is required',
    'must be',
    'cannot be empty',
    'format is invalid',
  ];
  return patterns.any((p) => error.contains(p));
}

bool _isNotFoundError(String error) {
  const patterns = [
    '404',
    'not found',
    'does not exist',
    'no such',
    'could not find',
    'resource not found',
    'item not found',
  ];
  return patterns.any((p) => error.contains(p));
}

bool _isRateLimitError(String error) {
  const patterns = [
    '429',
    'too many requests',
    'rate limit',
    'rate exceeded',
    'quota exceeded',
    'throttl',
  ];
  return patterns.any((p) => error.contains(p));
}

bool _isServerError(String error) {
  const patterns = [
    '500',
    '502',
    '503',
    '504',
    'internal server error',
    'bad gateway',
    'service unavailable',
    'gateway timeout',
    'server error',
  ];
  return patterns.any((p) => error.contains(p));
}
