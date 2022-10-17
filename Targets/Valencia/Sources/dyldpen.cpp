//
//  dyldpen.cpp
//  Valencia
//
//  Created by Eric Rabil on 11/2/22.
//  Copyright © 2022 tuist.io. All rights reserved.
//

#include <stdio.h>
#include <sys/types.h>
#include <sys/ptrace.h>

#define DYLD_INTERPOSE(_replacement,_replacee) \
   __attribute__((used)) static struct { const void* replacement; const void* replacee; } _interpose_##_replacee \
            __attribute__ ((section ("__DATA,__interpose,interposing"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };


int ptrace_ghetto(int request, pid_t pid, caddr_t addr, int data) {
    return 0;
}

DYLD_INTERPOSE(ptrace_ghetto, ptrace);
