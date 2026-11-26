# ==============================================================================
# run_mdx_queries.ps1
# Execute all MDX queries in ssas/mdx/01_olap_mdx_queries.mdx against .\SSAS
# and export verified markdown results to ssas/mdx/mdx_execution_results.md
# ==============================================================================
param(
    [string]$SsasServer = ".\SSAS",
    [string]$OlapDatabase = "HotelBooking_OLAP",
    [string]$MdxFile = "C:\Users\ADMIN\Desktop\Hotel-Booking-Demand\ssas\mdx\01_olap_mdx_queries.mdx",
    [string]$OutMd = "C:\Users\ADMIN\Desktop\Hotel-Booking-Demand\ssas\mdx\mdx_execution_results.md"
)

$ErrorActionPreference = "Stop"
[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.AnalysisServices.AdomdClient")

$raw = Get-Content -Path $MdxFile -Raw -Encoding UTF8
# Split queries on "-- Q" markers
$blocks = [regex]::Split($raw, "(?m)^(?=-- Q\d+\.)") | Where-Object { $_ -match "^-- Q\d+\." }

$conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=$SsasServer;Catalog=$OlapDatabase;")
$conn.Open()

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Kết quả chạy thực tế Bộ Truy Vấn MDX trên SSAS Multidimensional Cube")
[void]$md.AppendLine("")
[void]$md.AppendLine("- **SSAS Server:** ``$SsasServer`` (Multidimensional Mode)")
[void]$md.AppendLine("- **OLAP Database:** ``$OlapDatabase``")
[void]$md.AppendLine("- **Cube:** ``Hotel Booking Cube``")
[void]$md.AppendLine("- **Source MDX:** [01_olap_mdx_queries.mdx](01_olap_mdx_queries.mdx)")
[void]$md.AppendLine("")

$okCount = 0
try {
    foreach ($blk in $blocks) {
        $lines = $blk.Trim() -split "`r?`n"
        $title = ($lines[0] -replace "^--\s*", "").Trim()
        $queryText = ($lines | Where-Object { $_ -notmatch "^\s*--" }) -join "`n"
        $queryText = $queryText.Trim().TrimEnd(";")

        $cmd = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdCommand($queryText, $conn)
        $cs = $cmd.ExecuteCellSet()
        $okCount++

        [void]$md.AppendLine("## $title")
        [void]$md.AppendLine("")
        [void]$md.AppendLine('```mdx')
        [void]$md.AppendLine($queryText + ";")
        [void]$md.AppendLine('```')
        [void]$md.AppendLine("")

        $axesCount = $cs.Axes.Count
        if ($axesCount -eq 0) {
            $val = $cs.Cells[0].FormattedValue
            [void]$md.AppendLine("**Result:** ``$val``")
        }
        elseif ($axesCount -eq 1) {
            $cols = $cs.Axes[0].Set.Tuples
            $headers = @()
            $vals = @()
            for ($c = 0; $c -lt $cols.Count; $c++) {
                $h = ($cols[$c].Members | ForEach-Object { $_.Caption }) -join " / "
                $headers += $h
                $fv = $cs.Cells[$c].FormattedValue
                if ([string]::IsNullOrEmpty($fv)) { $fv = "(null)" }
                $vals += $fv
            }
            [void]$md.AppendLine("| " + ($headers -join " | ") + " |")
            [void]$md.AppendLine("| " + (($headers | ForEach-Object { "---" }) -join " | ") + " |")
            [void]$md.AppendLine("| " + ($vals -join " | ") + " |")
        }
        else {
            $cols = $cs.Axes[0].Set.Tuples
            $rows = $cs.Axes[1].Set.Tuples
            $colHeaders = @("Row Dimension")
            for ($c = 0; $c -lt $cols.Count; $c++) {
                $colHeaders += (($cols[$c].Members | ForEach-Object { $_.Caption }) -join " / ")
            }
            [void]$md.AppendLine("| " + ($colHeaders -join " | ") + " |")
            [void]$md.AppendLine("| " + (($colHeaders | ForEach-Object { "---" }) -join " | ") + " |")

            $maxRows = [Math]::Min($rows.Count, 25)
            for ($r = 0; $r -lt $maxRows; $r++) {
                $rLabel = ($rows[$r].Members | ForEach-Object { $_.Caption }) -join " | "
                $rVals = @($rLabel)
                for ($c = 0; $c -lt $cols.Count; $c++) {
                    $fv = $cs.Cells[$c, $r].FormattedValue
                    if ([string]::IsNullOrEmpty($fv)) { $fv = "-" }
                    $rVals += $fv
                }
                [void]$md.AppendLine("| " + ($rVals -join " | ") + " |")
            }
            if ($rows.Count -gt $maxRows) {
                [void]$md.AppendLine("")
                [void]$md.AppendLine("*... (showing first $maxRows of $($rows.Count) rows)*")
            }
        }
        [void]$md.AppendLine("")
        Write-Host "[OK] $title"
    }
} finally {
    $conn.Close()
}

[System.IO.File]::WriteAllText($OutMd, $md.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host ""
Write-Host "[DONE] Executed $okCount / $($blocks.Count) MDX queries successfully -> $OutMd"
