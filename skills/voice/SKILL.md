---
name: voice
description: Learn and maintain the user's writing voice so anything written for them (commit messages, PR/issue text, docs) sounds like them. Three entrypoints inferred from the prompt - "mine" (default) analyzes the user's commit messages across all repos under ~/dev and refreshes the voice profile; "feedback" turns a comment about my writing into a durable voice rule; "train" runs a few rounds where I draft a snippet and the user rewrites it in their voice, then synthesizes the deltas into the profile. Use for "mine my voice", "update my voice profile", "learn my writing style", "/voice feedback ...", "/voice train".
allowed-tools: Bash, Read, Edit, Write
---

# voice

Build and maintain a profile of how the user writes, so I can write in their voice.

The profile lives in the XDG data dir (NOT under `~/.claude`, so it can be granted read access
in settings.json without exposing `~/.claude`):
`${XDG_DATA_HOME:-~/.local/share}/agents/voice/voice-profile.md`. Resolve and create it with the
resource script - never hardcode the path:

```bash
{{self}}/resources/voice-paths.sh --ensure   # prints the path; seeds from template if missing
```

It prints the resolved profile path. Read and edit the profile **at that printed path**; it is the single source of truth and is read by my
global writing instructions. It is not part of the installed skill, so no `x install` is needed
after updating it.

The only mechanical steps (gathering commits, resolving the path) are resource scripts;
analysis, interpreting feedback, and synthesizing training deltas are the reasoning done here.

## Mode (inferred from the prompt)

- **mine** (default) - analyze the corpus of the user's commit messages and refresh the
  profile's Observed patterns and Distilled rules.
- **feedback `<comment>`** - the user gave a comment about my writing; turn it into a durable
  rule.
- **train** - run a few draft/rewrite rounds, then fold the deltas into the profile.

Announce the resolved mode at the start.

## mine

1. Gather the corpus with the resource script (read-only; no edits):

   ```bash
   {{self}}/resources/mine-commits.sh ~/dev
   {{self}}/resources/mine-commits.sh ~/dev --full   # include bodies
   ```

   It prints one commit subject per line (subject+body with `--full`) across every git repo
   under the root, filtered to the user's author identity (auto-detected from git config), and a
   one-line summary on stderr. Pass `--author` to mine a different identity.

2. Analyze the corpus for voice signal, not content. Look for: subject **structure** (e.g.
   `type: summary`, scope, trailing PR refs), **mood/tense** (imperative vs past), **length** and
   whether bodies are used, **capitalization** and terminal punctuation, **vocabulary** and
   recurring verbs, and any consistent **conventions**. Note rough frequencies (e.g. "~70% use a
   conventional-commit prefix").

3. Update the profile (at the path printed by `voice-paths.sh --ensure`): rewrite **Observed
   patterns** from this run, and refine **Distilled rules** so they capture the dominant,
   repeatable habits (not one-offs). Set the `Last updated` line. Keep rules concrete and
   imperative ("lead the subject with a conventional-commit type"), not vague ("be concise").

## feedback

Input: a comment about my writing (e.g. "too formal", "you over-explain", "I'd never start a PR
body with 'This PR'").

1. Translate the comment into one or more **concrete, testable rules** (what to do or avoid, and
   when).
2. Add them to **Distilled rules** (merge with or supersede any conflicting existing rule -
   newer feedback wins), and append a dated entry to the **Feedback log** with the original
   comment and the rule it produced.
3. If the feedback contradicts an Observed pattern, prefer the feedback and note the override.

## train

A short interactive loop to capture the gap between how I write and how the user writes.

1. Pick a genre relevant to the user (commit subject, PR description, issue reply, doc blurb).
   Draft a realistic snippet in that genre and show it as "MY DRAFT".
2. Ask the user to rewrite it in their voice ("how would you have written this?").
3. Record the pair and identify the **delta** - the specific change their rewrite makes (tone,
   structure, word choice, length). State the delta back in one line to confirm.
4. Repeat for **2-3 rounds**, varying the genre, to build a small corpus of pairs. Stop when the
   deltas start repeating (the signal has converged) or the user says stop.
5. Synthesize: fold the recurring deltas into **Distilled rules**, and save the clearest pairs
   under **Before / after examples** (prune weak or redundant ones). Append a Feedback-log entry
   summarizing what the round taught.

## After any update

- The profile is edited in place in the XDG data dir, so there is nothing to `x install` for it
  (the skill's scripts and template are installed; the profile is not).
- CLAUDE.md only *references* this profile - one line under Technical writing pointing at
  `~/.local/share/agents/voice/voice-profile.md` - so writing tasks load it on demand and this
  file stays the single source of truth. Never copy the rules into CLAUDE.md. If that reference,
  or the settings.json read-allow for the voice dir (`Read(~/.local/share/agents/voice/**)`), is
  missing, add it once to the user's `~/.claude` config (CLAUDE.md / settings.json); do not
  duplicate the rules.
