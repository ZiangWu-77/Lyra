#include "../Sources/OfflineGate.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>

/* Isolated regression test. Loopback only, no user data, no Internet target.
   Refused connection is NOT a pass: the OS must deny the operation itself. */
int keytone_verify_network_denied(void) {
    int passed = 0;
    for (int familyIndex = 0; familyIndex < 2; familyIndex++) {
        int family = familyIndex ? AF_INET6 : AF_INET;
        struct sockaddr_storage address;
        memset(&address, 0, sizeof(address));
        socklen_t length;
        if (family == AF_INET) {
            struct sockaddr_in *a = (struct sockaddr_in *)&address;
            a->sin_family = AF_INET;
            a->sin_port = htons(9);
            a->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            length = sizeof(*a);
        } else {
            struct sockaddr_in6 *a = (struct sockaddr_in6 *)&address;
            a->sin6_family = AF_INET6;
            a->sin6_port = htons(9);
            a->sin6_addr = in6addr_loopback;
            length = sizeof(*a);
        }
        for (int operation = 0; operation < 3; operation++) {
            int fd = socket(family, operation == 1 ? SOCK_DGRAM : SOCK_STREAM, 0);
            if (fd < 0) {
                if (errno == EPERM || errno == EACCES) { passed++; continue; }
                return -1;
            }
            int result;
            if (operation == 0) result = connect(fd, (struct sockaddr *)&address, length);
            else if (operation == 1) result = (int)sendto(fd, "test", 4, 0, (struct sockaddr *)&address, length);
            else {
                if (family == AF_INET) ((struct sockaddr_in *)&address)->sin_port = 0;
                else ((struct sockaddr_in6 *)&address)->sin6_port = 0;
                result = bind(fd, (struct sockaddr *)&address, length);
            }
            int denied = result < 0 && (errno == EPERM || errno == EACCES);
            close(fd);
            if (!denied) return -1;
            passed++;
        }
    }
    return passed == 6 ? 0 : -1;
}

int main(void) {
    if (keytone_lock_network() != 0) return 70;
    int result = keytone_verify_network_denied();
    puts(result == 0 ? "PASS: IPv4/IPv6 TCP, UDP and bind denied by OS" : "FAIL: network gate");
    return result == 0 ? 0 : 1;
}
