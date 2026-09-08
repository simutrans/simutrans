#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Create and destroy the throw-away keychain that holds the Developer ID
# identity for exactly one workflow run.
#
# Usage: keychain.sh setup
#        keychain.sh teardown
#
# setup expects, in the environment:
#   MACOS_CERTIFICATE_P12           base64 of the Developer ID Application .p12
#   MACOS_CERTIFICATE_P12_PASSWORD  the password that .p12 is encrypted with
#   MACOS_SIGNING_IDENTITY          the exact identity string that must appear,
#                                   e.g. "Developer ID Application: Name (TEAMID)"
#
# Nothing secret is ever echoed.  The keychain password is generated here, used
# here, and never leaves this script.
#
# teardown is safe to call when setup never ran, and never fails the job: it is
# meant to be wired to an always() step.

set -euo pipefail

KEYCHAIN_PATH=${SIMU_KEYCHAIN_PATH:-${RUNNER_TEMP:-/tmp}/simutrans-signing.keychain-db}
SEARCH_LIST_BACKUP="${KEYCHAIN_PATH}.search-list"

# Holds the decrypted .p12 while it is being validated and imported.  Declared
# at script scope, not inside setup(), because the trap that removes it runs
# after the function has returned and would otherwise have nothing to remove.
workdir=""
trap 'if [ -n "$workdir" ]; then rm -rf "$workdir"; fi' EXIT

# ---------------------------------------------------------------------------

require_secret() {
	local name=$1
	local value=${!name:-}
	if [ -z "$value" ]; then
		echo "::error::required secret '$name' is empty or not set."
		echo "::error::This workflow cannot sign without it.  See .github/macos/README.md"
		echo "::error::for the list of secrets and how a maintainer configures them."
		return 1
	fi
	return 0
}

