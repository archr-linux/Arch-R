/*
 * input-merge — Merge gpio-keys + adc-joystick into single virtual gamepad
 *
 * The R36S has buttons (gpio-keys) and analog sticks (adc-joystick) as
 * separate evdev devices. RetroArch's udev driver assigns each to a
 * different player port, so analog sticks end up on "player 2" and are
 * ignored when max_users=1.
 *
 * This daemon:
 *   1. Finds both devices by name in /dev/input/
 *   2. Grabs them (EVIOCGRAB) so only we read their events
 *   3. Creates a virtual "Arch R Gamepad" via uinput with all capabilities
 *   4. Forwards all events from both sources to the virtual device
 *
 * Started by retroarch-launch.sh before RetroArch, killed on RA exit.
 * While grabbed, EmulationStation and other programs won't see the
 * original devices — that's fine because RA is the only thing running.
 *
 * Build: aarch64-linux-gnu-gcc -static -O2 -o input-merge input-merge.c
 */

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define DEVICE_NAME    "Arch R Gamepad"
#define MAX_EVENTS     16
#define RETRY_DELAY_US 200000  /* 200ms between retries */
#define MAX_RETRIES    50      /* 10 seconds max wait */

static volatile int running = 1;

static void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

/* Find /dev/input/eventX by device name, return fd or -1 */
static int find_device(const char *name)
{
    char path[64];
    char dev_name[256];
    int i;

    for (i = 0; i < 32; i++) {
        int fd;
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0)
            continue;

        if (ioctl(fd, EVIOCGNAME(sizeof(dev_name)), dev_name) >= 0) {
            if (strcmp(dev_name, name) == 0)
                return fd;
        }
        close(fd);
    }
    return -1;
}

/* Create uinput virtual device with capabilities from both sources */
static int setup_uinput(int gpio_fd, int adc_fd)
{
    int ufd;
    struct uinput_setup setup;
    unsigned long bits[(KEY_MAX + 1) / (8 * sizeof(unsigned long)) + 1];
    int i;

    ufd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (ufd < 0) {
        perror("open /dev/uinput");
        return -1;
    }

    /* Enable EV_KEY + copy key bits from gpio-keys */
    ioctl(ufd, UI_SET_EVBIT, EV_KEY);
    memset(bits, 0, sizeof(bits));
    if (ioctl(gpio_fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) >= 0) {
        for (i = 0; i <= KEY_MAX; i++) {
            if (bits[i / (8 * sizeof(unsigned long))] &
                (1UL << (i % (8 * sizeof(unsigned long))))) {
                ioctl(ufd, UI_SET_KEYBIT, i);
            }
        }
    }

    /* Enable EV_ABS + copy abs bits from adc-joystick (with absinfo) */
    ioctl(ufd, UI_SET_EVBIT, EV_ABS);
    memset(bits, 0, sizeof(bits));
    if (ioctl(adc_fd, EVIOCGBIT(EV_ABS, sizeof(bits)), bits) >= 0) {
        for (i = 0; i <= ABS_MAX; i++) {
            if (bits[i / (8 * sizeof(unsigned long))] &
                (1UL << (i % (8 * sizeof(unsigned long))))) {
                struct uinput_abs_setup abs_setup;
                memset(&abs_setup, 0, sizeof(abs_setup));
                abs_setup.code = i;
                if (ioctl(adc_fd, EVIOCGABS(i), &abs_setup.absinfo) >= 0)
                    ioctl(ufd, UI_ABS_SETUP, &abs_setup);
            }
        }
    }

    /* Device identity */
    memset(&setup, 0, sizeof(setup));
    strncpy(setup.name, DEVICE_NAME, UINPUT_MAX_NAME_SIZE - 1);
    setup.id.bustype = BUS_VIRTUAL;
    setup.id.vendor  = 0x4152;  /* "AR" */
    setup.id.product = 0x3336;  /* "36" */
    setup.id.version = 1;

    if (ioctl(ufd, UI_DEV_SETUP, &setup) < 0) {
        perror("UI_DEV_SETUP");
        close(ufd);
        return -1;
    }
    if (ioctl(ufd, UI_DEV_CREATE) < 0) {
        perror("UI_DEV_CREATE");
        close(ufd);
        return -1;
    }

    return ufd;
}

int main(void)
{
    int gpio_fd = -1, adc_fd = -1, ufd, epfd;
    int retries = 0;
    struct epoll_event ev, events[MAX_EVENTS];
    struct input_event ie;

    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);

    /* Wait for both devices to appear (kernel may still be probing) */
    while (running && retries < MAX_RETRIES) {
        if (gpio_fd < 0)
            gpio_fd = find_device("gpio-keys");
        if (adc_fd < 0)
            adc_fd = find_device("adc-joystick");
        if (gpio_fd >= 0 && adc_fd >= 0)
            break;
        usleep(RETRY_DELAY_US);
        retries++;
    }

    if (gpio_fd < 0 || adc_fd < 0) {
        fprintf(stderr, "input-merge: devices not found (gpio=%d adc=%d)\n",
                gpio_fd, adc_fd);
        if (gpio_fd >= 0) close(gpio_fd);
        if (adc_fd >= 0) close(adc_fd);
        return 1;
    }

    /* Grab both devices (exclusive access) */
    if (ioctl(gpio_fd, EVIOCGRAB, 1) < 0)
        perror("EVIOCGRAB gpio-keys");
    if (ioctl(adc_fd, EVIOCGRAB, 1) < 0)
        perror("EVIOCGRAB adc-joystick");

    /* Create virtual combined device */
    ufd = setup_uinput(gpio_fd, adc_fd);
    if (ufd < 0) {
        ioctl(gpio_fd, EVIOCGRAB, 0);
        ioctl(adc_fd, EVIOCGRAB, 0);
        close(gpio_fd);
        close(adc_fd);
        return 1;
    }

    /* Small delay for uinput device to settle */
    usleep(50000);

    /* Signal ready: write PID file so launcher knows we're up */
    {
        int pfd = open("/run/input-merge.pid", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (pfd >= 0) {
            char buf[16];
            int len = snprintf(buf, sizeof(buf), "%d\n", getpid());
            write(pfd, buf, len);
            close(pfd);
        }
    }

    fprintf(stderr, "input-merge: active (gpio=%d adc=%d -> %s)\n",
            gpio_fd, adc_fd, DEVICE_NAME);

    /* epoll on both source devices */
    epfd = epoll_create1(0);

    ev.events = EPOLLIN;
    ev.data.fd = gpio_fd;
    epoll_ctl(epfd, EPOLL_CTL_ADD, gpio_fd, &ev);

    ev.data.fd = adc_fd;
    epoll_ctl(epfd, EPOLL_CTL_ADD, adc_fd, &ev);

    /* Event forwarding loop */
    while (running) {
        int n = epoll_wait(epfd, events, MAX_EVENTS, 1000);
        int i;
        for (i = 0; i < n; i++) {
            while (read(events[i].data.fd, &ie, sizeof(ie)) == sizeof(ie)) {
                write(ufd, &ie, sizeof(ie));
            }
        }
    }

    /* Cleanup */
    ioctl(ufd, UI_DEV_DESTROY);
    close(ufd);
    ioctl(gpio_fd, EVIOCGRAB, 0);
    ioctl(adc_fd, EVIOCGRAB, 0);
    close(gpio_fd);
    close(adc_fd);
    close(epfd);
    unlink("/run/input-merge.pid");

    fprintf(stderr, "input-merge: stopped\n");
    return 0;
}
