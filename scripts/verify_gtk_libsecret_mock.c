// Minimal GTK + libsecret program: does calling secret_password_storev_sync
// from a GTK main loop round-trip through the mock Secret Service?
//
// This reproduces the Flutter app's execution context (GTK app, libsecret sync
// call dispatched from the platform/main thread) far more closely than the
// plain scripts/verify_libsecret_mock.c probe, ruling out "GTK main-loop +
// libsecret sync" as a class of failure.
//
// Build + run:
//   gcc scripts/verify_gtk_libsecret_mock.c $(pkg-config --cflags --libs gtk+-3.0 libsecret-1) -o /tmp/gtls
//   scripts/run-with-mock-keyring.sh /tmp/gtls
//
// Expected (decisive): `VERDICT_GTK: OK` (the store+lookup round-trips and the
// mock's secrets.json gains the item). See docs/specs/UX_REVIEW_ROUND3.md
// addendum.
#include <libsecret/secret.h>
#include <gtk/gtk.h>
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>

static const SecretSchema SCHEMA = {
    "gtk.test.schema", SECRET_SCHEMA_NONE,
    { { "account", SECRET_SCHEMA_ATTRIBUTE_STRING }, { NULL, 0 } } };

static gboolean do_probe(gpointer data) {
    GError *err = NULL;
    fprintf(stderr, "GTK: calling secret_password_storev_sync...\n");
    GHashTable *attr = g_hash_table_new(g_str_hash, g_str_equal);
    g_hash_table_insert(attr, (gchar*)"account", (gchar*)"gtkprobe");
    gboolean ok = secret_password_storev_sync(&SCHEMA, attr, NULL,
        "GTK Probe", "hello", NULL, &err);
    if (!ok) { fprintf(stderr, "GTK: store FAILED: %s\n", err?err->message:"?"); }
    else fprintf(stderr, "GTK: store OK\n");

    gchar *back = secret_password_lookupv_sync(&SCHEMA, attr, NULL, &err);
    fprintf(stderr, "GTK: lookup -> %s (matches=%d)\n",
        back?back:"NULL", back && g_strcmp0(back,"hello")==0);
    secret_password_free(back);
    fprintf(stderr, "VERDICT_GTK: %s\n", ok ? "OK" : "FAIL");
    exit(ok ? 0 : 7);
}

static gboolean bail(gpointer data) { fprintf(stderr, "VERDICT_GTK: HUNG (timed out after 8s)\n"); exit(99); return G_SOURCE_REMOVE; }

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    // Run the libsecret probe on the GTK main loop (idle callback), exactly as
    // the Flutter plugin would invoke it from the UI thread.
    g_idle_add(do_probe, NULL);
    // Safety: bail after 8s if it hangs.
    g_timeout_add_seconds(8, bail, NULL);
    gtk_main();
    return 0;
}
