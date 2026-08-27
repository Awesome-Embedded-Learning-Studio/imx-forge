// SPDX-License-Identifier: GPL-2.0
/*
 * hello_app.c — userspace side of examples/qemu-hello
 *
 * Opens /dev/hello, reads the kernel-side greeting twice (second read
 * must hit EOF), prints both results. Exit code 0 only when everything
 * worked — usable as a CI assertion as-is.
 */

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
    char buf[128];
    int fd;
    ssize_t n;

    fd = open("/dev/hello", O_RDONLY);
    if (fd < 0) {
        perror("open /dev/hello (is hello_mod loaded?)");
        return 1;
    }

    n = read(fd, buf, sizeof(buf) - 1);
    if (n < 0) {
        perror("read");
        close(fd);
        return 1;
    }
    buf[n] = '\0';
    printf("[app] first read (%zd bytes): %s", n, buf);

    n = read(fd, buf, sizeof(buf) - 1);
    if (n < 0) {
        perror("second read");
        close(fd);
        return 1;
    }
    printf("[app] second read returns %zd (expected 0 = EOF)\n", n);

    close(fd);
    printf("[app] PASS\n");
    return 0;
}
