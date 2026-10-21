# reviewwatcher

Watches GitLab for merge requests where you are a reviewer and raises a macOS
notification. Clicking the notification opens the merge request in your browser.
A menu bar icon lists every open review request, with its diff size, and lets you
approve or merge the small ones without leaving the desk.

Polls through `glab`, so it inherits whatever instance and credentials glab uses.

## Install

Needs an Apple Silicon Mac on macOS 13 or later, the Command Line Tools
(`xcode-select --install`), and `glab` and `librsvg` from Homebrew. librsvg
renders the icons at build time.

```sh
brew install glab librsvg
glab auth login
./install.sh
```

`install.sh` builds the app on your machine and writes a config for the GitLab
user `glab` is logged in as. It then asks for a personal access token with `api`
scope, which Approve and Merge need to write, and loads a LaunchAgent so the
watcher starts at login. For a self-managed GitLab, run
`GITLAB_HOST=gitlab.example.com ./install.sh`.

Everyone builds their own copy. The app is signed ad hoc, so Gatekeeper blocks a
copy built on another machine.

## What it notifies

macOS cannot tint a notification banner, so pipeline state shows up as a coloured
badge attachment plus an emoji in the title.

| When | Looks like |
| --- | --- |
| Asked to review, pipeline green | 🟢 Review requested |
| Asked to review, pipeline red | 🔴 Review requested |
| Asked to review, pipeline still running or absent | 🟡 Review requested |
| A merge request you were shown red turns green | 🟢 Pipeline fixed |
| New commits removed your approval | 🟡 Your approval was removed |

A pipeline breaking raises nothing: the only follow-up is the one that tells you
a blocked review is now worth opening.

Notifications can also wait for the merge request to be worth opening: a passed
(or at least not failed) pipeline, no conflicts, not a draft. A review request
or removed approval that misses a condition is held and announced as soon as it
meets them, unless you approve in the meantime. A merge request without a pipeline passes the
pipeline condition. These conditions apply to every notification.

Each poll is a single GraphQL query that returns the review requests together
with their pipeline, diff size, approvals and merge status.

## Menu bar

The icon carries the number of review requests still waiting on your approval.
Clicking it refreshes and opens the list:

| Shows | Meaning |
| --- | --- |
| Coloured dot | Pipeline passed, failed or still running; grey when there is none. |
| `+12 −3 · 2 files` | Diff size, as GitLab counts it. |
| Grey chip | What stands between the merge request and a merge: `Needs approval`, `Waiting on pipeline`, `Conflicts`, … |
| 🔍 | Opens the diff in a window. Disabled past 2000 changed lines. |
| 🧭 | Opens the merge request in the browser. |
| **Approve** | Approves. Shown while you have not approved yet. |
| **Unapprove** | Revokes your approval. Shown once you have approved. |
| **Merge** | Merges, or turns on auto-merge when a check is still pending. Asks for a second click within four seconds. |

**Merge** shows only when nothing but approvals or a running check blocks the
merge request: drafts, conflicts, unresolved threads and a failed pipeline the
project requires to pass go through GitLab. It uses the merge request's own
squash and branch-deletion settings.

Approve and Merge pin the commit the list was loaded at. If the author pushes after
that, GitLab rejects the action and the row shows the error; the next refresh
shows the new state.

## Diff window

Each file is a card whose header stays pinned while you scroll through it.
Clicking the header collapses or expands the file; **Expand all** and
**Collapse all** act on every file at once.

Files open collapsed when GitLab marks them generated (lock files, `go.sum`) or
when their path matches one of `collapsedFilePatterns`. The header shows the
pattern that matched. Patterns are globs over the whole path, matched without
regard to case, and `*` also crosses `/`:

| Pattern | Collapses |
| --- | --- |
| `*test*` | `foo_test.go`, `testdata/x.json`, `src/__tests__/a.ts` — and also `latest.go` |
| `*spec/*` | `spec/models/user_spec.rb`, `engines/billing/spec/x.rb` |
| `*_test.go` | Go tests only |

Between hunks, a blue row stands for the unchanged lines GitLab left out.
↑ shows 20 more above the next change, ↓ 20 more below the previous one, and
**Show N hidden lines** reveals the whole stretch. The first click fetches the file
at the commit the diff was taken from.

The window takes ⌘W to close and ⌘C to copy a selected line.

## Configuration

The gear in the popover opens the settings: polling interval, which events
notify, the conditions above, and the diff window's collapse patterns. Changes
apply at once and are saved to `~/.config/reviewwatcher/config.json`:

| Key | Default | Meaning |
| --- | --- | --- |
| `host` | `gitlab.com` | GitLab instance, passed to glab as `GITLAB_HOST`. |
| `username` | from `glab api user` | Whose review requests to watch. |
| `pollIntervalSeconds` | `60` | Clamped to a 30s minimum. |
| `notifyOnNewReviewRequest` | `true` | Ping when a merge request first lists you as reviewer. |
| `notifyOnApprovalRemoved` | `true` | Ping when new commits take away your approval, as GitLab does when the project resets approvals on push. Revoking it yourself stays quiet. |
| `notifyOnPipelineFixed` | `true` | Ping when a review you were shown red turns green. |
| `notifyOnActivity` | `false` | Also ping when one you already review gets new commits or comments. |
| `notifyBacklogOnFirstRun` | `false` | Announce the merge requests already waiting when the watcher first starts. |
| `notifyOnlyWhen.pipeline` | `"any"` | `"any"`, `"notFailed"` or `"passed"`. |
| `notifyOnlyWhen.noConflicts` | `false` | Hold merge requests with conflicts. |
| `notifyOnlyWhen.notDraft` | `false` | Hold drafts. |
| `collapsedFilePatterns` | `["*test*", "*spec/*"]` | Files the diff window opens collapsed; see [Diff window](#diff-window). |

`host` and `username` are set by `install.sh` and shown read-only in the settings.
The settings window rewrites the file, so edit it by hand only to change those two,
then restart:

```sh
launchctl kickstart -k "gui/$UID/app.reviewwatcher"
```

The token lives beside it in `~/.config/reviewwatcher/token` (mode 600), read
separately so the config stays safe to share. Rotating the token means rewriting
that file.

## Operating

- Log: `~/Library/Logs/reviewwatcher.log` — approvals and merges made from the
  menu bar are logged there too.
- Seen state: `~/.local/state/reviewwatcher/seen.json` — delete it to re-announce
  everything currently open.

Merged and closed merge requests drop out of the state file on the next poll, so
reopening one announces it again.

## Notification permission

The app is ad-hoc signed, so macOS grants notifications to one exact binary. A
rebuild produces a new signature and the grant silently lapses — the log then
reads `notification authorization failed`, and macOS will not re-prompt for a
bundle identifier it has already seen.

After any rebuild, re-enable ReviewWatcher under System Settings > Notifications.
If it is missing from that list, change `BUNDLE_ID` in `build.sh` to get a fresh
prompt.

`install.sh` builds only when `build/ReviewWatcher.app` is absent, so a routine
reinstall keeps the approved binary. Rebuild deliberately with `./build.sh`.

## Sleep and battery

The agent polls only while the machine is awake and the screen is on. It suspends
on system sleep and on display sleep, and polls once immediately on wake, so
coming back to the desk shows the current queue without waiting out an interval.

It holds no power assertion, so it never wakes the machine and never keeps it
awake. A merge request assigned while the lid is shut surfaces on the next wake,
not before.

## Uninstall

```sh
./uninstall.sh
```
