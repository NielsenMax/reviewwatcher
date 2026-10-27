# reviewwatcher

Watches GitLab for merge requests where you are a reviewer and raises a macOS
notification. Clicking the notification opens the merge request in your browser.
A menu bar icon lists every open review request, with its diff size, and lets you
approve or merge the small ones without leaving the desk.

Polls through `glab`, so it inherits whatever instance and credentials glab uses.

An **Epic** tab in the same popover follows Jira epics through `acli`: each
one's children and their subtasks, with a notification whenever one is added,
changes status, is reassigned or gets a comment.

An **Argo** tab lists the Argo CD applications through the `argocd` CLI and
syncs them from the menu bar.

The **Ruleta** button beside the tabs opens the ticket roulette: a casino wheel
that deals the tickets of a Jira search out to the developers in a GitLab group's
teams, assigning each in Jira as the ball lands.

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
scope, which Approve and Merge need to write; leave it empty to use glab's own
login when that already carries `api`. Last it loads a LaunchAgent so the
watcher starts at login.

For the Epic tab, log in to Jira through acli before installing. `install.sh`
reads the site and your email from that login, and `EPIC` follows a first epic:

```sh
brew install atlassian/acli/acli
acli jira auth login
EPIC=PROJ-123 ./install.sh
```

For a self-managed GitLab, run
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
| The watcher approved one for you | 🟢 Auto-approved release / version bump |

A pipeline breaking raises nothing: the only follow-up is the one that tells you
a blocked review is now worth opening.

Notifications can also wait for the merge request to be worth opening: a passed
(or at least not failed) pipeline, no conflicts, not a draft. A review request
or removed approval that misses a condition is held and announced as soon as it
meets them, unless you approve in the meantime. A merge request without a pipeline passes the
pipeline condition. These conditions apply to every notification except an
auto-approval, which always notifies.

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
| **Approve & merge** | Takes the place of **Merge** while your approval is missing: approves, then merges. GitLab's auto-merge waits on approvals too, so a plain merge would sit until you approved. |

**Merge** shows only when nothing but approvals or a running check blocks the
merge request: drafts, conflicts, unresolved threads and a failed pipeline the
project requires to pass go through GitLab. It uses the merge request's own
squash and branch-deletion settings.

A merge that lands at once is celebrated on the screen in use, popover open or
not: the room dims to felt green, a gilded bull charges across with a bellow,
and where it passes the middle a shockwave throws casino chips and gold leaf
under the merge request's name. It lasts under four seconds and every click
goes through to the windows beneath. In the popover the row turns green and
slides out once GitLab drops it. With Reduce motion on nothing moves: the name
fades in and out, and the bellow still sounds.

Approve and Merge pin the commit the list was loaded at. If the author pushes after
that, GitLab rejects the action and the row shows the error; the next refresh
shows the new state.

## Auto-approval

Two kinds of merge request can be approved without opening them, each behind its
own setting, both off by default:

- **Releases**: from `develop` into `main` or `master`, within the same project.
- **Version bumps**: every changed file is an existing YAML file, and every
  changed line is a kustomize `newTag:` or a container `image:` that keeps its
  key, indentation and image, moving the tag to a version such as `1.2.3`,
  `v1.2.3` or `1.2.3-rc.1`. A tag like `"1801"`, a digest, a new or renamed
  image, a reformatted file or any other line in the diff leaves the merge
  request to you.

Drafts are never auto-approved. The approval pins the commit that was checked,
so a push that lands meanwhile is rejected by GitLab and checked again on the
next poll. Each head is judged once: if you revoke an auto-approval, it stays
revoked until new commits arrive.

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

## Epic tab

The search box at the top finds open epics whose title holds every word typed,
or any ticket by its key; clicking a result follows it. Each followed epic gets
a section whose title opens it in Jira, with a count of what is done and an ×
that stops following it. Following an epic again later starts afresh.

A section lists the epic's children, each followed by its subtasks: work in
progress first, then what waits, then what is done. Finished tickets are hidden
until the ✓ in the header shows them; a finished child stays while a subtask of
it is open.

