# Merge S5 (22 models) + expansion (25 models) + Jamba into combined summary

$existing = Import-Csv "$PSScriptRoot/../data/experiment-session5-summary.csv"
$expansion = Import-Csv "$PSScriptRoot/../data/experiment-s5-expansion-summary.csv"
$expansionRaw = Import-Csv "$PSScriptRoot/../data/experiment-s5-expansion-raw.csv"

# Fix expansion summary (convert N/A strings to null)
$expansion = $expansion | ForEach-Object {
    $_.e_code = if ($_.e_code -eq "" -or $_.e_code -eq "N/A") { $null } else { [double]$_.e_code }
    $_.e_prose = if ($_.e_prose -eq "" -or $_.e_prose -eq "N/A") { $null } else { [double]$_.e_prose }
    $_.e_blended = if ($_.e_blended -eq "" -or $_.e_blended -eq "N/A") { $null } else { [double]$_.e_blended }
    $_.blend_60_40 = if ($_.blend_60_40 -eq "" -or $_.blend_60_40 -eq "N/A") { $null } else { [double]$_.blend_60_40 }
    $_.blend_33_33_33 = if ($_.blend_33_33_33 -eq "" -or $_.blend_33_33_33 -eq "N/A") { $null } else { [double]$_.blend_33_33_33 }
    $_
}

$combined = $existing + $expansion

# Jamba Large 1.7 — tested in S5 but not in models.json. Add manually.
$jambaCode = $existing | Where-Object { $_.model_name -eq "Jamba Large 1.7" }
if (-not $jambaCode) {
    $combined += [PSCustomObject]@{
        rank = 0
        family = "ai21"
        model_id = "ai21/jamba-large-1.7"
        model_name = "Jamba Large 1.7"
        e_code = 2.82
        e_prose = 1.22
        e_blended = 1.90
        blend_60_40 = 2.18
        blend_33_33_33 = 1.98
    }
}

# Add models.json tier data
$jsonUrl = "https://raw.githubusercontent.com/ClockLobsterLabs/LLM-Cost-Comparison/main/models.json"
$rawJson = Invoke-RestMethod -Uri $jsonUrl

# Sort by blend_60_40
$sorted = $combined | Sort-Object { if ($_.blend_60_40) { [double]$_.blend_60_40 } else { 999 } }

$i = 1
$sortedWithRank = $sorted | ForEach-Object {
    $_.rank = $i; $i++
    # Add tier from models.json
    $slug = $_.model_id -replace "/", "-"
    $slug2 = $_.model_id.Split('/')[1] -replace "\.", "-"
    # Find matching model in models.json
    $match = $null
    foreach ($prop in $rawJson.models.PSObject.Properties) {
        $jsSlug = $prop.Name
        $jsName = $prop.Value.name
        if ($jsName -eq $_.model_name -or $jsSlug -eq $slug -or $jsSlug -eq $slug2) {
            $match = $prop.Value
            break
        }
    }
    $tier = if ($match) { $match.tier } else { "unknown" }
    $_.tier = $tier
    $_
}

$sortedWithRank | Format-Table rank, tier, model_name, e_code, e_prose, blend_60_40 -AutoSize

$outPath = "$PSScriptRoot/../data/experiment-s5-all-summary.csv"
$sortedWithRank | Export-Csv -Path $outPath -NoTypeInformation -Force
Write-Host "Combined summary ($($sortedWithRank.Count) models): $outPath"
