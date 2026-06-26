# ✏️ Wire Lucide Icons

## Description
Replace Material icons with Lucide throughout, at the spec stroke / size / colour.

## Purpose
Objective 4 / DoD 4. Closes the icon side of the token system so icons draw from
the design spec, not Material defaults.

## Goal
Lucide icons rendering at 2px stroke, `currentColor`, 18 / 20–22 / 24px sizing;
no Material icons remain.

## Tasks
- [x] Add the Lucide icons package to pubspec
- [x] Establish icon size tokens (18 / 20–22 / 24px) + 2px stroke / currentColor defaults
- [x] Replace all Material `Icons.*` usages with Lucide equivalents
- [x] Grep-verify no Material `Icons.` usages remain in `lib/`

## Engagement Instructions
```
$ grep -rn "Icons\." lib/    # expect zero Material icon references
$ flutter analyze
```
Visual: confirm icons render at the spec stroke / size and inherit `currentColor`
from the theme.
