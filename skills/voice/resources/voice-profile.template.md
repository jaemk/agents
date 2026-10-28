# Voice profile

The evidence behind the user's voice rules, maintained by the `/voice` skill. The rules
themselves are in `voice-rules.md` next to this file, which is what gets applied when writing;
this file is read only when the rules are refreshed.

Last updated: (not yet populated - run `/voice mine`)

## Observed patterns (from commit mining)

_Patterns mined from the user's commits across `~/dev`: subject structure, mood/tense, length,
capitalization, punctuation, vocabulary, and conventions (e.g. prefixes, PR refs), with rough
frequencies. Populated by `/voice mine`._

## Before / after examples (from training)

_Concrete pairs from `/voice train`. Each entry: my draft, the user's rewrite, and the one-line
delta it teaches. These are few-shot references - keep the strongest, prune the rest._

## Feedback log

_Dated entries from `/voice feedback`: the feedback the user gave and the rule it produced._
