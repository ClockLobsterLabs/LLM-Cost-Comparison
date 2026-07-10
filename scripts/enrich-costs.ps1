# Enrich raw CSV files with calculated API costs
. "$PSScriptRoot/../experiment-config.ps1"
$key = $script:OPENROUTER_API_KEY
$orModels = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/models" -Headers @{ "Authorization" = "Bearer $key" }
$priceMap = @{}
foreach ($m in $orModels.data) {
    $priceMap[$m.id] = @{ prompt = [double]$m.pricing.prompt; completion = [double]$m.pricing.completion }
}

$files = @(
    "$PSScriptRoot/../data/experiment-session5-raw.csv",
    "$PSScriptRoot/../data/experiment-s5-expansion-raw.csv",
    "$PSScriptRoot/../data/experiment-s5-max-variants-raw.csv"
)

# Map old/expired model IDs to current ones
$oldIdMap = @{
    "meta-llama/llama-4-maverick-17b-128e" = "meta-llama/llama-4-maverick"
    "deepseek/deepseek-chat-v3" = "deepseek/deepseek-chat"
    "deepseek/deepseek-chat-v3.2" = "deepseek/deepseek-v3.2"
    "moonshotai/kimi-k2.5-code" = "moonshotai/kimi-k2.7-code"
    "deepseek/deepseek-chat-v4-flash" = "deepseek/deepseek-v4-flash"
}

foreach ($file in $files) {
    $csv = Import-Csv $file
    $updated = 0; $missing = 0
    $output = @()
    foreach ($row in $csv) {
        $mid = $row.model_id
        $pt = [double]$row.prompt_tokens
        $ct = [double]$row.completion_tokens
        $costVal = "N/A"
        # Try direct lookup, then old ID mapping, then free model fallback
        $resolvedMid = $mid
        if (-not $priceMap.ContainsKey($resolvedMid) -and $oldIdMap.ContainsKey($resolvedMid)) {
            $resolvedMid = $oldIdMap[$resolvedMid]
        }
        if ($priceMap.ContainsKey($resolvedMid)) {
            $p = $priceMap[$resolvedMid]
            $cost = $pt * $p.prompt + $ct * $p.completion
            $costVal = [math]::Round($cost, 8)
            $updated++
        } else {
            $missing++
        }
        # Handle CSV rows that lack a cost column
        if ($row.PSObject.Properties.Name -contains "cost") {
            $row.cost = $costVal
        } else {
            $row | Add-Member -NotePropertyName "cost" -NotePropertyValue $costVal -Force
        }
        $output += $row
    }
    $output | Export-Csv $file -NoTypeInformation -Force
    $name = Split-Path $file -Leaf
    Write-Host ("{0}: {1} rows enriched, {2} missing pricing" -f $name, $updated, $missing)
}

Write-Host "`nDone. All CSVs updated with per-call cost."
