$modelsPath = "$PSScriptRoot/../models.json"
$summaryPath = "$PSScriptRoot/../data/experiment-session5-summary.csv"

$json = Get-Content $modelsPath -Raw | ConvertFrom-Json
$summary = Import-Csv $summaryPath

# Map S5 model_id -> models.json key
$modelIdMap = @{
    'cohere/command-a'                      = 'command-a'
    'mistralai/codestral-2508'              = 'codestral'
    'mistralai/mistral-large-2512'          = 'mistral-large-3'
    'openai/o3-mini'                        = 'o3-mini'
    'amazon/nova-premier-v1'                = 'nova-premier-v1'
    'perplexity/sonar-pro-search'           = 'perplexity-sonar-pro-search'
    'perplexity/sonar-pro'                  = 'perplexity-sonar-pro'
    'amazon/nova-pro-v1'                    = 'nova-pro'
    'microsoft/phi-4'                       = 'phi-4'
    'meta-llama/llama-3.3-70b-instruct'     = 'llama-3-3-70b'
    'google/gemini-2.5-pro-preview-05-06'   = 'gemini-2-5-pro'
    'deepseek/deepseek-chat-v3'             = 'deepseek-chat-v3'
    'deepseek/deepseek-r1'                  = 'deepseek-r1'
    'minimax/minimax-m2.5'                  = 'minimax-m3'
    'x-ai/grok-4.5'                         = 'grok-4-5'
    'z-ai/glm-5.2'                          = 'glm-5-2'
    'openai/gpt-5.4-nano'                   = 'gpt-5-4-nano'
    'anthropic/claude-haiku-4.5'            = 'claude-haiku-4-5'
    'deepseek/deepseek-v4-flash'            = 'deepseek-v4-flash'
    'moonshotai/kimi-k2.7-code'             = 'kimi-k2-7-code'
    'deepseek/deepseek-v3.2'                = 'deepseek-v3-2'
    'meta-llama/llama-4-maverick'           = 'llama-4-maverick'
}

$s5Keys = $modelIdMap.Values | ForEach-Object { $_ }

# Build lookup from summary data
$s5Data = @{}
foreach ($row in $summary) {
    $key = $modelIdMap[$row.model_id]
    if (-not $key) { continue }
    $s5Data[$key] = @{
        e_code       = [double]$row.e_code
        e_prose      = [double]$row.e_prose
        e_blended    = [double]$row.e_blended
        blend_60_40  = [double]$row.blend_60_40
        blend_33_33  = [double]$row.blend_33_33_33
    }
}

$updatedCount = 0
$removedCount = 0

foreach ($modelKey in $json.models.PSObject.Properties.Name) {
    $model = $json.models.$modelKey

    if ($s5Data.ContainsKey($modelKey)) {
        # Update with Session 5 data
        $data = $s5Data[$modelKey]
        $model | Add-Member -NotePropertyName 'tokenizer_efficiency' -NotePropertyValue $data.blend_60_40 -Force
        $model | Add-Member -NotePropertyName 'tokenizer_efficiency_date' -NotePropertyValue '2026-07-09' -Force
        $model | Add-Member -NotePropertyName 'tokenizer_efficiency_source' -NotePropertyValue 'Session 5 (consistent protocol: same key, max_tokens=20, 306/235/250 word samples)' -Force
        # Add breakdown
        $breakdown = [PSCustomObject]@{
            code          = $data.e_code
            prose         = $data.e_prose
            blended       = $data.e_blended
            blend_60_40   = $data.blend_60_40
            blend_33_33   = $data.blend_33_33
        }
        $model | Add-Member -NotePropertyName 'tokenizer_efficiency_breakdown' -NotePropertyValue $breakdown -Force
        $updatedCount++
        Write-Host "  UPDATED $modelKey : $($data.blend_60_40) (was old value, now S5)"
    } else {
        # Not in Session 5 — deprecate old value
        $hasOldValue = $null -ne $model.tokenizer_efficiency
        if ($hasOldValue) {
            $model | Add-Member -NotePropertyName 'tokenizer_efficiency' -NotePropertyValue $null -Force
            $model | Add-Member -NotePropertyName 'tokenizer_efficiency_date' -NotePropertyValue '2026-07-09' -Force
            $model | Add-Member -NotePropertyName 'tokenizer_efficiency_source' -NotePropertyValue 'DEPRECATED — from Sessions 1-4 (inconsistent protocol). Not re-measured in Session 5.' -Force
            $removedCount++
        }
    }
}

Write-Host "`nDone. Updated $updatedCount models with Session 5 data. Deprecated $removedCount models' old values."

$json | ConvertTo-Json -Depth 10 | Set-Content $modelsPath -Encoding utf8
Write-Host "Saved to $modelsPath"
