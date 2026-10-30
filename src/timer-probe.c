/* Read-only QNX timer characterization; this is not a random generator. */
#include <sys/neutrino.h>
#include <sys/syspage.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

static uint64_t monotonic(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) return 0;
    return (uint64_t)now.tv_sec * 1000000000ULL + now.tv_nsec;
}

static void measure(const char *name, uint64_t (*timer)(void))
{
    uint64_t prev = timer(), min = ~(uint64_t)0, max = 0;
    unsigned i, zero = 0, backwards = 0, changed = 0;
    for (i = 0; i < 100000; i++) {
        uint64_t now = timer();
        if (now == prev) zero++;
        else if (now < prev) backwards++;
        else {
            uint64_t delta = now - prev;
            if (delta < min) min = delta;
            if (delta > max) max = delta;
            changed++;
        }
        prev = now;
    }
    printf("%s samples=100000 unchanged=%u increasing=%u backwards=%u min_delta=%llu max_delta=%llu\n",
           name, zero, changed, backwards,
           (unsigned long long)(changed ? min : 0), (unsigned long long)max);
}

static uint64_t cycles(void) { return ClockCycles(); }

int main(void)
{
    struct timespec resolution;
    alarm(15);
    printf("ClockCycles frequency=%llu Hz; qtime tick=%lu ns; timer_load=%lu\n",
           (unsigned long long)SYSPAGE_ENTRY(qtime)->cycles_per_sec,
           SYSPAGE_ENTRY(qtime)->nsec_inc, SYSPAGE_ENTRY(qtime)->timer_load);
    if (!clock_getres(CLOCK_MONOTONIC, &resolution))
        printf("CLOCK_MONOTONIC resolution=%ld.%09ld seconds\n",
               (long)resolution.tv_sec, resolution.tv_nsec);
    measure("ClockCycles", cycles);
    measure("CLOCK_MONOTONIC", monotonic);
    return 0;
}
