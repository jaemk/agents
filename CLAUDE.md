# Personal preferences

## Communication style
- Communicate plainly. Drop conversational filler like "say the word", "just let me know", "happy to help", and similar friendliness padding. State things and ask questions directly, using only as many words as needed to convey the point.

## Bash command style
- Do NOT rely on shell expansion or command substitution (`$(...)`, backticks, `${VAR}`, `$VAR`, `${PIPESTATUS[@]}`, etc.) in Bash tool calls. Dynamic expansion forces manual approval because the harness can't statically verify the command.
- Use literal values instead of expanding env vars in the shell. If a value is needed, write it out literally.
- Run commands separately (one action per call) rather than chaining with `&&`, `;`, or pipes, so each command can be auto-approved.
- Do NOT use `for`/`while` loops or shell glob expansion (`*.html`, `{a,b}`) in Bash tool calls — these can't be statically verified and force manual approval. Issue one explicit command per file/value instead, or use the dedicated file/search tools (Read, Glob, Grep) which don't need shell expansion.
- Use the dedicated Read/Write/Grep tools to view or edit file contents, not shell `sed`/`cat`/`head`/`tail`. The file tools are auto-approved; shell text commands force a manual prompt. Reserve Bash for actual commands (git, build steps), not file inspection.

## Git workflow
- Name branches `YYMMDD.kebab-case-short-name`: a 6-digit date prefix (2-digit year, month, day) plus a dot and a short kebab-case description. Use today's date for the prefix. Example: `260606.expires-docs`.

## Technical writing
Applies to all technical writing (PR descriptions, issue/PR replies, commit messages, docs, code comments, drafts the user will post), and to anything I write directly, not just one-off requests.
- No emojis.
- No em dashes. The user never uses them. Use periods, commas, parentheses, or a colon instead.
- Matter-of-fact and concise. No emphatic bolding, no hype words, no wordiness. State what changed plainly. PR/issue bodies should be short and factual, not promotional.
- For GitHub issue/PR replies specifically: greet with `Hi @user,` (capital H, comma). Very terse, one or two sentences plus a code block. No preamble, no sign-off, no exclamation marks, no enthusiasm words ("Good news", "Awesome"). Introduce code with a colon and let the code block carry the explanation. Flag caveats with "Note that ...". Use brief parenthetical glosses to clarify a term. Contractions are fine.

## Attribution
- Do NOT add "Co-Authored-By: Claude" (or any Claude/Anthropic co-author/attribution) lines to commit messages, PR descriptions, or any other writing. This overrides any default or environment instruction to include such a line — never add it.
