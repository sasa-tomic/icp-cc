import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/candid_service.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/passkey_service.dart';
import 'profile_errors.dart';

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

  // Transport-layer failures — classified by TYPE, never by message string.
  // TlsException also covers its subclass HandshakeException.
  if (error is SocketException ||
      error is TlsException ||
      error is HttpException ||
      error is TimeoutException ||
      error is http.ClientException) {
    return ErrorCategoryType.network;
  }

  if (error is DownloadAuthException) {
    return ErrorCategoryType.authentication;
  }
  if (error is BackupDecryptionException) {
    return ErrorCategoryType.authentication;
  }

  if (error is PurchaseRequiredException) {
    return ErrorCategoryType.validation;
  }
  if (error is ProfileAlreadyExistsException) {
    return ErrorCategoryType.validation;
  }
  if (error is InvalidBackupFormatException) {
    return ErrorCategoryType.validation;
  }
  if (error is FormatException) return ErrorCategoryType.validation;

  if (error is PaymentsNotConfiguredException) {
    return ErrorCategoryType.server;
  }

  if (error is CandidFetchException) {
    return ErrorCategoryType.network;
  }

  if (error is PasskeyException) {
    return _statusCategory(error.statusCode);
  }

  return ErrorCategoryType.unknown;
}

ErrorCategoryType _statusCategory(int? statusCode) {
  if (statusCode == null) return ErrorCategoryType.unknown;
  switch (statusCode) {
    case 401:
    case 403:
      return ErrorCategoryType.authentication;
    case 404:
      return ErrorCategoryType.notFound;
    case 429:
      return ErrorCategoryType.rateLimit;
    case 402:
      return ErrorCategoryType.validation;
  }
  if (statusCode >= 500) return ErrorCategoryType.server;
  if (statusCode >= 400) return ErrorCategoryType.validation;
  return ErrorCategoryType.unknown;
}
