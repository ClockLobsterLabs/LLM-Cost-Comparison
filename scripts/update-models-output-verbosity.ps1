$modelsJson = Get-Content "$PSScriptRoot/../models.json" -Raw | ConvertFrom-Json
$csv = Import-Csv "$PSScriptRoot/../data/output-experiment/session6-output-verbosity.csv"

# Map OpenRouter model_id -> models.json slug
$slugMap = @{
    "deepseek/deepseek-v4-flash"       = "deepseek-v4-flash"
    "anthropic/claude-haiku-4.5"       = "claude-haiku-4-5"
    "openai/gpt-5.4-nano"              = "gpt-5-4-nano"
    "z-ai/glm-5.2"                     = "glm-5-2"
    "moonshotai/kimi-k2.7-code"        = "kimi-k2-7-code"
    "x-ai/grok-4.5"                    = "grok-4-5"
    "minimax/minimax-m2.5"             = "minimax-m3"
    "deepseek/deepseek-r1"             = "deepseek-r1"
    "deepseek/deepseek-v3.2"           = "deepseek-v3-2"
    "deepseek/deepseek-chat-v3"        = "deepseek-chat-v3"
    "google/gemini-2.5-pro-preview-05-06" = "gemini-2-5-pro"
    "meta-llama/llama-3.3-70b-instruct" = "llama-3-3-70b"
    "meta-llama/llama-4-maverick"       = "llama-4-maverick"
    "microsoft/phi-4"                  = "phi-4"
    "amazon/nova-pro-v1"               = "nova-pro"
    "perplexity/sonar-pro"             = "perplexity-sonar-pro"
    "perplexity/sonar-pro-search"      = "perplexity-sonar-pro-search"
    "amazon/nova-premier-v1"           = "nova-premier-v1"
    "openai/o3-mini"                   = "o3-mini"
    "mistralai/mistral-large-2512"     = "mistral-large-3"
    "mistralai/codestral-2508"         = "codestral"
    "cohere/command-a"                 = "command-a"
    "deepseek/deepseek-v4-pro"         = "deepseek-v4-pro"
}

# For each model in CSV, compute per-task stats
$modelResults = $csv | Group-Object model_id
$updatedCount = 0
$skippedCount = 0

foreach ($group in $modelResults) {
    $modelId = $group.Name
    $slug = $slugMap[$modelId]
    if (-not $slug) { $skippedCount++; continue }
    if (-not $modelsJson.models.$slug) { $skippedCount++; continue }

    # Only include successful rows (status=success or maxed_at_4096)
    $successRows = $group.Group | Where-Object { $_.status -ne "error" }
    
    # Per-task stats
    $perTask = $successRows | Group-Object task_id | ForEach-Object {
        $tokens = $_.Group | Where-Object { $_.output_tokens } | ForEach-Object { [int]$_.output_tokens }
        $words = $_.Group | Where-Object { $_.output_words } | ForEach-Object { [int]$_.output_words }
        if ($tokens.Count -gt 0) {
            [PSCustomObject]@{
                task_id    = $_.Name
                count      = $tokens.Count
                avg_tokens = [math]::Round(($tokens | Measure-Object -Average).Average, 1)
                max_tokens = ($tokens | Measure-Object -Maximum).Maximum
                min_tokens = ($tokens | Measure-Object -Minimum).Minimum
                avg_words  = [math]::Round(($words | Measure-Object -Average).Average, 1)
            }
        }
    }

    # Overall stats
    $allTokens = $successRows | Where-Object { $_.output_tokens } | ForEach-Object { [int]$_.output_tokens }
    $allWords = $successRows | Where-Object { $_.output_words } | ForEach-Object { [int]$_.output_words }
    $maxedRows = $successRows | Where-Object { $_."is_maxed" -eq "True" }

    $outputVerbosity = [PSCustomObject]@{
        session        = 6
        date           = "2026-07-09"
        max_tokens     = 1500
        fallback_tokens = 4096
        total_calls    = $successRows.Count
        error_calls    = ($group.Group | Where-Object { $_.status -eq "error" }).Count
        maxed_out_1500 = ($successRows | Where-Object { $_."is_maxed" -eq "True" }).Count
        still_maxed_4096 = ($successRows | Where-Object { $_.status -eq "maxed_at_4096" }).Count
        avg_output_tokens = [math]::Round(($allTokens | Measure-Object -Average).Average, 1)
        avg_words_per_call = [math]::Round(($allWords | Measure-Object -Average).Average, 1)
        per_task       = @{}
    }

    foreach ($task in $perTask) {
        $taskObj = [PSCustomObject]@{
            avg_tokens = $task.avg_tokens
            max_tokens = $task.max_tokens
            min_tokens = $task.min_tokens
            avg_words  = $task.avg_words
        }
        $outputVerbosity.per_task[$task.task_id] = $taskObj
    }

    # Add to models.json
    $modelsJson.models.$slug | Add-Member -NotePropertyName "output_verbosity" -NotePropertyValue $outputVerbosity -Force
    $updatedCount++
}

Write-Host "Updated $updatedCount models"
if ($skippedCount -gt 0) { Write-Host "Skipped $skippedCount models (no slug mapping or not in models.json)" }

# Convert back to JSON and save
$json = $modelsJson | ConvertTo-Json -Depth 10
$json | Set-Content "$PSScriptRoot/../models.json" -Encoding UTF8
Write-Host "Saved to models.json"