Each row offers:

| Control | Does |
| --- | --- |
| 🧭 | Opens the ticket in Jira. |
| **Move** | Transitions the ticket to the chosen status. |
| **Assign to me** / **Unassign** | Takes the ticket, or lets it go once it is yours. |

acli cannot list a ticket's transitions, so **Move** offers every status the
project used in its 200 most recently updated tickets. Jira refuses one the
workflow does not allow from where the ticket stands, and the row shows why.

A ticket raises one notification per poll, listing everything that changed:

| When | Looks like |
| --- | --- |
| A ticket is filed under the epic or one of its children | ⚪ New in PROJ-123 |
| It changes status | 🔵 To Do → In Progress |
| It is assigned or unassigned | ⚪ Assigned to you |
| Someone else comments | 🔵 Ana commented — the comment is the body |

The dot follows the ticket's status category: ⚪ to do, 🔵 in progress, 🟢 done.
Moves and assignments made from the menu bar stay quiet. Ones you make in Jira
itself notify like anyone else's, since acli does not say who made a change.

Every epic is read on its own and all of them at once, so one that fails, say
deleted or out of your reach, shows its error in its section and leaves the
others alone. Each read runs two searches for the tree and one more for tickets
updated since that epic's last poll; only those, and tickets seen for the first
time, are opened one by one to read their comments. A newly followed epic starts
silently: its first poll only takes note of what is there.

## Argo tab

The tab reads the applications the current `argocd` context can see, each with
its sync status, health, auto-sync and, when the last sync failed while the app
is still out of sync, that sync's error. It shows the out-of-sync ones by
default, out of sync first under **All**, and the field above narrows them to
apps whose name, project or destination namespace holds every word typed.

**Sync** asks for a second click within four seconds, then runs
`argocd app sync <app> --async` with the app's own sync options and no prune.
The row follows that operation every three seconds until Argo reports it
finished, and shows the outcome or the error. 🧭 opens the app in Argo CD.

Log in once with `argocd login <server> --sso --grpc-web`. Argo rotates the SSO
refresh token each time it is used, so the tab runs one argocd command at a time
and only while it is open or a sync it started is running; when the login
lapses, the tab says so and a new `argocd login` brings it back.

## Ticket roulette

A native port of the Node roulette, in its own window. Every opening reloads the
table unless a spin is on it.

**Players** come from the subgroups of the GitLab group in `roulette.teamsGroup`,
each with the teams they belong to; owners of the group are left out. Each one is
found in Jira through the issues assigned to `firstlast@domain`, built from the
GitLab name and the domain of `jira.email`, since acli has no user search; someone
never assigned anything has no Jira user and cannot play. The **Jugadores** tab's switch takes a person
off the table for leave or on-call.

**The pool** is whatever the JQL in the **Pozo** tab returns, up to 100 tickets;
**Buscar** runs a new one and keeps it only if Jira accepts it. The list groups by
epic or by tag, and **Sortear** on a group makes every spin take the next ticket
from it until it runs dry.

**A spin** picks a pocket at random. In **Pareja** every seated player has the
same pocket; **Compensada** shrinks it for whoever holds more of the open tickets
`roulette.loadJQL` finds. Team chips narrow the table to one team. The ticket shown
**En juego** is assigned in Jira to the winner the moment the ball is thrown, and
the result says whether Jira took it; with an empty pool the wheel just draws a
name. Space spins too.

**The result** offers the wheel and the winner as a 1200×630 PNG for the chat,
the ticket as text, and **Deshacer**, which unassigns it in Jira and returns it
to the pool. **Planilla** lists every assignment the wheel made, by day, with the
same undo and a copy of today's.

The table lives in `~/.local/state/reviewwatcher/ruleta.json`, in the same shape
as the Node version's `estado.json`: copy that file there to keep its history,
absentees and Jira mapping.

## Configuration

