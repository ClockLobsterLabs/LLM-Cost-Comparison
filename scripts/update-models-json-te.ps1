# Update models.json tokenizer_efficiency values from experiment data
$jsonPath = "$PSScriptRoot/../models.json"
$summaryPath = "$PSScriptRoot/../data/experiment-s5-all-summary.csv"

$json = Get-Content $jsonPath -Raw | ConvertFrom-Json
$summary = Import-Csv $summaryPath

# Map model slugs to their experimental blend_60_40 values
$slugMap = @{}
$json.models.PSObject.Properties | ForEach-Object { $slugMap[$_.Name] = $_.Value.name }

# Handle name mismatches between CSV and JSON
$nameAliases = @{
    "MiMo-V2.5" = "MiMo-V2.5 Free"   # CSV has no "Free" suffix
}

$updated = 0
$missing = @()
foreach ($slug in $slugMap.Keys) {
    $modelName = $slugMap[$slug]
    # Check alias map first
    $csvName = $modelName
    foreach ($alias in $nameAliases.Keys) {
        if ($nameAliases[$alias] -eq $modelName) { $csvName = $alias; break }
    }
    $row = $summary | Where-Object { $_.model_name -eq $csvName } | Select-Object -First 1
    if ($row -and $row.blend_60_40) {
        $value = [math]::Round([double]$row.blend_60_40, 2)
        $json.models.$slug.tokenizer_efficiency = $value
        $updated++
    } else {
        $missing += "$slug ($modelName)"
    }
}

# Write back
$json | ConvertTo-Json -Depth 10 | Set-Content $jsonPath -Force

Write-Host "Updated $updated models with experimental tokenizer_efficiency values"
if ($missing.Count -gt 0) {
    Write-Host "WARNING: $($missing.Count) models not found in experiment data:"
    $missing | ForEach-Object { Write-Host "  $_" }
}

# Show before/after for a few key models
$keys = @("claude-opus-4-6", "claude-opus-4-7", "gpt-5-5", "deepseek-v4-flash", "glm-5-2", "grok-4-5")
foreach ($k in $keys) {
    if ($json.models.$k) {
        Write-Host "$k ($($json.models.$k.name)): te=$($json.models.$k.tokenizer_efficiency)"
    }
}
