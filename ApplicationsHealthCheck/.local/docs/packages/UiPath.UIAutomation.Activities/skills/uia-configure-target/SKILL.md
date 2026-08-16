---
name: uia-configure-target
description: "Primary entry point for configuring a UiPath target -- ensures the screen and element exist in the Object Repository, checking for existing entries before creating new ones. Returns the OR reference ID. Supports both UiPath-selector and Computer-Vision (CV) element targeting: CV fallback is enabled by default, so the skill automatically falls back to CV when selector-based resolution fails; pass `--cv false` to disable it. Supports batch element configuration via pipe-separated list (e.g., --elements \"Five button | Plus button | Equals button\") to avoid redundant window captures and screen lookups. Use when asked to 'configure target', 'configure application', 'set up target', 'set up application', 'create target in OR', 'find or create target', 'get OR reference for an element', 'select application window', 'create window selector', 'create selector', 'get selector for', 'find selector', 'add target to object repository', 'configure CV target', 'target via computer vision', or when an orchestrator agent needs an OR element reference for a UI element. Trigger this whenever building automation workflows that need reliable OR references."
argument-hint: "--window <description> [--elements <descriptions>] [--screen-reference-id <id>] [--cv false] [--semantic] [--no-improve] [--project-dir <path>]"
allowed-tools: Bash, Read, Write, Agent, AskUserQuestion
---

Ensure a UI target (screen + elements) exists in the Object Repository. Checks for existing OR entries first -- creates new ones only when needed. Returns the OR reference ID(s).

`$ARGUMENTS` format: `--window <description> [--elements <descriptions>] [--screen-reference-id <id>] [--cv false] [--semantic] [--no-improve] [--project-dir <path>]`

**IMPORTANT: Use forward slashes in ALL paths.**

**IMPORTANT: The CLI is a native OS executable — every path passed to it (`--folder-path`, `--definition-file-path`, `--project-dir`, `--refs` JSON, etc.) must be an absolute path in the host OS's own format.** On Windows that means a drive-letter path like `C:/Work/.../folder`. Do **not** pass a shell-emulation path such as a git-bash/MSYS/Cygwin `pwd` result (`/c/Work/...`), a WSL `/mnt/c/...` path, or any relative path — the native CLI cannot resolve these and will silently write artifacts to the wrong place or fail with confusing "path not found" errors. When you need to derive an absolute path inside git-bash on Windows, use `pwd -W` (or `cygpath -m`), which yields the `C:/...` forward-slash form, **never** a bare `pwd`.

**IMPORTANT: Follow the steps mechanically. Do NOT add commentary or analysis between steps.**

**IMPORTANT: For full details on Object Repository concepts (Application, Screen, Element) and the complete CLI command reference, see [`object-repository.md`](../../references/object-repository.md).**

## CLI

Define a shell **function** named `cli` that wraps the CLI, then call it as `cli <subcommand> ...` everywhere below:

```bash
cli() { uip rpa uia "$@"; }
```

If `$PROJECT_DIR` is set, define it with the project dir baked in instead:

```bash
cli() { uip rpa uia --project-dir "$PROJECT_DIR" "$@"; }
```

Either way, every `cli ...` call below automatically uses the right base command and `--project-dir`. Using a function (not a `CLI="..."` string variable) keeps argument boundaries intact when any path -- `--project-dir`, `--folder-path`, `--definition-file-path`, or a `--refs` JSON value -- contains spaces.

> **WARNING -- never put the command in a string variable. Re-expanding a command from a string breaks on any path containing spaces. Use the `cli` function, or write `uip rpa uia ...` out in full with every path double-quoted at the call site. Re-declare the `cli` function at the top of each Bash invocation that calls it (shell state does not persist between tool calls). Several steps below chain multiple `cli` calls with `&&` in ONE invocation to save round-trips; declare `cli` once at the top of that invocation and every chained call shares it — the re-declare rule applies per invocation, not per chained call.
>
> **JSON arguments** (`--refs`, `--definition-file-paths`): keep each path inside the double-quoted JSON literal exactly as shown at each call site, and never reconstruct the JSON by re-expanding a bare variable -- that re-introduces the same word-splitting bug.
>
> **Misleading error decode.** If the CLI reports `'uia' requires the 'UiPath.UIAutomation.CLI' package`, this is almost always a **bad or truncated `--project-dir`** (commonly a project path with spaces that got word-split), **not** a real missing-package problem. Verify `--project-dir` arrived as a single quoted argument before touching package versions.

## Call Batching

Steps below chain their CLI calls with `&&` into single shell invocations at the call sites that say so. **Stop between invocations only to reason** (pick a ref, match a screen, assess a selector) — issuing one CLI call per turn when the next command does not depend on unread output is the single largest source of wasted round-trips in capture sessions. TARGET-8 (CV fallback) and TARGET-10 (anchors) are inherently iterative — each CLI call's output feeds the next decision — so batch only what their sub-steps allow (e.g., one `resolve-default` call for all CV refs in TARGET-CV-2).

**Never suppress a chained CLI command's stdout** — no `>/dev/null`, no `| tail`/`| grep`, and no command substitution around it (sole exception: the `selector-intelligence evaluate` **output redirect** in TARGET-2, shown at its call site). Each `snapshot capture` prints one `Created snapshot file <path>.` line per artifact — those printed paths are what tell you where the rendered tree (`window-tree.md`, `tree.md`, `cv-tree.md`) and the other snapshot artifacts landed; if an expected artifact seems missing, check the printed paths before re-capturing.

## Input Parsing

Extract from `$ARGUMENTS`:

