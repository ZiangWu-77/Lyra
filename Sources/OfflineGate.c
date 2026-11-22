#include "OfflineGate.h"
#include <sandbox.h>
#include <stddef.h>

/* Apply before AppKit, audio, preferences, or input capture. Fail closed.
   Seatbelt is deprecated by Apple; no fallback to an unsandboxed launch.
   No webview, URL loader, helper process, or updater exists in this app. */
int keytone_lock_network(void) {
    char *error = NULL;
    const char *profile = "(version 1)(allow default)(deny network*)(deny process-fork)(deny process-exec)";
    int result = sandbox_init(profile, 0, &error);
    if (error) sandbox_free_error(error);
    return result;
}
