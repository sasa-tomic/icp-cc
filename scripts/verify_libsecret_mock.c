// Ground-truth diagnostic: prove the committed mock Secret Service
// (scripts/mock_secret_service.py) interoperates with the REAL libsecret (C)
// library using the EXACT access pattern that flutter_secure_storage_linux
// uses (see its bundled include/Secret.hpp):
//   1. warmupKeyring(): store a dummy item under schema=NULL so libsecret is
//      convinced the keyring is unlocked (gnome-keyring quirk, crbug.com/660005).
//   2. storeToKeyring(): store ONE JSON blob under schema {account:STRING} with
//      attribute account="com.example.icp_autorun.secureStorage".
//   3. readFromKeyring(): secret_password_lookupv_sync the blob back.
//
// Build + run INSIDE the mock's dbus-run-session:
//   gcc scripts/verify_libsecret_mock.c $(pkg-config --cflags --libs libsecret-1) -o /tmp/lsm
//   scripts/run-with-mock-keyring.sh /tmp/lsm
//
// Expected (decisive): `VERDICT: OK libsecret(C)<->mock round-trip byte-identical`
// and the mock's secrets.json gains the warmup + account-blob items.
// This is the foundational proof that profile creation's secure-storage write
// works under the mock (see docs/specs/UX_REVIEW_ROUND3.md addendum).
#include <libsecret/secret.h>
#include <glib.h>
#include <string.h>
#include <stdio.h>

static const SecretSchema APP_SCHEMA = {
    "com.example.icp_autorun/FlutterSecureStorage",
    SECRET_SCHEMA_NONE,
    { { "account", SECRET_SCHEMA_ATTRIBUTE_STRING }, { NULL, 0 } } };

int main(void) {
    GError *err = NULL;
    const gchar *account = "com.example.icp_autorun.secureStorage";
    const gchar *blob = "{\"keypair_private_key_k1\":\"PK\",\"keypair_mnemonic_k1\":\"MN\"}";

    // 1) warmup (schema NULL, attribute "explanation")
    GHashTable *warm = g_hash_table_new(g_str_hash, g_str_equal);
    g_hash_table_insert(warm, (gchar*)"explanation",
        (gchar*)"flutter_secret_storage dummy unlock entry (crbug.com/660005)");
    gboolean wok = secret_password_storev_sync(NULL, warm, NULL,
        "FlutterSecureStorage Control", "The meaning of life", NULL, &err);
    if (!wok) { fprintf(stderr, "VERDICT: FAIL warmup: %s\n",
        err ? err->message : "?"); return 1; }
    fprintf(stderr, "warmup store: OK\n");

    // 2) store main blob
    GHashTable *attr = g_hash_table_new(g_str_hash, g_str_equal);
    g_hash_table_insert(attr, (gchar*)"account", (gchar*)account);
    gboolean sok = secret_password_storev_sync(&APP_SCHEMA, attr, NULL,
        "com.example.icp_autorun/FlutterSecureStorage", blob, NULL, &err);
    if (!sok) { fprintf(stderr, "VERDICT: FAIL store blob: %s\n",
        err ? err->message : "?"); return 2; }
    fprintf(stderr, "blob store: OK\n");

    // 3) lookup blob back
    gchar *back = secret_password_lookupv_sync(&APP_SCHEMA, attr, NULL, &err);
    if (err) { fprintf(stderr, "VERDICT: FAIL lookup err: %s\n", err->message); return 3; }
    int verdict = 5;
    if (back == NULL) {
        fprintf(stderr, "VERDICT: FAIL lookup returned NULL (silent data loss)\n");
    } else if (strcmp(back, blob) == 0) {
        fprintf(stderr, "VERDICT: OK libsecret(C)<->mock round-trip byte-identical\n");
        verdict = 0;
    } else {
        fprintf(stderr, "VERDICT: FAIL mismatch: got '%s'\n", back);
    }
    secret_password_free(back);
    return verdict;
}
