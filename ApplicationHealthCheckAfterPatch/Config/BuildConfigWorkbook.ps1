<#
    One-time generator for Config.xlsx.
    Run this script once (or after schema changes) to (re)build the workbook.
    Requires Excel installed locally. Does not touch any other project folder.

    Holds only the pure framework/run settings: GlobalConfig. The Applications list
    and its per-app TC_<AppName> scenario sheets live in Applications.xlsx instead —
    see BuildApplicationsWorkbook.ps1.
#>

$ErrorActionPreference = "Stop"
$outPath = Join-Path $PSScriptRoot "Config.xlsx"

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

# --- Sheet 1: GlobalConfig (key/value) ---
$gcHeaders = @("Key","Value")
$gcRows = @(
    [ordered]@{Key="RunFolderRoot";Value="C:\HealthCheck"}
    [ordered]@{Key="DefaultReportRecipients";Value="health-check-team@example.com"}
    [ordered]@{Key="DefaultCleanupMode";Value="Delete"}
    [ordered]@{Key="DefaultNotifyEmail";Value="health-check-team@example.com"}
    [ordered]@{Key="TriggerMode";Value="Adhoc"}
)
Write-Sheet -Workbook $wb -Name "GlobalConfig" -Index 1 -Headers $gcHeaders -Rows $gcRows | Out-Null

# Remove any extra default sheets beyond the 1 we defined
while ($wb.Sheets.Count -gt 1) {
    $wb.Sheets.Item($wb.Sheets.Count).Delete()
}

$wb.Sheets.Item(1).Select()
$wb.SaveAs($outPath, 51)  # 51 = xlOpenXMLWorkbook (.xlsx)
$wb.Close($false)
$excel.Quit()

[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
Write-Output "Created $outPath"
