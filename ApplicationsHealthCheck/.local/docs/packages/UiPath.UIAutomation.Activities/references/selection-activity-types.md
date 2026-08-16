# Selection Activity Types

The activity type tells the CLI what the workflow will do with a target element, which tunes the default selector it generates. It is passed per element as the `activityType` field in the `--refs` JSON of `target-anchorable resolve-defaults` (see [`uia-configure-target`](../skills/uia-configure-target/SKILL.md), TARGET-6).

Pick the value matching how the element will be used (from its description and the surrounding request); default to `None` when unclear. Values are case-sensitive — use the exact spelling below; an unrecognized value falls back to `None`. Only element-targeting interactions apply; SAP, Semantic (Fill Form, …) and Extract Table Data are out of scope (see USAGE.md).

### Neutral — no activity-specific tuning

| `activityType` | Interaction | Choose when |
|---|---|---|
| `None` | No specific interaction | The intended interaction is unknown, or none of the types below fit. Produces a neutral, untuned selector. |

### Pointer / focus / visual — no attribute restrictions

| `activityType` | Interaction | Choose when |
|---|---|---|
| `Click` | Click an element | The element is pressed/activated (buttons, links, menu items). |
| `Hover` | Hover over an element | The workflow only needs to move the pointer over it. |
| `Highlight` | Visually highlight an element | The element is highlighted for demonstration/debugging. |
| `SetFocus` | Put keyboard focus on an element | The element only needs focus, without typing. |
| `TakeScreenshot` | Capture an element's image | A screenshot of the element is taken. |
| `MouseScroll` | Scroll over an element | The element is the scroll target. |
| `DragAndDrop` | Drag the element / drop onto it | The element is a drag source or drop destination. |
| `KeyboardShortcut` | Send keystrokes to an element | Keys are sent while the element holds focus. |
| `InjectJsScript` | Run JavaScript against an element | A script is injected targeting the element. |
| `GetAttribute` | Read an attribute value | An arbitrary attribute is read (does not identify by content). |

### Text read/write — avoid content-reflecting attributes (`text`, `aaname`, `visibleinnertext`, `innertext`)

| `activityType` | Interaction | Choose when |
|---|---|---|
| `TypeInto` | Type text into a field | The element is a text input the workflow fills. |
| `SetText` | Set a field's text directly | Text is written without simulated typing. |
| `GetText` | Read text from an element | The element's text content is read. |

### Checkbox / toggle — avoid state attributes (`checked`, `aastate`)

| `activityType` | Interaction | Choose when |
|---|---|---|
| `Check` | Check / uncheck a control | The element is a checkbox or radio button being toggled. |
| `CheckState` | Read a control's state | The element's checked/enabled state is read without changing it. |

### Selection — avoid value attributes (`selecteditem`, `value`)

| `activityType` | Interaction | Choose when |
|---|---|---|
| `SelectItem` | Select an option | The element is a dropdown / combo box / list whose option is chosen. |

### Presence / multiplicity / scope

| `activityType` | Interaction | Choose when |
|---|---|---|
| `CheckElement` | Verify an element's presence/state | The workflow checks whether the element exists / is in a given state. |
| `FindElements` | Find all matching elements | The selector is meant to match a **set** of elements — do not over-constrain it to a single instance. |
| `ForEachUiElement` | Iterate over matching elements | The workflow loops over every element matching the selector. Like `FindElements`, the selector matches a set. |
| `ElementScope` | Scope subsequent actions to a container | The element is a container that scopes nested activities. |

### Triggers — monitor an element for an event (strict selector only)

| `activityType` | Interaction | Choose when |
|---|---|---|
| `ClickTrigger` | Fire when the element is clicked | The element is watched for clicks in a trigger scope. |
| `KeyboardTrigger` | Fire on a key press | The element is watched for keyboard input. |
| `NativeTrigger` | Fire on a native UI event | The element is watched for a native UI event. |

### Window-level

| `activityType` | Interaction | Choose when |
|---|---|---|
| `WindowOperations` | Operate on a window | The target is a window (minimize/maximize/move/close), not an inner element. |
