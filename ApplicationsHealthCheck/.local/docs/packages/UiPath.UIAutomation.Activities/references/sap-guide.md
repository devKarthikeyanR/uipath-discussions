# SAP Automation Guide

Cross-cutting guidance for automating SAP with UI Automation — **SAP GUI (WinGUI)** desktop and **SAP web** (Fiori/UI5, Web GUI, Ariba). For per-activity details see the SAP activities (SAP Logon, SAP Login, Call Transaction, Read Status Bar, …) in the [activities reference](../activities/).

## Input mode: use Simulate for SAP

Simulate is the recommended input mode for SAP (WinGUI and web). For WinGUI it changes how it waits for SAP:

- **Hardware Events** injects OS-level mouse/keyboard input and returns as soon as the input is dispatched — *fire-and-forget*. A click that triggers a server-side step (a transaction, a long-running report) returns immediately, before SAP finishes.
- **Simulate** drives the element through the **SAP Scripting API** (WinGUI or web - when available), which is **synchronous**.

Set it once at the project level — **Project Settings → UI Automation Modern → Targeting methods → SAP → Input mode → Simulate** — or per activity via `InteractionMode` (see [NInteractionMode](../activities/common/NInteractionMode.md)).

Use the Default UI framework to utilize SAP GUI Scripting.

Some control-action pairs won't support Simulate and return an explicit error. Use HardwareEvents for those.

## SAP GUI (WinGUI)

**Prerequisite:** SAP GUI Scripting must be enabled on both server and client. Setup: https://docs.uipath.com/activities/other/latest/ui-automation/sap-wingui-configuration-steps

- **The status bar is the confirmation channel.** SAP reports operation outcomes — success `S`, error `E`, warning `W`, info `I`, abort `A` — on the status bar. Read it after an action to confirm success and surface errors; the read is also a synchronous round-trip, so it doubles as a wait point.
- **Tables expose only visible rows.** A snapshot/scrape sees only the rows in view. Use **Extract Table** for the full dataset.
- **Use longer timeouts** for SAP operations than for typical desktop/web apps.
- **Never pass the SAP login password as a command-line value** (it leaks into argv, shell history, and logs). With `interact sap login`, pipe it via `--password-stdin` — e.g. `Get-Content secret.txt | uip rpa uia interact sap login <w-ref> --user <name> --client <nnn> --language <xx> --password-stdin` — or name an environment variable with `--password-env <VAR>`.
- **Ensure a clean state while authoring.** A clean state reduces unexpected errors and makes authoring **faster**. Never skip it.
  - **Workflows:** use `NSAPLogon` with `OpenMode="Always"`; `CloseMode="Never"` while authoring so that end state stays visible, then close the session before each new run.  Don't try `OpenMode="IfNotOpen"` or `OpenMode="Never"` since SapLogon always opens a new session window. Switch to `CloseMode="Always"` once the test is stable.
  - **Exploration:** use `interact sap logon` to open a fresh session, close every window whose `sapSysSessionId` differs from it, then `interact sap login`.

## Discovering control items (`interact get … items`)

Several SAP controls don't expose their inner entries as separate snapshot nodes — read them with `uip rpa uia interact get <ref> items` (or `get-all`) and pass a returned value as the activity's `Item`:

- **Toolbar buttons** — `get <toolbarRef> items` → the button identifiers, for **Click Toolbar Button**.
- **Dropdown / combobox entries** — `get <comboRef> items` → the selectable entries, for **Select Item**.
- **Menu items** — `get <menuBarRef> items` (the menu-bar element) returns the full slash-separated menu paths. Navigate ad-hoc with `interact select <menuBarRef> "<menu/path>"`, or pass a path to the **Select Menu Item** activity.

## Target configuration

- NSAPLogon, NSAPLogin, NSAPCallTransaction, and NSAPReadStatusBar do not require target configuration as they address SAP through the connection and session, not a captured selector. 
- **Prefer `[sap]`-tagged nodes.** SAP web framework elements (Fiori/UI5, Web GUI, Ariba) carry richer, more stable attributes than generic HTML, so they produce more reliable selectors. 
- **SAP session window:** `<wnd app='saplogon.exe' cls='SAP_FRONTEND_SESSION' />`
- **Modal dialogs are their own window.** A SAP popup is a separate OS window with same `sapSysSessionId` as the session, title = the dialog caption and `cls='#32770'`.

## Other Gotchas

- **SAP UI5 autocomplete re-renders.** When selecting from a combobox/autocomplete dropdown, the list can re-render briefly after typing; give the click on the dropdown item a small `DelayBefore` (and use Simulate) so it doesn't hit a stale node.
- **Use [Select Menu Item](../activities/SAPSelectMenuItem.md)** for menu navigation. A direct menu-bar selector, like `<sap id='mbar/menu[a]/menu[b]'/>`, is positional and will shift between screens (the System menu may be `menu[4]` on SAP Easy Access but `menu[3]` elsewhere).
- **Context menus are a native `#32768` popup.** Right-click the target with **HardwareEvents** to open it; the menu appears as a separate `#32768` window. Read and click its `MenuItem`s with `--framework UIA`.

## See also

- [NInteractionMode](../activities/common/NInteractionMode.md) / [NChildInteractionMode](../activities/common/NChildInteractionMode.md) — input-mode values.
- SAP activities: [SAP Logon](../activities/SAPLogon.md), [SAP Login](../activities/SAPLogin.md), [Call Transaction](../activities/SAPCallTransaction.md), [Read Status Bar](../activities/SAPReadStatusbar.md), and the rest in the [activities reference](../activities/).
