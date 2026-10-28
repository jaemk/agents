---
name: voice
description: Learn and maintain the user's writing voice so anything written for them (commit messages, PR/issue text, docs, replies) sounds like them. Three entrypoints inferred from the prompt - "mine" (default) analyzes the user's commit messages across all repos under ~/dev and refreshes the voice rules; "feedback" turns a comment about my writing into a durable voice rule; "train" runs a few rounds where I draft a snippet and the user rewrites it in their voice, then synthesizes the deltas into the rules. Use for "mine my voice", "update my voice profile", "learn my writing style", "/voice feedback ...", "/voice train".
allowed-tools: Bash, Read, Edit, Write
---

# voice

Build and maintain a description of how the user writes, so I can write in their voice.

It is two files in the XDG data dir (NOT under `~/.claude`, so they can be granted read access
in settings.json without exposing `~/.claude`), under
`${XDG_DATA_HOME:-~/.local/share}/agents/voice/`:

- `voice-rules.md` - the distilled rules. This is what gets applied: `~/.claude/CLAUDE.md`
  imports it, so it is in context for every session and is reloaded after a compaction. Keep
  it to concrete rules; it costs context in every session.
- `voice-profile.md` - the evidence behind the rules: observed patterns from mining,
  before/after training pairs, and the feedback log. Only this skill reads it.

Resolve and create them with the resource script - never hardcode the paths:

```bash
{{self}}/resources/voice-paths.sh --ensure           # the profile path; seeds both files if missing
{{self}}/resources/voice-paths.sh --rules --ensure   # the rules path
```

Read and edit the files **at the printed paths**. They are not part of the installed skill, so
nothing needs reinstalling after an update.

The only mechanical steps (gathering commits, resolving the paths) are resource scripts;
analysis, interpreting feedback, and synthesizing training deltas are the reasoning done here.

## Mode (inferred from the prompt)

- **mine** (default) - analyze the corpus of the user's commit messages, refresh the profile's
  Observed patterns, and refine the rules.
- **feedback `<comment>`** - the user gave a comment about my writing; turn it into a durable
  rule.
- **train** - run a few draft/rewrite rounds, then fold the deltas into the rules.

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

3. Rewrite the profile's **Observed patterns** from this run, then refine the rules file so it
   captures the dominant, repeatable habits (not one-offs). Set the `Last updated` line in both.
   Keep rules concrete and imperative ("lead the subject with a conventional-commit type"), not
   vague ("be concise").

## feedback

Input: a comment about my writing (e.g. "too formal", "you over-explain", "I'd never start a PR
body with 'This PR'").

1. Translate the comment into one or more **concrete, testable rules** (what to do or avoid, and
   when).
2. Add them to the rules file (merge with or supersede any conflicting existing rule - newer
   feedback wins), and append a dated entry to the profile's **Feedback log** with the original
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
5. Synthesize: fold the recurring deltas into the rules file, and save the clearest pairs under
   the profile's **Before / after examples** (prune weak or redundant ones). Append a
   Feedback-log entry summarizing what the round taught.

## Wiring: keep the rules in effect

Two pieces of the user's `~/.claude` config apply the rules. Check both after any update and
add whichever is missing (once; never copy the rules themselves into CLAUDE.md):

1. **The import.** `~/.claude/CLAUDE.md` has a line importing the rules file, so every session
   starts with them in context and they are reloaded after a compaction:

   ```
   @~/.local/share/agents/voice/voice-rules.md
   ```

   settings.json also needs `Read(~/.local/share/agents/voice/**)` in its allow list.

2. **The hook.** `resources/voice-hook.sh` is a `PreToolUse` hook that adds a one-line
   reminder naming the rules file right before a `git commit` (Bash) or a write to a prose file
   (`.md`, `.txt`, `.rst`, commit/PR message files via Write or Edit). It never blocks the call
   and does nothing when neither file exists. Register it in `~/.claude/settings.json`:

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash|Write|Edit",
           "hooks": [{ "type": "command", "command": "{{self}}/resources/voice-hook.sh" }]
         }
       ]
     }
   }
   ```

## Migrating a single-file profile

An older profile keeps its rules under a `## Distilled rules` heading in `voice-profile.md`.
Move that section's content into the rules file (seeded by `--rules --ensure`), drop the
section from the profile, and point the CLAUDE.md import at the rules file. Until then the hook
names the profile instead.
