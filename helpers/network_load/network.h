#include <stdio.h>
#include <string.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <sys/sysctl.h>
#include <time.h>
struct network {
  uint32_t row;
  struct ifmibdata data;
  struct timespec ts_prev;

  double up_mbps;
  double down_mbps;
};

static inline void ifdata(uint32_t net_row, struct ifmibdata* data) {
	static size_t size = sizeof(struct ifmibdata);
  static int32_t data_option[] = { CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, 0, IFDATA_GENERAL };
  data_option[4] = net_row;
  sysctl(data_option, 6, data, &size, NULL, 0);
}

static inline int network_init(struct network* net, const char* ifname) {
  memset(net, 0, sizeof(struct network));

  if (!ifname || ifname[0] == '\0') return 0;
  net->row = if_nametoindex(ifname);
  if (net->row == 0) return 0;
  ifdata(net->row, &net->data);
  return 1;
}

static inline void network_update(struct network* net) {
  struct timespec ts_now;
  clock_gettime(CLOCK_MONOTONIC, &ts_now);
  if (net->ts_prev.tv_sec == 0 && net->ts_prev.tv_nsec == 0) {
    net->ts_prev = ts_now;
    return;
  }
  double time_scale = (double)(ts_now.tv_sec - net->ts_prev.tv_sec)
                      + (double)(ts_now.tv_nsec - net->ts_prev.tv_nsec) / 1e9;
  net->ts_prev = ts_now;

  uint64_t ibytes_nm1 = net->data.ifmd_data.ifi_ibytes;
  uint64_t obytes_nm1 = net->data.ifmd_data.ifi_obytes;
  ifdata(net->row, &net->data);

  if (time_scale <= 0.0 || time_scale > 1e2) return;
  double delta_ibytes = (double)(net->data.ifmd_data.ifi_ibytes - ibytes_nm1)
                        / time_scale;
  double delta_obytes = (double)(net->data.ifmd_data.ifi_obytes - obytes_nm1)
                        / time_scale;

  if (delta_ibytes < 0) delta_ibytes = 0;
  if (delta_obytes < 0) delta_obytes = 0;

  net->down_mbps = (delta_ibytes * 8.0) / 1000000.0;
  net->up_mbps = (delta_obytes * 8.0) / 1000000.0;
}
