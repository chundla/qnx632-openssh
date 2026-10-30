/* Loopback EGD command-2 adapter for upstream Jitterentropy.
 * No saved seed, output cache, fallback generator or external entropy input.
 * Any collector failure stops the service without returning that buffer.
 */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/resource.h>
#include <sys/mman.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#ifdef __QNXNTO__
#include <sys/poll.h>
#else
#include <poll.h>
#endif
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "jitterentropy.h"

static volatile sig_atomic_t stopping;
static void stop_service(int sig) { (void)sig; stopping = 1; }

static int transfer(int fd, unsigned char *data, size_t length, int sending)
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
        count = sending ? write(fd, data + offset, length - offset) :
                          read(fd, data + offset, length - offset);
        if (count < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (count <= 0) return -1;
        offset += (size_t)count;
    }
    return offset == length ? 0 : -1;
}

int main(int argc, char **argv)
{
    const unsigned flags = JENT_FORCE_FIPS | JENT_DISABLE_INTERNAL_TIMER;
    struct rand_data *collector = NULL;
    struct sockaddr_in address;
    struct rlimit no_core;
    struct sigaction action;
    unsigned char response[255];
    int listener = -1, client = -1, port = 708, result = 1, init;
    char *end;
    long value;

    if (argc == 2) {
        errno = 0;
        value = strtol(argv[1], &end, 10);
        if (errno || !*argv[1] || *end || value < 0 || value > 65535)
            return 1;
        port = (int)value;
    } else if (argc != 1) return 1;
#ifndef JITTER_EGD_TESTING
    if (geteuid() != 0 || port < 1 || port > 1023) {
        fprintf(stderr, "Run as root; optional loopback port must be 1..1023\n");
        return 1;
    }
#endif
    no_core.rlim_cur = no_core.rlim_max = 0;
    if (setrlimit(RLIMIT_CORE, &no_core)) return 1;
#ifdef __QNXNTO__
    {
        struct sched_param priority;
        priority.sched_priority = 1;
        if (sched_setscheduler(0, SCHED_OTHER, &priority)) {
            perror("lower entropy collector priority");
            return 1;
        }
    }
#endif
#ifndef JITTER_EGD_TESTING
    if (mlockall(MCL_CURRENT | MCL_FUTURE)) {
        perror("lock entropy process memory");
        return 1;
    }
#endif
    memset(&action, 0, sizeof(action));
    action.sa_handler = stop_service;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    signal(SIGPIPE, SIG_IGN);
    listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) goto done;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons((unsigned short)port);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address))) {
        perror("bind loopback EGD port");
        goto done;
    }
    alarm(60);
    init = jent_entropy_init_ex(3, flags);
    if (init || stopping) {
        fprintf(stderr, "Jitterentropy initialization failed: %d\n", init);
        goto done;
    }
    collector = jent_entropy_collector_alloc(3, flags);
    alarm(0);
    if (!collector || stopping) {
        fprintf(stderr, "Jitterentropy collector startup failed\n");
        goto done;
    }
    if (listen(listener, 8)) goto done;
    {
        socklen_t size = sizeof(address);
        if (getsockname(listener, (struct sockaddr *)&address, &size)) goto done;
        printf("JITTER_EGD_READY 127.0.0.1:%u version=%u OSR=3 health_tests=enabled\n",
               (unsigned)ntohs(address.sin_port), jent_version());
        fflush(stdout);
    }
    result = 0;
    while (!stopping) {
        struct pollfd event;
        unsigned char request[2];
        ssize_t count;
        int ready, fd_flags;
        event.fd = listener;
        event.events = POLLIN;
        event.revents = 0;
        ready = poll(&event, 1, 1000);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0) { result = 1; break; }
        if (!ready) continue;
        client = accept(listener, NULL, NULL);
        if (client < 0) continue;
        fd_flags = fcntl(client, F_GETFL, 0);
        if (fd_flags < 0 || fcntl(client, F_SETFL, fd_flags | O_NONBLOCK))
            goto close_client;
        if (transfer(client, request, 2, 0) || request[0] != 2 || !request[1])
            goto close_client;
        /* Bound collection time. SIGALRM terminates without publishing a
         * partially filled buffer; there is no retry or weaker fallback. */
        alarm(20);
        count = jent_read_entropy(collector, (char *)response, request[1]);
        alarm(0);
        if (count != request[1]) {
            fprintf(stderr, "Jitterentropy read/health failure: %ld; stopping\n",
                    (long)count);
            result = 1;
            break;
        }
        if (!stopping) (void)transfer(client, response, request[1], 1);
close_client:
        jent_memset_secure(response, sizeof(response));
        close(client);
        client = -1;
    }
done:
    alarm(0);
    jent_memset_secure(response, sizeof(response));
    if (client >= 0) close(client);
    if (listener >= 0) close(listener);
    if (collector) jent_entropy_collector_free(collector);
    return result;
}
