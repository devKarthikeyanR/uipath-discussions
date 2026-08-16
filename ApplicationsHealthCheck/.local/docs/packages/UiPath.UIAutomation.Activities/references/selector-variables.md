# Selector Variables

How to inject variable/argument values into selector text. The form depends on **how** you are editing the selector:

- In an **XAML** authored by hand (the value lives in an `InArgument<string>`) → you write the `string.Format` wrapper yourself. (The selector *text* inside it still comes only from a configured target — see the hard rule below.)
- In a **definition file** (`window.xaml` / `target-n.xaml`) → **never hand-edit the file.** Run the `update-definition` CLI command and pass the selector with `{{variableName}}` curly-bracket tokens; the command converts them to `string.Format` and rewrites the definition.

Both forms come to rest as the same `string.Format` `InArgument` and resolve to the same selector at runtime. The `{{variableName}}` syntax is only the *input* the CLI accepts — it is **not** what ends up stored on disk.

> **Important:** Every variable referenced from a selector — in either form — must be declared in the XAML, either as an argument or as a variable on an enclosing activity (for example, the parent `Sequence`). The runtime resolves variables against the activity context; tokens that cannot be resolved fall back to literal text.

> **Definition files are produced and consumed only by the [`uia-configure-target`](../skills/uia-configure-target/SKILL.md) skill** (`window.xaml`, `target-n.xaml`), and the only supported way to mutate them is the CLI — `target-app update-definition` for a window, `target-anchorable update-definition` for an element. Outside of that flow — i.e. when authoring or editing an XAML directly — selector variables live in an InArgument and you write the `string.Format` form by hand.

## Hard rule: only parametrize a configured target — never hand-add an attribute

Selector *text* (tags and attributes) comes **only** from target configuration: `resolve-defaults` probes the live element, and the `uia-improve-selector` subagent hardens it. Never compose a selector, edit its attribute set, or add an attribute yourself — in either form (XAML `InArgument` or definition file). The `string.Format` / `{{variable}}` wrapping only binds a variable into a value position; it never licenses writing or altering the selector text.

So:

1. **Only parametrize a target configured with [`uia-configure-target`](../skills/uia-configure-target/SKILL.md).** Never parametrize a selector you authored by hand.
2. **Parametrizing replaces a value — it never adds an attribute.**

### Choosing how to parametrize

Find the attribute whose value must vary, read the configured selector, and follow the first row that matches:

| Attribute to parametrize | Action |
|--------------------------|--------|
| **Already present** (strict or fuzzy) | Swap that literal value for a `{{variable}}` token via `update-definition`, keeping the exact attribute set. |
| **Missing from a strict selector** (`SearchSteps` contains `Selector`) | Run the `uia-improve-selector` subagent and name the attribute to add and parametrize in its `$ATTR_INFO`. |
| **Missing from a fuzzy selector** (`SearchSteps` is `FuzzySelector`) | The subagent can't act on a fuzzy selector. Parametrize a different attribute already present that expresses the same variation, or **abort** — never hand-add the attribute. |

Give the subagent context: which element it targets (`$NODE_INFO`) and the attribute to add/parametrize (`$ATTR_INFO`). See [`uia-configure-target`](../skills/uia-configure-target/SKILL.md) TARGET-7, section 7.3.

## In XAML

The InArguments that carry selector text and support variable interpolation are:

- `Selector` — selector on a `TargetApp` (Use Application/Browser). This is the only property on `TargetApp` that supports variables.
- `ScopeSelectorArgument` — window selector on a `TargetAnchorable`.
- `FullSelectorArgument` — strict element selector on a `TargetAnchorable`.
- `FuzzySelectorArgument` — fuzzy element selector on a `TargetAnchorable`.

When the selector value is provided through one of these `InArgument<string>`s, the expression must follow `string.Format` rules:

- Positional placeholders: `{0}`, `{1}`, …
- Each placeholder is bound, in order, to the variables listed after the format string.
- Literal `{` and `}` must be escaped as `{{` and `}}`.

VB expression:

```text
String.Format("<webctrl id='{0}' tag='{1}' />", elementId, tagName)
```

C# expression:

```text
string.Format("<webctrl id='{0}' tag='{1}' />", elementId, tagName)
```

A single-variable selector is also accepted as the bare variable name (no `string.Format` wrapper):

```text
mySelector
```

### XAML example

The formatted expression goes into `ScopeSelectorArgument` / `FullSelectorArgument` / `FuzzySelectorArgument` on a `TargetAnchorable`:

