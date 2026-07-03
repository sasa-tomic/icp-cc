import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Error "mo:base/Error";

// icp-cc Poll — a per-principal voting dapp.
//
// State:
//   polls : pollId  -> PollRecord
//   votes : pollId  -> (voter principal -> chosen option index)
//
// `vote` is idempotent-per-principal: re-voting REPLACES the previous choice
// (no stacking). All inputs are validated and rejected loudly with clear
// messages (project rules: no silent errors).
persistent actor Poll {
  public type PollRecord = {
    id : Text;
    question : Text;
    options : [Text];
    creator : Principal;
  };

  // Stable backing arrays — serialized in preupgrade, restored in postupgrade.
  // `transient`: these only carry state across one upgrade window (set in
  // preupgrade, read in postupgrade), so they do not need to persist between
  // normal message execution. They auto-reset to [] after postupgrade.
  private transient var pollEntries : [(Text, PollRecord)] = [];
  private transient var voteEntries : [(Text, [(Principal, Nat)])] = [];
  private var nextId : Nat = 0; // implicitly stable (Nat), survives upgrades

  // In-memory state (rebuilt from the transient arrays in postupgrade). Marked
  // `transient` to acknowledge explicitly that they do not survive an upgrade
  // by themselves — only their serialized snapshots in *Entries do.
  private transient let polls = HashMap.HashMap<Text, PollRecord>(0, Text.equal, Text.hash);
  private transient let votes = HashMap.HashMap<Text, HashMap.HashMap<Principal, Nat>>(0, Text.equal, Text.hash);

  system func preupgrade() {
    pollEntries := Iter.toArray(polls.entries());
    voteEntries := Iter.toArray(
      Iter.map<(Text, HashMap.HashMap<Principal, Nat>), (Text, [(Principal, Nat)])>(
        votes.entries(),
        func((id, m)) { (id, Iter.toArray(m.entries())) },
      ),
    );
  };

  // On upgrade the actor is re-instantiated, so `polls`/`votes` start empty —
  // no clear() needed (HashMap has no clear anyway). Re-populate from stable.
  system func postupgrade() {
    for ((id, p) in pollEntries.vals()) { polls.put(id, p) };
    for ((id, entries) in voteEntries.vals()) {
      let m = HashMap.HashMap<Principal, Nat>(0, Principal.equal, Principal.hash);
      for ((voter, opt) in entries.vals()) { m.put(voter, opt) };
      votes.put(id, m);
    };
  };

  // Monotonic id generator (stable across upgrades via `nextId`).
  private func genId() : Text {
    nextId += 1;
    Nat.toText(nextId);
  };

  // --- Queries ---

  public shared query ({ caller }) func whoami() : async Text {
    Principal.toText(caller);
  };

  public query func listPolls() : async [PollRecord] {
    Iter.toArray(polls.vals());
  };

  // Returns a tally sized to the poll's option list, indexed by option.
  // An unknown poll id yields an empty vector: a deliberate read default,
  // documented here. Mutations (createPoll/vote) reject unknown ids loudly.
  public query func getTally(pollId : Text) : async [Nat] {
    switch (polls.get(pollId)) {
      case (null) { [] };
      case (?poll) {
        let tally = Array.init<Nat>(poll.options.size(), 0);
        switch (votes.get(pollId)) {
          case (null) { [] };
          case (?m) {
            for ((_voter, opt) in m.entries()) {
              if (opt < tally.size()) { tally[opt] += 1 };
            };
            Array.freeze(tally);
          };
        };
      };
    };
  };

  // --- Updates ---

  public shared ({ caller }) func createPoll(question : Text, options : [Text]) : async Text {
    if (Text.size(Text.trim(question, #char ' ')) == 0) {
      throw Error.reject("createPoll: question must not be empty");
    };
    if (options.size() < 2) {
      throw Error.reject("createPoll: provide at least 2 options");
    };
    for (o in options.vals()) {
      if (Text.size(Text.trim(o, #char ' ')) == 0) {
        throw Error.reject("createPoll: options must not be empty");
      };
    };
    let id = genId();
    polls.put(id, { id; question; options; creator = caller });
    votes.put(id, HashMap.HashMap<Principal, Nat>(0, Principal.equal, Principal.hash));
    id;
  };

  public shared ({ caller }) func vote(pollId : Text, optionIndex : Nat) : async () {
    let poll = switch (polls.get(pollId)) {
      case (null) { throw Error.reject("vote: unknown poll id '" # pollId # "'") };
      case (?p) { p };
    };
    if (optionIndex >= poll.options.size()) {
      throw Error.reject(
        "vote: optionIndex " # Nat.toText(optionIndex) #
        " out of range (0.." # Nat.toText(poll.options.size() - 1) # ")",
      );
    };
    let m = switch (votes.get(pollId)) {
      case (null) {
        let fresh = HashMap.HashMap<Principal, Nat>(0, Principal.equal, Principal.hash);
        votes.put(pollId, fresh);
        fresh;
      };
      case (?existing) { existing };
    };
    // One vote per principal — re-voting REPLACES the previous choice.
    m.put(caller, optionIndex);
  };
};
