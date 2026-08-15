//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//

//
// Regression tests for the simutrans specific changes to the squirrel vm.
//
// These freeze current behaviour. They are deliberately independent of the
// pakset, of the map and of wall clock time.
//


// The vm counts every executed instruction: _ops_total goes up, _ops_remaining
// goes down.  Both are exported as get_ops_total() and get_ops_remaining().
function test_vm_ops_counters_are_integers()
{
	ASSERT_EQUAL(typeof get_ops_total(), "integer")
	ASSERT_EQUAL(typeof get_ops_remaining(), "integer")
}


// Opcodes spent must show up in both counters, with the same amount.
// sleep() first, so that the budget is full and the vm cannot be suspended
// in the middle of the measurement, which would refill _ops_remaining.
function test_vm_ops_counters_track_each_other()
{
	sleep()

	local total_before     = get_ops_total()
	local remaining_before = get_ops_remaining()

	local sum = 0
	for (local i = 0; i < 200; i++) {
		sum += i
	}

	local total_after     = get_ops_total()
	local remaining_after = get_ops_remaining()

	// the loop really ran
	ASSERT_EQUAL(sum, 19900)

	local spent = total_after - total_before

	// at least one opcode per iteration
	ASSERT_TRUE(spent >= 200)
	// no suspension happened, so the budget dropped by exactly what was spent
	ASSERT_EQUAL(remaining_before - remaining_after, spent)
}


// sleep() suspends the vm. The engine resumes it and hands it a fresh budget.
// The important part is that execution continues where it stopped, with the
// local state of the running function intact.
function test_vm_suspend_resume_keeps_state()
{
	local before = "value before suspend"
	local number = 1234
	local list   = [1, 2, 3]

	sleep()

	// same function, same locals, after the vm was suspended and resumed
	ASSERT_EQUAL(before, "value before suspend")
	ASSERT_EQUAL(number, 1234)
	ASSERT_EQUAL(list.len(), 3)
	ASSERT_EQUAL(list[2], 3)

	// and it can still compute
	ASSERT_EQUAL(number + list[0], 1235)
}


// After a suspend the script gets a full budget again.
function test_vm_suspend_refills_budget()
{
	sleep()
	ASSERT_TRUE(get_ops_remaining() > 1000)
}


// simutrans extends the "wrong number of parameters" message of the vm by the
// name of the called function. For native functions the name is the only
// context, and it does not depend on any file path.
function test_vm_arity_diagnostic_native()
{
	local msg = null
	try {
		get_ops_total(1, 2, 3)
	}
	catch (err) {
		msg = "" + err
	}

	ASSERT_TRUE(msg != null)
	ASSERT_EQUAL(msg, "wrong number of parameters: 4 provided (instead 1) in call to get_ops_total")
}


// For squirrel functions the message also carries source and function name.
// The source is an absolute path, and Raise_Error_vl() truncates the message to
// a buffer sized from the format string, so how much of it survives depends on
// the length of the base directory. Only the stable part is checked here.
function test_vm_arity_diagnostic_squirrel()
{
	local msg = null
	try {
		coord(1)
	}
	catch (err) {
		msg = "" + err
	}

	ASSERT_TRUE(msg != null)
	ASSERT_EQUAL(msg.find("wrong number of parameters: 2 provided (instead 3) in call to "), 0)
	// a source name was appended, whatever survived of it
	ASSERT_TRUE(msg.len() > 62)
}


// _OP_LOADFLOAT is an upstream opcode, but simutrans decodes its argument with
// memcpy instead of an aliasing cast. All values below are exactly
// representable as SQFloat, so they must compare equal without a tolerance.
function test_vm_float_literals()
{
	ASSERT_EQUAL(typeof 1.5, "float")

	ASSERT_TRUE(0.0 == 0.0)
	ASSERT_TRUE(1.0 == 1.0)
	ASSERT_TRUE(1.5 + (-1.5) == 0.0)
	ASSERT_TRUE(0.5 + 0.25 == 0.75)
	ASSERT_TRUE(-0.125 * 2.0 == -0.25)
	ASSERT_TRUE(1024.5 - 1024.0 == 0.5)
	ASSERT_TRUE(1.5 * 2.0 == 3.0)

	// distinct literals must not decode to the same value
	ASSERT_TRUE(1.0 != 1.5)
	ASSERT_TRUE(0.5 != -0.5)

	// and they survive a round trip through a local and an array
	local values = [0.0, 1.0, -1.5, 0.25, 1024.5]
	ASSERT_EQUAL(values.len(), 5)
	ASSERT_TRUE(values[2] == -1.5)
	ASSERT_TRUE(values[4] == 1024.5)
	ASSERT_TRUE(values[1] + values[3] == 1.25)
}


// Returns the number of call frames below the caller.
function vm_test_stack_depth()
{
	local depth = 0
	while (::getstackinfos(depth) != null) {
		depth++
	}
	return depth
}


// Tail calls are still optimized, so a call in tail position reuses the frame
// and the stack does not grow with the recursion depth. Simutrans only disabled
// the sq_tailcall() entry point for native closures, not _OP_TAILCALL.
function test_vm_tail_recursion_reuses_the_frame()
{
	local depth_at_bottom = -1

	local countdown = null
	countdown = function(n) {
		if (n <= 0) {
			depth_at_bottom = vm_test_stack_depth()
			return 0
		}
		return countdown(n - 1) // tail position
	}

	ASSERT_EQUAL(countdown(10), 0)
	local shallow = depth_at_bottom

	ASSERT_EQUAL(countdown(50), 0)
	local deep = depth_at_bottom

	// the recursion depth does not reach the stack
	ASSERT_EQUAL(shallow, deep)
}


// The counter test: without a tail call the stack does grow, which is what
// makes the test above meaningful.
function test_vm_non_tail_recursion_grows_the_stack()
{
	local depth_at_bottom = -1

	local countdown = null
	countdown = function(n) {
		if (n <= 0) {
			depth_at_bottom = vm_test_stack_depth()
			return 0
		}
		local result = countdown(n - 1) // not a tail call
		return result
	}

	ASSERT_EQUAL(countdown(10), 0)
	local shallow = depth_at_bottom

	ASSERT_EQUAL(countdown(50), 0)
	local deep = depth_at_bottom

	ASSERT_EQUAL(deep - shallow, 40)
}


// closure.call() works. In simutrans it is a plain call, because the tail call
// branch of closure_call() waits for sq_tailcall() to be enabled again.
function test_vm_closure_call()
{
	local add = function(a, b) {
		return a + b
	}

	ASSERT_EQUAL(add.call(this, 2, 3), 5)
	ASSERT_EQUAL(add.acall([this, 4, 5]), 9)
	ASSERT_EQUAL(add.pcall(this, 6, 7), 13)
}
