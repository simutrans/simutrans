#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#

# SDL3 now the default choice as ARM64 does no longer support SDL2 properly
if (SDL3_FOUND AND Freetype_FOUND)
	list(APPEND AVAILABLE_BACKENDS "sdl3")
	mark_as_advanced(SDL3_DIR)
endif ()

if (SDL2_FOUND AND Freetype_FOUND)
	list(APPEND AVAILABLE_BACKENDS "sdl2")
	mark_as_advanced(SDL2_DIR)
endif ()

if (WIN32 AND Freetype_FOUND)
	list(APPEND AVAILABLE_BACKENDS "gdi")
endif ()

list(APPEND AVAILABLE_BACKENDS "none")

string(REGEX MATCH "^[^;][^;]*" FIRST_BACKEND "${AVAILABLE_BACKENDS}")
set(SIMUTRANS_BACKEND "${FIRST_BACKEND}" CACHE STRING "Graphics backend")
set_property(CACHE SIMUTRANS_BACKEND PROPERTY STRINGS ${AVAILABLE_BACKENDS})
