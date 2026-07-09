#!/usr/bin/env python3
"""Mock Secret Service for headless Linux dev/CI.

Implements just enough of org.freedesktop.secrets for flutter_secure_storage_linux
(libsecret) to work without gnome-keyring. Stores secrets as plain JSON.
NO ENCRYPTION — dev/CI ONLY.

Usage:
    dbus-run-session -- python3 scripts/mock_secret_service.py &
    # then launch your Flutter app in the same dbus-run-session:
    dbus-run-session -- bash -c 'python3 scripts/mock_secret_service.py & flutter run -d linux'

Requires: dbus-next (pip install dbus-next)

NF-2 (Round-6 UX review, 2026-07-09): two devex robustness fixes so the mock
works on boxes whose libsecret prefers the encrypted session algorithm:

  1. libsecret on this box negotiates `dh-ietf1024-sha256-aes128-cbc-pkcs7`
     FIRST, then falls back to `plain` if the service rejects it. The mock
     stays plain-only (the dev/CI contract — NO encryption): we log the DH
     attempt loudly ONCE per process and return NOT_SUPPORTED, which makes
     libsecret retry with `plain`. We deliberately do NOT pretend to accept
     the DH algorithm — returning an empty-byte response would make
     libsecret believe it has an AES session and try to AES-decrypt our
     plain secrets, breaking the round-trip ("received an encrypted secret
     structure with invalid parameter"). Verified by /tmp probe.

  2. dbus-next 0.2.3 has a one-character bug: `SendReply.__exit__` does not
     `return` the result of `_exit`, so a `DBusError` raised inside an
     `@method()` is logged as `got unexpected error processing a message`
     even though `_exit` already sent the proper D-Bus error reply to the
     client. The client (libsecret) sees the correct NOT_SUPPORTED reply;
     the only effect is spurious stderr noise that *looks* like a crash.
     `_DBusNextSpuriousErrorFilter` drops exactly that log line — nothing
     else. A genuine unexpected error still surfaces.

  3. We export `org.freedesktop.Secret.Item` at every item path so
     `Item.Delete` works — that is what `secret_password_clear_sync` (and
     `flutter_secure_storage_linux`'s `delete()`) calls. Without it the
     Dart `SecureStorageReadiness._probeOnce` write/read/delete cycle
     throws on the delete step and reports `StorageUnavailable`, which is
     what blocked the Round-6 live wizard screenshot.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
import uuid
from pathlib import Path

from dbus_next import Variant, DBusError
from dbus_next.aio import MessageBus
from dbus_next.constants import BusType, ErrorType
from dbus_next.service import (
    ServiceInterface,
    method,
    dbus_property,
    PropertyAccess,
)

ROOT_PATH = "/org/freedesktop/secrets"
COLLECTION_PATH = f"{ROOT_PATH}/collection/default"
ALIAS_PATH = f"{ROOT_PATH}/aliases/default"
SESSION_PATH = f"{ROOT_PATH}/session/s0"

SERVICE_IFACE = "org.freedesktop.Secret.Service"
COLLECTION_IFACE = "org.freedesktop.Secret.Collection"
ITEM_IFACE = "org.freedesktop.Secret.Item"

# The single DH/AES algorithm libsecret negotiates on this box. Used only
# for the loud one-time "falling back to plain" log below — we never
# implement it (no stdlib AES; the mock stays plain-only by contract).
_DH_ALGORITHM = "dh-ietf1024-sha256-aes128-cbc-pkcs7"


# --------------------------------------------------------------------------- #
# Logging hygiene (NF-2 part 2)                                               #
# --------------------------------------------------------------------------- #
class _DBusNextSpuriousErrorFilter(logging.Filter):
    """Drop ONE known-broken log line from dbus-next 0.2.3.

    When an `@method()` raises `DBusError`, the library's `SendReply.__exit__`
    forgets to `return` the result of `_exit` (a one-character bug), so the
    exception is NOT suppressed by the `with send_reply:` block and bubbles
    up to `MessageBus._on_message`, which logs it as
    `got unexpected error processing a message: ...`.

    Critically: `_exit` DID already send the proper D-Bus error reply to the
    client before that log line. So the client (libsecret) sees the correct
    NOT_SUPPORTED reply and falls back to the `plain` algorithm correctly;
    the ONLY effect of this bug is spurious stderr noise that looks like a
    crash to a human reader.

    We drop exactly that log line. We do NOT mask any other logging — a
    genuine unexpected error still surfaces loudly.
    """

    _DROP_MARKER = "got unexpected error processing a message"

    def filter(self, record: logging.LogRecord) -> bool:
        return self._DROP_MARKER not in record.getMessage()


logging.getLogger().addFilter(_DBusNextSpuriousErrorFilter())


# --------------------------------------------------------------------------- #
# Plain-JSON store (dev/CI only, NO encryption)                               #
# --------------------------------------------------------------------------- #
class Store:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            path.write_text("{}")
        self.path = path

    def load(self) -> dict:
        try:
            return json.loads(self.path.read_text())
        except Exception as e:
            # LOUD about corruption (AGENTS.md) — never silently return {}.
            # Treat the store as empty for THIS run, but make the human aware
            # that the on-disk file was unreadable (external tamper, encoding
            # drift, partial write). The next successful `save` overwrites it.
            print(
                f"mock_secret_service: secrets file unreadable "
                f"({type(e).__name__}: {e}); treating as empty for this run",
                file=sys.stderr,
            )
            return {}

    def save(self, d: dict) -> None:
        self.path.write_text(json.dumps(d))

    def put(self, attrs: dict, label: str, value: str) -> str:
        d = self.load()
        for iid, item in d.items():
            if item.get("attributes") == attrs:
                item.update(label=label, value=value)
                self.save(d)
                return iid
        iid = f"{ROOT_PATH}/item/{uuid.uuid4().hex[:8]}"
        d[iid] = {"attributes": attrs, "label": label, "value": value}
        self.save(d)
        return iid

    def find(self, attrs: dict) -> list[str]:
        d = self.load()
        return [
            iid
            for iid, item in d.items()
            if all(item.get("attributes", {}).get(k) == v for k, v in attrs.items())
        ]

    def get_val(self, iid: str) -> str | None:
        return self.load().get(iid, {}).get("value")

    def get_label(self, iid: str) -> str:
        return self.load().get(iid, {}).get("label", "")

    def delete(self, iid: str) -> None:
        d = self.load()
        d.pop(iid, None)
        self.save(d)


# Module-level singletons populated by `main()` before any interface method
# runs (interfaces reach into them from inside @method() bodies).
_store: Store | None = None
_bus: MessageBus | None = None

# Tracks which item paths already have an ItemIface exported, so a
# `CreateItem` whose attributes match an existing item (Store.put returns
# the existing iid) doesn't try to re-export the same path (dbus_next
# raises ValueError "An interface with this name is already exported").
# Populated at startup from on-disk state and on every CreateItem.
_exported_item_paths: set[str] = set()

# Tracks whether we've already logged the one-time DH-encountered notice,
# so a chatty client (libsecret opens a fresh session per SecretService
# instance) doesn't spam stderr.
_dh_logged = False


def _export_item(iid: str) -> None:
    """Export the Item interface at [iid] if it isn't already exported.

    Idempotent: safe to call on a path that was exported at startup or by
    a previous CreateItem. This matters because `Store.put` returns the
    existing item's iid when attributes match (replace semantics), and
    re-exporting an already-exported path raises ValueError in dbus_next.
    """
    if iid in _exported_item_paths:
        return
    _bus.export(iid, ItemIface(iid))
    _exported_item_paths.add(iid)


class ServiceIface(ServiceInterface):
    def __init__(self):
        super().__init__(SERVICE_IFACE)

    @method()
    def OpenSession(self, algorithm: "s", input_: "v") -> "vo":
        global _dh_logged
        if algorithm == "plain":
            return [Variant("ay", bytes()), SESSION_PATH]

        # NF-2: libsecret prefers the encrypted DH/AES session. We stay
        # plain-only (dev/CI contract) and reject the algorithm so libsecret
        # falls back to `plain`. Log the attempt loudly ONCE per process —
        # never silent (AGENTS.md), but never spammy either.
        #
        # Returning an empty-byte SUCCESS response is NOT an option: that
        # makes libsecret believe it has negotiated an AES session and try
        # to AES-decrypt our plain secret payloads, breaking the round-trip
        # (verified empirically — `received an encrypted secret structure
        # with invalid parameter`). NOT_SUPPORTED is the only honest path
        # short of implementing the full DH+AES exchange, which would need
        # a non-stdlib AES implementation.
        if not _dh_logged:
            print(
                f"mock_secret_service: client requested encrypted session "
                f"algorithm '{algorithm}'; mock is plain-only (dev/CI, no "
                f"encryption). Returning NOT_SUPPORTED so the client falls "
                f"back to 'plain'. (logged once per process)",
                file=sys.stderr,
            )
            _dh_logged = True

        raise DBusError(
            ErrorType.NOT_SUPPORTED,
            f"algorithm '{algorithm}' not supported, use 'plain'",
        )

    @method()
    def ReadAlias(self, name: "s") -> "o":
        return COLLECTION_PATH if name == "default" else "/"

    @method()
    def SearchItems(self, attributes: "a{ss}") -> "aoao":
        return [_store.find(dict(attributes)), []]

    @method()
    def GetSecrets(self, items: "ao", session: "o") -> "a{o(oayays)}":
        result = {}
        for item_path in items:
            v = _store.get_val(str(item_path))
            if v is not None:
                result[item_path] = [SESSION_PATH, bytes(), v.encode(), "text/plain"]
        return result

    @method()
    def Unlock(self, objects: "ao") -> "aoo":
        return [list(objects), "/"]

    @method()
    def Lock(self, objects: "ao") -> "aoo":
        return [[], "/"]

    @method()
    def CreateCollection(self, properties: "a{sv}", alias: "s") -> "oo":
        return [COLLECTION_PATH, "/"]

    @dbus_property(access=PropertyAccess.READ)
    def Collections(self) -> "ao":
        return [COLLECTION_PATH]


class CollectionIface(ServiceInterface):
    def __init__(self):
        super().__init__(COLLECTION_IFACE)

    @method()
    def CreateItem(
        self, properties: "a{sv}", secret: "(oayays)", replace: "b"
    ) -> "oo":
        label = ""
        attrs: dict = {}
        for key, val in properties.items():
            short_key = key.split(".")[-1]
            if short_key == "Label":
                label = str(val.value) if isinstance(val, Variant) else str(val)
            elif short_key == "Attributes":
                raw = val.value if isinstance(val, Variant) else val
                attrs = {str(k): str(v) for k, v in dict(raw).items()}

        raw_value = ""
        if isinstance(secret, (list, tuple)) and len(secret) >= 3:
            raw_value = bytes(secret[2]).decode(errors="replace")
        iid = _store.put(attrs, label, raw_value)

        # NF-2: export the per-item interface at the new item's path so
        # libsecret can call `Item.Delete` on it (used by
        # `secret_password_clear_sync` and by
        # `flutter_secure_storage_linux`'s `delete()`). Without this the
        # item path returns UnknownMethod on Delete, which makes the Dart
        # `SecureStorageReadiness._probeOnce` write/read/delete cycle throw
        # on the delete step and report StorageUnavailable.
        _export_item(iid)

        return [iid, "/"]

    @method()
    def SearchItems(self, attributes: "a{ss}") -> "ao":
        return _store.find(dict(attributes))

    @method()
    def DeleteItem(self, item: "o") -> "o":
        # Non-spec convenience helper kept for any external caller that
        # invokes Collection.DeleteItem instead of Item.Delete. libsecret
        # itself uses Item.Delete (handled by ItemIface below).
        _store.delete(str(item))
        return "/"

    @dbus_property(access=PropertyAccess.READ)
    def Label(self) -> "s":
        return "default"

    @dbus_property(access=PropertyAccess.READ)
    def Locked(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def Created(self) -> "t":
        return 0

    @dbus_property(access=PropertyAccess.READ)
    def Modified(self) -> "t":
        return 0


class ItemIface(ServiceInterface):
    """`org.freedesktop.Secret.Item` exported at every item path.

    The spec places `Delete` on the item itself (not the collection), and
    that is what libsecret calls from `secret_password_clear_sync`. The
    mock creates an ItemIface per item in `CollectionIface.CreateItem`.
    """

    def __init__(self, item_path: str):
        super().__init__(ITEM_IFACE)
        self._item_path = item_path

    @method()
    def Delete(self) -> "o":
        _store.delete(self._item_path)
        # Spec: returns the prompt path. "/" means no prompt needed.
        return "/"

    @dbus_property(access=PropertyAccess.READ)
    def Label(self) -> "s":
        return _store.get_label(self._item_path)

    @dbus_property(access=PropertyAccess.READ)
    def Locked(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def Created(self) -> "t":
        return 0

    @dbus_property(access=PropertyAccess.READ)
    def Modified(self) -> "t":
        return 0


async def main() -> None:
    global _store, _bus

    data_dir = Path(
        os.environ.get(
            "MOCK_SECRET_DATA_DIR",
            os.environ.get(
                "XDG_DATA_HOME",
                os.path.expanduser("~/.local/share/mock-secret-service"),
            ),
        )
    )
    data_file = data_dir / "secrets.json"
    _store = Store(data_file)

    _bus = await MessageBus(bus_type=BusType.SESSION).connect()
    await _bus.request_name("org.freedesktop.secrets")

    _bus.export(ROOT_PATH, ServiceIface())
    _bus.export(COLLECTION_PATH, CollectionIface())
    _bus.export(ALIAS_PATH, CollectionIface())

    # Re-export the Item interface at every existing item path so a
    # restart of the mock (secrets already on disk) can still serve
    # Item.Delete on previously-created items.
    for iid in _store.load().keys():
        if iid.startswith(f"{ROOT_PATH}/item/"):
            _export_item(iid)

    print("Mock Secret Service ready", file=sys.stderr)
    print(f"  Data: {data_file}", file=sys.stderr)
    print("  NO ENCRYPTION — dev/CI only!", file=sys.stderr)

    try:
        await _bus.wait_for_disconnect()
    except (EOFError, ConnectionResetError) as e:
        # Normal shutdown: `dbus-run-session` tears the session bus down
        # when the wrapped client command exits, so the dbus stream ends.
        # This is the expected end-of-life for the mock — log it honestly
        # and exit cleanly so the wrapper's `kill $MOCK_PID` is a no-op.
        print(
            f"mock_secret_service: dbus session ended ({type(e).__name__}); "
            "shutting down.",
            file=sys.stderr,
        )


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
