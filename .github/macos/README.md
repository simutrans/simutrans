# Signing and notarizing the macOS build

Apps distributed outside the Mac App Store are expected to be signed with a
**Developer ID Application** certificate and **notarized** by Apple.

What actually happens without that, stated no more strongly than it is: an
archive downloaded with a browser is marked as quarantined, and on first launch
macOS blocks it, saying it cannot verify the developer or that the app is free
of malware. The user is not stuck — Apple documents a per-app way through it,
in *System Settings → Privacy & Security → Open Anyway* — but they have to know
to do that, and they have to decide to trust software macOS has just told them
it could not check. Nothing here requires anyone to turn Gatekeeper off
globally, and Apple documents no such setting; do not describe it that way.

Signing and notarizing removes that step, and lets macOS tell the user the
opposite: that Apple checked the app for malicious software and found none.

This directory holds the pieces that produce a signed, notarized and stapled
`simutrans.app`. The workflow that drives them is
[`../workflows/macos-sign-notarize.yml`](../workflows/macos-sign-notarize.yml).

It **publishes nothing**. It ends with a verified archive and stops. Attaching
anything to a release remains the job of the existing nightly workflows and is
a separate decision.

---

## What a maintainer has to do once

Three things have to exist before the workflow can do anything: an Apple
Developer account with a Developer ID certificate, an App Store Connect API
key for the notary service, and the environment that holds them on GitHub.

### 1. Apple Developer Program

* A paid **Apple Developer Program** membership on the account that will own
  the signature. Developer ID certificates are not available on a free account.
