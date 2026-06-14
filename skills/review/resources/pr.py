#!/usr/bin/env python3
"""
pr.py - GitHub-PR and local-diff helper for the /review skill.

Language-agnostic: build/test/lint/readme commands are obtained from
resources/detect-project.sh, not hardcoded. The base branch is auto-detected
(origin/HEAD, else origin/main, else origin/master) and overridable with --base.

Usage:
  pr.py [PR_NUMBER] COMMAND [COMMAND ...] [options]

The leading PR_NUMBER is optional: required only for the GitHub commands
(comments, threads, resolve, rerequest, minimize). The local commands
(ci, readme, pushpreview, diff) need no PR number - e.g. `pr.py ci`.

Commands (executed in the order given):
  comments     Fetch and display all inline PR review comments (new vs pre-existing)
  threads      List all review threads with resolution status
  resolve      Resolve all open review threads
  rerequest    Re-request Copilot review
  minimize     Minimize (hide) all eligible pre-push comments as "resolved"
  ci           Run the detected CI/test command; exit non-zero on real failures
  readme       Run the detected README generator (if any)
  pushpreview  Print the git log + diff --stat push preamble for the current branch
  diff         Print `git diff <base>` (for handing to reviewer agents)

Options:
  --owner OWNER     GitHub owner (auto-detected from `gh repo view`)
  --repo REPO       GitHub repo  (auto-detected from `gh repo view`)
  --base REF        Base ref for diff/pushpreview (default: auto-detected)
  --branch BRANCH   Branch name for pushpreview (auto-detected if omitted)
  --since TS        ISO timestamp; comments after this are 'new' (default: last push)
  --ci-cmd CMD      Override the detected CI command (for `ci`)
  --readme-cmd CMD  Override the detected README command (for `readme`)
  --ignore REGEX    For `ci`: tolerate failure lines matching this regex (repeatable)
  --dry-run         For resolve/minimize: list targets without mutating
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

COMMANDS = ("comments", "threads", "resolve", "rerequest", "minimize",
            "ci", "readme", "pushpreview", "diff")
GH_COMMANDS = {"comments", "threads", "resolve", "rerequest", "minimize"}


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def gh(*args, check=True, **kwargs):
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=check, **kwargs)


def repo_info():
    r = gh("repo", "view", "--json", "owner,name", check=False)
    if r.returncode != 0:
        sys.exit("Cannot auto-detect owner/repo. Pass --owner and --repo explicitly.")
    d = json.loads(r.stdout)
    return d["owner"]["login"], d["name"]


def graphql(query):
    return gh("api", "graphql", "-f", f"query={query}")


def parse_utc(ts):
    return datetime.fromisoformat(ts.rstrip("Z")).replace(tzinfo=timezone.utc)


def section(title):
    print(f"\n{'=' * 3} {title} {'=' * (max(0, 60 - len(title)))}")


def detector_path():
    # pr.py installs at <root>/.agents/skills/review/resources/pr.py; the shared
    # detector is at <root>/.agents/resources/detect-project.sh.
    return Path(__file__).resolve().parents[2].parent / "resources" / "detect-project.sh"


def detect(what):
    det = detector_path()
    if not det.exists():
        return ""
    r = subprocess.run([str(det), ".", "--what", what], capture_output=True, text=True)
    if r.returncode != 0:
        return ""
    return r.stdout.strip()


def default_base():
    r = subprocess.run(["git", "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD"],
                       capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip().replace("refs/remotes/", "")
    for cand in ("origin/main", "origin/master"):
        rr = subprocess.run(["git", "rev-parse", "--verify", "--quiet", cand],
                            capture_output=True, text=True)
        if rr.returncode == 0:
            return cand
    return "origin/main"


# ---------------------------------------------------------------------------
# comments
# ---------------------------------------------------------------------------

def cmd_comments(pr, owner, repo, since=None):
    section(f"PR #{pr} inline comments")

    r = gh("api", f"repos/{owner}/{repo}/pulls/{pr}/comments", "--paginate")
    comments = json.loads(r.stdout)

    if since is None:
        r2 = gh("api", f"repos/{owner}/{repo}/pulls/{pr}/commits",
                "--paginate", check=False)
        if r2.returncode == 0 and r2.stdout.strip():
            commits = json.loads(r2.stdout)
            if commits:
                since = commits[-1]["commit"]["committer"]["date"]

    since_dt = parse_utc(since) if since else None

    new_comments, old_comments = [], []
    for c in comments:
        if since_dt and parse_utc(c["created_at"]) > since_dt:
            new_comments.append(c)
        else:
            old_comments.append(c)

    print(f"Total inline comments: {len(comments)}")
    if since_dt:
        print(f"  New (after {since}): {len(new_comments)}")
        print(f"  Pre-existing: {len(old_comments)}")
    print()

    def show(c, label):
        line = c.get("line") or c.get("original_line") or "?"
        print(f"[{label}] id={c['id']}  {c['created_at']}  {c['path']}:{line}  @{c['user']['login']}")
        body = c["body"].replace("\n", " ").strip()
        if len(body) > 320:
            body = body[:317] + "..."
        print(f"  {body}")
        print()

    if new_comments:
        print("=== NEW COMMENTS ===")
        for c in new_comments:
            show(c, "NEW")

    if old_comments:
        print("=== PRE-EXISTING COMMENTS ===")
        for c in old_comments:
            show(c, "OLD")


# ---------------------------------------------------------------------------
# threads
# ---------------------------------------------------------------------------

_THREADS_QUERY = """\
{{
  repository(owner: "{owner}", name: "{repo}") {{
    pullRequest(number: {pr}) {{
      reviewThreads(first: 100) {{
        nodes {{
          id
          isResolved
          comments(first: 1) {{
            nodes {{
              databaseId
              createdAt
              body
            }}
          }}
        }}
      }}
    }}
  }}
}}"""


def fetch_threads(owner, repo, pr):
    r = graphql(_THREADS_QUERY.format(owner=owner, repo=repo, pr=pr))
    nodes = json.loads(r.stdout)["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]
    threads = []
    for n in nodes:
        first = n["comments"]["nodes"][0] if n["comments"]["nodes"] else {}
        threads.append({
            "id": n["id"],
            "isResolved": n["isResolved"],
            "created_at": first.get("createdAt", ""),
            "database_id": first.get("databaseId"),
            "body_preview": first.get("body", "")[:200],
        })
    return threads


def cmd_threads(pr, owner, repo):
    section(f"PR #{pr} review threads")
    threads = fetch_threads(owner, repo, pr)
    unresolved = sum(1 for t in threads if not t["isResolved"])
    print(f"Total: {len(threads)}  Unresolved: {unresolved}")
    print(json.dumps(threads, indent=2))


# ---------------------------------------------------------------------------
# resolve
# ---------------------------------------------------------------------------

_RESOLVE_MUTATION = """\
mutation {{
  resolveReviewThread(input: {{threadId: "{thread_id}"}}) {{
    thread {{ id isResolved }}
  }}
}}"""


def cmd_resolve(pr, owner, repo, dry_run=False):
    section(f"PR #{pr} resolve threads")
    threads = fetch_threads(owner, repo, pr)
    unresolved = [t["id"] for t in threads if not t["isResolved"]]
    print(f"Found {len(unresolved)} unresolved thread(s).")

    if not unresolved:
        print("Nothing to do.")
        return

    if dry_run:
        print("Dry run - would resolve:")
        for tid in unresolved:
            print(f"  {tid}")
        return

    resolved = 0
    for tid in unresolved:
        print(f"  Resolving {tid} ...", end=" ", flush=True)
        r = graphql(_RESOLVE_MUTATION.format(thread_id=tid))
        if r.returncode == 0:
            print("ok")
            resolved += 1
        else:
            print(f"FAILED: {r.stderr.strip()}")

    print(f"\nResolved {resolved}/{len(unresolved)} thread(s).")
    if resolved < len(unresolved):
        sys.exit(1)


# ---------------------------------------------------------------------------
# minimize
# ---------------------------------------------------------------------------

_MINIMIZE_MUTATION = """\
mutation {{
  minimizeComment(input: {{subjectId: "{node_id}", classifier: RESOLVED}}) {{
    minimizedComment {{
      isMinimized
      minimizedReason
    }}
  }}
}}"""


def cmd_minimize(pr, owner, repo, since=None, dry_run=False):
    section(f"PR #{pr} minimize comments")

    # Cutoff: only minimize comments created at or before this timestamp (default:
    # last push), so comments opened after the cycle started are left visible.
    if since is None:
        r0 = gh("api", f"repos/{owner}/{repo}/pulls/{pr}/commits",
                "--paginate", "--jq", "[-1].commit.committer.date", check=False)
        if r0.returncode == 0 and r0.stdout.strip():
            since = r0.stdout.strip().strip('"')

    since_dt = parse_utc(since) if since else None
    if since_dt:
        print(f"Cutoff: {since} (comments after this timestamp are skipped)")

    r = gh("api", f"repos/{owner}/{repo}/pulls/{pr}/comments", "--paginate")
    review_comments = json.loads(r.stdout)

    r2 = gh("api", f"repos/{owner}/{repo}/issues/{pr}/comments", "--paginate")
    issue_comments = json.loads(r2.stdout)

    eligible = [
        c for c in review_comments + issue_comments
        if since_dt is None or parse_utc(c["created_at"]) <= since_dt
    ]
    print(f"Found {len(eligible)} eligible comment(s) to minimize.")

    if dry_run:
        for c in eligible:
            print(f"  Would minimize: {c['node_id']}  @{c['user']['login']}  {c.get('path', '<issue comment>')}  {c['created_at']}")
        return

    minimized = 0
    for c in eligible:
        print(f"  Minimizing {c['node_id']} (@{c['user']['login']}) ...", end=" ", flush=True)
        r = graphql(_MINIMIZE_MUTATION.format(node_id=c["node_id"]))
        if r.returncode == 0:
            print("ok")
            minimized += 1
        else:
            print(f"FAILED: {r.stderr.strip()}")

    print(f"\nMinimized {minimized}/{len(eligible)} comment(s).")
    if minimized < len(eligible):
        sys.exit(1)


# ---------------------------------------------------------------------------
# rerequest
# ---------------------------------------------------------------------------

def cmd_rerequest(pr, owner, repo):
    section(f"PR #{pr} re-request Copilot review")
    gh("api", f"repos/{owner}/{repo}/pulls/{pr}/requested_reviewers",
       "-X", "POST", "-f", "reviewers[]=copilot-pull-request-reviewer[bot]")
    print(f"Copilot review re-requested for {owner}/{repo}#{pr}.")


# ---------------------------------------------------------------------------
# ci
# ---------------------------------------------------------------------------

def cmd_ci(ci_cmd=None, ignore=()):
    section("CI")
    cmd = ci_cmd or detect("ci") or detect("test")
    if not cmd:
        print("No CI/test command detected (detect-project.sh found none). Skipping.")
        return
    print(f"Running: {cmd}")
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    combined = r.stdout + r.stderr

    if r.returncode == 0:
        print("CI passed.")
        return

    lines = combined.splitlines()
    real = []
    for line in lines:
        if ignore and any(re.search(p, line) for p in ignore):
            continue
        low = line.lower()
        if "error" in low or "failed" in low or "panic" in low:
            real.append(line)

    if ignore and not real:
        print("CI exited non-zero, but all failure lines matched --ignore patterns; treating as pass.")
        return

    shown = real or lines
    print(f"CI FAILED (exit {r.returncode}). Failure lines:")
    for line in shown[:80]:
        print(f"  {line}")
    if len(shown) > 80:
        print(f"  ... ({len(shown) - 80} more lines)")
    sys.exit(r.returncode or 1)


# ---------------------------------------------------------------------------
# readme
# ---------------------------------------------------------------------------

def cmd_readme(readme_cmd=None):
    section("README")
    cmd = readme_cmd or detect("readme")
    if not cmd:
        print("No README generator detected; skipping.")
        return
    print(f"Running: {cmd}")
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"README generator failed (exit {r.returncode}):")
        print(r.stderr)
        sys.exit(r.returncode)
    if r.stdout.strip():
        with open("README.md", "w") as f:
            f.write(r.stdout)
        print("README.md regenerated from generator stdout.")
    else:
        print("README generator ran (no stdout; assumed to write in place).")


# ---------------------------------------------------------------------------
# pushpreview
# ---------------------------------------------------------------------------

def _current_branch():
    r = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"],
                       capture_output=True, text=True, check=True)
    return r.stdout.strip()


def cmd_pushpreview(branch=None):
    section("Push preview")
    if branch is None:
        branch = _current_branch()
    origin_ref = f"origin/{branch}"

    print(f"Branch: {branch}  ->  {origin_ref}\n")

    r1 = subprocess.run(["git", "log", f"{origin_ref}..HEAD", "--oneline"],
                        capture_output=True, text=True)
    if r1.stdout.strip():
        print("Commits to push:")
        for line in r1.stdout.strip().splitlines():
            print(f"  {line}")
    else:
        print("No commits ahead of remote.")

    print()
    r2 = subprocess.run(["git", "diff", origin_ref, "--stat"],
                        capture_output=True, text=True)
    if r2.stdout.strip():
        print("Files changed:")
        print(r2.stdout.rstrip())
    else:
        print("No file changes vs remote.")


# ---------------------------------------------------------------------------
# diff
# ---------------------------------------------------------------------------

def cmd_diff(base):
    section(f"diff {base}")
    r = subprocess.run(["git", "diff", base], capture_output=True, text=True)
    print(r.stdout)
    if r.stderr:
        print(r.stderr, file=sys.stderr)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("tokens", nargs="+", metavar="[PR_NUMBER] COMMAND ...",
                    help=f"optional leading PR number then one or more of: {', '.join(COMMANDS)}")
    ap.add_argument("--owner")
    ap.add_argument("--repo")
    ap.add_argument("--base", help="base ref for diff/pushpreview (default: auto-detected)")
    ap.add_argument("--branch", help="branch for pushpreview (auto-detected if omitted)")
    ap.add_argument("--since", help="ISO timestamp for 'comments' new/old split")
    ap.add_argument("--ci-cmd", dest="ci_cmd", help="override detected CI command")
    ap.add_argument("--readme-cmd", dest="readme_cmd", help="override detected README command")
    ap.add_argument("--ignore", action="append", default=[],
                    help="ci: tolerate failure lines matching this regex (repeatable)")
    ap.add_argument("--dry-run", action="store_true", help="resolve/minimize: list without mutating")
    args = ap.parse_args()

    tokens = list(args.tokens)
    pr = None
    if tokens and tokens[0].isdigit():
        pr = int(tokens.pop(0))
    commands = tokens

    if not commands:
        ap.error("no command given; expected one or more of: " + ", ".join(COMMANDS))
    unknown = [c for c in commands if c not in COMMANDS]
    if unknown:
        ap.error(f"unknown command(s): {', '.join(unknown)}; choose from {', '.join(COMMANDS)}")
    needs_pr = [c for c in commands if c in GH_COMMANDS]
    if needs_pr and pr is None:
        ap.error(f"a PR number is required for: {', '.join(needs_pr)} (e.g. `pr.py 264 comments`)")

    owner = repo = None
    if needs_pr:
        owner, repo = args.owner, args.repo
        if not owner or not repo:
            owner, repo = repo_info()

    base = args.base or (default_base() if ("diff" in commands or "pushpreview" in commands) else None)

    for cmd in commands:
        if cmd == "comments":
            cmd_comments(pr, owner, repo, since=args.since)
        elif cmd == "threads":
            cmd_threads(pr, owner, repo)
        elif cmd == "resolve":
            cmd_resolve(pr, owner, repo, dry_run=args.dry_run)
        elif cmd == "rerequest":
            cmd_rerequest(pr, owner, repo)
        elif cmd == "minimize":
            cmd_minimize(pr, owner, repo, since=args.since, dry_run=args.dry_run)
        elif cmd == "ci":
            cmd_ci(ci_cmd=args.ci_cmd, ignore=args.ignore)
        elif cmd == "readme":
            cmd_readme(readme_cmd=args.readme_cmd)
        elif cmd == "pushpreview":
            cmd_pushpreview(branch=args.branch)
        elif cmd == "diff":
            cmd_diff(base)


if __name__ == "__main__":
    main()
