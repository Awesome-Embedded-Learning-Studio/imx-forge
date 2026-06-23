/**
 * @file rtc_alarm_demo.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief SNVS RTC alarm one-shot demo — arm an alarm N seconds ahead and block until it fires
 * @note 验证 drivers/rtc/rtc-snvs.c 的 alarm 一次性中断：RTC_WKALM_SET 设闹钟 → 阻塞 read
 *       → 到点由 snvs_rtc_irq_handler 里的 rtc_update_irq 唤醒。
 *       连续运行两次可见 alarm 是 one-shot（handler 触发后自动 alarm_irq_enable(0)）。
 * @version 0.1
 * @date 2026-06-23
 * @copyright Copyright (c) 2026
 */

#define _GNU_SOURCE		/* timegm */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/rtc.h>

static void print_usage(const char *name)
{
	printf("Usage: %s /dev/rtcN <seconds>\n", name);
	printf("  Arm an RTC alarm <seconds> ahead, then block until it fires.\n");
	printf("  Demonstrates the one-shot alarm interrupt of rtc-snvs.c.\n");
}

int main(int argc, char *argv[])
{
	int fd, ret, secs;
	struct rtc_time now;
	struct rtc_wkalrm alarm;
	struct tm tm;
	time_t t;
	unsigned long fired;

	if (argc != 3) {
		print_usage(argv[0]);
		return 1;
	}
	secs = atoi(argv[2]);
	if (secs <= 0) {
		fprintf(stderr, "seconds must be a positive integer\n");
		return 1;
	}

	fd = open(argv[1], O_RDWR);
	if (fd < 0) {
		perror("open rtc");
		return 1;
	}

	/* 1. 读当前硬件时间 */
	ret = ioctl(fd, RTC_RD_TIME, &now);
	if (ret < 0) {
		perror("RTC_RD_TIME");
		close(fd);
		return 1;
	}
	printf("current RTC: %04d-%02d-%02d %02d:%02d:%02d\n",
	       now.tm_year + 1900, now.tm_mon + 1, now.tm_mday,
	       now.tm_hour, now.tm_min, now.tm_sec);

	/* 2. 当前时间 + secs 秒，用 timegm 规范化（处理秒→分→时进位；RTC 存 UTC，不涉时区） */
	memcpy(&tm, &now, sizeof(tm));
	tm.tm_sec += secs;
	tm.tm_isdst = -1;
	t = timegm(&tm);
	if (t == (time_t)-1) {
		fprintf(stderr, "timegm: invalid time\n");
		close(fd);
		return 1;
	}
	memcpy(&alarm.time, &tm, sizeof(alarm.time));

	/* 3. 设闹钟：RTC_WKALM_SET 支持带日期的闹钟，enabled=1 同时使能中断 */
	alarm.enabled = 1;
	alarm.pending = 0;
	ret = ioctl(fd, RTC_WKALM_SET, &alarm);
	if (ret < 0) {
		perror("RTC_WKALM_SET");
		close(fd);
		return 1;
	}
	printf("alarm armed: %04d-%02d-%02d %02d:%02d:%02d, blocking %d s...\n",
	       alarm.time.tm_year + 1900, alarm.time.tm_mon + 1, alarm.time.tm_mday,
	       alarm.time.tm_hour, alarm.time.tm_min, alarm.time.tm_sec, secs);

	/* 4. 阻塞 read，等闹钟中断到来（snvs_rtc_irq_handler → rtc_update_irq 唤醒） */
	ret = read(fd, &fired, sizeof(fired));
	if (ret < 0) {
		perror("read (waiting for alarm)");
		close(fd);
		return 1;
	}
	printf("alarm fired! interrupts=%lu\n", fired);

	close(fd);
	return 0;
}
