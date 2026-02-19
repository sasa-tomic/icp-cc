enum ScriptExecutionPhase {
  idle,
  initializing,
  callingCanister,
  processingResponse,
  rendering,
  complete,
  error;

  String get label {
    switch (this) {
      case ScriptExecutionPhase.idle:
        return 'Idle';
      case ScriptExecutionPhase.initializing:
        return 'Initializing';
      case ScriptExecutionPhase.callingCanister:
        return 'Calling canister';
      case ScriptExecutionPhase.processingResponse:
        return 'Processing response';
      case ScriptExecutionPhase.rendering:
        return 'Rendering';
      case ScriptExecutionPhase.complete:
        return 'Complete';
      case ScriptExecutionPhase.error:
        return 'Error';
    }
  }

  bool get isInProgress {
    switch (this) {
      case ScriptExecutionPhase.idle:
      case ScriptExecutionPhase.complete:
      case ScriptExecutionPhase.error:
        return false;
      case ScriptExecutionPhase.initializing:
      case ScriptExecutionPhase.callingCanister:
      case ScriptExecutionPhase.processingResponse:
      case ScriptExecutionPhase.rendering:
        return true;
    }
  }
}

class ScriptExecutionProgress {
  const ScriptExecutionProgress({
    this.phase = ScriptExecutionPhase.idle,
    this.message = '',
    this.isCancellable = false,
  });

  final ScriptExecutionPhase phase;
  final String message;
  final bool isCancellable;

  ScriptExecutionProgress copyWith({
    ScriptExecutionPhase? phase,
    String? message,
    bool? isCancellable,
  }) {
    return ScriptExecutionProgress(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      isCancellable: isCancellable ?? this.isCancellable,
    );
  }

  static const ScriptExecutionProgress idle = ScriptExecutionProgress();

  static ScriptExecutionProgress initializing(
      [String message = 'Initializing script...']) {
    return ScriptExecutionProgress(
      phase: ScriptExecutionPhase.initializing,
      message: message,
      isCancellable: true,
    );
  }

  static ScriptExecutionProgress callingCanister(
      String canisterId, String method) {
    return ScriptExecutionProgress(
      phase: ScriptExecutionPhase.callingCanister,
      message: 'Calling $method on $canisterId...',
      isCancellable: true,
    );
  }

  static ScriptExecutionProgress processingResponse(
      [String message = 'Processing response...']) {
    return ScriptExecutionProgress(
      phase: ScriptExecutionPhase.processingResponse,
      message: message,
      isCancellable: false,
    );
  }

  static ScriptExecutionProgress rendering(
      [String message = 'Rendering UI...']) {
    return ScriptExecutionProgress(
      phase: ScriptExecutionPhase.rendering,
      message: message,
      isCancellable: false,
    );
  }

  static ScriptExecutionProgress complete([String message = 'Complete']) {
    return ScriptExecutionProgress(
      phase: ScriptExecutionPhase.complete,
      message: message,
      isCancellable: false,
    );
  }

  static ScriptExecutionProgress error(String message) {
    return ScriptExecutionProgress(
      phase: ScriptExecutionPhase.error,
      message: message,
      isCancellable: false,
    );
  }
}
