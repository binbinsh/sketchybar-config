#ifndef NETWORK_INTERFACE_RESOLVER_H
#define NETWORK_INTERFACE_RESOLVER_H

#include <stdbool.h>
#include <stddef.h>
#include <SystemConfiguration/SystemConfiguration.h>

bool sb_copy_primary_interface(SCDynamicStoreRef store,
                               char *buffer,
                               size_t buffer_size);
bool sb_resolve_effective_interface(SCDynamicStoreRef store,
                                    char *buffer,
                                    size_t buffer_size);

#endif
