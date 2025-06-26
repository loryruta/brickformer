#include <tinyformat.h>

#ifndef ARP_LOG_LEVEL // Not defined externally
#   ifdef NDEBUG
#       define ARP_LOG_LEVEL 2 // INFO
#   else
#       define ARP_LOG_LEVEL 3 // DEBUG
#   endif
#endif

#define ARP_LOG(level, format, ...) \
    tfm::printf("[" level "] [" ARP_LOG_CONTEXT "] " format "\n", ##__VA_ARGS__)

#if ARP_LOG_LEVEL >= 3
#define ARP_DEBUG(...) ARP_LOG("DEBUG", __VA_ARGS__)
#else
#define ARP_DEBUG(x, ...)
#endif

#if ARP_LOG_LEVEL >= 2
#define ARP_INFO(...) ARP_LOG("INFO ", __VA_ARGS__)
#else
#define ARP_INFO(x, ...)
#endif

#if ARP_LOG_LEVEL >= 1
#define ARP_WARN(...) ARP_LOG("WARN ", __VA_ARGS__)
#else
#define ARP_WARN(x, args)
#endif

#if ARP_LOG_LEVEL >= 0
#define ARP_ERROR(...) ARP_LOG("ERROR", __VA_ARGS__)
#else
#define ARP_ERROR(...)
#endif
