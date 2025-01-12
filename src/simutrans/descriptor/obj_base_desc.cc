/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include "obj_base_desc.h"
#include "../network/checksum.h"
#include "intro_dates.h"
#include "../simdebug.h"


void obj_desc_timelined_t::calc_checksum(checksum_t *chk) const
{
#if MSG_LEVEL>0
	PAKSET_INFO("name=","%s",get_name());
	if(get_copyright()) PAKSET_INFO("copyright=","%s",get_copyright());
	if(intro_date!=DEFAULT_INTRO_DATE) {
		PAKSET_INFO("intro_year=","%d",intro_date/12);
		if(intro_date%12) PAKSET_INFO("intro_month=","%d",(intro_date%12)+1);
	}
	if(retire_date!=DEFAULT_RETIRE_DATE) {
		PAKSET_INFO("retire_year=","%d",retire_date/12);
		if(retire_date%12) PAKSET_INFO("retire_month=","%d",(retire_date%12)+1);
	}
#endif
	chk->input(intro_date);
	chk->input(retire_date);
}


void obj_desc_transport_related_t::calc_checksum(checksum_t *chk) const
{
	obj_desc_timelined_t::calc_checksum(chk);
#if MSG_LEVEL>0
	if(maintenance) PAKSET_INFO("maintenance=","%d",maintenance);
	if(price) PAKSET_INFO("cost=","%d",price);
	switch(wtyp) {
		case ignore_wt:      PAKSET_INFO("waytype=","none"); break;
		case track_wt:       PAKSET_INFO("waytype=","track"); break;
		case maglev_wt:      PAKSET_INFO("waytype=","maglev_track"); break;
		case monorail_wt:    PAKSET_INFO("waytype=","monorail_track"); break;
		case narrowgauge_wt: PAKSET_INFO("waytype=","narrowgauge_track"); break;
		case air_wt:         PAKSET_INFO("waytype=","air"); break;
		case water_wt:       PAKSET_INFO("waytype=","water"); break;
		case tram_wt:        PAKSET_INFO("waytype=","tram_track"); break;
		case powerline_wt:   PAKSET_INFO("waytype=","power"); break;
		case decoration_wt:  PAKSET_INFO("waytype=","decoration"); break;
		default:
		break;
	}
	if(topspeed) PAKSET_INFO("speed=","%d",topspeed);
	if(axle_load) PAKSET_INFO("axle_load=","%d",axle_load);
#endif
	chk->input(maintenance);
	chk->input(price);
	chk->input(wtyp);
	chk->input(topspeed);
	chk->input(axle_load);
}
