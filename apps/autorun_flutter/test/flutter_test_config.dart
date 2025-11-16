import 'dart:async';
import 'test_helpers/test_signature_utils.dart';

/// Global test configuration
/// This file is automatically loaded by Flutter test framework
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Initialize test signature utilities before running any tests
  await TestSignatureUtils.ensureInitialized();

  // Run the actual tests
  await testMain();
}
