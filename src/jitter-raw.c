/* Diagnostic raw-noise recorder, never used to supply production entropy.
 * Writes the low eight bits of 1,000,000 unconditioned timer deltas for
 * NIST's non-IID estimators. Does not modify the upstream noise source.
 */
#include <sys/resource.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "jitterentropy.h"
#include "jitterentropy-internal.h"
#include "jitterentropy-noise.h"
#include "jitterentropy-health.h"

int main(int argc, char **argv)
{
    const unsigned flags = JENT_FORCE_FIPS | JENT_DISABLE_INTERNAL_TIMER;
    struct rand_data *collector;
    struct rlimit no_core;
    struct sched_param priority;
    unsigned char *samples;
    unsigned i, health, stuck = 0;
    int fd, ret;
    FILE *file;

    if (argc != 2) return 1;
    no_core.rlim_cur = no_core.rlim_max = 0;
    if (setrlimit(RLIMIT_CORE, &no_core)) return 1;
    priority.sched_priority = 1;
    if (sched_setscheduler(0, SCHED_OTHER, &priority)) return 1;
    alarm(1800);
    ret = jent_entropy_init_ex(3, flags);
    printf("RAW initialization=%d OSR=3 samples=1000000 bits_per_sample=8\n", ret);
    fflush(stdout);
    if (ret) return 1;
    collector = jent_entropy_collector_alloc(3, flags);
    if (!collector) return 1;
    samples = malloc(1000000);
    if (!samples) return 1;
    fd = open(argv[1], O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0 || !(file = fdopen(fd, "wb"))) return 1;
    for (i = 0; i < 1000000; i++) {
        uint64_t delta;
        stuck += !!jent_measure_jitter(collector, 0, &delta);
        samples[i] = (unsigned char)(delta & 255);
        if ((i + 1) % 100000 == 0) {
            printf("RAW progress=%u\n", i + 1);
            fflush(stdout);
        }
    }
    health = jent_health_failure(collector);
    ret = fwrite(samples, 1, 1000000, file) == 1000000 ? 0 : 1;
    if (fclose(file)) ret = 1;
    printf("RAW complete health_failure_mask=%u stuck=%u cpu_seconds=%.3f\n",
           health, stuck, (double)clock() / CLOCKS_PER_SEC);
    free(samples);
    jent_entropy_collector_free(collector);
    return ret || health ? 1 : 0;
}