* A **Developer ID Application** certificate. Create it in
  *Certificates, Identifiers & Profiles* (or from Xcode's *Accounts* pane) on a
  Mac, because the private key is generated on that Mac and never leaves it
  otherwise.
* Export the certificate **together with its private key** from *Keychain
  Access* as a `.p12`, protected with a strong password.

  A `.cer` downloaded from the developer portal is only the public half and
  cannot sign anything. If the private key is missing from Keychain Access, the
  certificate has to be reissued on the machine that will export it.

Only a **Developer ID Application** certificate is used. Simutrans ships a
`.app` inside a `.zip`, not an installer package, so no *Developer ID
Installer* certificate is needed and none should be created.

### 2. App Store Connect API key for notarization

The workflow authenticates to the notary service with an App Store Connect API
key, not with an Apple ID and app-specific password. The key is not tied to a
person's Apple ID, can be revoked on its own, and does not break when whoever
set it up enables or changes two-factor authentication.

In App Store Connect, *Users and Access → Integrations → App Store Connect API*:

* Use the **Team Keys** tab. Apple's current documentation on creating App
  Store Connect API keys lists two kinds, Team and Individual, and says of the
  latter that individual keys "aren't able to use Provisioning endpoints,
  access Sales and Finance, or `notaryTool`". An individual key will not work
  here whatever role it is given. (Checked against Apple's page on 2026-09-07
  rather than carried over from an older write-up; re-check it before assuming
  it still holds.)
* Give the key the **Developer** role. That is enough for notarization. Do not
  use Admin: an Admin key can create and delete users.
* Generating a team key requires an Admin account in App Store Connect.
* Download the `.p8` file. **Apple allows this exactly once and keeps no copy.**
  Note the **Key ID** and the **Issuer ID** shown on the same page.

### 3. The GitHub environment

Create an environment named **`macos-signing`** in
*Settings → Environments*, and set **Required reviewers** on it. A job that
references an environment must satisfy its protection rules before it can read
that environment's secrets, so this is what actually gates the use of the
signing identity behind a human approval.

> If the environment does not exist, GitHub creates it on first use **without
> any protection rule and without any secret**. The workflow then fails at its
> first step with a message naming what is missing. It will never fall back to
> an ad-hoc signature or hand back an unsigned package.

Add these to the **`macos-signing`** environment.

#### Secrets

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64 of the Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_P12_PASSWORD` | The password that `.p12` is encrypted with |
| `MACOS_NOTARY_API_KEY_P8` | Base64 of the App Store Connect API key `.p8` |
| `MACOS_NOTARY_API_KEY_ID` | The key ID, e.g. `T9GPZ92M7K` |
| `MACOS_NOTARY_API_ISSUER_ID` | The issuer UUID |

#### Variables

These are not secret. They are variables so that the workflow can check that
the certificate it was handed is the one the project expects.

| Variable | What it is |
| --- | --- |
| `MACOS_SIGNING_IDENTITY` | The exact identity string, e.g. `Developer ID Application: Example Org (AB12CD34EF)` |
| `MACOS_TEAM_ID` | The 10-character Team ID, e.g. `AB12CD34EF` |

#### Producing the base64 values

On a Mac, in a terminal, without writing the value to a file:

```sh
base64 -i DeveloperID.p12        | pbcopy   # -> MACOS_CERTIFICATE_P12
base64 -i AuthKey_T9GPZ92M7K.p8  | pbcopy   # -> MACOS_NOTARY_API_KEY_P8
```

Then paste straight into the GitHub secret field and clear the clipboard.

**Base64 is an encoding, not encryption.** Anyone who obtains the value has the
file. The `.p12` is additionally protected by its own password; the `.p8` is
not protected by anything, which is why it lives in a secret and is written to
disk only inside a run, with `umask 077`, and deleted afterwards.

Never commit a `.p12`, `.p8`, `.cer`, `.key` or any password to this
repository — including "just for a test". This repository is public, and a
Developer ID private key that lands in it has to be treated as compromised and
revoked.

---

## Before it can be run at all

GitHub only offers `workflow_dispatch` for a workflow that exists on the
repository's **default branch**: *"This event will only trigger a workflow run
if the workflow file exists on the default branch."* Once it has been there and
has run once, it can be dispatched against other branches and tags through the
API or the CLI — but not before.

So this workflow cannot be exercised from a pull request branch. It has to
reach `master` first. There is no way around that, and the ways people reach
for — pushing a temporary tag, pushing to master to "just try it" — are worse
than waiting. See [Rehearsing it](#rehearsing-it) for what can be done instead.

## Running it

*Actions → macOS signed build (Developer ID) → Run workflow.*

| Input | Meaning |
| --- | --- |
| `ref` | Commit to sign. Empty means the ref the run was started from. |
| `architecture` | `arm64`, `x86_64`, or `both`. |
| `upload_artifact` | Whether the signed archive is kept as a workflow artifact. Off by default. |
| `rehearsal` | Mark the result NOT-FOR-DISTRIBUTION. **On by default.** |
| `allow_unmerged` | Trust exception: permit a commit that is not on master history. Off by default. |

The run then waits for an environment reviewer to approve it before the signing
job starts.

### Which revisions are accepted

The ref is resolved to a full commit SHA, and that SHA has to be **on
`master`'s history**. That is the whole rule.

**A tag is not accepted as evidence of anything**, and this is not caution for
its own sake:

* `Nightly` is moved to whatever commit was pushed last. It has already pointed
  at a work branch.
* `124.0` and `124.1` are not on `master`'s history at all.
* Tags differ between clones unless they are force-fetched, so "it has a tag"
  is not even a stable statement.

A tag is therefore only ever a convenient way to *name* a commit here; the
commit still has to pass the same test as any other.

The environment should carry the same restriction from the other side. Set a
**deployment branch policy** on `macos-signing` so the identity can only be
reached from the refs you intend — `master`, plus a named rehearsal branch if
you are using one. The workflow's own check and the environment's check are
independent, and neither is a reason to skip the other.

### Rehearsing it

Two separate questions, and two separate inputs, on purpose.

**`rehearsal` — is what comes out meant for anyone?** On by default. When set,
the archive is named `…-REHEARSAL-NOT-FOR-DISTRIBUTION.zip` and the provenance
record says `not_for_distribution=true`. This is independent of which revision
was built: a rehearsal of `master` itself is the normal case, and should not
require choosing an odd commit to get the label.

**`allow_unmerged` — may this revision be signed at all?** Off by default. It
permits a commit that is not on `master`'s history, and it is deliberately
awkward: it has to be asked for by name, and `ref` must be the **full
40-character SHA**, because a branch or a tag can be moved between the approval
and the run. A revision admitted this way is always marked not for
distribution, whatever `rehearsal` is set to.

Folding these into one input would mean a rehearsal could only be had by
picking an off-master commit — the wrong reason to choose a revision — and
would let "it is only a rehearsal" turn into permission to sign code the
project has not accepted.

**The label is not a restriction.** A rehearsal is signed with the same real
Developer ID and notarized by Apple like anything else. `NOT-FOR-DISTRIBUTION`
in the file name is a note to humans; it constrains nothing cryptographically,
and the binary would pass Gatekeeper on any Mac it reached.

### About artifact visibility

This repository is **public**. A workflow artifact is downloadable by anyone
who can read the repository — it is not private storage. That is why
`upload_artifact` defaults to off: a rehearsal can prove the whole chain works
without leaving a signed binary behind. Turn it on only when the archive is
meant to be fetched, and remember that the retention period is the only thing
that removes it.

---

## What the workflow actually does

```text
resolve (ubuntu, no secrets)
   resolve the ref to a commit, refuse anything not on master or tagged
        |
build (macos-15 / macos-15-intel, no secrets)
   check out the revision to build, and the scripts, separately
   brew install deps, cmake build + install, inspect the bundle,
   archive it with ditto, record provenance
        |
sign (macos-15 / macos-15-intel, environment: macos-signing)
   check the configuration is complete
   check out the signing scripts, and nothing else
   verify the artifact came from this run, this commit, this architecture
   create a throw-away keychain, validate the certificate
   sign every Mach-O from the inside out, then the bundle
   verify signature, Hardened Runtime, timestamp, entitlements
   submit to the notary service, wait, staple the ticket
   rebuild the archive, extract it again and verify what a user would get
   destroy the keychain
```

The build job and the signing job are separate on purpose. The build installs
Homebrew packages and downloads language files over the network; the Developer
ID is not present in that environment. The signing job takes only **data** from
the build job, never code, and it never checks out the product's source at all —
it has no use for it.

Two different questions get two different answers about *which* commit is
involved. **What is built** is the revision the resolve job authorised. **What
does the building and signing** is this workflow and the scripts beside it,
taken from the ref the run was dispatched from — the same commit the workflow
file itself was read from, so it adds no trust surface. A revision on `master`
is a thing to sign, not a thing that gets to define how signing works.

The payload that moves between the two jobs is checked before the identity is
loaded. `check-payload.sh` runs first and rejects an archive that extracted to
symlinks pointing outside the tree, absolute symlinks, setuid or setgid files,
more than one bundle, a bundle in the wrong place, or anything sitting beside
it. "It is only data" is not a safety argument on its own: the signing steps
walk that tree, so the tree is checked before there is anything worth stealing
on the machine.

### Version identity

The resolve job records three separate things, and keeps them separate:

* the **commit SHA**, which identifies the tree exactly;
* the **Subversion base revision**, taken from the nearest ancestor that came
  from the mirror;
* how many commits sit **on top of** that base.

The base revision says which trunk revision the tree was taken from. It does
**not** say the tree is that revision — searching back for a `git-svn-id` finds
an ancestor, not an identity. So a build that is exactly r12263 is labelled
`r12263`, and one with two commits on top is labelled `r12263+2.g<sha>` rather
than being rounded to either number.

If no reachable commit carries a `git-svn-id` at all — a history that never
touched the mirror, or a shallow clone that does not reach one — the run fails.
It does not invent a number, and it does not fall back to a commit count plus
an offset. A package whose version cannot be stated truthfully is not signed.

### The scripts

| Script | Runs in | Does |
| --- | --- | --- |
| `inspect-bundle.sh` | build | Lists every Mach-O file, checks they are all the expected architecture, measures the effective minimum macOS across the whole bundle, and fails if any dependency or rpath still points at a Homebrew prefix or the runner's home directory |
| `check-payload.sh` | sign | Runs before the keychain exists: rejects escaping or absolute symlinks, setuid/setgid files, a second bundle, a misplaced bundle, or strays beside it |
| `keychain.sh` | sign | Creates and destroys the temporary keychain; validates the certificate's type, issuer, expiry and identity before importing it |
| `sign.sh` | sign | Signs nested code first and the bundle last, then verifies the result before anything is sent to Apple |
| `notarize.sh` | sign | Submits to the notary service, distinguishes a rejection from a transport failure, staples the ticket |
| `verify.sh` | sign | Extracts the finished archive and checks signature, ticket, Gatekeeper verdict, archive fidelity and architecture |

### Decisions worth knowing about

**No `codesign --deep` for signing.** `--deep` applies one set of flags to
whatever it happens to find and skips what it does not recognise. Every Mach-O
file is signed by name instead, deepest first. `--deep` *is* used for
verification, which is what Apple recommends.

**No entitlements.** Simutrans requests no restricted capability: the sources
contain no `dlopen`/`dlsym`, no JIT or writable-executable mapping, and no
audio input, camera or location use. Every library it loads ships inside the
bundle and is signed here with the same Team ID, so the Hardened Runtime's
library validation is satisfied without disabling it. An empty entitlement set
is the minimum that works, and adding entitlements "just in case" would weaken
the runtime for no gain.

**`ditto`, not `zip`.** The bundle contains symlinked libraries and files whose
permissions matter. `zip -r` flattens symlinks into duplicate copies — the
archives currently published contain zero symlinks for exactly that reason —
and GitHub artifacts do not preserve permissions either, which is why what
moves between jobs is a single `ditto` archive rather than a directory tree.

**The ticket goes on the `.app`, not on the zip.** Apple does not staple zip
archives. The archive is submitted, the ticket is stapled to the application,
and the distribution archive is then built again from the stapled bundle and
verified after a full extract.

**Two single-architecture builds, not a universal binary.** `arm64` and
`x86_64` are built and signed separately, matching the two archives the project
already ships. Merging them with `lipo` would mean reconciling two different
sets of Homebrew libraries, and a universal binary that has not been verified
slice by slice should not be called universal.

**Runner labels are pinned, and the deployment target is chosen.** `macos-15`
and `macos-15-intel` rather than `macos-latest`, and
`CMAKE_OSX_DEPLOYMENT_TARGET=13.0` rather than whatever the SDK defaults to.
Leaving it unset is how the two published nightlies ended up with minimums of
14.0 and 26.0 without anyone deciding either. Both labels are *standard*
runners, free and unlimited on public repositories — no larger-runner label
appears anywhere here, so this cannot incur a charge. GitHub still updates the
contents of a pinned image, so the exact toolchain is recorded in every run.

**The minimum macOS is measured, not declared.** Setting a deployment target on
our own code does not lower the floor for the bundle: the Homebrew libraries
inside it were built for the runner's macOS and carry their own minimums. So
`inspect-bundle.sh` reads the minimum of *every* Mach-O file and reports the
**maximum** as the effective minimum, printing the main executable's own value
beside it so the two cannot be confused. Do not quote the executable's
deployment target as the system requirement.

Read that number for what it is. It is the highest minimum **declared by the
Mach-O files in that one build**, not a test result: nothing here has been run
on that version of macOS, and building on macOS 15.7.9 does not demonstrate
that the result works on 15.0. It also changes when the dependencies change —
a Homebrew update to any bundled library can move it — so it has to be read
from the build being shipped, never carried over from a previous one.

**A package labelled for one architecture must contain that architecture.**
The inspection fails outright when a package named for `x86_64` contains no
`x86_64` binary at all — which is the shape of the `simumac-intel-nightly.zip`
that was downloaded and examined here. That statement is about the specific
archives inspected, identified by their sha256 in the pull request; it is not a
claim about every archive the project has ever published. The name of a file is
not evidence about its contents, and neither is the name of a workflow.

---

## Reproducibility, and what cannot be pinned

The build downloads two kinds of input that are outside this repository:

**Homebrew packages.** Whatever versions the runner's Homebrew resolves at the
time. The exact versions installed are recorded in the build manifest.

**The language pack.** `tools/get_lang_files.sh` POSTs to the translator to
*regenerate* an export and then downloads it, so the content is whatever the
server produces at that moment. There is no version, tag or revision to pin.
This is not theoretical: between the two nightlies of 2026-09-07, `dk.tab` went
from 2613 to 599 entries and `gr.tab` from 2679 to 679, while `de.tab` and
`en.tab` changed by two lines. Both shrunken files are well-formed and end
cleanly, so this is a content change upstream, not a truncated download — but
it means **the same commit does not produce the same package twice**.

What is done about it:

* the manifest records the sha256 of every `.tab` that went into the build,
  along with the Homebrew versions and the toolchain;
* the archive the build uploads *is* the preserved copy, and the signing job
  consumes exactly that — it never re-downloads anything and never rebuilds.

A hash records which bytes were used. It does not let anyone fetch those bytes
again. If a specific build has to be reproducible later, the archive is the
only thing that makes it so, and it has to be kept.

## Surviving a verdict that arrives too late

Apple does not always answer while the run is still there. On 2026-09-08 a
bundle was signed and submitted, the run ended with the submission still being
processed, and the signed bytes went with the runner — so an acceptance
arriving later had nothing left to staple.

Two things fix that, and they are separate.

**The archive is preserved before it is submitted.** Not after: a run that dies
between the submit and the upload would leave the same gap. The submission id
only exists afterwards, so it is bound to the archive in a second, tiny record
(`bind-submission.sh`) that points back at the same bytes by hash. If a
submission was made but no id came back, nothing is bound and the archive is
marked unreconciled — it cannot be resumed, and it must not be resubmitted on
the assumption the first attempt failed.

**A separate workflow finishes the job.** `macOS finish notarization (resume)`
recovers the archive, asks Apple about the submission it is bound to,
and only staples if the answer is `Accepted`. It does not build, does not
sign, never loads the `.p12` and has no submit path.

### Why it is encrypted

The archive is kept as a workflow artifact, and **a workflow artifact in a
public repository is not private**: GitHub's documentation requires "read
access to the repository" to download one, and on a public repository everyone
has that. So what is stored is ciphertext: an OpenPGP message, AES-256 in
**OCB** — an AEAD mode from RFC 7253 — produced by GnuPG, which is already on
the runner.

That mode is asked for explicitly, because GnuPG's default for symmetric
encryption is not AEAD. Being accurate about what the default *is*: it is not
an unprotected message either. OpenPGP's classic mode carries a Modification
Detection Code and GnuPG refuses to return plaintext when it fails. The MDC is
simply the weaker of the two — a SHA-1 construction bolted onto CFB rather
than a modern authenticated mode. AEAD is chosen because it is better, not
because the alternative is naked.

Every container is inspected after it is made and rejected if it is not
AES-256 OCB, since a default can move in either direction.

`.github/macos/artifact-lib.sh` carries the full specification, including two
things that are easy to misread: the `cb=` value in a packet dump is the
chunk-size octet (2^(cb+6) octets), **not** the tag length; and the S2K count
is a number of octets fed to the hash, **not** a number of iterations.

Encryption does not settle who may read it, how long it lives, or how it is
checked. Those are separate, and they are:

* **access** — whoever holds `MACOS_ARTIFACT_KEY`, an environment secret behind
  the same reviewer gate as the signing identity;
* **retention** — 7 days, set by `retention-days` on the upload;
* **integrity** — the sha256 of the plaintext is in the manifest and is
  re-checked on every restore, along with the product commit, the submission id
  and the signing identity, against values the resuming run already knows.

`MACOS_ARTIFACT_KEY` is optional. Without it, signing still works and the
workflow says plainly that a late verdict will not be usable.

### What is never in the artifact

No `.p12`, no `.p8`, no password, no keychain. The manifest is descriptive
only, and `preserve-artifact.sh` refuses to write one that looks like it
contains credential material.

**Apple accepting a submission is not on its own permission to finish.** The
recovered archive still has to prove it is the archive that was submitted.
Both questions are asked, separately, and either one failing stops the run.

## What has been validated, and what has not

Being a draft and being unvalidated are different things; so are these five
levels, and they should not be quoted as one another:

| | Status |
| --- | --- |
| Static validation (`actionlint`, `shellcheck`) | done, clean |
| Control-flow tests against mocked macOS tools | done, 52 cases |
| The scripts executed for real on macOS | **not done** |
| The whole workflow executed in GitHub Actions | **not done** — it cannot be, until it is on the default branch |
| A real signature and a real notarization | **not done** |

The mocked tests prove failure behaviour and control flow: that a rejection is
never retried, that a missing secret stops the run, that cleanup happens on the
failure paths. They prove nothing about whether `codesign` or the notary
service will accept this bundle. Holding a certificate, or having a Mac
available, is not validation either.

## Diagnosing failures

| Symptom | Cause |
| --- | --- |
| `required secret 'X' is empty or not set` | The `macos-signing` environment is missing that secret, or the run was started against an environment that GitHub auto-created empty. |
| `this is not a Developer ID Application certificate` | The `.p12` holds an *Apple Development*, *Mac Developer* or *Mac App Distribution* certificate. Those cannot be notarized. |
| `could not read the .p12` | Wrong `MACOS_CERTIFICATE_P12_PASSWORD`, or the base64 was truncated on paste. |
| `the imported certificate does not provide the expected identity` | `MACOS_SIGNING_IDENTITY` does not match the certificate. Copy the string from `security find-identity -v -p codesigning` exactly, including the team ID in brackets. |
| `the signature carries no secure timestamp` | `timestamp.apple.com` was unreachable during signing. Re-run; it is transient. |
| `the notary service rejected this artifact` | A real verdict about the artifact. The redacted notary log is printed directly above; fix the cause and start a new run. The workflow does **not** resubmit a rejected artifact. |
| `no verdict from the notary service after 3 attempts` | Apple's service did not answer. Nothing is known about the artifact and it is **not** notarized. |
| `Gatekeeper does not see this as a notarized Developer ID application` | Signing and notarization succeeded but the ticket did not survive; check the stapling step. |
| `build-machine path leaked into ...` | `fixup_bundle` did not rewrite a dependency. The bundle would fail on a user's Mac; it is not a signing problem. |

The notary log is printed **redacted**: runner paths, the key ID and the issuer
ID are replaced. It is never uploaded as an artifact.

## Renewing the certificate

Developer ID certificates last five years. `keychain.sh` warns when fewer than
30 days remain and fails once it has expired.

To renew: create a new Developer ID Application certificate, export a new
`.p12`, and replace `MACOS_CERTIFICATE_P12` and
`MACOS_CERTIFICATE_P12_PASSWORD`. Update `MACOS_SIGNING_IDENTITY` if the
common name changed.

Already-notarized builds keep working: the notarization ticket and the secure
timestamp on the signature mean a shipped app does not stop launching when the
certificate behind it expires.

## Turning the flow off

Deleting or disabling the workflow — *Actions → macOS signed build (Developer
ID) → ⋯ → Disable workflow* — stops signing entirely. Nothing else changes:
the nightly build workflows are untouched by it and keep producing the same
archives as before, and no certificate needs to be revoked.

Revoking the certificate is a different and much heavier action: it invalidates
signatures that are not covered by a secure timestamp. Do it only if the
private key is believed to be compromised, and then also delete
`MACOS_CERTIFICATE_P12` and revoke the App Store Connect key.

## Secret hygiene, and one honest limitation

Secrets are written to disk only inside a job, under `umask 077`, in a
`mktemp -d` directory that is removed on success and on failure, and the
temporary keychain is deleted by an `always()` step. No secret is echoed, no
shell tracing is enabled, and nothing secret is placed in a cache, an output,
a step summary or an artifact.

One thing cannot be hidden: `security import` takes the `.p12` password as a
command-line argument, because it offers no way to read it from a file or the
environment. On a multi-user machine that argument would be visible in the
process list. GitHub-hosted runners are single-tenant and destroyed after the
job, so the exposure is limited to a machine that already has the decrypted
`.p12` in memory — but it is a real property of the tool and is stated here
rather than glossed over. It is another reason not to point this workflow at a
persistent self-hosted runner.

## One warning before you push a branch here

Every other workflow in this repository is `on: [push]` with no branch filter.
Pushing *any* branch therefore runs the whole nightly chain: it moves the
`Nightly` tag to the pushed commit, rebuilds and overwrites the release
assets, and publishes an Android build to the Play Store beta track.

This workflow is not part of that — it only ever runs from
`workflow_dispatch` — but the branch you push it on will still set the rest
off. Expect it, or cancel the runs. A manual workflow existing alongside
automatic publishers does not make a push safe.

A commit that did not come from the SVN mirror also loses its revision number.
Both `tools/get_revision.sh` and `cmake/SimutransRevision.cmake` read only
`git log -1`, so neither finds a `git-svn-id` on such a commit and both fall
back. Measured on 2026-09-07, from one push of a work branch:

* the binary's banner read `Simutrans 124.5.1 Nightly - r1`, because the cmake
  fallback counts commits in what `actions/checkout` clones — one, since it
  clones shallow — and because its `+328` correction is added to `res_var`,
  the exit status of the preceding command, instead of to the revision;
* the release title read `Nightly build r12261`, because the release workflow
  clones with full depth and got the commit count plus 328 instead;
* the real content was r12263 plus one commit;
* and Google Play rejected the upload with `Version code 12261 has already
  been used`, because that number belongs to an earlier, genuine revision.

All of it predates this work and none of it is fixed here. It matters for two
reasons: it is why these files should reach `master` through SVN rather than a
merge, and it is why this workflow refuses to sign a revision whose Subversion
base it cannot establish.

## Relationship with SVN

Simutrans develops in Subversion; this GitHub repository is a one-way mirror of
`trunk`, and `.github/` is versioned in SVN like any other directory. A change
merged here alone would be overwritten by the next mirror update, so these
files have to be committed to SVN trunk to survive. See the pull request that
introduced them for the details.
