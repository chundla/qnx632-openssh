/* Bounded hardware feasibility check; never prints random output. */
#include <sys/resource.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "jitterentropy.h"

int main(void)
{
    const unsigned flags = JENT_FORCE_FIPS | JENT_DISABLE_INTERNAL_TIMER;
    struct rand_data *collector;
    struct rlimit no_core;
    unsigned char data[32], previous[32] = {0};
    struct timespec start, end;
    char status[2048];
    unsigned i;
    int result;

    no_core.rlim_cur = no_core.rlim_max = 0;
    if (setrlimit(RLIMIT_CORE, &no_core)) return 1;
    alarm(45);
    clock_gettime(CLOCK_MONOTONIC, &start);
    result = jent_entropy_init_ex(3, flags);
    printf("Jitterentropy version=%u OSR=3 health_tests=enabled init=%d\n",
           jent_version(), result);
    fflush(stdout);
    if (result) return 1;
    collector = jent_entropy_collector_alloc(3, flags);
    if (!collector) {
        fprintf(stderr, "Collector allocation/startup failed\n");
        return 1;
    }
    if (!jent_status(collector, status, sizeof(status))) puts(status);
    for (i = 0; i < 32; i++) {
        ssize_t count = jent_read_entropy(collector, (char *)data, sizeof(data));
        if (count != sizeof(data) || !memcmp(data, previous, sizeof(data))) {
            fprintf(stderr, "Read/health/repeated-block failure: block=%u result=%ld\n",
                    i, (long)count);
            jent_entropy_collector_free(collector);
            return 1;
        }
        memcpy(previous, data, sizeof(data));
    }
    jent_memset_secure(data, sizeof(data));
    jent_memset_secure(previous, sizeof(previous));
    jent_entropy_collector_free(collector);
    clock_gettime(CLOCK_MONOTONIC, &end);
    printf("JITTER_PROBE_OK bytes=1024 total_seconds=%.3f cpu_seconds=%.3f\n",
           (double)(end.tv_sec - start.tv_sec) +
           (double)(end.tv_nsec - start.tv_nsec) / 1000000000.0,
           (double)clock() / CLOCKS_PER_SEC);
    return 0;
}