setup() {
	# Anything this function writes is readable only by the current user.
	umask 077

	local missing=0
	require_secret MACOS_CERTIFICATE_P12          || missing=1
	require_secret MACOS_CERTIFICATE_P12_PASSWORD || missing=1
	require_secret MACOS_SIGNING_IDENTITY         || missing=1
	if [ "$missing" -ne 0 ]; then
		echo "::error::refusing to continue with missing signing credentials."
		echo "::error::No unsigned or ad-hoc signed package will be produced as a substitute."
		exit 1
	fi

	workdir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/simu-signing.XXXXXX")

	local p12="$workdir/identity.p12"
	local pem="$workdir/identity.pem"

	# openssl is used instead of base64(1) because the BSD and GNU flags for
	# decoding differ, and openssl behaves the same on every macOS image.
	printf '%s' "$MACOS_CERTIFICATE_P12" | openssl base64 -d -A > "$p12" || {
		echo "::error::MACOS_CERTIFICATE_P12 is not valid base64."
		echo "::error::Re-export it with:  base64 -i DeveloperID.p12 | pbcopy"
		exit 1
	}
	if [ ! -s "$p12" ]; then
		echo "::error::MACOS_CERTIFICATE_P12 decoded to an empty file."
		exit 1
	fi

	# -----------------------------------------------------------------------
	# Validate the certificate before it is imported anywhere.
	#
	# Checked here, deliberately, rather than after import: an expired or
	# wrong-type certificate should be reported as such, not as a confusing
	# codesign failure ten steps later.
	# -----------------------------------------------------------------------
	if ! P12PASS="$MACOS_CERTIFICATE_P12_PASSWORD" openssl pkcs12 \
			-in "$p12" -clcerts -nokeys -passin env:P12PASS -out "$pem" 2>"$workdir/openssl.err"; then
		echo "::error::could not read the .p12.  The usual cause is a wrong"
		echo "::error::MACOS_CERTIFICATE_P12_PASSWORD.  OpenSSL said:"
		# The error text is about the container, not its contents; it carries
		# no key material.
		sed 's/^/::error::  /' "$workdir/openssl.err" || true
		exit 1
	fi

	local subject issuer not_after
	subject=$(openssl x509 -in "$pem" -noout -subject | sed 's/^subject= *//')
	issuer=$(openssl x509 -in "$pem" -noout -issuer  | sed 's/^issuer= *//')
	not_after=$(openssl x509 -in "$pem" -noout -enddate | sed 's/^notAfter=//')

	echo "certificate subject : $subject"
	echo "certificate issuer  : $issuer"
	echo "certificate expires : $not_after"

	# A "Developer ID Application" common name is only ever issued by Apple's
	# Developer ID CA, so these two checks together establish the type.
	case "$subject" in
		*"Developer ID Application:"*) ;;
		*)
			echo "::error::this is not a Developer ID Application certificate."
			echo "::error::Its subject is: $subject"
			echo "::error::Direct distribution outside the Mac App Store requires a"
			echo "::error::'Developer ID Application' certificate.  A 'Mac Developer',"
			echo "::error::'Apple Development' or 'Mac App Distribution' certificate"
			echo "::error::cannot be notarized."
			exit 1
			;;
	esac
	case "$issuer" in
		*"Developer ID Certification Authority"*) ;;
		*)
			echo "::error::certificate was not issued by Apple's Developer ID Certification Authority."
			echo "::error::Its issuer is: $issuer"
			exit 1
			;;
	esac

	# Validity window.  -checkend takes seconds.
	if ! openssl x509 -in "$pem" -noout -checkend 0 >/dev/null; then
		echo "::error::the Developer ID certificate expired on $not_after."
		echo "::error::Renew it in the Apple Developer account and replace the"
		echo "::error::MACOS_CERTIFICATE_P12 secret.  See .github/macos/README.md."
		exit 1
	fi
	if ! openssl x509 -in "$pem" -noout -checkend 2592000 >/dev/null; then
		echo "::warning::the Developer ID certificate expires within 30 days ($not_after)."
		echo "::warning::Plan the renewal now; signing will start failing once it lapses."
	fi

	# -----------------------------------------------------------------------
	# Build the keychain.
	# -----------------------------------------------------------------------
	local kc_pass
	kc_pass=$(openssl rand -base64 24)
	# Belt and braces: this value is generated, never stored, and never
	# printed, but mask it anyway so an accidental echo cannot leak it.
	echo "::add-mask::$kc_pass"

	rm -f "$KEYCHAIN_PATH"
	security create-keychain -p "$kc_pass" "$KEYCHAIN_PATH"
	# Lock on sleep and after two hours.  A workflow job cannot outlive that.
	security set-keychain-settings -lut 7200 "$KEYCHAIN_PATH"
	security unlock-keychain -p "$kc_pass" "$KEYCHAIN_PATH"

	# Prepend to the user search list rather than replacing it, and remember
	# what was there so teardown can put it back.  Clobbering the search list
	# is how CI recipes break the login keychain of a non-ephemeral machine.
	security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//' > "$SEARCH_LIST_BACKUP"
	# shellcheck disable=SC2046  # word splitting is what rebuilds the list
	security list-keychains -d user -s "$KEYCHAIN_PATH" $(cat "$SEARCH_LIST_BACKUP")

	# -T limits which tools may use the key without an interactive prompt.
	# codesign is the only one that needs it.
	security import "$p12" \
		-k "$KEYCHAIN_PATH" \
		-P "$MACOS_CERTIFICATE_P12_PASSWORD" \
		-T /usr/bin/codesign \
		-f pkcs12

	# Without this, codesign blocks on a UI prompt that no runner can answer.
	# It prints the whole keychain on success, which is noise, not secrets;
	# discard it either way.
	security set-key-partition-list \
		-S apple-tool:,apple:,codesign: \
		-s -k "$kc_pass" "$KEYCHAIN_PATH" >/dev/null 2>&1

	# -----------------------------------------------------------------------
	# The identity must be exactly the one the maintainers declared.
	# -----------------------------------------------------------------------
	local identities
	identities=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH")
	echo "== codesigning identities in the temporary keychain =="
	echo "$identities"

	if ! printf '%s' "$identities" | grep -qF "$MACOS_SIGNING_IDENTITY"; then
		echo "::error::the imported certificate does not provide the expected identity."
		echo "::error::MACOS_SIGNING_IDENTITY is set to: $MACOS_SIGNING_IDENTITY"
		echo "::error::but the keychain offers the identities listed above."
		echo "::error::Fix the MACOS_SIGNING_IDENTITY variable, or the .p12 secret,"
		echo "::error::so that the two agree exactly."
		exit 1
	fi

	local valid_count
	valid_count=$(printf '%s' "$identities" | grep -c 'Developer ID Application:' || true)
	if [ "$valid_count" -ne 1 ]; then
		echo "::error::expected exactly one Developer ID Application identity, found $valid_count."
		echo "::error::Export a .p12 that contains only the identity used for signing."
		exit 1
	fi

	echo "temporary keychain ready at $KEYCHAIN_PATH"
}

teardown() {
	# Cleanup must never be the reason a run is marked failed, and must run
	# identically after success and after failure.
	if [ -f "$SEARCH_LIST_BACKUP" ]; then
		# shellcheck disable=SC2046
		security list-keychains -d user -s $(cat "$SEARCH_LIST_BACKUP") 2>/dev/null || true
		rm -f "$SEARCH_LIST_BACKUP"
	fi
	if [ -f "$KEYCHAIN_PATH" ]; then
		security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
		rm -f "$KEYCHAIN_PATH"
		echo "temporary keychain removed"
	else
		echo "no temporary keychain to remove"
	fi
	# Any credential material the other scripts may have left behind.
	rm -rf "${RUNNER_TEMP:-/tmp}"/simu-signing.* 2>/dev/null || true
	rm -rf "${RUNNER_TEMP:-/tmp}"/simu-notary.* 2>/dev/null || true
	return 0
}

case "${1:-}" in
	setup)    setup ;;
	teardown) teardown ;;
	*)
		echo "usage: keychain.sh setup|teardown" >&2
		exit 64
		;;
esac
