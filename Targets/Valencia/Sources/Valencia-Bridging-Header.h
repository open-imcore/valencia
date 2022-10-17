//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#include <stdint.h>
#include <mach-o/loader.h>

struct dyld_interpose_tuple {
    const void* replacement;
    const void* replacee;
};
extern void dyld_dynamic_interpose(const struct mach_header* mh, const struct dyld_interpose_tuple array[], size_t count);