The gear in the popover opens the settings: polling interval, which events
notify, the conditions above, auto-approval, and the diff window's collapse
patterns. Changes apply at once and are saved to
`~/.config/reviewwatcher/config.json`:

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
| `autoApproveReleases` | `false` | Approve releases from `develop`; see [Auto-approval](#auto-approval). |
| `autoApproveVersionBumps` | `false` | Approve merge requests that only bump image tags. |
| `collapsedFilePatterns` | `["*test*", "*spec/*"]` | Files the diff window opens collapsed; see [Diff window](#diff-window). |
| `jira.site` | from `acli jira auth status` | Jira Cloud site the ticket links point at. |
| `jira.email` | from `acli jira auth status` | Who "you" is, for assignments and your own comments. |
| `jira.epics` | `[EPIC]`, or empty | Tickets whose branches the Epic tab follows, in the order shown; managed from the tab. |
| `jira.notifyOnNewTicket` | `true` | Ping when a ticket is filed under the epic. |
| `jira.notifyOnStatusChange` | `true` | Ping when a ticket changes status. |
| `jira.notifyOnAssigneeChange` | `true` | Ping when a ticket is assigned or unassigned. |
| `jira.notifyOnComment` | `true` | Ping when someone else comments. |
| `jira.showDoneTickets` | `false` | List finished tickets too; the ✓ in the Epic tab toggles it. |
| `roulette.teamsGroup` | empty | GitLab group whose subgroups are the roulette's teams, such as `acme/teams`. |
| `roulette.loadJQL` | empty | Open tickets counted per player for **Compensada**, such as `project = PROJ AND statusCategory != Done AND assignee IS NOT EMPTY`; empty keeps the odds even. |

`host`, `username`, `jira.site` and `jira.email` are set by `install.sh` and shown
read-only in the settings; `roulette.teamsGroup` and `roulette.loadJQL` are yours to
fill in. The settings window rewrites the file, so edit it by hand only to change
those, then restart:

```sh
launchctl kickstart -k "gui/$UID/app.reviewwatcher"
```

The token lives beside it in `~/.config/reviewwatcher/token` (mode 600), read
separately so the config stays safe to share. Rotating the token means rewriting
that file.

## Operating

- Log: `~/Library/Logs/reviewwatcher.log` — approvals and merges made from the
  menu bar are logged there too, as is the full output of an update that failed
  to build.
- Roulette: `~/.local/state/reviewwatcher/ruleta.json` — pool JQL, absentees,
  Jira users and the log of assignments.
- Epic state: `~/.local/state/reviewwatcher/epic.json` — the last status,
  assignee and comment seen on each ticket, per followed epic.
- Seen state: `~/.local/state/reviewwatcher/seen.json` — delete it to re-announce
  everything currently open.

Merged and closed merge requests drop out of the state file on the next poll, so
reopening one announces it again.

## Updates

The app checks this repository's tags on GitHub at launch and every hour. When
a `vX.Y.Z` tag is newer than the running build, it notifies once (clicking the
notification opens what changed on GitHub) and shows **Update** above the
popover's tabs. Nothing installs until you click it.

Updating downloads the source of the commit the tag pointed to when it was
checked, builds it with that release's `build.sh` in
`~/Library/Caches/reviewwatcher/update`, replaces the installed app and restarts
the LaunchAgent. It needs the same Command Line Tools and librsvg as the first
install. The config, the token, the state files and the LaunchAgent stay as they
are; a release that changes `install.sh` says so in its notes, and needs
`./install.sh` run by hand. Rebuilding can also cost the notification grant; see
[Notification permission](#notification-permission).

The settings show the running version: a release such as `1.2.3`, or
`git describe` output such as `1.2.3-4-gabc1234-dirty` for a local build, which
is offered only releases newer than `1.2.3`. **Check now** checks without waiting
for the hour.

To publish a release, tag a commit on `main` and push the tag:

```sh
git tag v1.2.3
git push origin v1.2.3
```

A `v*` tag cannot be moved or deleted once pushed, so a published release always
builds the same commit. A mistake is fixed with a new version.

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
