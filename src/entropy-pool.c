/* One-session EGD transport for Linux-generated entropy; no PRNG of its own.
 * Consumes and deletes a private RAM input file before serving. Each byte is
 * returned at most once; exhaustion closes the service. No entropy is logged.
 */
#define _POSIX_C_SOURCE 200112L
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#ifdef __QNXNTO__
#include <sys/poll.h>
#else
#include <poll.h>
#endif
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define POOL_LIMIT (16U * 1024U * 1024U)
#define EGD_PORT 708
static volatile sig_atomic_t stopping;

static void wipe(void *memory, size_t length)
{
    volatile unsigned char *p = memory;
    while (length--) *p++ = 0;
}

static void stop_service(int sig)
{
    (void)sig;
    stopping = 1;
}

static int transfer(int fd, unsigned char *buffer, size_t length, int sending)
{
    size_t offset = 0;
    while (offset < length && !stopping) {
        struct pollfd event;
        ssize_t count;
        int ready;
        event.fd = fd;
        event.events = sending ? POLLOUT : POLLIN;
        event.revents = 0;
        ready = poll(&event, 1, 2000);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0) return -1;
        count = sending ? write(fd, buffer + offset, length - offset) :
                          read(fd, buffer + offset, length - offset);
        if (count < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (count <= 0) return -1;
        offset += (size_t)count;
    }
    return offset == length ? 0 : -1;
}

int main(int argc, char **argv)
{
    unsigned char *pool = NULL;
    size_t length = 0, offset = 0, loaded = 0;
    struct stat before, opened;
    struct sockaddr_in address;
    struct rlimit no_core;
    struct sigaction action;
    int source = -1, listener = -1, port = EGD_PORT, result = 1;

#ifdef ENTROPY_POOL_TESTING
    if (argc == 3) port = atoi(argv[2]);
    if (argc < 2 || argc > 3 || port < 0 || port > 65535) {
#else
    if (argc != 2 || geteuid() != 0) {
#endif
        fprintf(stderr, "Usage: entropy-pool PRIVATE_RAM_POOL_FILE (run as root)\n");
        return 1;
    }
    no_core.rlim_cur = no_core.rlim_max = 0;
    if (setrlimit(RLIMIT_CORE, &no_core) != 0) {
        perror("disable core dumps");
        return 1;
    }
    if (lstat(argv[1], &before) != 0 || !S_ISREG(before.st_mode) ||
        before.st_uid != geteuid() || (before.st_mode & 077) != 0 ||
        before.st_nlink != 1 || before.st_size < 256 ||
        before.st_size > POOL_LIMIT) {
        fprintf(stderr, "Pool must be a private, single-link regular file, 256 bytes to 16 MiB\n");
        return 1;
    }
    source = open(argv[1], O_RDONLY | O_NONBLOCK);
    if (source < 0 || fstat(source, &opened) != 0 ||
        opened.st_dev != before.st_dev || opened.st_ino != before.st_ino ||
        opened.st_size != before.st_size) {
        fprintf(stderr, "Pool changed while opening\n");
        goto done;
    }
    length = (size_t)opened.st_size;
    pool = malloc(length);
    if (!pool) goto done;
    while (loaded < length) {
        ssize_t count = read(source, pool + loaded, length - loaded);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) goto done;
        loaded += (size_t)count;
    }
    listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) goto done;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons((unsigned short)port);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0) {
        perror("bind loopback EGD port");
        goto done;
    }
    /* Delete the only RAM input before accepting any entropy request. */
    if (lstat(argv[1], &before) != 0 || before.st_dev != opened.st_dev ||
        before.st_ino != opened.st_ino || unlink(argv[1]) != 0) {
        fprintf(stderr, "Unable to consume RAM pool file\n");
        goto done;
    }
    close(source);
    source = -1;
    if (listen(listener, 8) != 0) goto done;
    memset(&action, 0, sizeof(action));
    action.sa_handler = stop_service;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    signal(SIGPIPE, SIG_IGN);
    {
        socklen_t size = sizeof(address);
        if (getsockname(listener, (struct sockaddr *)&address, &size) != 0) goto done;
        printf("EGD ready at 127.0.0.1:%u; %lu one-use bytes\n",
               (unsigned)ntohs(address.sin_port), (unsigned long)length);
        fflush(stdout);
    }
    while (!stopping && offset < length) {
        struct pollfd event;
        unsigned char request[2];
        unsigned char response[255];
        int client, ready, flags;
        size_t requested;
        event.fd = listener;
        event.events = POLLIN;
        event.revents = 0;
        ready = poll(&event, 1, 1000);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0) goto done;
        if (!ready) continue;
        client = accept(listener, NULL, NULL);
        if (client < 0) continue;
        flags = fcntl(client, F_GETFL, 0);
        if (flags < 0 || fcntl(client, F_SETFL, flags | O_NONBLOCK) != 0) {
            close(client);
            continue;
        }
        /* Only EGD command 2, the blocking-read command used by OpenSSH. */
        if (transfer(client, request, sizeof(request), 0) != 0 ||
            request[0] != 2 || request[1] == 0) {
            close(client);
            continue;
        }
        requested = request[1];
        if (requested > length - offset) {
            close(client);
            continue;
        }
        memcpy(response, pool + offset, requested);
        wipe(pool + offset, requested);
        offset += requested; /* Reserve even if the client disconnects. */
        (void)transfer(client, response, requested, 1);
        wipe(response, sizeof(response));
        close(client);
    }
    fprintf(stderr, "EGD stopped; %lu unused bytes discarded\n",
            (unsigned long)(length - offset));
    result = 0;
done:
    if (source >= 0) close(source);
    if (listener >= 0) close(listener);
    if (pool) {
        wipe(pool, length);
        free(pool);
    }
    return result;
}
