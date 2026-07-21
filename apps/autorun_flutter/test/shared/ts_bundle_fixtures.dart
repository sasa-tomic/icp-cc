library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/script_runner.dart';

const List<String> _pilotBundleCandidates = <String>[
  'test/assets/pilot_sample.bundle.js',
  'apps/autorun_flutter/test/assets/pilot_sample.bundle.js',
  '../../crates/icp_core/tests/fixtures/pilot_sample.bundle.js',
  '/code/icp-cc/apps/autorun_flutter/test/assets/pilot_sample.bundle.js',
  '/code/icp-cc/crates/icp_core/tests/fixtures/pilot_sample.bundle.js',
];

String loadPilotBundle() {
  for (final String path in _pilotBundleCandidates) {
    final File f = File(path);
    if (f.existsSync()) {
      return f.readAsStringSync();
    }
  }
  fail('pilot_sample.bundle.js not found in any candidate location:\n'
      '${_pilotBundleCandidates.join("\n")}');
}

const List<String> _pollBundleCandidates = <String>[
  'lib/examples/06_icp_poll.js',
  'apps/autorun_flutter/lib/examples/06_icp_poll.js',
  '/code/icp-cc/apps/autorun_flutter/lib/examples/06_icp_poll.js',
];

/// Loads the on-chain poll app-lifecycle bundle (06_icp_poll.js). Centralized
/// here next to [loadPilotBundle] so every bundle loader lives in one module.
String loadPollBundle() {
  for (final String path in _pollBundleCandidates) {
    final File f = File(path);
    if (f.existsSync()) {
      return f.readAsStringSync();
    }
  }
  fail('06_icp_poll.js not found in any candidate location:\n'
      '${_pollBundleCandidates.join("\n")}');
}

const List<String> _ledgerBundleCandidates = <String>[
  'lib/examples/07_icp_ledger.js',
  'apps/autorun_flutter/lib/examples/07_icp_ledger.js',
  '/code/icp-cc/apps/autorun_flutter/lib/examples/07_icp_ledger.js',
];

/// Loads the ICP Ledger mainnet app-lifecycle bundle (07_icp_ledger.js). The
/// always-working counterpart to [loadPollBundle] — read-only queries against
/// the real public mainnet ICP ledger.
String loadLedgerBundle() {
  for (final String path in _ledgerBundleCandidates) {
    final File f = File(path);
    if (f.existsSync()) {
      return f.readAsStringSync();
    }
  }
  fail('07_icp_ledger.js not found in any candidate location:\n'
      '${_ledgerBundleCandidates.join("\n")}');
}

const List<String> _nnsProposalsBundleCandidates = <String>[
  'lib/examples/08_nns_proposals.js',
  'apps/autorun_flutter/lib/examples/08_nns_proposals.js',
  '/code/icp-cc/apps/autorun_flutter/lib/examples/08_nns_proposals.js',
];

/// Loads the NNS Proposals mainnet read-only browser bundle
/// (08_nns_proposals.js). Calls NNS Governance `list_proposals` — same
/// canister ALPHA-Vote automates in Rust. The governance headliner demo.
String loadNnsProposalsBundle() {
  for (final String path in _nnsProposalsBundleCandidates) {
    final File f = File(path);
    if (f.existsSync()) {
      return f.readAsStringSync();
    }
  }
  fail('08_nns_proposals.js not found in any candidate location:\n'
      '${_nnsProposalsBundleCandidates.join("\n")}');
}

const List<String> _snsProposalsBundleCandidates = <String>[
  'lib/examples/09_sns_proposals.js',
  'apps/autorun_flutter/lib/examples/09_sns_proposals.js',
  '/code/icp-cc/apps/autorun_flutter/lib/examples/09_sns_proposals.js',
];

/// Loads the SNS Proposals mainnet read-only browser bundle
/// (09_sns_proposals.js). Same UI as the NNS variant but configurable per
/// DAO via runtime canister-id override + a script-supplied colour theme.
String loadSnsProposalsBundle() {
  for (final String path in _snsProposalsBundleCandidates) {
    final File f = File(path);
    if (f.existsSync()) {
      return f.readAsStringSync();
    }
  }
  fail('09_sns_proposals.js not found in any candidate location:\n'
      '${_snsProposalsBundleCandidates.join("\n")}');
}

const List<String> _alphaVoteBundleCandidates = <String>[
  'lib/examples/10_alpha_vote.js',
  'apps/autorun_flutter/lib/examples/10_alpha_vote.js',
  '/code/icp-cc/apps/autorun_flutter/lib/examples/10_alpha_vote.js',
];

/// Loads the ALPHA-Vote authenticated neuron voting bundle
/// (10_alpha_vote.js). The authenticated sequel to the read-only NNS / SNS
/// browsers: emits authenticated `manage_neuron RegisterVote` and `Follow`
/// effects against NNS Governance, signed by the active profile's keypair.
String loadAlphaVoteBundle() {
  for (final String path in _alphaVoteBundleCandidates) {
    final File f = File(path);
    if (f.existsSync()) {
      return f.readAsStringSync();
    }
  }
  fail('10_alpha_vote.js not found in any candidate location:\n'
      '${_alphaVoteBundleCandidates.join("\n")}');
}

bool nativeLibAvailable(RustBridgeLoader loader) {
  final String? probe = loader.jsExec(script: '1', jsonArg: null);
  return probe != null;
}

ScriptAppRuntime bootRuntime() {
  return ScriptAppRuntime(RustScriptBridge(const RustBridgeLoader()));
}
