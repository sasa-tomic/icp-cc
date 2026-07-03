// icp-cc Poll frontend — vanilla TS + @dfinity/agent.
//
// Dual identity mode:
//   - If window.__ICPCC_IDENTITY is present (injected by icp-cc's webview),
//     build an Ed25519KeyIdentity from the injected secret key — no Internet
//     Identity popup.
//   - Otherwise (standalone browser demo) use a random local identity, kept
//     stable across reloads via localStorage so your principal / votes persist.
//
// Every button is wired to a REAL canister call. Errors are surfaced in the UI
// and logged to the console with full detail (no silent failures).

import { Actor, HttpAgent } from "@dfinity/agent";
import { Ed25519KeyIdentity } from "@dfinity/identity";
import { idlFactory } from "../../declarations/backend/backend.did.js";

// Build-time constants injected by vite.config.ts (see `define`).
declare const __DFX_NETWORK__: string;
declare const __BACKEND_CANISTER_ID__: string;

interface PollRecord {
  id: string;
  question: string;
  options: string[];
  creator: string; // Principal, serialized by the agent as a string-ish value
}

interface IcpccIdentity {
  secretKeyB64: string;
  principal: string;
}

declare global {
  interface Window {
    __ICPCC_IDENTITY?: IcpccIdentity;
  }
}

const isMainnet = __DFX_NETWORK__ === "ic";
const HOST = isMainnet ? "https://icp-api.io" : "http://127.0.0.1:4943";
const LS_KEY = "icp_poll_identity_secret";

function bytesFromBase64(b64: string): Uint8Array {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}
function bytesToBase64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}

function buildIdentity(): Ed25519KeyIdentity {
  const injected = window.__ICPCC_IDENTITY;
  if (injected && typeof injected.secretKeyB64 === "string" && injected.secretKeyB64.length > 0) {
    // Injected by icp-cc's webview — sign as the active profile's principal.
    return Ed25519KeyIdentity.fromSecretKey(bytesFromBase64(injected.secretKeyB64));
  }
  // Standalone browser: stable random identity in localStorage.
  let b64 = localStorage.getItem(LS_KEY);
  if (!b64) {
    const secret = crypto.getRandomValues(new Uint8Array(32));
    b64 = bytesToBase64(secret);
    localStorage.setItem(LS_KEY, b64);
  }
  return Ed25519KeyIdentity.fromSecretKey(bytesFromBase64(b64));
}

// ---- App state ----
const state = {
  principal: "",
  polls: [] as PollRecord[],
  tallies: {} as Record<string, number[]>,
};

const el = (id: string) => document.getElementById(id);

function principalString(p: unknown): string {
  // The agent returns Principal objects; coerce to text defensively.
  if (p === null || p === undefined) return "—";
  if (typeof p === "string") return p;
  if (typeof p === "number" || typeof p === "bigint") return String(p);
  const maybe = p as {
    toString?: () => string;
    toText?: () => string;
    __principal__?: string;
  };
  if (typeof maybe.toText === "function") return maybe.toText();
  if (typeof maybe.__principal__ === "string") return maybe.__principal__;
  if (typeof maybe.toString === "function") {
    const s = maybe.toString();
    if (s && s !== "[object Object]") return s;
  }
  return String(p);
}

function setStatus(msg: string, isError = false): void {
  const node = el("status");
  if (!node) return;
  node.textContent = msg;
  node.className = isError ? "error" : "info";
}

function logError(context: string, err: unknown): void {
  const detail = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
  console.error(`[icp_poll] ${context}:`, err);
  setStatus(`${context}: ${detail}`, true);
}

async function refresh(actor: ReturnType<typeof Actor.createActor>): Promise<void> {
  try {
    const [principal, polls] = await Promise.all([
      (actor as { whoami: () => Promise<unknown> }).whoami(),
      (actor as { listPolls: () => Promise<PollRecord[]> }).listPolls(),
    ]);
    state.principal = principalString(principal);
    state.polls = polls;
    // Fetch every tally in parallel (demonstrates batched reads).
    const tallies = await Promise.all(
      polls.map(async (p) => [p.id, await (actor as { getTally: (id: string) => Promise<number[]> }).getTally(p.id)] as const),
    );
    state.tallies = Object.fromEntries(tallies);
    render(actor);
    setStatus(isMainnet ? "Connected to mainnet." : "Connected to local replica.");
  } catch (err) {
    logError("Refresh failed", err);
    render(actor);
  }
}

