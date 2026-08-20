<#
    One-time generator for Config.xlsx.
    Run this script once (or after schema changes) to (re)build the workbook.
    Requires Excel installed locally. Does not touch any other project folder.
#>

$ErrorActionPreference = "Stop"
$outPath = Join-Path $PSScriptRoot "Config.xlsx"

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $excel.Workbooks.Add()

function Write-Sheet {
    param($Workbook, [string]$Name, [int]$Index, [array]$Headers, [array[]]$Rows)

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
        $row = ,$Rows[$r]
        $row = $row[0]
        for ($c = 0; $c -lt $row.Count; $c++) {
            $val = $row[$c]
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
    @("APP001","Outlook","C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE","","Y",1,120,"Delete","outlook-owner@example.com")
    @("APP002","Teams","C:\Program Files\Microsoft\Teams\current\Teams.exe","","N",1,120,"Delete","teams-owner@example.com")
)
Write-Sheet -Workbook $wb -Name "Applications" -Index 1 -Headers $appHeaders -Rows $appRows | Out-Null

# --- Sheet 2: TC_Outlook (scenario sheet, one per app; naming convention TC_<AppID or AppName>) ---
$tcHeaders = @("ScenarioID","ScenarioName","Enabled","Operation","CorrelatesWithScenarioID","InputData","TargetRecipient","AttachmentSourcePath","SelectorHint","TimeoutSec","PollIntervalSec","RetryCount","RetryOnTimeoutOnly","Priority")
$tcRows = @(
    @("OL-S01","Send Test Email","Y","SendEmail","", "Health check test email - {token}","self","","",30,0,0,"N",1)
    @("OL-V01","Verify Test Email Received","Y","VerifyReceive","OL-S01","","self","","",120,10,1,"Y",2)
    @("OL-S02","Send Email With Attachment","Y","SendEmail","", "Health check attachment test - {token}","self","C:\HealthCheck\SampleFiles\test-attachment.pdf","",30,0,0,"N",3)
    @("OL-V02","Verify Attachment Received","Y","VerifyReceiveAttachment","OL-S02","","self","test-attachment.pdf","",120,10,1,"Y",4)
)
Write-Sheet -Workbook $wb -Name "TC_Outlook" -Index 2 -Headers $tcHeaders -Rows $tcRows | Out-Null

# --- Sheet 3: GlobalConfig (key/value) ---
$gcHeaders = @("Key","Value")
$gcRows = @(
    @("RunFolderRoot","C:\HealthCheck")
    @("DefaultReportRecipients","health-check-team@example.com")
    @("DefaultCleanupMode","Delete")
    @("DefaultNotifyEmail","health-check-team@example.com")
    @("TriggerMode","Adhoc")
)
Write-Sheet -Workbook $wb -Name "GlobalConfig" -Index 3 -Headers $gcHeaders -Rows $gcRows | Out-Null

# Remove any extra default sheets beyond the 3 we defined
while ($wb.Sheets.Count -gt 3) {
    $wb.Sheets.Item($wb.Sheets.Count).Delete()
}

$wb.Sheets.Item(1).Select()
$wb.SaveAs($outPath, 51)  # 51 = xlOpenXMLWorkbook (.xlsx)
$wb.Close($false)
$excel.Quit()

[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
Write-Output "Created $outPath"
