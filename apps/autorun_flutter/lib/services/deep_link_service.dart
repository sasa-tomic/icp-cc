import 'dart:async';

import 'package:flutter/foundation.dart';

class DeepLinkService {
  static DeepLinkService? _instance;
  static DeepLinkService get instance =>
      _instance ??= DeepLinkService._internal();

  factory DeepLinkService() => instance;
  DeepLinkService._internal();

  static const String _scheme = 'icpautorun';
  static const String _scriptPath = 'script';

  StreamController<DeepLinkData>? _linkController;

  Stream<DeepLinkData> get linkStream {
    _linkController ??= StreamController<DeepLinkData>.broadcast();
    return _linkController!.stream;
  }

  DeepLinkData? parseUri(Uri uri) {
    if (uri.scheme != _scheme) {
      debugPrint('DeepLinkService: Invalid scheme ${uri.scheme}');
      return null;
    }

    if (uri.host == _scriptPath) {
      final pathSegments = uri.pathSegments;
      if (pathSegments.isEmpty) {
        debugPrint('DeepLinkService: Missing script ID');
        return null;
      }
      final scriptId = pathSegments.first;
      if (scriptId.isEmpty) {
        debugPrint('DeepLinkService: Empty script ID');
        return null;
      }
      return DeepLinkData(
        type: DeepLinkType.script,
        scriptId: scriptId,
      );
    }

    debugPrint('DeepLinkService: Unknown host ${uri.host}');
    return null;
  }

  DeepLinkData? parseUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return parseUri(uri);
    } catch (e) {
      debugPrint('DeepLinkService: Failed to parse URL: $e');
      return null;
    }
  }

  void handleLink(Uri uri) {
    final data = parseUri(uri);
    if (data != null) {
      _linkController?.add(data);
    }
  }

  void handleUrl(String url) {
    final data = parseUrl(url);
    if (data != null) {
      _linkController?.add(data);
    }
  }

  static void resetForTesting() {
    _instance?._linkController?.close();
    _instance = null;
  }
}

enum DeepLinkType {
  script,
}

class DeepLinkData {
  final DeepLinkType type;
  final String? scriptId;

  const DeepLinkData({
    required this.type,
    this.scriptId,
  });

  @override
  String toString() => 'DeepLinkData(type: $type, scriptId: $scriptId)';
}
