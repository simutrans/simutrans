/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include "../simtypes.h"
#include "../simmem.h"
#include "freelist.h"
#include "../tpl/freelist_tpl.h"

 // for 64 bit, set this to 128
#define MAX_LIST_INDEX (128)

// on arm and linux, pointers are enforced on 8 bytes borders, wasting 4 bytes per tree  and 5 per water tile ...
#define FREELIST_ALIGNMENT (sizeof(void*))

// list for nodes size 8...64
#define NUM_LIST (33)

static freelist_size_t* all_lists[NUM_LIST] = {
	NULL, NULL, NULL, NULL,
	NULL, NULL, NULL, NULL,
	NULL, NULL, NULL, NULL,
	NULL, NULL, NULL, NULL,
	NULL, NULL, NULL, NULL,
	NULL, NULL, NULL, NULL,
	NULL, NULL, NULL, NULL,
	NULL, NULL, NULL, NULL,
	NULL
};

#ifdef MULTI_THREAD
static pthread_mutex_t freelist_mutex_create = PTHREAD_MUTEX_INITIALIZER;
#endif

void* freelist_t::gimme_node(size_t size)
{
	size_t idx = (size + FREELIST_ALIGNMENT -1 ) / FREELIST_ALIGNMENT;
	if (idx > NUM_LIST) {
		return xmalloc(size);
	}
	if (all_lists[idx] == NULL) {
#ifdef MULTI_THREAD
		pthread_mutex_lock(&freelist_mutex_create);
#endif
		all_lists[idx] = new freelist_size_t(idx * FREELIST_ALIGNMENT);
#ifdef MULTI_THREAD
		pthread_mutex_unlock(&freelist_mutex_create);
#endif
	}
	return all_lists[idx]->gimme_node();
}

void freelist_t::putback_node(size_t size, void* p)
{
	size = (size + FREELIST_ALIGNMENT - 1) / FREELIST_ALIGNMENT;
	if (size > NUM_LIST) {
		free(p);
	}
	else {
		all_lists[size]->putback_node(p);
	}
}

void free_all_nodes()
{
	for (int size = 0; size < NUM_LIST; size++) {
		if (all_lists[size]) {
			delete all_lists[size];
			all_lists[size] = NULL;
		}
	}
}
