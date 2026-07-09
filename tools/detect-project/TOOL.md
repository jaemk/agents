---
description: Detect a project's type, version files, and build/test/lint/readme/ci commands.
bin: detect-project.sh
---
Shared project detector. Skills and agents route all build/test/lint/readme/ci
commands through it instead of hardcoding a toolchain. Invoke via {{tools:detect-project}}.
