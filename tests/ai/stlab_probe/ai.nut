//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


//
// Test fixture Script AI. Not shipped with the game: it lives with the automated
// tests and is attached through the test support in api_ai_test.cc.
//
// Its only job is to prove that a script ai vm loaded and that the engine
// dispatched start(). It calls no gameplay tool, so it is safe to attach while the
// game is pretending to be a network server - a tool call would suspend the vm.
//

function start(pl)
{
	aitest_note("start:" + pl)
}
