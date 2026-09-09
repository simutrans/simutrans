#!/bin/bash
set -e

#
# Runs the automated test scenario and decides whether it passed.
#
# Two kinds of signal, kept apart, because conflating them made the result
# depend on when the poll happened to look:
#
#   * The suite's own verdict. It prints "Tests completed successfully." when
#     every test passed and dumps </error> when an assertion throws. Both are
#     unambiguous, so they are watched while the game runs and a broken suite
#     is caught at once rather than at the CPU limit.
#
#   * Engine script errors. These say a script failed to load or a call
#     failed, which normally means a test broke without saying so. But a test
#     may drive a failure path on purpose, and then the same line appears for a
#     good reason. Those are classified ONCE, after the run, against what the
#     suite announced with EXPECT_SCRIPT_ERROR - never inside the loop, where
#     whether the poll fell before or after the last test decided the result.
#
# An announcement excuses only lines containing the text it names, and an
# announced error that never happened is itself a failure, so a declaration
# cannot quietly become a blanket excuse.
#

pushd simutrans
../sim -use_workdir -objects pak -lang en -scenario automated-tests -addons -debug 2 2>&1 | ts -s | tee output.log &
pid=$!

result=1

while :
do
	sleep 1

	if [[ ! -d /proc/$pid/ ]]
	then
		# process crashed etc.
		echo "Process crashed (test failed)"
		result=1
		break
	fi

	if [[ -n "$(grep 'Tests completed successfully.' output.log)" ]]
	then
		# every test passed; the game itself never exits
		kill %1
		result=0
		break
	fi

	if [[ -n "$(grep '</error>' output.log)" ]]
	then
		# a test threw: the suite's own failure report
		echo "Killing process (test failed)"
		kill %1
		result=1
		break
	fi
done

# The game has been told to stop; wait for the pipeline behind it to finish so
# that output.log is everything it wrote. Reading while tee is still draining
# could miss the last lines, and a missed error line reads as a pass.
wait %1 2>/dev/null || true

if [[ $result -eq 0 ]]
then
	# Engine script errors, judged against what the suite announced.
	#
	# One announcement excuses ONE occurrence. A test that provokes the same
	# failure twice announces it twice; a second, unannounced occurrence of the
	# same text is a defect producing the same message, and has to be seen.
	mapfile -t errors < <(grep -E 'error \[Call function failed\] calling|error \[Reading / compiling script failed\] calling' output.log || true)
	mapfile -t expected < <(sed -n 's/.*EXPECTED SCRIPT ERROR: //p' output.log || true)

	used=()
	for i in "${!expected[@]}"
	do
		used[$i]=0
	done

	for line in "${errors[@]}"
	do
		[[ -n "$line" ]] || continue
		excused=0
		for i in "${!expected[@]}"
		do
			[[ ${used[$i]} -eq 0 ]] || continue
			[[ -n "${expected[$i]}" ]] || continue
			case "$line" in
				*"${expected[$i]}"*) used[$i]=1; excused=1; break ;;
			esac
		done
		if [[ $excused -eq 0 ]]
		then
			echo "Unexpected script error (test failed): $line"
			result=1
		fi
	done

	# an announcement nothing matched means the test stopped covering what it
	# says it covers
	for i in "${!expected[@]}"
	do
		if [[ -n "${expected[$i]}" && ${used[$i]} -eq 0 ]]
		then
			echo "Announced error never happened: ${expected[$i]} (test failed)"
			result=1
		fi
	done

	if [[ $result -eq 0 ]]
	then
		echo "Killing process (test succeeded)"
	fi
fi

popd

exit $result