function render(actor: ReturnType<typeof Actor.createActor>): void {
  const principalNode = el("principal");
  if (principalNode) principalNode.textContent = state.principal || "—";

  const list = el("polls");
  if (!list) return;
  list.innerHTML = "";

  if (state.polls.length === 0) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.textContent = "No polls yet — create one below.";
    list.appendChild(empty);
    return;
  }

  for (const poll of state.polls) {
    const tally = state.tallies[poll.id] ?? [];
    const card = document.createElement("section");
    card.className = "card";

    const title = document.createElement("h3");
    title.textContent = poll.question;
    card.appendChild(title);

    const meta = document.createElement("p");
    meta.className = "muted";
    meta.textContent = `id: ${poll.id} · creator: ${principalString(poll.creator)}`;
    card.appendChild(meta);

    const opts = document.createElement("div");
    opts.className = "options";
    poll.options.forEach((opt, i) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = `${opt} (${tally[i] ?? 0})`;
      btn.addEventListener("click", () => vote(actor, poll.id, i));
      opts.appendChild(btn);
    });
    card.appendChild(opts);
    list.appendChild(card);
  }
}

async function vote(actor: ReturnType<typeof Actor.createActor>, pollId: string, optionIndex: number): Promise<void> {
  try {
    setStatus(`Voting on poll ${pollId}, option ${optionIndex}…`);
    await (actor as { vote: (id: string, opt: number) => Promise<void> }).vote(pollId, optionIndex);
    await refresh(actor);
  } catch (err) {
    logError(`Vote failed (poll ${pollId}, option ${optionIndex})`, err);
  }
}

async function createPoll(actor: ReturnType<typeof Actor.createActor>): Promise<void> {
  const q = (el("question") as HTMLInputElement | null)?.value?.trim() ?? "";
  const raw = (el("options") as HTMLInputElement | null)?.value ?? "";
  const options = raw.split(",").map((o) => o.trim()).filter((o) => o.length > 0);

  if (!q) {
    setStatus("Enter a question.", true);
    return;
  }
  if (options.length < 2) {
    setStatus("Provide at least 2 comma-separated options.", true);
    return;
  }

  try {
    setStatus("Creating poll…");
    const id = await (actor as { createPoll: (q: string, opts: string[]) => Promise<string> }).createPoll(q, options);
    setStatus(`Created poll ${id}.`);
    (el("question") as HTMLInputElement | null)?.value && ((el("question") as HTMLInputElement).value = "");
    (el("options") as HTMLInputElement | null)?.value && ((el("options") as HTMLInputElement).value = "");
    await refresh(actor);
  } catch (err) {
    logError("Create poll failed", err);
  }
}

async function main(): Promise<void> {
  const app = el("app");
  if (!app) throw new Error("#app element missing");

  if (!__BACKEND_CANISTER_ID__) {
    setStatus("Backend canister id not configured — run `dfx deploy` first.", true);
    return;
  }

  const identity = buildIdentity();
  const agent = new HttpAgent({ host: HOST, identity });
  if (!isMainnet) {
    await agent.fetchRootKey(); // local replica: trust the dev key
  }
  const actor = Actor.createActor(idlFactory, { agent, canisterId: __BACKEND_CANISTER_ID__ });

  // Wire the create form.
  const form = el("create-form");
  if (form) {
    form.addEventListener("submit", (ev) => {
      ev.preventDefault();
      void createPoll(actor);
    });
  }
  const refreshBtn = el("refresh");
  if (refreshBtn) {
    refreshBtn.addEventListener("click", () => void refresh(actor));
  }

  await refresh(actor);
}

void main().catch((err) => logError("Fatal", err));
