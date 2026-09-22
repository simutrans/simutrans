/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */


#include "gui_waytype_tab_panel.h"

#include "../../simskin.h"
#include "../../simhalt.h"

#include "../../builder/vehikelbauer.h"
#include "../../builder/wegbauer.h"

#include "../../obj/way/kanal.h"
#include "../../obj/way/maglev.h"
#include "../../obj/way/monorail.h"
#include "../../obj/way/narrowgauge.h"
#include "../../obj/way/runway.h"
#include "../../obj/way/schiene.h"
#include "../../obj/way/strasse.h"

#include "../../dataobj/translator.h"

#include "../../descriptor/skin_desc.h"

#include "../../world/simworld.h"

void gui_waytype_tab_panel_t::init_tabs(gui_component_t* c)
{
	uint8 max_idx = 0;

	// some request no generic waytype
	if (include_all) {
		add_tab(c, translator::translate("All"));
		tabs_to_waytype[max_idx++] = ignore_wt;
	}

	const uint32 month_now = world()->get_timeline_year_month();

	// now add all specific tabs
	if (strasse_t::default_strasse) {
		add_tab(c, translator::translate("Truck"), skinverwaltung_t::autohaltsymbol, translator::translate("Truck"));
		tabs_to_waytype[max_idx++] = road_wt;
	}
	if (way_builder_t::weg_search(track_wt, 1, month_now, type_flat)) {
		add_tab(c, translator::translate("Train"), skinverwaltung_t::zughaltsymbol, translator::translate("Train"));
		tabs_to_waytype[max_idx++] = track_wt;
	}
	if (way_builder_t::weg_search(narrowgauge_wt, 1, month_now, type_flat)) {
		add_tab(c, translator::translate("Narrowgauge"), skinverwaltung_t::narrowgaugehaltsymbol, translator::translate("Narrowgauge"));
		tabs_to_waytype[max_idx++] = narrowgauge_wt;
	}
	if (vehicle_builder_t::vehicle_search(tram_wt, month_now, 0, 0, NULL, true, false)) {
		add_tab(c, translator::translate("Tram"), skinverwaltung_t::tramhaltsymbol, translator::translate("Tram"));
		tabs_to_waytype[max_idx++] = tram_wt;
	}
	if (way_builder_t::weg_search(maglev_wt, 1, month_now, type_flat)  ||  way_builder_t::weg_search(maglev_wt, 1, month_now, type_elevated)) {
		add_tab(c, translator::translate("Maglev"), skinverwaltung_t::maglevhaltsymbol, translator::translate("Maglev"));
		tabs_to_waytype[max_idx++] = maglev_wt;
	}
	if (way_builder_t::weg_search(monorail_wt, 1, month_now, type_flat)  ||  way_builder_t::weg_search(monorail_wt, 1, month_now, type_elevated)) {
		add_tab(c, translator::translate("Monorail"), skinverwaltung_t::monorailhaltsymbol, translator::translate("Monorail"));
		tabs_to_waytype[max_idx++] = monorail_wt;
	}
	if (vehicle_builder_t::vehicle_search(water_wt, month_now, 0, 0, NULL, true, false)) {
		add_tab(c, translator::translate("Ship"), skinverwaltung_t::schiffshaltsymbol, translator::translate("Ship"));
		tabs_to_waytype[max_idx++] = water_wt;
	}
	if (way_builder_t::weg_search(air_wt, 1, month_now, type_flat)) {
		add_tab(c, translator::translate("Aircraft"), skinverwaltung_t::airhaltsymbol, translator::translate("Aircraft"));
		tabs_to_waytype[max_idx++] = air_wt;
	}
}


void gui_waytype_tab_panel_t::set_active_tab_waytype(waytype_t wt)
{
	for(uint32 i=0;  i < get_count();  i++  ) {
		if (wt == tabs_to_waytype[i]) {
			set_active_tab_index(i);
			return;
		}
	}
	// assume invalid type
	set_active_tab_index(0);
}


haltestelle_t::stationtyp gui_waytype_tab_panel_t::get_active_tab_stationtype() const
{
	switch(get_active_tab_waytype()) {
		case air_wt:         return haltestelle_t::airstop;
		case road_wt:        return haltestelle_t::loadingbay | haltestelle_t::busstop;
		case track_wt:       return haltestelle_t::railstation;
		case water_wt:       return haltestelle_t::dock;
		case monorail_wt:    return haltestelle_t::monorailstop;
		case maglev_wt:      return haltestelle_t::maglevstop;
		case tram_wt:        return haltestelle_t::tramstop;
		case narrowgauge_wt: return haltestelle_t::narrowgaugestop;
		default:             return haltestelle_t::invalid;

	}
}


