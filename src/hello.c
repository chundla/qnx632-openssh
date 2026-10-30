#include <stdio.h>
#include <sys/utsname.h>

int main(void)
{
    struct utsname system;
    if (uname(&system) != 0) {
        perror("uname");
        return 1;
    }
    printf("MMI SHLE toolchain test: %s %s %s\n",
           system.sysname, system.release, system.machine);
    return 0;
}
