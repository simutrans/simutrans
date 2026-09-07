# Signing and notarizing the macOS build

Apps distributed outside the Mac App Store have to be signed with a **Developer
ID Application** certificate and **notarized** by Apple. Without that, macOS
puts a downloaded copy in quarantine and refuses to open it, and the user is
told the app "is damaged and can't be opened" — which is what the current
unsigned nightly archives do on a modern macOS.

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

* Use the **Team Keys** tab. Apple states that individual keys "aren't able to
  use Provisioning endpoints, access Sales and Finance, or `notaryTool`", so an
  individual key will not work here whatever role it is given.
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

## Running it

*Actions → macOS signed build (Developer ID) → Run workflow.*

| Input | Meaning |
| --- | --- |
| `ref` | Commit SHA or tag to sign. Empty means the branch the run was started from. |
| `architecture` | `arm64`, `x86_64`, or `both`. |
| `upload_artifact` | Whether the signed archive is kept as a workflow artifact. Off by default. |

The run then waits for an environment reviewer to approve it before the signing
job starts.

The revision is resolved to a full commit SHA and is only accepted if it is an
ancestor of `master` or carries a tag in this repository. An arbitrary branch,
or a pull request from a fork, is refused. This is deliberate: it is the
mechanism that stops the signing identity from ever being applied to code the
project has not accepted.

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

That separation is also what makes it possible to rehearse the whole flow
against a real `master` revision *before* these files are on `master`: dispatch
the workflow from the branch that carries it, and point `ref` at the commit to
build.

### The scripts

| Script | Runs in | Does |
| --- | --- | --- |
| `inspect-bundle.sh` | build | Lists every Mach-O file, checks they are all the expected architecture, and fails if any dependency or rpath still points at a Homebrew prefix or the runner's home directory |
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

**Runner labels are pinned.** `macos-15` and `macos-15-intel` rather than
`macos-latest`. The project sets no `CMAKE_OSX_DEPLOYMENT_TARGET`, so the
minimum macOS version of the product is whatever the runner's SDK defaults to;
following `macos-latest` moves that floor without anyone deciding to. Both are
*standard* runners, which are free and unlimited on public repositories — no
larger runner label appears anywhere in this workflow, so it cannot incur a
charge. GitHub still updates the contents of a pinned image, so the exact
toolchain is recorded in every run's log rather than assumed.

---

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

## Relationship with SVN

Simutrans develops in Subversion; this GitHub repository is a one-way mirror of
`trunk`, and `.github/` is versioned in SVN like any other directory. A change
merged here alone would be overwritten by the next mirror update, so these
files have to be committed to SVN trunk to survive. See the pull request that
introduced them for the details.
