### Documentation is included in the Documentation folder ###


## Application Health Check After Patch

Runs on a dedicated, always-on-SSO test machine after a Windows patch. For each enabled
application in `Config\Config.xlsx` ("Applications" sheet), launches the app and runs its
scenario sheet (e.g. `TC_Outlook`), verifying real user operations still work post-patch
(send email, receive email, attachments). One app failing does not stop the others — each
is isolated in its own Try/Catch/Finally. Produces a holistic per-app summary email (every
scenario listed, pass or fail) plus a master HTML report across all apps, saved under
`<RunFolderRoot>\<yyyyMMdd>\Run_<HHmmss>\Configs|Evidence|Reports`.

This is a **tabular-mode** REFramework: `GetTransactionData.xaml` reads one row per enabled
application from `Config\Config.xlsx` instead of an Orchestrator queue — there is no queue
to configure. Trigger is adhoc only (Orchestrator "Start Job"); no scheduling is wired up.

**Config schema** (`Config\Config.xlsx`, rebuild via `Config\BuildConfigWorkbook.ps1` if changed):
- `Applications`: AppID, AppName, ExePath, LaunchArgs, Enabled, MaxRetries, TimeoutSec, CleanupMode, NotifyEmail
- `TC_<AppName>` (one per app, e.g. `TC_Outlook`): ScenarioID, ScenarioName, Enabled, Operation,
  CorrelatesWithScenarioID, InputData, TargetRecipient, AttachmentSourcePath, SelectorHint,
  TimeoutSec, PollIntervalSec, RetryCount, RetryOnTimeoutOnly, Priority
- `GlobalConfig`: RunFolderRoot, DefaultReportRecipients, DefaultCleanupMode, DefaultNotifyEmail, TriggerMode

Send/Verify scenario pairs are matched with a correlation token (`HC-{RunID}-{AppID}-{ScenarioID}-{timestamp}`)
embedded in the email subject on send, and polled for on the paired verify step (`Get Text` /
list extraction on the inbox) up to `TimeoutSec` at `PollIntervalSec` intervals. If a verify
step times out and `RetryOnTimeoutOnly=Y` with `RetryCount>0`, the send+verify pair retries —
a hard UI error does not retry.

**Outlook is Outlook Classic (`OUTLOOK.EXE`), not New Outlook** — selectors differ.

### Status — what's implemented vs. what needs Studio work

Everything below builds/validates clean via `uip rpa build` **except** the Outlook UI
interaction steps, which use UiPath's documented Placeholder-Selector Stub Pattern: real
UI Automation activities with `TODO Indicate` markers instead of captured selectors, since
this was authored without a live, human-driven Outlook Classic session to capture against.

**Before this can run against real Outlook**, open these files in Studio with Outlook
Classic running and click **Indicate** on every activity whose display name starts with
`TODO Indicate`:
- `Applications\Outlook\Outlook_SendEmail.xaml` — New Email button, To/Subject/Body fields, Send button
- `Applications\Outlook\Outlook_AddAttachment.xaml` — same, plus the Attach/Insert File dialog
- `Applications\Outlook\Outlook_VerifyReceive.xaml` — Inbox folder, subject-list read target
- `Applications\Outlook\Outlook_VerifyReceiveAttachment.xaml` — same, plus attachment-list read target
- `Applications\Outlook\Outlook_Close.xaml` — the app-attach target has no selector set yet

Also worth a look before first real run:
- `Reporting\EmailReport.xaml` sends the report body via Type Into (plain text) — HTML markup
  will not render in the sent mail as-is; needs a clipboard-paste or Outlook-native HTML body approach.
- `UiPath.UIAutomation.Activities` is pinned to `26.10.1` in `project.json`; consider upgrading
  before the Indicate pass if Studio suggests a newer version.
- `TC_Outlook` scenario execution follows the sheet's row order — if you reorder rows, `Priority`
  is descriptive only and not enforced by an explicit sort.
- Teams has a placeholder row in `Applications` (`Enabled=N`) but no scenario sheet or app-library
  workflows yet — out of scope for this pass.

Run with:
```
uip rpa run --file-path "Main.xaml" --project-dir "<this folder>"
```


### REFrameWork Template ###
**Robotic Enterprise Framework**

* Built on top of *Transactional Business Process* template
* Uses *State Machine* layout for the phases of automation project
* Offers high level logging, exception handling and recovery
* Keeps external settings in *Config.xlsx* file and Orchestrator assets
* Pulls credentials from Orchestrator assets and *Windows Credential Manager*
* Gets transaction data from Orchestrator queue and updates back status
* Takes screenshots in case of system exceptions


### How It Works ###

1. **INITIALIZE PROCESS**
 + ./Framework/*InitiAllSettings* - Load configuration data from Config.xlsx file and from assets
 + ./Framework/*GetAppCredential* - Retrieve credentials from Orchestrator assets or local Windows Credential Manager
 + ./Framework/*InitiAllApplications* - Open and login to applications used throughout the process

2. **GET TRANSACTION DATA**
 + ./Framework/*GetTransactionData* - Fetches transactions from an Orchestrator queue defined by Config("OrchestratorQueueName") or any other configured data source

3. **PROCESS TRANSACTION**
 + *Process* - Process trasaction and invoke other workflows related to the process being automated 
 + ./Framework/*SetTransactionStatus* - Updates the status of the processed transaction (Orchestrator transactions by default): Success, Business Rule Exception or System Exception

4. **END PROCESS**
 + ./Framework/*CloseAllApplications* - Logs out and closes applications used throughout the process


### For New Project ###

1. Check the Config.xlsx file and add/customize any required fields and values
2. Implement InitiAllApplications.xaml and CloseAllApplicatoins.xaml workflows, linking them in the Config.xlsx fields
3. Implement GetTransactionData.xaml and SetTransactionStatus.xaml according to the transaction type being used (Orchestrator queues by default)
4. Implement Process.xaml workflow and invoke other workflows related to the process being automated
