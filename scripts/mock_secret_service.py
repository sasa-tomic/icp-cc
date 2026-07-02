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
"""

from __future__ import annotations

import json
import os
import sys
import uuid
from pathlib import Path

from dbus_next import Variant, DBusError
from dbus_next.aio import MessageBus
from dbus_next.constants import BusType, ErrorType
from dbus_next.service import ServiceInterface, method, dbus_property, PropertyAccess
import asyncio

ROOT_PATH = "/org/freedesktop/secrets"
COLLECTION_PATH = f"{ROOT_PATH}/collection/default"
ALIAS_PATH = f"{ROOT_PATH}/aliases/default"
SESSION_PATH = f"{ROOT_PATH}/session/s0"

SERVICE_IFACE = "org.freedesktop.Secret.Service"
COLLECTION_IFACE = "org.freedesktop.Secret.Collection"


class Store:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            path.write_text("{}")
        self.path = path

    def load(self) -> dict:
        try:
            return json.loads(self.path.read_text())
        except Exception:
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
        return [iid for iid, item in d.items()
                if all(item.get("attributes", {}).get(k) == v for k, v in attrs.items())]

    def get_val(self, iid: str) -> str | None:
        return self.load().get(iid, {}).get("value")

    def delete(self, iid: str) -> None:
        d = self.load()
        d.pop(iid, None)
        self.save(d)


_store: Store | None = None


class ServiceIface(ServiceInterface):
    def __init__(self):
        super().__init__(SERVICE_IFACE)

    @method()
    def OpenSession(self, algorithm: "s", input_: "v") -> "vo":
        if algorithm != "plain":
            raise DBusError(ErrorType.NOT_SUPPORTED,
                            f"algorithm '{algorithm}' not supported, use 'plain'")
        return [Variant("ay", bytes()), SESSION_PATH]

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
    def CreateItem(self, properties: "a{sv}", secret: "(oayays)", replace: "b") -> "oo":
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
        return [iid, "/"]

    @method()
    def SearchItems(self, attributes: "a{ss}") -> "ao":
        return _store.find(dict(attributes))

    @method()
    def DeleteItem(self, item: "o") -> "o":
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


async def main():
    global _store
    data_dir = Path(os.environ.get(
        "MOCK_SECRET_DATA_DIR",
        os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share/mock-secret-service"))))
    data_file = data_dir / "secrets.json"
    _store = Store(data_file)

    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    await bus.request_name("org.freedesktop.secrets")

    bus.export(ROOT_PATH, ServiceIface())
    bus.export(COLLECTION_PATH, CollectionIface())
    bus.export(ALIAS_PATH, CollectionIface())

    print(f"Mock Secret Service ready", file=sys.stderr)
    print(f"  Data: {data_file}", file=sys.stderr)
    print(f"  NO ENCRYPTION — dev/CI only!", file=sys.stderr)

    await bus.wait_for_disconnect()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
