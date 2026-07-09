#!/usr/bin/env python3
"""Self-contained D-Bus regression test for scripts/mock_secret_service.py.

Drives the mock via `dbus_next` (no libsecret, no compiler) the same way
libsecret does at the wire level, and pins the NF-2 acceptance gates:

  1. `OpenSession('plain')` succeeds.
  2. `OpenSession('dh-ietf1024-sha256-aes128-cbc-pkcs7')` returns a
     NOT_SUPPORTED error (the loud-but-honest fallback that lets libsecret
     retry on `plain`); the mock process stays alive afterward.
  3. `Collection.CreateItem` stores a secret and returns an item path.
  4. `Service.SearchItems` finds the new item by attributes.
  5. `Service.GetSecrets` returns the stored value.
  6. `Item.Delete` on the new item path succeeds (NF-2 — without the
     ItemIface export, libsecret's `secret_password_clear_sync` (and
     `flutter_secure_storage_linux`'s `delete()`) would get UnknownMethod
     here, which is what blocked the Round-6 Dart readiness probe).
  7. After delete, `SearchItems` returns empty.

Run:
    # Inside the wrapper (uses run-with-mock-keyring.sh's dbus-run-session):
    PYTHONPATH=<dbus-next path> scripts/run-with-mock-keyring.sh \\
        python3 scripts/test_mock_secret_service.py

    # Or bare, inside any dbus-run-session:
    dbus-run-session -- python3 scripts/test_mock_secret_service.py

Exit code: 0 on success, non-zero on the first failed assertion.
"""

from __future__ import annotations

import asyncio
import sys

from dbus_next import Variant
from dbus_next.aio import MessageBus
from dbus_next.constants import BusType
from dbus_next.errors import DBusError

ROOT = "/org/freedesktop/secrets"
COLLECTION = f"{ROOT}/collection/default"
SESSION = f"{ROOT}/session/s0"
DH_ALG = "dh-ietf1024-sha256-aes128-cbc-pkcs7"


def _ok(msg: str) -> None:
    print(f"  PASS  {msg}", file=sys.stderr, flush=True)


async def _assert(cond: bool, msg: str) -> None:
    if not cond:
        print(f"  FAIL  {msg}", file=sys.stderr, flush=True)
        raise AssertionError(msg)
    _ok(msg)


async def main() -> int:
    bus = await MessageBus(bus_type=BusType.SESSION).connect()

    intr = await bus.introspect("org.freedesktop.secrets", ROOT)
    proxy = bus.get_proxy_object("org.freedesktop.secrets", ROOT, intr)
    svc = proxy.get_interface("org.freedesktop.Secret.Service")

    # ------------------------------------------------------------------ #
    print("[1/7] OpenSession('plain')", file=sys.stderr, flush=True)
    result, session_path = await svc.call_open_session(
        "plain", Variant("ay", bytes())
    )
    await _assert(session_path == SESSION, f"session path == {SESSION}")
    await _assert(
        isinstance(result.value, bytes) and len(result.value) == 0,
        "plain session result is empty byte array",
    )

    # ------------------------------------------------------------------ #
    print(f"[2/7] OpenSession('{DH_ALG}') -> NOT_SUPPORTED", file=sys.stderr,
          flush=True)
    raised = False
    try:
        await svc.call_open_session(DH_ALG, Variant("ay", bytes([0x01] * 128)))
    except DBusError as e:
        # The honest fallback: the mock stays plain-only (dev/CI contract)
        # and rejects the encrypted algorithm so libsecret retries on plain.
        raised = "not supported" in str(e).lower()
        if not raised:
            print(f"        unexpected error text: {e}", file=sys.stderr,
                  flush=True)
    await _assert(raised, "DH OpenSession returns NOT_SUPPORTED")

    # Mock must still respond after the rejected DH attempt (i.e. the
    # dbus-next SendReply.__exit__ bug must NOT bring the service down).
    peer = proxy.get_interface("org.freedesktop.DBus.Peer")
    await peer.call_ping()
    _ok("mock still responds to Ping after DH rejection")

    # ------------------------------------------------------------------ #
    print("[3/7] Collection.CreateItem", file=sys.stderr, flush=True)
    coll_intr = await bus.introspect("org.freedesktop.secrets", COLLECTION)
    coll_proxy = bus.get_proxy_object(
        "org.freedesktop.secrets", COLLECTION, coll_intr
    )
    coll = coll_proxy.get_interface("org.freedesktop.Secret.Collection")

    attrs = {"service": "icp", "account": "nf2-test"}
    properties = {
        "org.freedesktop.Secret.Item.Label": Variant("s", "NF-2 probe"),
        "org.freedesktop.Secret.Item.Attributes": Variant("a{ss}", attrs),
    }
    # Secret struct signature: (o, ay, ay, s) — session path, params, value,
    # content-type. The mock only consumes the value (third element). dbus_next
    # requires STRUCT bodies to be Python lists (not tuples).
    secret = [SESSION, bytes(), b"nf2-secret-value", "text/plain"]
    item_path, prompt = await coll.call_create_item(properties, secret, False)
    await _assert(item_path.startswith(f"{ROOT}/item/"),
                  f"CreateItem returns an item path (got {item_path})")
    await _assert(prompt == "/", "no prompt returned")

    # ------------------------------------------------------------------ #
    print("[4/7] Service.SearchItems finds it by attributes",
          file=sys.stderr, flush=True)
    found, _locked = await svc.call_search_items(attrs)
    await _assert(item_path in found,
                  f"SearchItems result contains the new item ({found})")

    # ------------------------------------------------------------------ #
    print("[5/7] Service.GetSecrets returns the value",
          file=sys.stderr, flush=True)
    secrets = await svc.call_get_secrets([item_path], SESSION)
    await _assert(item_path in secrets, "GetSecrets contains the item")
    # Secret tuple: (o, ay, ay, s). Third element (index 2) is the value.
    stored = secrets[item_path]
    await _assert(
        bytes(stored[2]) == b"nf2-secret-value",
        f"GetSecrets value matches (got {bytes(stored[2])!r})",
    )

    # ------------------------------------------------------------------ #
    print("[6/7] Item.Delete succeeds (NF-2 — the regression gate)",
          file=sys.stderr, flush=True)
    item_intr = await bus.introspect("org.freedesktop.secrets", item_path)
    item_proxy = bus.get_proxy_object(
        "org.freedesktop.secrets", item_path, item_intr
    )
    item = item_proxy.get_interface("org.freedesktop.Secret.Item")
    # The acceptance gate: before NF-2 this raised UnknownMethod because the
    # mock never exported an Item interface at item paths.
    delete_prompt = await item.call_delete()
    await _assert(delete_prompt == "/", "Delete returns '/' (no prompt)")

    # ------------------------------------------------------------------ #
    print("[7/7] SearchItems returns empty after delete",
          file=sys.stderr, flush=True)
    found_after, _ = await svc.call_search_items(attrs)
    await _assert(item_path not in found_after and len(found_after) == 0,
                  f"SearchItems after delete is empty (got {found_after})")

    print("\nALL OK — mock Secret Service satisfies the NF-2 contract.",
          file=sys.stderr, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