```xml
<uix:TargetAnchorable Version="V6">
  <uix:TargetAnchorable.ScopeSelectorArgument>
    <InArgument x:TypeArguments="x:String">[string.Format("&lt;wnd app='chrome.exe' title='{0} - Google Chrome' /&gt;", pageTitle)]</InArgument>
  </uix:TargetAnchorable.ScopeSelectorArgument>
  <uix:TargetAnchorable.FullSelectorArgument>
    <InArgument x:TypeArguments="x:String">[string.Format("&lt;webctrl id='{0}' tag='BUTTON' /&gt;", elementId)]</InArgument>
  </uix:TargetAnchorable.FullSelectorArgument>
  <uix:TargetAnchorable.FuzzySelectorArgument>
    <InArgument x:TypeArguments="x:String">[string.Format("&lt;webctrl id='{0}' /&gt;", elementId)]</InArgument>
  </uix:TargetAnchorable.FuzzySelectorArgument>
</uix:TargetAnchorable>
```

For a `TargetApp`, the same applies to `Selector` (the only `TargetApp` property that supports variables):

```xml
<uix:TargetApp Version="V2">
  <uix:TargetApp.Selector>
    <InArgument x:TypeArguments="x:String">[string.Format("&lt;wnd app='chrome.exe' title='{0} - Google Chrome' /&gt;", pageTitle)]</InArgument>
  </uix:TargetApp.Selector>
</uix:TargetApp>
```

## In definition files

A definition is a serialized `TargetApp` (`window.xaml`) or `TargetAnchorable` (`target-n.xaml`) plus a sibling `*.xaml.metadata` file. On disk, the selector lives in an `InArgument` in the **same `string.Format` form as XAML** — definition files do **not** store `{{variable}}` tokens.

**Do not hand-edit definition files, and do not hand-write `string.Format` into them.** To set or change a selector, or to add variables to one, run the `update-definition` CLI command and pass the selector with `{{variableName}}` curly-bracket tokens. The command converts each token to a positional `string.Format` placeholder and rewrites the `.xaml` (and its `.xaml.metadata`) atomically.

The `{{...}}` input syntax:

- The token between `{{` and `}}` must be a valid identifier; otherwise it is treated as literal text.
- The same variable can appear multiple times — every occurrence maps to the same `string.Format` placeholder (`{0}`), and there is exactly one trailing argument per distinct variable.
- A bare single variable (e.g. `mySelector`) is stored as that variable expression directly, with no `string.Format` wrapper.

### Element selector (`target-anchorable`)

`--full-selector` (strict), `--fuzzy-selector`, `--scope-selector` (window scope), and `--semantic-selector` each accept the `{{variable}}` syntax. `--full-selector` and `--fuzzy-selector` are mutually exclusive.

```bash
# resolve-defaults already wrote this into target-1.xaml:
#   FullSelectorArgument = <webctrl data-test='BUN' data-field='result' tag='INPUT' />
# 'data-test' is already present, so swap its value directly:
# replace ONLY the literal 'BUN' -> {{testName}}, keeping the exact attribute set.
uip rpa uia target-anchorable update-definition \
  --definition-file-path "C:/path/to/target-1.xaml" \
  --full-selector "<webctrl data-test='{{testName}}' data-field='result' tag='INPUT' />"
```

`testName` is the variable. After the command runs, `target-1.xaml` holds the converted `string.Format` form:

```xml
<uix:TargetAnchorable.FullSelectorArgument>
  <InArgument x:TypeArguments="x:String">[string.Format("&lt;webctrl data-test='{0}' data-field='result' tag='INPUT' /&gt;", testName)]</InArgument>
</uix:TargetAnchorable.FullSelectorArgument>
```

### Window selector (`target-app`)

`--selector` is the only `TargetApp` property that supports variables.

```bash
uip rpa uia target-app update-definition \
  --definition-file-path "C:/path/to/window.xaml" \
  --selector "<wnd app='chrome.exe' title='{{pageTitle}} - Google Chrome' />"
```

Resulting `window.xaml`:

```xml
<uix:TargetApp.Selector>
  <InArgument x:TypeArguments="x:String">[string.Format("&lt;wnd app='chrome.exe' title='{0} - Google Chrome' /&gt;", pageTitle)]</InArgument>
</uix:TargetApp.Selector>
```

> `update-definition` only swaps a `{{variable}}` token in for a value the configured selector **already** contains — never to write new attributes. If the attribute is missing, follow the decision table in the hard rule above (strict → subagent; fuzzy → swap another present attribute or abort). Never hand-write the attribute set into `--full-selector` / `--fuzzy-selector`. See the [`uia-configure-target`](../skills/uia-configure-target/SKILL.md) skill for the full procedure.

## Conversion between the two forms

| Form | Where it appears | Example |
|------|------------------|---------|
| `{{variable}}` | input you pass to `update-definition` (the CLI/UI "string view") | `<webctrl id='{{x}}' />` |
| `string.Format` | the `InArgument` stored in the XAML / definition file | `string.Format("<webctrl id='{0}' />", x)` |

`update-definition` converts `{{variable}}` → `string.Format` when it writes the definition.
