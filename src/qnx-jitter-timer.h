/* QNX 6 SH timer adapter for a single-threaded Jitterentropy collector. */
#ifndef MMI_QNX_JITTER_TIMER_H
#define MMI_QNX_JITTER_TIMER_H
#include <stdint.h>
#include <sys/neutrino.h>

static inline void jent_get_nstime(uint64_t *out)
{
    /* QNX places the 32-bit TMU count in ClockCycles' upper half. Strip
     * its fixed zero bits and extend wraps. Timer ticks need no scaling.
     * A gap longer than one wrap loses elapsed whole wraps, not the timing
     * variations of consecutive samples used by the collector.
     */
    static uint32_t previous;
    static uint64_t accumulated;
    uint32_t current = (uint32_t)(ClockCycles() >> 32);
    accumulated += (uint32_t)(current - previous);
    previous = current;
    *out = accumulated;
}
#endif
