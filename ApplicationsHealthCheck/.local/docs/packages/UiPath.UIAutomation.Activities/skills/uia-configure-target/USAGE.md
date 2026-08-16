# uia-configure-target — invocation

The skill is invoked by an agent to ensure a screen (and optionally one or more elements) exist in the Object Repository. It returns the OR reference ID(s) for workflow attachment.

## Invocation modes

- **TargetAnchorable** (element within a window — Click, TypeInto, GetText, etc.):

  ```
  --window <description> --elements <description>
  ```

- **TargetApp** (window only — Use Application/Browser):

  ```
  --window <description>
  ```

- **Disable CV fallback** (fail/prompt instead of falling back to CV when selector resolution can't produce a confident result):

  ```
  --window <description> --elements <description> --cv false
  ```

  Use this only when selector-only resolution is required.

## Automatic CV fallback

CV fallback is **enabled by default** (pass `--cv false` to disable it). The skill falls back to CV per element when selector-based resolution cannot produce a confident result:

- The element description has no clear match in the live tree (after the UIA-framework retry and a screenshot disambiguation pass).
- The selector that was produced is still `NEEDS_IMPROVEMENT` after the snapshot-retry and the uia-improve-selector subagent pass.

In both cases, with fallback enabled the skill silently moves the element to the CV track instead of stopping or prompting; with `--cv false` it surfaces the failure to the user instead. Elements that resolve cleanly via selectors stay on the selector track. The final OR registration mixes both kinds freely.

## Batch element configuration

Separate multiple element descriptions with `|` in a single `--elements` value to capture the window once and reuse it for all elements:

```
--window <description> --elements "element one | element two | element three"
```

Batch invocation avoids redundant window captures and screen lookups when multiple elements live on the same screen. The batch may end up with a mix of selector-based and CV-based elements after automatic fallback.

## Multi-screen capture sessions

The skill returns the screen reference ID alongside the element IDs. When capturing several UI states of the **same window** (advance → capture → advance), pass that ID back on every subsequent invocation:

```
--window <description> --elements "..." --screen-reference-id <id-from-first-invocation>
```

This skips the Object Repository screen lookup on every screen after the first. Combined with batch `|` elements, each screen runs the same short set of chained invocations. Omit the flag when the window (application) changes — the skill then searches the OR as usual.

- **Advance ONLY via the interact CLI** acting on elements visible in the live app (e.g. click the control that leads to the next state). NEVER navigate by typing a URL from memory or training knowledge — the next state is reached by interacting with what was captured, not by guessing addresses. NEVER run a partial workflow (`uip rpa run` / `debug start`) to advance state — the run lifecycle can close the application.
- **Complete-then-advance:** finish the current screen's capture AND Object Repository registration before advancing the app.
- **Returning refs per screen is not an instruction to author per screen.** Follow the calling skill's phase ordering — on capture-first tasks, capture ALL screens before any workflow authoring.

## What the skill does

Searches the Object Repository for existing matches before creating new entries, generates selectors from the live application tree (or CV-based element targets, when selector resolution fails and CV fallback is enabled), optionally improves and anchors them, and registers everything in the OR. After completion, the skill returns the reference ID(s) — one per element, plus the screen reference.

## Unsupported activities

This skill does not configure targets for the following activities:

- **UI Automation.Semantic**: Fill Form, Update UI Element, Close Popup, Extract Form Data, Extract UI Data
- **Extract Table Data**

## Full argument reference

`SKILL.md` (sibling file) documents every argument with defaults and valid values, including `--screen-reference-id`, `--cv`, `--semantic`, `--no-improve`, and `--project-dir`. The CV sub-procedure invoked via automatic fallback is documented in the **CV Element Resolution** section of [`SKILL.md`](SKILL.md#cv-element-resolution-sub-procedure).
