param(
  [Parameter(Mandatory)] [string] $InPath,
  [Parameter(Mandatory)] [string] $OutPath
)

# Convert a .docx to .pdf using Word COM automation.
# Requires Microsoft Word to be installed.

$ErrorActionPreference = "Stop"
$InPath  = (Resolve-Path -LiteralPath $InPath).Path
$OutPath = [System.IO.Path]::GetFullPath($OutPath)

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0  # wdAlertsNone

try {
  $doc = $word.Documents.Open($InPath, $false, $true)  # ReadOnly = true
  # ExportAsFixedFormat: 17 = wdExportFormatPDF
  $doc.ExportAsFixedFormat($OutPath, 17, $false, 0, 0, 1, 999, 0, $false, $true, 1, $false, $false, $false)
  $doc.Close($false)
  Write-Host "PDF written to: $OutPath"
  Write-Host "Size: $((Get-Item $OutPath).Length) bytes"
} finally {
  $word.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
