/* Exercise an EGD endpoint on the target without printing its output. */
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    struct sockaddr_in address;
    unsigned char data[255], previous[40] = {0};
    struct timespec start, end;
    int i, fd;
    if (argc != 2 || atoi(argv[1]) < 1 || atoi(argv[1]) > 1023) return 1;
    signal(SIGPIPE, SIG_IGN);
    alarm(50);
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons((unsigned short)atoi(argv[1]));
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (i = 0; i < 12; i++) {
        unsigned char request[2] = {2, 40};
        size_t length = 0;
        fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0 || connect(fd, (struct sockaddr *)&address, sizeof(address))) return 1;
        if (write(fd, request, 2) != 2) return 1;
        while (length < 40) {
            ssize_t count = read(fd, data + length, sizeof(data) - length);
            if (count <= 0) return 1;
            length += (size_t)count;
        }
        if (length != 40 || !memcmp(data, previous, 40)) return 1;
        memcpy(previous, data, 40);
        close(fd);
    }
    memset(data, 0, sizeof(data));
    memset(previous, 0, sizeof(previous));
    clock_gettime(CLOCK_MONOTONIC, &end);
    printf("EGD_PROBE_OK requests=12 bytes=480 total_seconds=%.3f\n",
           (double)(end.tv_sec - start.tv_sec) +
           (double)(end.tv_nsec - start.tv_nsec) / 1000000000.0);
    return 0;
}
