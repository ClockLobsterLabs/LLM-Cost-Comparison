. "$PSScriptRoot/../experiment-config.ps1"
$key = $script:OPENROUTER_API_KEY
$orModels = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/models" -Headers @{ "Authorization" = "Bearer $key" }
$priceMap = @{}
foreach ($m in $orModels.data) { $priceMap[$m.id] = @{ prompt = [double]$m.pricing.prompt; completion = [double]$m.pricing.completion } }

# Old model ID mapping for enrichment
$oldIdMap = @{
    "meta-llama/llama-4-maverick-17b-128e" = "meta-llama/llama-4-maverick"
    "deepseek/deepseek-chat-v3" = "deepseek/deepseek-chat"
    "deepseek/deepseek-chat-v3.2" = "deepseek/deepseek-v3.2"
    "moonshotai/kimi-k2.5-code" = "moonshotai/kimi-k2.7-code"
    "deepseek/deepseek-chat-v4-flash" = "deepseek/deepseek-v4-flash"
    "google/gemini-2.5-pro-preview-05-06" = "google/gemini-2.5-pro"
    "minimax/minimax-m2.5" = "minimax/minimax-m2.5"
    "amazon/nova-pro-v1" = "amazon/nova-pro-v1"
    "amazon/nova-premier-v1" = "amazon/nova-premier-v1"
    "mistralai/mistral-large-2512" = "mistralai/mistral-large-2512"
    "mistralai/codestral-2508" = "mistralai/codestral-2508"
    "perplexity/sonar-pro" = "perplexity/sonar-pro"
    "perplexity/sonar-pro-search" = "perplexity/sonar-pro-search"
    "x-ai/grok-build-0.1" = "x-ai/grok-build-0.1"
}

function Enrich-Csv($path) {
    $csv = Import-Csv $path
    $output = @(); $enriched = 0; $missing = 0
    foreach ($row in $csv) {
        $mid = $row.model_id
        $resolvedMid = $mid
        if (-not $priceMap.ContainsKey($resolvedMid) -and $oldIdMap.ContainsKey($resolvedMid)) {
            $resolvedMid = $oldIdMap[$resolvedMid]
        }
        $costVal = "N/A"
        if ($priceMap.ContainsKey($resolvedMid)) {
            $p = $priceMap[$resolvedMid]
            $pt = [double]$row.prompt_tokens
            $ct = [double]$row.output_tokens
            $cost = $pt * $p.prompt + $ct * $p.completion
            $costVal = [math]::Round($cost, 8)
            $enriched++
        } else { $missing++ }
        
        if ($row.PSObject.Properties.Name -contains "cost") {
            $row.cost = $costVal
        } else {
            $row | Add-Member -NotePropertyName "cost" -NotePropertyValue $costVal -Force
        }
        $output += $row
    }
    $output | Export-Csv $path -NoTypeInformation -Force
    return @{total=$csv.Count; enriched=$enriched; missing=$missing}
}

Write-Host "=== Enriching S6 expansion with costs ==="
$r = Enrich-Csv "$PSScriptRoot/../data/output-experiment/session6-expansion-raw.csv"
Write-Host ("  {0} rows, {1} enriched, {2} missing" -f $r.total, $r.enriched, $r.missing)

Write-Host "`n=== Enriching original S6 with costs ==="
$r = Enrich-Csv "$PSScriptRoot/../data/output-experiment/session6-output-verbosity.csv"
Write-Host ("  {0} rows, {1} enriched, {2} missing" -f $r.total, $r.enriched, $r.missing)

Write-Host "`n=== Merging S6 datasets ==="
$orig = Import-Csv "$PSScriptRoot/../data/output-experiment/session6-output-verbosity.csv"
$exp = Import-Csv "$PSScriptRoot/../data/output-experiment/session6-expansion-raw.csv"
$merged = $orig + $exp
$merged | Export-Csv "$PSScriptRoot/../data/output-experiment/session6-merged.csv" -NoTypeInformation -Force

Write-Host ("Merged: {0} + {1} = {2} rows" -f $orig.Count, $exp.Count, $merged.Count)
Write-Host ("Models: {0}" -f (($merged | Select-Object model_name -Unique).Count))

# Per-task summary
Write-Host "`n=== Per-task summary ==="
$summary = $merged | Where-Object { $_.status -eq "success" } | Group-Object task_id | ForEach-Object {
    $taskId = $_.Name
    $tokens = $_.Group | Where-Object { $_.output_tokens } | ForEach-Object { [double]$_.output_tokens }
    $words = $_.Group | Where-Object { $_.output_words } | ForEach-Object { [double]$_.output_words }
    $maxedCount = ($_.Group | Where-Object { $_.is_maxed -eq "True" }).Count
    $costs = $_.Group | Where-Object { $_.cost -and $_.cost -ne "N/A" } | ForEach-Object { [double]$_.cost }
    [PSCustomObject]@{
        task_id = $taskId
        count = $_.Count
        avg_tokens = if ($tokens.Count -gt 0) { [math]::Round(($tokens | Measure-Object -Average).Average, 1) } else { "N/A" }
        max_tokens_val = if ($tokens.Count -gt 0) { ($tokens | Measure-Object -Maximum).Maximum } else { "N/A" }
        min_tokens_val = if ($tokens.Count -gt 0) { ($tokens | Measure-Object -Minimum).Minimum } else { "N/A" }
        avg_words = if ($words.Count -gt 0) { [math]::Round(($words | Measure-Object -Average).Average, 1) } else { "N/A" }
        maxed_count = $maxedCount
        total_cost = if ($costs.Count -gt 0) { [math]::Round(($costs | Measure-Object -Sum).Sum, 5) } else { 0 }
    }
}
$summary | Sort-Object { [double]$_.avg_tokens } -Descending | Format-Table -AutoSize
$summary | Export-Csv "$PSScriptRoot/../data/output-experiment/session6-per-task-summary.csv" -NoTypeInformation -Force

# Grand total cost
$totalCost = 0; $naCount = 0
foreach ($row in $merged) {
    if ($row.cost -and $row.cost -ne "N/A") { $totalCost += [double]$row.cost }
    else { $naCount++ }
}
Write-Host ("`nTotal S6 cost: `${0} ({1} rows enriched, {2} N/A)" -f [math]::Round($totalCost,5), ($merged.Count - $naCount), $naCount)
Write-Host ("S6 total with 5.5% OpenRouter fee: `${0}" -f [math]::Round($totalCost * 1.055, 5))
