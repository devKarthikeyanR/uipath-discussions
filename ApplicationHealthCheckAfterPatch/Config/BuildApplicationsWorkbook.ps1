<#
    One-time generator for Applications.xlsx.
    Run this script once (or after schema changes) to (re)build the workbook.
    Requires Excel installed locally. Does not touch any other project folder.

    Holds the "Applications list and its operations" sheets: Applications, plus one
    TC_<AppName> scenario sheet per app (e.g. TC_Outlook). Add future TC_<AppName>
    sheets here, not in Config.xlsx.
#>

$ErrorActionPreference = "Stop"
$outPath = Join-Path $PSScriptRoot "Applications.xlsx"

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $excel.Workbooks.Add()

function Write-Sheet {
    # $Rows is an array of ordered hashtables (one per row), each keyed by header name.
    # Using named lookups instead of positional nested arrays avoids PowerShell's
    # parameter-binding flattening of array-of-arrays into a single flat list.
    param($Workbook, [string]$Name, [int]$Index, [string[]]$Headers, [System.Collections.Specialized.OrderedDictionary[]]$Rows)

    if ($Index -le $Workbook.Sheets.Count) {
        $ws = $Workbook.Sheets.Item($Index)
        $ws.Name = $Name
    } else {
        $ws = $Workbook.Sheets.Add([System.Reflection.Missing]::Value, $Workbook.Sheets.Item($Workbook.Sheets.Count))
        $ws.Name = $Name
    }

    for ($c = 0; $c -lt $Headers.Count; $c++) {
        $cell = $ws.Cells.Item(1, $c + 1)
        $cell.Value2 = $Headers[$c]
        $cell.Font.Bold = $true
        $cell.Interior.Color = 15773696  # light blue
    }

    for ($r = 0; $r -lt $Rows.Count; $r++) {
        $rowObj = $Rows[$r]
        for ($c = 0; $c -lt $Headers.Count; $c++) {
            $val = $rowObj[$Headers[$c]]
            $cell = $ws.Cells.Item($r + 2, $c + 1)
            if ($val -is [int] -or $val -is [double]) {
                $cell.Value2 = [double]$val
            } else {
                $cell.Value2 = [string]$val
            }
        }
    }

    $used = $ws.UsedRange
    $used.Columns.AutoFit() | Out-Null
    $ws.Rows.Item(1).AutoFilter() | Out-Null
    return $ws
}

# --- Sheet 1: Applications ---
$appHeaders = @("AppID","AppName","ExePath","LaunchArgs","Enabled","MaxRetries","TimeoutSec","CleanupMode","NotifyEmail")
$appRows = @(
    [ordered]@{AppID="APP001";AppName="Outlook";ExePath="C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE";LaunchArgs="";Enabled="Y";MaxRetries=1;TimeoutSec=120;CleanupMode="Delete";NotifyEmail="outlook-owner@example.com"}
    [ordered]@{AppID="APP002";AppName="Teams";ExePath="C:\Program Files\Microsoft\Teams\current\Teams.exe";LaunchArgs="";Enabled="N";MaxRetries=1;TimeoutSec=120;CleanupMode="Delete";NotifyEmail="teams-owner@example.com"}
)
Write-Sheet -Workbook $wb -Name "Applications" -Index 1 -Headers $appHeaders -Rows $appRows | Out-Null

# --- Sheet 2: TC_Outlook (scenario sheet, one per app; naming convention TC_<AppID or AppName>) ---
$tcHeaders = @("ScenarioID","ScenarioName","Enabled","Operation","CorrelatesWithScenarioID","InputData","TargetRecipient","AttachmentSourcePath","SelectorHint","TimeoutSec","PollIntervalSec","RetryCount","RetryOnTimeoutOnly","Priority")
$tcRows = @(
    [ordered]@{ScenarioID="OL-S01";ScenarioName="Send Test Email";Enabled="Y";Operation="SendEmail";CorrelatesWithScenarioID="";InputData="Health check test email - {token}";TargetRecipient="self";AttachmentSourcePath="";SelectorHint="";TimeoutSec=30;PollIntervalSec=0;RetryCount=0;RetryOnTimeoutOnly="N";Priority=1}
    [ordered]@{ScenarioID="OL-V01";ScenarioName="Verify Test Email Received";Enabled="Y";Operation="VerifyReceive";CorrelatesWithScenarioID="OL-S01";InputData="";TargetRecipient="self";AttachmentSourcePath="";SelectorHint="";TimeoutSec=120;PollIntervalSec=10;RetryCount=1;RetryOnTimeoutOnly="Y";Priority=2}
    [ordered]@{ScenarioID="OL-S02";ScenarioName="Send Email With Attachment";Enabled="Y";Operation="SendEmail";CorrelatesWithScenarioID="";InputData="Health check attachment test - {token}";TargetRecipient="self";AttachmentSourcePath="C:\HealthCheck\SampleFiles\test-attachment.pdf";SelectorHint="";TimeoutSec=30;PollIntervalSec=0;RetryCount=0;RetryOnTimeoutOnly="N";Priority=3}
    [ordered]@{ScenarioID="OL-V02";ScenarioName="Verify Attachment Received";Enabled="Y";Operation="VerifyReceiveAttachment";CorrelatesWithScenarioID="OL-S02";InputData="";TargetRecipient="self";AttachmentSourcePath="test-attachment.pdf";SelectorHint="";TimeoutSec=120;PollIntervalSec=10;RetryCount=1;RetryOnTimeoutOnly="Y";Priority=4}
)
Write-Sheet -Workbook $wb -Name "TC_Outlook" -Index 2 -Headers $tcHeaders -Rows $tcRows | Out-Null

# Remove any extra default sheets beyond the 2 we defined
while ($wb.Sheets.Count -gt 2) {
    $wb.Sheets.Item($wb.Sheets.Count).Delete()
}

$wb.Sheets.Item(1).Select()
$wb.SaveAs($outPath, 51)  # 51 = xlOpenXMLWorkbook (.xlsx)
$wb.Close($false)
$excel.Quit()

[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
Write-Output "Created $outPath"