- `--window <description>` -> `$WINDOW`. Window/tab description to target.
- `--elements <descriptions>` -> pipe-separated list of target element descriptions (optional). Also accepts `--element`. Use `|` to separate multiple elements (e.g., `"Five button | Plus button | Equals button"`). If omitted, run in **screen-only mode**.
- `--cv false` -> `$USE_CV=false` (default: `true`). CV fallback is enabled by default: unresolved element selectors are routed to the [CV Element Resolution sub-procedure](#cv-element-resolution-sub-procedure) in TARGET-8 instead of stopping or prompting. Use this only when selector-only behavior is required. There is no force-CV mode; the flow is always selector-first. Ignored in screen-only mode.
- `--semantic` -> `$CONFIGURE_SEMANTIC=true` (default: `false`). Enable Semantic (NLP) secondary targeting. Ignored in screen-only mode.
- `--no-improve` -> `$NO_IMPROVE=true` (default: `false`). Skip the uia-improve-selector subagent (7.3).
- `--screen-reference-id <id>` -> `$SCREEN_REF_ID` (optional). The OR screen reference for this window, when the caller already holds it (returned by an earlier invocation in the same capture session). Skips the TARGET-3 screen lookup. Pass it only while the current window still matches the referenced screen's window selector (same app window, different UI state); when in doubt, omit — TARGET-3 will search.
- `--project-dir <path>` -> `$PROJECT_DIR` (optional). UiPath project directory. Passed through to all CLI commands and subagent prompts.

If `$WINDOW` is not provided, ask the user which application/window to target.

**Parse elements:** Split the `--elements` value on `|` and trim whitespace from each entry to produce `$ELEMENT_LIST` (array). Derive `$ELEMENT_NAMES` by converting each entry to Title Case (e.g., "add to cart button" -> `Add To Cart Button`).

Derive `$SCREEN_NAME` from `$WINDOW` by converting to Title Case (e.g., "google chrome" -> `Google Chrome`).

## Definition Files

A **definition** describes a single window or element and is split into two on-disk parts: a XAML file that holds the runtime activity object (a `TargetApp` or `TargetAnchorable` -- see [Target.md](../../activities/common/Target.md)) and a sibling `.xaml.metadata` JSON file that holds the design-time metadata (names, ids, activity type, etc.). The CLI reads/writes both as a pair.

**The `.xaml.metadata` file MUST always exist alongside the `.xaml` file and share the same base name** (e.g., `window.xaml` and `window.xaml.metadata`). One never appears without the other.

**Window definition** -- describes the application window/screen. Used for OR screen registration.

- `window.xaml` -- a serialized [`TargetApp`](../../activities/common/Target.md#targetapp). Created by `target-app resolve-defaults` in TARGET-2.
- `window.xaml.metadata` -- JSON metadata file: `Name`, `Description`.

**Element definition** -- describes a single UI element inside a window. Used for OR element registration. Two flavors are possible per element; both end up as `target-${INDEX}.xaml` + `target-${INDEX}.xaml.metadata` and both register the same way in TARGET-11:

- **Selector-based element** (produced in TARGET-7 by `target-anchorable resolve-defaults`) — a serialized [`TargetAnchorable`](../../activities/common/Target.md#targetanchorable) whose selector references live tree attributes, scoped to `window.xaml`.
- **CV-based element** (produced in TARGET-8 from CV refs) — a serialized `TargetAnchorable` that uses Computer Vision search instead of selector search steps, scoped to `window.xaml`.

**IMPORTANT:** Definition files are ALWAYS generated by the CLI -- `cli target-app resolve-defaults ...` for a window definition or `cli target-anchorable resolve-defaults ...` for an element definition. **Never create or hand-edit `.xaml` or `.xaml.metadata` files yourself.** Once created, the only supported way to mutate a definition file is `cli target-app update-definition ...` or `cli target-anchorable update-definition ...` with a selector generated by TARGET-7. Both rewrite the XAML and the metadata atomically. You MAY read `.xaml` and `.xaml.metadata` files to inspect selectors and metadata.

## Error Handling

After every CLI command, check the exit code. If non-zero, show the CLI's stderr/stdout to the user and stop. Common failures:
- **snapshot capture**: application not running, window minimized, or not visible on screen
- **target-app resolve-defaults / target-anchorable resolve-defaults**: invalid ref or element not found in tree
- **ref resolution** (`Target eN not found in snapshot` / `Target eN is stale`): no snapshot is currently loaded for that ref kind (capture/inspect first), or the ref targets an element that is gone / belongs to an older snapshot that has since been replaced.

## TARGET-1: Prepare Working Folder

Always start from a clean folder -- never reuse a previous run's folder. Stale artifacts from a prior run may reference a different window or app state.

```bash
rm -rf .local/.uia/.configure-target && mkdir -p .local/.uia/.configure-target
```

Set `$WORK_FOLDER` to the **absolute path** of `.local/.uia/.configure-target` (the CLI requires absolute paths). Resolve it in the host OS's native format — on Windows, derive it from `pwd -W` (or `cygpath -m "$(pwd)"`) so you get a `C:/...` drive-letter path, **not** a bare git-bash `pwd` (`/c/...`), which the native CLI cannot resolve (see the path note at the top of this file). Verify the resulting `$WORK_FOLDER` starts with a drive letter before passing it on.

Run this folder prep in the **same Bash invocation** as TARGET-2's top-level `snapshot capture`, chained with `&&`: declare the `cli` function, run the prep, resolve `$WORK_FOLDER`, then the capture — folder-prep-through-top-level-capture is one round-trip.

## TARGET-2: Create Window Selector

Capture the top-level tree — the continuation of TARGET-1's Bash invocation (chained onto the folder prep with `&&`). No definition file exists yet, so omit `--definition-file-path` -- the CLI captures the full top-level snapshot without scoping to a target:

```bash
cli snapshot capture --folder-path "$WORK_FOLDER" && cat "$WORK_FOLDER/window-tree.md"
```

This produces a rendered `window-tree.md` (stdout: one `Created snapshot file <path>.` line per artifact); the chained `cat` returns it in the same round-trip so the `$WREF` decision needs no extra turn.

When the application was just launched during pre-flight, this top-level capture also serves as the launch confirmation — do NOT run a separate `snapshot inspect` between launching the app and this capture.

Read the `cat` output. Match `$WINDOW` against window titles and app names (partial, case-insensitive). Browser tabs are labeled `BrowserTab` with `b` prefix refs (e.g., `b3`) -- prefer those over native browser windows for web apps. Regular windows use `w` prefix refs (e.g., `w3`).

Save the matching ref as `$WREF`. If no match, present the list and ask the user.

Get the window selector (the CLI creates the default `TargetApp` with the default selector on the `Selector` and writes the XAML to `window.xaml` and its `window.xaml.metadata`). Pass `--refs` as a JSON literal; the forward-slash rule above keeps the JSON safe (Windows backslashes would be interpreted as JSON escapes).

**If `$ELEMENT_LIST` is not empty**, chain the app-level capture directly onto `resolve-default` in the **same Bash invocation** (`&&`) so both run in one round-trip. The app-level capture locates the window by `--window-ref "$WREF"` (the ref you selected above), **not** by the definition's selector, so the title stabilization below — which only rewrites `window.xaml`'s selector — does not invalidate the captured artifacts:

```bash
cli target-app resolve-defaults \
  --refs "[{\"ref\":\"$WREF\",\"definitionFilePath\":\"$WORK_FOLDER/window.xaml\"}]" \
  --name "$SCREEN_NAME" --from-snapshot \
  && cli snapshot capture --folder-path "$WORK_FOLDER" --definition-file-path "$WORK_FOLDER/window.xaml" --window-ref "$WREF" \
  && cli object-repository get-screens --definition-file-path "$WORK_FOLDER/window.xaml" \
  && cat "$WORK_FOLDER/window.xaml"
```

When `--screen-reference-id` was passed, replace the `get-screens` link with TARGET-4's `cli object-repository get-elements --screen-reference-id "$SCREEN_REF_ID"`.

The app-level capture produces `ApplicationLevelNodeTreeInfo.json`, `ApplicationLevelApplicationMetadata.json`, and `ApplicationScreenshot.jpg`. The chained `cat` returns `window.xaml` in the same round-trip, so the title-stabilization judgment below needs no extra read turn. **In screen-only mode** (`$ELEMENT_LIST` empty), omit the `&& cli snapshot capture ...` continuation (keep the `get-screens` link and the `cat`) — there is no app-level capture without elements.

**Stabilize title if needed:** Read `$WORK_FOLDER/window.xaml` and inspect the `Selector`'s `title` attribute (if present). The `title` often reflects the current page content (e.g., article headline, search query, email subject) rather than just the application identity. If the title contains volatile page-specific content beyond the app name, simplify it — keep only the stable app-identifying portion with wildcards (e.g., `title='*10 Unread - dan@ - Outlook*'` → `title='*Outlook*'`). The kept portion must be a substring of the original title value (ignoring wildcards) so it still matches the current window. If the title already looks stable (e.g., a desktop app like `title='Calculator'`), leave it as-is. If a change is needed, use the CLI to write it back — **Batch:** run the write-back and its mandatory evaluate below as one chained invocation (nothing between reads the title, and it MUST pass the evaluate gate before TARGET-7.1 resolves element selectors, which seed their `ScopeSelectorArgument` from `window.xaml`):

This hand-edit is allowed **only for the window selector**, not for element selectors — those come only from TARGET-7

```bash
cli target-app update-definition \
  --definition-file-path "$WORK_FOLDER/window.xaml" \
  --selector "$STABILIZED_WINDOW_SELECTOR"
```

**Mandatory if you ran `update-definition` above — evaluate the edit.** Evaluate the selector now in `window.xaml` (omit `--improve-selector-response-file-path` so it evaluates the definition's own selector):

```bash
cli selector-intelligence evaluate \
  --folder-path "$WORK_FOLDER" \
  --definition-file-path "$WORK_FOLDER/window.xaml" \
  --mode improve > "$WORK_FOLDER/window-evaluation-result.txt" 2>&1
```

Passes only if the candidate has `IsValid` and `MatchesOriginalTarget` true, a single `MatchedWindowIds`, and no blocking `ToolingFeedback`. On failure, re-run `target-app resolve-defaults` above to restore the probed selector, then re-stabilize less aggressively (or keep it) and evaluate again. Do not proceed past TARGET-2 with a failing selector.

On success, if the candidate's `WindowSelector` differs from the one in `window.xaml`, write the evaluated selector back:

```bash
cli target-app update-definition \
  --definition-file-path "$WORK_FOLDER/window.xaml" \
  --selector "$EVALUATED_WINDOW_SELECTOR"
```

## TARGET-3: Find or Register the Screen in the Object Repository

**Skip this step entirely when `--screen-reference-id` was provided** — `$SCREEN_REF_ID` is already set; TARGET-4's `get-elements` is chained into TARGET-2's `resolve-default` invocation instead (replacing the `get-screens` link). The app-reuse listing and screen registration are also skipped.

The `get-screens` listing already ran chained after the app-level capture in TARGET-2's invocation. Read its output — the OR screens table — here; do not re-run the command.

Initialize `$SCREEN_REF_ID` to empty and `$SCREEN_CREATED` to false.

**If the table has rows:** compare each row against `$WINDOW` to find the best match:

- **Name match** (case-insensitive): strong signal.
- **Selector match**: if the stored window selector targets the same application and window title, strong signal.

**Confident match found:** save the screen's `ReferenceId` as `$SCREEN_REF_ID`.

**Multiple plausible matches:** list the candidates and ask the user to pick.

**If the table is empty or the command fails** -- leave `$SCREEN_REF_ID` empty.

### Reuse an existing application (only when no screen matched)

When `$SCREEN_REF_ID` is empty, file the new screen under an **existing application** if the window belongs to one already in the OR — otherwise `create-screen` mints a duplicate app for the same application (e.g. a main window and its `#32770` Properties/Save dialog).

Initialize `$APP_REF_ID` to empty; **skip this block if `$SCREEN_REF_ID` is set** (that screen's app is reused implicitly).

1. **App identity** from `window.xaml`'s `Selector`: desktop → the `app=` executable (shared by the app's main window, dialogs, and `#32770` common dialogs); browser → the URL host, NOT the browser exe (distinct sites are distinct apps).
2. **List unfiltered** — its own invocation (no `--definition-file-path`, or sibling windows of the same app are hidden): `cli object-repository get-screens`. If command fails, leave `$APP_REF_ID` empty.
3. **Find** a screen that belongs to an application with the same app identity (same executable or URL host); use that screen's AppReferenceId as $APP_REF_ID. If several matches, prefer the best `Name`/screen fit for `$WINDOW`, ask if ambiguous. If none, leave `$APP_REF_ID` empty.

### Register the screen (only when no screen matched)

**Skip this whole subsection if `$SCREEN_REF_ID` is set** — a matching screen already exists; reuse it.

Register the screen before resolving elements: `create-screen` reads the opened URL from the live app, and element resolution can navigate it off the **entry** screen.

Compose a `$SCREEN_DESCRIPTION` that captures what the screen represents — the app name, the purpose of the screen/page, and any distinguishing context (e.g., `"The main login page of the Acme HR portal"`, `"Calculator application main window"`). Write the name and description into the definition:

```bash
cli target-app update-definition \
  --definition-file-path "$WORK_FOLDER/window.xaml" \
  --name "$SCREEN_NAME" \
  --description "$SCREEN_DESCRIPTION"
```

Then create the screen, chained onto the `update-definition` above in the **same Bash invocation** (`&&`) — `update-definition` writes the name/description silently, then `create-screen` reads the updated definition and prints `$SCREEN_REF_ID`. Use whichever variant applies. **When `$APP_REF_ID` is set** (an existing application matched above), pass `--app-reference-id` so the screen is filed under that application instead of minting a duplicate:

```bash
cli object-repository create-screen \
  --definition-file-path "$WORK_FOLDER/window.xaml" \
  --app-reference-id "$APP_REF_ID"
```

**When `$APP_REF_ID` is empty** (no existing application matched), omit `--app-reference-id` entirely — a new application is created automatically:

```bash
cli object-repository create-screen --definition-file-path "$WORK_FOLDER/window.xaml"
```

Save stdout as `$SCREEN_REF_ID` and set `$SCREEN_CREATED` to true; if the command fails, show the error and stop. (`$SCREEN_CREATED` flags a screen minted this run, so TARGET-8 / TARGET-11 can roll it back if no element registers; a reused screen stays false and is never deleted.)

In **screen-only mode** (no `--elements`), assess the window selector here: read `$WORK_FOLDER/window.xaml` and check the window `Selector` against the **Assessment criteria** in TARGET-7 — criteria 1-3, 5, and 6 (criterion 4 is element-specific and does not apply to a window). If it is fragile, record a warning for the final Output.

### Screen-only mode exit

**If no `--elements` were requested**, the screen is the deliverable and is registered (`$SCREEN_REF_ID`, whether reused or freshly created). Skip to **Output**.

## TARGET-4: Search for Existing Elements in Object Repository

**Skip if `$SCREEN_CREATED` is true** (the screen was just minted this run, so it has no elements yet). Mark all elements as needing creation, collect them into `$ELEMENTS_TO_CREATE`, and proceed to TARGET-5.

```bash
cli object-repository get-elements --screen-reference-id "$SCREEN_REF_ID"
```

**If elements exist:** compare each row against EVERY element in `$ELEMENT_LIST` to find matches:

- **Name match** (case-insensitive, allowing minor wording differences): strong signal.
- **Semantic selector match**: if the stored semantic description refers to the same UI element, strong signal.
- **Selector match**: if the stored selector targets the same control type with similar identifying attributes, supporting signal.
- If a screenshot file path is present and the match is uncertain, read the screenshot for visual confirmation.

For each element: **confident match** -> record `{$ELEMENT_NAME, $ELEMENT_REF_ID, found}` (skips TARGET-5 through TARGET-11). **No match** -> mark as needing creation.

Collect elements needing creation into `$ELEMENTS_TO_CREATE` (list of `{$INDEX, $ELEMENT, $ELEMENT_NAME}`). The `$INDEX` assigned here is the slot number used for the on-disk file (`target-${INDEX}.xaml`) and is shared across both selector-based and CV-based resolution — it never changes once assigned.

If `$ELEMENTS_TO_CREATE` is empty, skip to **Output**.

## TARGET-5: Choose the Resolution Route for Each Element

Two tracking lists drive the rest of the flow. Each entry from `$ELEMENTS_TO_CREATE` lives in exactly one list at a time:

- `$SELECTOR_ELEMENTS` -- elements that will be (or were) resolved via UiPath selectors in TARGET-6 / TARGET-7.
- `$CV_ELEMENTS` -- elements that will be resolved via Computer Vision in TARGET-8 by the [CV Element Resolution sub-procedure](#cv-element-resolution-sub-procedure).

Copy every entry from `$ELEMENTS_TO_CREATE` into `$SELECTOR_ELEMENTS` and proceed to TARGET-6 — the flow is always selector-first. When CV fallback is enabled (`$USE_CV` is `true`, the default), any element that cannot be confidently resolved in TARGET-6 (no clear tree match, even after a UIA-framework retry and a screenshot disambiguation) or whose selector cannot be made reliable in TARGET-7 (still `NEEDS_IMPROVEMENT` after the snapshot-retry and uia-improve-selector pass) is **moved** from `$SELECTOR_ELEMENTS` to `$CV_ELEMENTS` for CV resolution in TARGET-8. When `$USE_CV` is `false` (`--cv false`), there is no fallback — such elements are surfaced to the user instead (see TARGET-6 / TARGET-7). Both resolved lists feed TARGET-11 in the end.

## TARGET-6: Identify Element Reference

`snapshot capture` (TARGET-2) wrote `$WORK_FOLDER/tree.md`. Each visible node is rendered on one line:

```
  - Button [ref=e42] "Add to cart"
  - InputBox [ref=e15] [sap] "Username"
```

Use `Grep` (with regex if needed) as the primary discovery tool, then `Read` with `offset`/`limit` around grep hits to inspect surrounding context. The tree may be tens of thousands of lines — never read it unbounded. When configuring multiple elements, emit the `Grep` searches for ALL elements in `$SELECTOR_ELEMENTS` in a single message (parallel tool calls) — do not search one element per turn. Examples:

```
Grep pattern="Add to cart" path="$WORK_FOLDER/tree.md" output_mode="content"
Grep pattern="(?i)username.*\[ref=" path="$WORK_FOLDER/tree.md" output_mode="content"
```

The `[sap]` tag indicates the element belongs to a SAP web framework (Fiori/UI5, Web GUI, or Ariba). SAP framework elements carry richer, more stable attributes that produce more reliable selectors.

**SAP element selection rule:** Prefer the `[sap]`-tagged node over its plain child/parent when **they share the same Name** and sit **within 1–2 tree levels** of each other — they are the same logical element. This holds even when the `[sap]` node has a generic role (`Container`, `Group`) and the plain inner is the native control (`InputBox`, `Button`, `INPUT`). The `[sap]` node's selector probes the richer SAP framework attributes, which are more stable than the inner native control's attributes.

For each element still in `$SELECTOR_ELEMENTS`, match the description to a tree result and save its ref as `$EREF_${INDEX}`. If an element has no grep hits at all in the current `tree.md` (and the UIA framework retry below does not produce any either): **when CV fallback is enabled (`$USE_CV` is `true`), move that element from `$SELECTOR_ELEMENTS` to `$CV_ELEMENTS`** and skip it for the rest of TARGET-6 — do **not** stop and do **not** ask the user; TARGET-8 will resolve it via Computer Vision. **When `$USE_CV` is `false` (`--cv false`), do not fall back** — present the element to the user and ask how to proceed.

### Retry capture with UIA framework

If any element could not be confidently matched in the tree (no grep hits, or hits exist but none correspond to the described element), the default capture framework may have produced a tree that lacks those elements. Before retrying, check whether a different framework would help:

1. Read `$WORK_FOLDER/ApplicationLevelApplicationMetadata.json` and check the `"subsystem"` field.
2. **Only retry if `subsystem` is `"aa"`** (Active Accessibility) — UIA queries a different accessibility provider and may surface elements that AA missed. For any other subsystem (`"uia"`, `"webctrl"`, `"html"`, `"java"`, etc.), the framework-specific tree is richer than what UIA would produce. Skip the retry and proceed to screenshot disambiguation.

To retry:

```bash
rm -f "$WORK_FOLDER/ApplicationLevelNodeTreeInfo.json" "$WORK_FOLDER/ApplicationLevelApplicationMetadata.json" "$WORK_FOLDER/ApplicationScreenshot.jpg" "$WORK_FOLDER/tree.md"
cli snapshot capture --folder-path "$WORK_FOLDER" --definition-file-path "$WORK_FOLDER/window.xaml" --window-ref "$WREF" --framework uia
```

The recapture overwrites `tree.md`. Treat any previously recorded `eN` refs as unreliable against the new snapshot (they may resolve to a different element or become stale). Re-grep against the new tree and continue matching.

**If any element has multiple candidates or no clear match from the tree alone**, read the screenshot once to disambiguate:

```
Read "$WORK_FOLDER/ApplicationScreenshot.jpg"
```

Cross-reference the screenshot (visual) with the tree results (structural) to resolve the ambiguity. **If still ambiguous after checking the screenshot: when CV fallback is enabled (`$USE_CV` is `true`), do not list candidates and do not ask the user — move that element from `$SELECTOR_ELEMENTS` to `$CV_ELEMENTS` and continue** (TARGET-8 will resolve it via Computer Vision). **When `$USE_CV` is `false` (`--cv false`), list the candidates and ask the user.**

## TARGET-7: Get Element Selectors

**IMPORTANT**: Every element selector must be produced by `resolve-defaults` or the uia-improve-selector subagent. Those steps are the only source of a selector; work through them until it is `RELIABLE`. Never write an element selector with `target-anchorable update-definition --full-selector` (e.g. if you have the attributes from `interact get-all`). A selector that looks right to you but wasn't produced by TARGET-7 is **unverified**, however correct its attributes seem.

**To parametrize a selector on an argument** (e.g. any runtime text that appears in a common text attribute — `aaname`, `name`, `text`, etc.), do not write the `{{variable}}` yourself — run the uia-improve-selector subagent (7.3) and name the attribute to parametrize in its `$ATTR_INFO`. The subagent is the only approved way to produce a parametrized selector.

### 7.1: Get the default selector

**Do NOT use `--from-snapshot` here.** Element selectors must probe the live element. Each call seeds its `ScopeSelectorArgument` from the `TargetApp`'s `Selector` from the `window.xaml` and resolves the default `TargetAnchorable` into the element's definition file.

**Resolve each element's activity type.** For each element in `$SELECTOR_ELEMENTS`, pick the activity type matching how the workflow will use it (from the element description and the user request); default to `None` when unclear. Save as `$ACTIVITY_TYPE_${INDEX}`. See [`selection-activity-types.md`](../../references/selection-activity-types.md) for the supported values and selection guidance.

Build the `--refs` argument from the elements that **remain** in `$SELECTOR_ELEMENTS` (i.e., those that successfully matched a tree ref). Elements moved to `$CV_ELEMENTS` are excluded — they will be resolved in TARGET-8. If `$SELECTOR_ELEMENTS` is now empty (every element fell back to CV), skip the `resolve-defaults` call and proceed to TARGET-7 (which will short-circuit on the empty list).

Pass the refs as an inline JSON array — one object per element, each carrying its resolved `activityType` (`$ACTIVITY_TYPE_${INDEX}`). **Batch:** resolve every element in `$SELECTOR_ELEMENTS` in this single call:

```bash
cli target-anchorable resolve-defaults \
  --window-definition-file-path "$WORK_FOLDER/window.xaml" \
  --window-ref "$WREF" \
  --refs "[{\"ref\":\"$EREF_1\",\"definitionFilePath\":\"$WORK_FOLDER/target-1.xaml\",\"activityType\":\"$ACTIVITY_TYPE_1\"},{\"ref\":\"$EREF_2\",\"definitionFilePath\":\"$WORK_FOLDER/target-2.xaml\",\"activityType\":\"$ACTIVITY_TYPE_2\"}]"
```

`--window-ref "$WREF"` (the top-level window ref from TARGET-2) scopes resolution to the exact window the element refs were captured under. If omitted, the CLI locates the application by the window selector instead.

### What improvement can act on

Selector improvement operates **only** on the `FullSelectorArgument` — the selector used by the `Selector` (strict) search step — of a main target (`TargetAnchorable`) or an anchor (`Target`). It does **NOT** improve any other targeting method (`FuzzySelector`, `SemanticSelector`, `CV`, `TextNative`, `Image`).

**Skip TARGET-7 entirely if `$SELECTOR_ELEMENTS` is empty** (every element fell back to CV in TARGET-6). Jump to TARGET-8.

**Skip if `$NO_IMPROVE` is true.** Proceed to TARGET-8.

### Assess selector reliability

For each element in `$SELECTOR_ELEMENTS`, read `$WORK_FOLDER/target-${INDEX}.xaml` and assess the `FullSelectorArgument` from the `TargetAnchorable`. Read the definition files for all elements in one batch of parallel `Read` calls — not one element per turn. Also assess the `ScopeSelectorArgument` once (from the first element).

**A `FuzzySelector` element (its enabled `SearchSteps` is `FuzzySelector`, not `Selector`) is by definition NOT RELIABLE** — the criteria below describe a strict `Selector` and do not apply to it. Do not evaluate it against them; classify it NOT RELIABLE and let 7.2 route it (the snapshot retry frequently upgrades it to a strict `Selector`).

**Assessment criteria -- a selector is RELIABLE if ALL of the following hold:**

1. **Uses reliable attributes for its tag type.** Each tag has at least one developer-assigned or semantic identifier (e.g., `automationid`, `name`, `role`, `aria-label`, `id`, `app`, `cls`). Fragile if all identifying attributes are last-resort or unreliable for their tag type.

2. **Not positionally dependent.** The selector does NOT rely on `idx`, `tableRow` or `tableCol` or other attributes that are purely positional.

3. **Attribute values are stable.** Watch for auto-generated IDs (purely numeric like `id='89763184740'`), CSS-in-JS hashes (`class='css-1wq41pf'`), component-path IDs with 3+ dot-separated structural segments, or framework hashes in tag names.

4. **Activity-appropriate attributes.** For `GetText`/`SetText`/`TypeInto`: must NOT use content-reflecting attributes (`text`, `aaname`, `visibleinnertext`, `innertext`) as primary identifiers. For `Check`/`Uncheck`: must NOT rely on state attributes (`checked`, `aastate`). For `SelectItem`: must NOT rely on `selecteditem` or `value`.

5. **Good structure.** A typical selector has ~2 tags. Selectors with 4+ tags are over-specified and fragile. Each tag should have 2-3 meaningful attributes.

6. No `css-selector` attribute.

Mark each selector as `RELIABLE` or not.

**If all selectors are RELIABLE:** skip improvement entirely and proceed to TARGET-8 (it will short-circuit if `$CV_ELEMENTS` is empty and fall through to TARGET-9).

### 7.2: Retry with snapshot before improving

Do NOT skip directly to the improvement subagent. Every element not RELIABLE — except fuzzy ones that already have a registered anchor (excluded below) — MUST first go through one --from-snapshot retry and re-assessment. The subagent is reserved for elements that remain not RELIABLE after this retry. This retry is one cheap CLI call; its re-assessment is the decision gate for whether the more expensive subagent is warranted. Do not predict its outcome — run it.

Collect all element refs not marked `RELIABLE`, **except fuzzy ones that already have a registered anchor** (already disambiguated — leave them for TARGET-10). Decide this exclusion from the definition files already read in 7.1: exclude an element only when its `SearchSteps` is `FuzzySelector` **and** an anchor is registered in its definition. Do not infer either fact — read both from those files (consistent with the TARGET-10 `FuzzySelector` skip rule). Reuse the `$EREF_${INDEX}` you saved in TARGET-6.

**Batch the snapshot retry in a single CLI call** with an inline JSON array (omit `activityType` here — snapshot mode doesn't need it). The CLI writes each new selector directly into the definition file:

```bash
cli target-anchorable resolve-defaults \
  --window-definition-file-path "$WORK_FOLDER/window.xaml" \
  --window-ref "$WREF" \
  --refs "[{\"ref\":\"$EREF_1\",\"definitionFilePath\":\"$WORK_FOLDER/target-1.xaml\"},{\"ref\":\"$EREF_2\",\"definitionFilePath\":\"$WORK_FOLDER/target-2.xaml\"}]" \
  --from-snapshot
```

Re-read each updated `target-${INDEX}.xaml` and re-assess the new `FullSelectorArgument` using the same criteria above.

If the new selector is `RELIABLE`, mark it as such and skip improvement for it.

**Keep strict snapshot selectors; restore the rest.** The `--from-snapshot` call overwrote the definition files. Where the new snapshot selector is **strict**, keep it (an unreliable strict one is hardened in 7.3). Where it is **fuzzy**, re-run `target-anchorable resolve-defaults` **without** `--from-snapshot` to restore the original live-probe selector:

```bash
cli target-anchorable resolve-defaults \
  --window-definition-file-path "$WORK_FOLDER/window.xaml" \
  --window-ref "$WREF" \
  --refs "[{\"ref\":\"$EREF_X\",\"definitionFilePath\":\"$WORK_FOLDER/target-x.xaml\",\"activityType\":\"$ACTIVITY_TYPE_X\"},{\"ref\":\"$EREF_Y\",\"definitionFilePath\":\"$WORK_FOLDER/target-y.xaml\",\"activityType\":\"$ACTIVITY_TYPE_Y\"}]"
```

**If all selectors are now RELIABLE:** skip improvement entirely and proceed to TARGET-8 (it will short-circuit if `$CV_ELEMENTS` is empty and fall through to TARGET-9).

### 7.3: Run improvement on fragile selectors only

**Skip if `$NO_IMPROVE` is true.** Proceed to TARGET-8.

**Mandatory — not a judgment call.** Every element still not RELIABLE after 7.2 MUST go through improvement here.

**Not an alternative to TARGET-10**; it runs first. A selector improved to RELIABLE drops out of anchoring entirely (10.2 Rule 4), the most stable outcome, so you can't know which elements still need anchoring until 7.3 has run. Don't predict which will improve from its attributes — run it.

Collect only the elements not marked `RELIABLE` into `$ELEMENTS_TO_IMPROVE`. The window selector is preserved, so never add it.

**Gate - blocking — strict `Selector` required.** Before proceeding to subagent based improving, print the `SearchStep` of each element in `$ELEMENTS_TO_IMPROVE`, using its `TargetAnchorable`. You *may not* spawn a subagent for an element if its `SearchSteps` does not contain `Selector`. Do not infer or assume the value, read it from the previous output. **If `SearchSteps` of an element does not contain `Selector`, do NOT run the subagent for that element** — remove it from `$ELEMENTS_TO_IMPROVE`. Elements from `$ELEMENTS_TO_IMPROVE`, that pass the guard **MUST** go through step 7.3 - again, do not predict the outcome, run it. Elements excluded here (SearchSteps = FuzzySelector) are not improved by the subagent at all — they are stabilized by anchoring in TARGET-10.

For each element in `$ELEMENTS_TO_IMPROVE`, seed the subagent with the selector (from 7.1 or 7.2) that points to it. The subagent only hardens the element its seed points to — it does not look for a better element — so prefer a unique but volatile selector over a too-generic one. Restore it by re-running that step's `resolve-defaults`.

Spawn one `Agent` per element in `$ELEMENTS_TO_IMPROVE`, **all in a single message** so they run in parallel. Each agent improves only its element selector and preserves the window selector (`--preserve-window-selector`).

**Isolate per-agent artifacts.** The uia-improve-selector CLI writes fixed-name artifacts into its `--folder`. Parallel agents pointing at the same folder would overwrite each other. Give each agent its own subfolder, seeded with the already-captured snapshot so it skips re-capture:

```bash
# Element mode only -- run once before spawning agents
for INDEX in <indices of $ELEMENTS_TO_IMPROVE>; do
  SUBFOLDER="$WORK_FOLDER/improve_${INDEX}"
  mkdir -p "$SUBFOLDER"
  # All copies are best-effort -- if a snapshot step failed earlier, the missing file
  # will surface as a clearer error when the subagent tries to use it.
  cp "$WORK_FOLDER/ApplicationLevelNodeTreeInfo.json"        "$SUBFOLDER/" 2>/dev/null || true
  cp "$WORK_FOLDER/ApplicationLevelApplicationMetadata.json" "$SUBFOLDER/" 2>/dev/null || true
  cp "$WORK_FOLDER/ApplicationScreenshot.jpg"                "$SUBFOLDER/" 2>/dev/null || true
  cp "$WORK_FOLDER/TopLevelNodeTreeInfo.json"                "$SUBFOLDER/" 2>/dev/null || true
  cp "$WORK_FOLDER/TopLevelApplicationMetadata.json"         "$SUBFOLDER/" 2>/dev/null || true
done
```

The definition files stay in `$WORK_FOLDER` (each `target-${INDEX}.xaml` is already unique). The subagent updates its definition file in place, so TARGET-9/10/11 pick up improved selectors with no copy-back step.

**IMPORTANT**: Each agent must be a separate, self-contained `Agent` tool call. Use `model: "sonnet"`. Don't try to inline it.

Use the prompt below for each, with these substitutions:
- `$DEF_FILE` -> `$WORK_FOLDER/target-${INDEX}.xaml`
- `$AGENT_FOLDER` -> `$WORK_FOLDER/improve_${INDEX}`
- `$PRESERVE_ARG` -> `--preserve-window-selector` (the element is not a screen, so keep the window selector fixed)
- `$NODE_INFO` -> what is the purpose of this element, where is it located in the tree, what nodes should be present in the hierarchy
- `$ATTR_INFO` -> interesting attributes to include, volatile attributes to avoid, attributes that should be parametrized
---

You are improving UiPath selectors to make them more robust. Follow the instructions in the skill file mechanically.

Target element: $NODE_INFO
Attribute guidance: $ATTR_INFO

1. Read `../uia-improve-selector/SKILL.md` (relative to the directory this file is in) to learn the full procedure.
2. Execute the skill steps with these arguments: `$DEF_FILE --folder $AGENT_FOLDER --mode improve --quiet $PRESERVE_ARG` (add `--project-dir $PROJECT_DIR` if `$PROJECT_DIR` is set).
3. The definition file contains the current selectors. Improve them; with `--preserve-window-selector` the window selector is left unchanged and only the element selector is improved.

---

Wait for all agents to complete.

Re-assess each improved selector against the criteria above and record the current status/reason for the routing step below.

### Reassess after improvement and route stragglers to CV

After the uia-improve-selector subagent(s) return, re-read every element's `target-${INDEX}.xaml` whose selector was sent through improvement and re-apply the **Assessment criteria** above to the new `FullSelectorArgument`. For each element that is **still** marked `NEEDS_IMPROVEMENT` after this pass: **when CV fallback is enabled (`$USE_CV` is `true`), move it from `$SELECTOR_ELEMENTS` to `$CV_ELEMENTS`** — TARGET-8 will overwrite its `target-${INDEX}.xaml` with a CV-based definition; do **not** ship a fragile selector. **When `$USE_CV` is `false` (`--cv false`), keep the element on the selector track and surface the fragile selector to the user as a warning.** Selectors marked `RELIABLE` stay in `$SELECTOR_ELEMENTS` and proceed to TARGET-9 / TARGET-10 as usual.

## TARGET-8: Resolve Computer Vision elements

**Skip TARGET-8 if `$CV_ELEMENTS` is empty.** Proceed to TARGET-9.

The [CV Element Resolution sub-procedure](#cv-element-resolution-sub-procedure) operates **inside the same `$WORK_FOLDER`**. It reads `window.xaml` for the scope selector and writes CV element definition files into the same `target-${INDEX}.xaml` slots assigned in TARGET-4. There is no copy-back step.

**Build the `$CV_ELEMENTS` string.** Concatenate the elements in `$CV_ELEMENTS` as `INDEX:NAME:DESCRIPTION` triples separated by ` | ` (space-pipe-space). Use the per-element `$INDEX`, `$ELEMENT_NAME`, and the original user-provided element description (`$ELEMENT`):

```
$CV_ELEMENTS = "<index>:<Name>:<description> | <index>:<Name>:<description>"
```

Execute the [CV Element Resolution (sub-procedure)](#cv-element-resolution-sub-procedure) inline with:

- `$WORK_FOLDER` = the absolute path of `$WORK_FOLDER`
- `$WINDOW_DEFINITION` = `$WORK_FOLDER/window.xaml`
- `$CV_ELEMENTS` = the string built above
- `$ACTIVITY_TYPE` = the current activity type
- `$NO_IMPROVE` = the current no-improve flag
- `$WREF` = the top-level window ref selected in TARGET-2
- `$PROJECT_DIR` = the current project directory, if one was provided

The sub-procedure produces a `CV-RESULTS:` block. For each line:

- `RESOLVED` -> the sub-procedure confirmed the highlighted element against the requested element. Check that the reported `caption` plausibly identifies the element the user described; only when the caption looks wrong, read the reported `screenshot` from `$WORK_FOLDER` to confirm the highlighted element's position before deciding. If the caption is consistent, the element's `target-${INDEX}.xaml` is final and should be added to `$CV_ELEMENTS_FINAL`. If the caption mismatches the description, move the element to `$CV_FAILED` with reason "parent verification failed: <details>" instead of registering a wrong-element definition.
- `AMBIGUOUS`, `NOT_FOUND`, or `ERROR` -> the element could not be configured. Record it in `$CV_FAILED` along with the reason. The slot's XAML file, if any was produced, must not be sent to OR registration.

If **every** element in `$CV_ELEMENTS` ended in `RESOLVED`, continue to TARGET-9.

If **some** elements ended in `RESOLVED` and others did not, continue to TARGET-9 with the successful ones; surface the failures with their reasons to the user in the final Output but do not abort the run. The screen and resolved elements are still worth registering.

If **none** of the elements ended in `RESOLVED`:

- If `$SELECTOR_ELEMENTS` still contains valid selector-resolved elements, continue to TARGET-9 with those; surface the CV failures with their reasons to the user in the final Output but do not abort the run.
- Otherwise, no requested element could be configured. If this run minted the screen in TARGET-3 (`$SCREEN_CREATED` is true), roll it back so no empty screen is left behind, then surface the failures to the user and stop:

  ```bash
  cli object-repository delete-screen --reference-id "$SCREEN_REF_ID"
  ```

  A pre-existing screen (`$SCREEN_CREATED` is false) is left untouched — just surface the failures and stop.

## TARGET-9: Configure Semantic Targeting

**Skip if `$CONFIGURE_SEMANTIC` is `false`.** Proceed to TARGET-10.

For each element in `$SELECTOR_ELEMENTS` and `$CV_ELEMENTS_FINAL`:

Derive a natural-language description of the element from `$ELEMENT` (e.g., `"Submit button in the order form"`). Save as `$SEMANTIC_SELECTOR`.

Write the semantic selector into the element definition via the CLI (never edit the XAML directly):

```bash
cli target-anchorable update-definition \
  --definition-file-path "$WORK_FOLDER/target-${INDEX}.xaml" \
  --semantic-selector "$SEMANTIC_SELECTOR"
```

## TARGET-10: Configure Anchors

An **anchor** is a nearby, stably-identifiable element that disambiguates the main target when the target's own selector is not uniquely reliable. Find a good anchor by **reading the captured tree and reasoning about it**.

### 10.1 Gates and classification

For each element from `$ELEMENTS_TO_CREATE`, read the `SearchSteps` attribute from its `TargetAnchorable` in `$WORK_FOLDER/target-${INDEX}.xaml` and proceed accordingly, considering its selector search step:

- **`FuzzySelector`**: Read the definition file. **Skip if an anchor is already registered** — `resolve-defaults` (7.1/7.2) often auto-adds one, and a fuzzy element that has an anchor is already disambiguated; adding a second is a hard NO, not a judgment call. Only as a **fallback**, when the definition has **no anchor registered**, add the element to `$FUZZY_ELEMENTS_TO_ANCHOR`.
- **strict `Selector`**: Add the element to `$STRICT_ELEMENTS_TO_ANCHOR`.

### 10.2 Decide whether an anchor is needed

For each element in `$STRICT_ELEMENTS_TO_ANCHOR`, read its `FullSelectorArgument` from `$WORK_FOLDER/target-${INDEX}.xaml`. Anchor an
element **only when its selector cannot identify it uniquely AND stably on its own.** Apply the rules below in order and **stop at the first
that matches**:

1. **Positional ⇒ KEEP.** The selector contains `idx`, `tableRow`, `tableCol`, or any other purely positional attribute, anywhere in any
tag. Positional attributes are never stable -- keep it. A label or content constraint elsewhere in the selector (e.g.
`visibleinnertext='*ETH gas*'`) does **NOT** offset a positional attribute: `idx` present ⇒ positionally dependent, full stop.

2. **Volatile-as-identifier ⇒ KEEP.** The element's identity rests on an attribute that reflects the target's **own changing content** --
`text`/`aaname`/`visibleinnertext`/`innertext` matching the value, `checked`/`aastate`, or `selecteditem`/`value`. Keep it.
    - **Exception (does NOT trigger keep):** a content attribute that matches a *stable label, column, or header used to scope a
parent/row/column* -- e.g. `colName='Market cap'`, or `visibleinnertext='*Solana*'` on an enclosing `TR` to pick a row. That is
scope-by-stable-label, not identify-by-volatile-value.

3. **Unpinned sibling ⇒ KEEP.** The element is one of several near-identical siblings (a cell in a grid, a button repeated per row/card)
**AND** the selector does not already pin the specific one via a stable row/column/section scope (per the Rule 2 exception). If the selector
already pins it (stable row scope + `colName`, a header, etc.), it is not unpinned -- do not keep on this basis.

4. **Otherwise ⇒ DROP.** None of 1-3 matched, so the selector identifies the element uniquely and stably on its own (a developer-assigned
`automationid`/`id`/`name`, or a stable row-scope + column-name combination). An anchor would only add fragility. **Remove it from
`$STRICT_ELEMENTS_TO_ANCHOR`.**

### 10.3 Find anchor candidates

Create the `$ELEMENTS_TO_ANCHOR` list containing every element from `$STRICT_ELEMENTS_TO_ANCHOR`, plus every element from `$FUZZY_ELEMENTS_TO_ANCHOR`. 10.4 wires both buckets identically.

For each element in the new `$ELEMENTS_TO_ANCHOR` list, search the tree for the target's surroundings, then keep the candidates that make good anchors.

**Search the tree.** The target's snapshot ref is `$EREF_${INDEX}` (saved in TARGET-6). Locate it in `tree.md` and inspect its surroundings -- never read the tree unbounded:

```
Grep pattern="\[ref=$EREF_${INDEX}\]" path="$WORK_FOLDER/tree.md" output_mode="content" -n=true
```

Use the matched line number with `Read` (`offset`/`limit`) to view the target's parent, siblings, and nearby leaf nodes (indentation encodes structure). If structural proximity is ambiguous, read `$WORK_FOLDER/ApplicationScreenshot.jpg` once to confirm a candidate sits visually next to the target.

**A good anchor is:**

- **Stable** -- carries distinctive, non-volatile text or a developer-assigned identifier: a field label, a column/row header, a section caption, or static descriptive text. Avoid anything that changes with content, state, or data (timestamps, counts, row values).
- **Close** -- a sibling, the label immediately adjacent to the target, or a node within 1-2 tree levels. The closer and more directly associated, the better.
- **Unique** -- its own identity is unambiguous in the tree. Do not anchor to one of many identical nodes.
- **Not already an anchor** -- the candidate must not be an element the target already has as an anchor, regardless of how it got there (an auto-anchor from 7.1/7.2, or one registered at any earlier point of this run). The same element must never be added as an anchor twice.

**Duplicate check -- mandatory before picking a candidate.** Read the element's definition pair and list its registered anchors, then verify the candidate is not one of them: identify each registered anchor in the tree semantically (from its selector attributes and name) and compare that tree ref with the candidate's. If they resolve to the same node, it is a duplicate -- pick a different candidate.

Prefer in this order: an explicit label for the target (e.g., the static text immediately preceding an input), then the table header for a grid cell, then the nearest stable neighbor.

A target holds **up to four anchors** (slots `0..3`). One well-chosen anchor is usually enough -- prefer a single strong one. Select more only when no single anchor disambiguates the target on its own (e.g., a grid cell that needs both its column header and its row header). Don't pad the slots; each extra anchor must also be found at runtime, so a weak one adds fragility.

Pick the best candidate (or up to four). If no nearby element qualifies, **skip this element** -- a misleading anchor is worse than none.

### 10.4 Wire the anchors

For each element in `$ELEMENTS_TO_ANCHOR`, wire its chosen anchor(s) with `add-anchor` (never edit the XAML directly). **Wire one anchor at a time -- run steps 1-3 fully for one anchor before adding the next.** (`remove-anchor` in step 3 shifts the remaining slot indices down, so juggling several half-wired anchors at once makes a saved `$SLOT` go stale.)

For each anchor, save its tree ref as `$AREF` and a short Title-Case label as `$ANCHOR_NAME`, then **try the live selector first, falling back to the snapshot selector only if the live one is weak**:

1. **Add with the live selector** (no `--from-snapshot`). The call writes the anchor to the next free slot and returns its index -- save it as `$SLOT` (`0..3`):

   ```bash
   cli target-anchorable add-anchor \
     --element-ref "$AREF" \
     --window-ref "$WREF" \
     --definition-file-path "$WORK_FOLDER/target-${INDEX}.xaml" \
     --name "$ANCHOR_NAME"
   ```

2. **Assess the anchor's selector.** Read the anchor at slot `$SLOT` from `$WORK_FOLDER/target-${INDEX}.xaml`. An anchor resolves to **either** a strict or a fuzzy selector depending on the element (text-based anchors — labels, headers, static text — come out fuzzy), so first read the anchor's `SearchSteps` and assess whichever selector is enabled:
   - `Selector` (strict) → judge the `FullSelectorArgument`.
   - `FuzzySelector` (fuzzy) → judge the `FuzzySelectorArgument`.

   Judge it with the same reliability criteria as TARGET-7 (reliable identifying attributes, not positional, stable values, ~2 tags). If it is reliable, the anchor is done.

3. **If it is not reliable enough, retry from the snapshot.** Remove the anchor you just added, then re-add the same ref with `--from-snapshot` -- the snapshot tree can yield a more stable selector:

   ```bash
   cli target-anchorable remove-anchor \
     --definition-file-path "$WORK_FOLDER/target-${INDEX}.xaml" \
     --index "$SLOT"

   cli target-anchorable add-anchor \
     --element-ref "$AREF" \
     --window-ref "$WREF" \
     --definition-file-path "$WORK_FOLDER/target-${INDEX}.xaml" \
     --name "$ANCHOR_NAME" \
     --from-snapshot
   ```

   Re-assess the new anchor's enabled selector the same way as in step 2 (strict → `FullSelectorArgument`, fuzzy → `FuzzySelectorArgument`). If neither the live nor the snapshot selector is reliable, remove the anchor you just added (`remove-anchor --index "$SLOT"`), then pick a different anchor from 10.3 -- or skip the element.

## TARGET-11: Register Elements in the Object Repository

The screen was already registered in TARGET-3 (`$SCREEN_REF_ID`) — either a pre-existing match or one minted this run (`$SCREEN_CREATED` is true). Use `$SCREEN_REF_ID` as the `--screen-reference-id` below. (Screen-only mode already returned at TARGET-3 and never reaches this step.)

**Compose the registration set.** The elements to register are the union of `$SELECTOR_ELEMENTS` (selector-based, produced in TARGET-6 / TARGET-7) and `$CV_ELEMENTS_FINAL` (CV-based, produced in TARGET-8 and marked `RESOLVED`). Order them by their original `$INDEX` so the batch is deterministic. Both kinds register through the **same** `target-anchorable update-definition` + `object-repository create-elements` commands — the XAML content differs (selector search steps vs CV runtime fields), but the registration API does not.

**Update each element definition file with name and description** before registration. For each element in the registration set, compose a description that explains the element's role and location within the screen — include what type of control it is, what it does, and where it sits in the UI. CV-resolved elements reach this step with the inherited application name (the sub-procedure does not set a friendly `Name`); this step sets the `Name` and `Description` for selector- and CV-based elements alike, so both end up with the same metadata shape.

```bash
cli target-anchorable update-definition \
  --definition-file-path "$WORK_FOLDER/target-1.xaml" \
  --name "$ELEMENT_NAME_1" \
  --description "$ELEMENT_DESCRIPTION_1" \
&& cli target-anchorable update-definition \
  --definition-file-path "$WORK_FOLDER/target-2.xaml" \
  --name "$ELEMENT_NAME_2" \
  --description "$ELEMENT_DESCRIPTION_2"
# ... one per element in the registration set, each chained with &&
```

**Create all elements in a single batched CLI call**, chained onto the `update-definition` calls above with `&&` so the entire set runs in ONE Bash invocation. When `--semantic` was used, TARGET-9's semantic `update-definition` calls chain at the front of this same invocation, before the name/description `update-definition` calls. Each `update-definition` writes a distinct file, then `create-elements` consumes them all. Use comma-separated definition file paths — selector-based and CV-based paths are mixed freely in the same `--definition-file-paths` list:

```bash
cli object-repository create-elements \
  --screen-reference-id "$SCREEN_REF_ID" \
  --definition-file-paths "$WORK_FOLDER/target-1.xaml,$WORK_FOLDER/target-2.xaml"
```

`create-elements` persists the full `TargetAnchorable` content — including all CV runtime fields (`CvType`, `CvText`, `CvTextOccurrence`, `CvElementArea`, `CvTextArea`) when present — into the Object Repository entries. No extra step is needed to promote CV data.

Each output line prints `$ELEMENT_NAME -> $ELEMENT_REF_ID` (or `FAILED: $ELEMENT_NAME (error)`). Parse the output to collect `{$ELEMENT_NAME, $ELEMENT_REF_ID, created}` for every element.

**Roll back an orphan screen.** If this run minted the screen (`$SCREEN_CREATED` is true) **and** zero elements were registered (every entry in the set printed `FAILED`, or the set was empty), delete the screen so a fully-failed run leaves no empty screen behind:

```bash
cli object-repository delete-screen --reference-id "$SCREEN_REF_ID"
```

A screen that already existed (`$SCREEN_CREATED` is false) is never deleted. Surface the element failures in the Output.

## Output

Present the results concisely: the screen reference ID (`$SCREEN_REF_ID`), element reference IDs (table if multiple). Include any window-selector fragility warning recorded in screen-only mode (TARGET-3). If TARGET-8 produced any failures recorded in `$CV_FAILED`, list those element descriptions with their reasons so the user can decide whether to retry the run. No observations, no quality notes, no suggestions.

**Important:** Follow the TARGET steps sequentially with discipline. If you get sidetracked by errors, retries, or user questions, always return to complete the remaining steps in the flow.

## CV Element Resolution (sub-procedure)

Runs inside [TARGET-8](#target-8-resolve-computer-vision-elements) after the parent flow has created `$WORK_FOLDER/window.xaml` and selected which element slots need CV. The only job here is to produce CV-based `target-${INDEX}.xaml` + `.metadata` files for TARGET-11 to register.

Inputs from the parent:

- `$WORK_FOLDER`: absolute work folder containing `window.xaml`, `window.xaml.metadata`, and the existing selector snapshot.
- `$WINDOW_DEFINITION`: absolute path to `$WORK_FOLDER/window.xaml`; CV commands read the scope selector from it.
- `$CV_ELEMENTS`: pipe-separated `INDEX:NAME:DESCRIPTION` triples. Split on `|`, then on the first two `:`; keep later `:` characters in the description.
- `$ACTIVITY_TYPE`: activity type to put in each `--refs` JSON entry as `activityType` (for example `Click`, `TypeInto`, `GetText`).
- `$NO_IMPROVE`: when `true`, stop after the definition is created; no validation screenshot/caption will exist.
- `$WREF`: the top-level window ref (from TARGET-2); passed to `resolve-defaults` as `--window-ref` so CV scopes to the exact window.
- `$PROJECT_DIR`: optional; use the `cli` function from the top-level [CLI](#cli) section so `--project-dir` is consistently included.

`$TARGET_FILE` means `$WORK_FOLDER/target-${INDEX}.xaml` for the current element. All CLI paths are absolute host-OS paths using forward slashes.

### Definition Files

`target-anchorable resolve-defaults` with a CV ref (`cve*` or `cvw*`) creates a CV-only `TargetAnchorable`: `SearchSteps=CV`, scope selector copied from `$WINDOW_DEFINITION`, CV type/text/areas populated from the CV snapshot, and no selector search step. The metadata carries `ActivityType` and the inherited `Name`. TARGET-11 later writes the friendly `Name` and `Description` with `target-anchorable update-definition`.

Never create or edit the `.xaml` or `.xaml.metadata` files by hand. Mutate them only through `target-anchorable resolve-defaults`, `target-anchorable update-definition`, `target-anchorable add-anchor`, and `target-anchorable update-anchor-definition`.

### Volatile Text

`CvText` is matched at runtime. Prefer stable UI elements such as button captions, static labels, menu items, tab titles, and column headers. Avoid typed field contents, dates/times, counters, prices, notification badges, session IDs, user names, emails, tenants, and other environment-specific text. If only part of a caption is volatile, replace that span with `*`; if every distinguishing string is volatile, use a different ref, occurrence, or anchors instead of tightening text.

### TARGET-CV-1: Capture the CV Snapshot

Run CV once for the whole window:

```bash
cli snapshot capture --folder-path "$WORK_FOLDER" --definition-file-path "$WINDOW_DEFINITION" --type cv
```

The CLI prints each artifact as `Created snapshot file {path}.` The service always writes `cv-tree.md` on success and normally also writes `cv-application-screenshot.png`; if the screenshot path is not printed, do not assume it exists.

`cv-tree.md` contains 1-based CV refs (`cve1`, `cvw1`; `cve0`/`cvw0` are invalid), ordered top-to-bottom and left-to-right:

```text
- Button [ref=cve4] "Submit" [Labels="Email","etc"]
  - Text [ref=cvw3] "First name"
- Button [ref=cve5] "Cancel"
- Text [ref=cvw7] "standalone label"
```

`cve*` rows are detected CV elements. `cvw*` rows are OCR words; nested words sit inside the parent element's region and may appear under more than one containing element. `[Labels=...]` appears only on `cve*` rows with saved anchor-word relations; prefer those when otherwise-equivalent candidates need disambiguation, but still verify the final highlight.

### TARGET-CV-2: Pick Refs and Create Definitions

For each `$CV_ELEMENTS` entry, pick an expected CV type and a matching ref from `cv-tree.md`.

Common `CvType` choices:

| Visual appearance                         | CvType           |
|-------------------------------------------|------------------|
| Clickable button with text/icon           | `Button`         |
| Text input field, search box, textarea    | `InputBox`       |
| Checkbox (square toggle)                  | `CheckBox`       |
| Radio button (circular toggle)            | `RadioButton`    |
| Window close button (X)                   | `CloseButton`    |
| Window maximize button                    | `MaximizeButton` |
| Window minimize button                    | `MinimizeButton` |
| Small icon/glyph without text             | `Icon`           |
| Arrow/chevron/expand button               | `ArrowButton`    |
| Table/grid cell                           | `Cell`           |
| Static text label                         | `Text`           |
| Image/picture/logo                        | `Image`          |
| Generic region/container                  | `Area`           |
| Any text (OCR-based, no specific control) | `AnyText`        |
| Group of words                            | `AnyWordGroup`   |
| Any icon (generic icon match)             | `AnyIcon`        |
| Data table/grid                           | `Table`          |
| Specific table cell                       | `TableCell`      |

Use grep-style searches against `cv-tree.md`; do not read the whole file unbounded:

```text
Grep pattern="(?i)submit" path="$WORK_FOLDER/cv-tree.md" output_mode="content"
Grep pattern="^\s*- Button \[ref=.*Total" path="$WORK_FOLDER/cv-tree.md" output_mode="content"
```

Pick refs with these rules:

- Prefer a `cve*` element ref for clickable/editable controls. Use `cvw*` only when the target really is standalone text.
- If the expected type is absent but the screenshot clearly shows the element, use the closest detected type/ref and record the mismatch for validation.
- Avoid refs whose text is volatile; choose stable text or a textless control ref plus anchors.
- If multiple refs remain plausible, inspect `cv-application-screenshot.png` if it exists. If still ambiguous, mark that index `NOT_FOUND` with the candidate refs; do not invent a ref.

Build one JSON array for the refs you chose:

```text
$REFS = "[{\"ref\":\"$EREF_1\",\"definitionFilePath\":\"$WORK_FOLDER/target-1.xaml\",\"activityType\":\"$ACTIVITY_TYPE\"},{\"ref\":\"$EREF_2\",\"definitionFilePath\":\"$WORK_FOLDER/target-2.xaml\",\"activityType\":\"$ACTIVITY_TYPE\"}]"
```

Create definitions in one call:

```bash
cli target-anchorable resolve-defaults --window-definition-file-path "$WINDOW_DEFINITION" --window-ref "$WREF" --refs "$REFS"
```

Do not pass `--folder-path`; this command does not define that option. It prints one pipe-delimited row per entry:

```text
$EREF|$TARGET_FILE
$EREF|ERROR|$REASON
```

Selector-based rows can include a third selector segment, but CV rows omit it. Parse rows by `$EREF`, map back to `$INDEX`, and exclude error rows from validation. A single-entry retry uses the same command shape with only that element in `--refs`; it overwrites `$TARGET_FILE`.

### TARGET-CV-3: Validate and Refine

Skip this section when `$NO_IMPROVE=true`; return the created definition as `RESOLVED ... no_improve=true`.

For each created definition, make at most three attempts:

```bash
cli target-anchorable validate --definition-file-path "$TARGET_FILE"
```

The CLI prints exactly one of these result messages:

- `The target was found against the live application.` Optionally followed by `A screenshot highlighting the match was saved at {path}.`
- `The target was not found against the live application.`

Treat `The target was not found against the live application.` as a validation failure, not as proof that the intended UI element is absent. The same message covers both cases:

- **Zero candidates**: the target is not in the live CV snapshot, is hidden/occluded, or the chosen CV ref/definition no longer describes it.
- **Duplicate candidates**: two or more same-type/similar-text CV candidates exist and the runtime cannot disambiguate the intended one.

It is normal for the first default CV definition to fail validation. Refine the CV attributes before returning `NOT_FOUND` or `AMBIGUOUS`.

When found, read the printed screenshot path if present and verify the highlight/caption is the intended element. A deterministic match can still be the wrong sibling. If the highlight is wrong, pick a better `$NEW_EREF`, rerun `target-anchorable resolve-defaults` for this `$TARGET_FILE`, then validate again.

When not found, compare nearby same-type and similar-text candidates in `cv-tree.md` and the CV screenshot. Classify the failure before deciding the next step:

- If no plausible candidate is present, treat it as a wrong/absent ref: pick a better `$NEW_EREF` if one exists, rerun `target-anchorable resolve-defaults` for this `$TARGET_FILE`, then validate again. Return `NOT_FOUND` only after there is no usable ref or definition left to try.
- If a plausible candidate exists but duplicates or near-duplicates also match, treat it as ambiguity and improve the CV attributes. Try these in order, skipping steps that do not apply:

1. Tighten stable `CvText` when the target has text and the current text is too generic:

   ```bash
   cli target-anchorable update-definition --definition-file-path "$TARGET_FILE" --cv-text "$MORE_SPECIFIC_TEXT"
   ```

   `CvText` pattern support: `*` matches zero or more characters, `?` matches exactly one, and bare text (no `*`/`?`) is a case-insensitive substring match. Other regex metacharacters (`.`, `^`, `$`, `[]`, `|`, etc.) are matched literally, not as regex. Fuzzy matching is always on, governed by `CvTextAccuracy` (greater than 0, at most 1; default 0.7) — a wildcard also tightens the fuzzy branch, so keeping only the distinctive span of a caption is a valid de-ambiguation move.

2. Raise text accuracy when candidates have different visible captions and fuzzy text matches are colliding:

   ```bash
   cli target-anchorable update-definition --definition-file-path "$TARGET_FILE" --cv-text-accuracy $CV_TEXT_ACCURACY
   ```

3. Set occurrence only for true duplicate captions, after enumerating the intended 1-based position top-to-bottom, left-to-right. Do not use occurrence for textless controls.

   ```bash
   cli target-anchorable update-definition --definition-file-path "$TARGET_FILE" --cv-text-occurrence $CHOSEN_OCCURRENCE
   ```

4. Add a distinctive nearby anchor, especially for textless controls (`InputBox`, `Cell`, `TableCell`, icons). Pick anchor text that does not collide with sibling captions.

   ```bash
   cli target-anchorable add-anchor --element-ref "$AREF" --window-ref "$WREF" --definition-file-path "$TARGET_FILE"
   ```

   `add-anchor` prints `Anchor added at index {N}.` Parse that slot. It also accepts `--name`, `--description`, and `--validate`; with `--validate`, the validation messages above are appended. Do not pass `--folder-path`; this command does not define it.

   Refine an anchor with:

   ```bash
   cli target-anchorable update-anchor-definition --definition-file-path "$TARGET_FILE" --index $SLOT --cv-text "$ANCHOR_TEXT"
   ```

   `update-anchor-definition` prints `Anchor at index {N} updated.` and appends validation messages only when `--validate` is passed. If one anchor does not resolve the ambiguity, add a second anchor with different relative geometry rather than reinforcing the same side of the target.

`update-definition` succeeds silently unless `--validate` is passed; with `--validate`, it prints the same found/not-found and screenshot messages as `target-anchorable validate`.

After each change (`--cv-text`, `--cv-text-accuracy`, `--cv-text-occurrence`, `add-anchor`, or `update-anchor-definition`), validate again and verify the screenshot when one is printed. Do not mark an element `NOT_FOUND` solely because the initial default CV definition failed; reserve `NOT_FOUND` for absent/no-usable-ref cases, and use `AMBIGUOUS` when duplicate candidates remain after refinement. Do not register an unverified or wrong-element definition.

### Output

Return only this block, with one line per original CV element index:

```text
CV-RESULTS:
$INDEX $STATUS $WORK_FOLDER/target-${INDEX}.xaml [caption="..." screenshot="..." | no_improve=true | reason="..."]
```

Statuses:

- `RESOLVED`: validation found the intended element, or `$NO_IMPROVE=true` produced a definition. Include `caption` and `screenshot` when validation ran and a screenshot path was printed; use `no_improve=true` when validation was skipped.
- `AMBIGUOUS`: a definition exists, but validation still cannot distinguish the intended candidate. Include candidate refs/reason.
- `NOT_FOUND`: no confident ref or usable definition was produced. Include candidate refs considered when available.
- `ERROR`: a CLI command or CV service failed outside the normal ambiguous/not-found cases. Include the CLI error text.

Do not add prose around `CV-RESULTS:`; the parent flow parses it verbatim.
