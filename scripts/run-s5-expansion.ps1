# S5 Tokenizer Efficiency Extension — 25 untested models
param(
    [string]$OutDir = "$PSScriptRoot/../data"
)

. "$PSScriptRoot/../experiment-config.ps1"

$baseUrl = "https://openrouter.ai/api/v1/chat/completions"
$headers = @{
    Authorization = "Bearer $script:OPENROUTER_API_KEY"
    "Content-Type" = "application/json"
    "HTTP-Referer" = "https://github.com/ClockLobsterLabs/LLM-Cost-Comparison"
}

$samples = @{
    code    = @{ path = "$PSScriptRoot/../data/samples/code-sample.txt";    words = 306 }
    prose   = @{ path = "$PSScriptRoot/../data/samples/prose-sample.txt";   words = 235 }
    blended = @{ path = "$PSScriptRoot/../data/samples/blended-sample.txt"; words = 250 }
}

$models = @(
    @{ id = "deepseek/deepseek-v4-pro";                    name = "DeepSeek V4 Pro";          family = "deepseek" }
    @{ id = "anthropic/claude-fable-5";                    name = "Claude Fable 5";           family = "anthropic" }
    @{ id = "anthropic/claude-opus-4.8";                   name = "Claude Opus 4.8";          family = "anthropic" }
    @{ id = "anthropic/claude-opus-4.7";                   name = "Claude Opus 4.7";          family = "anthropic" }
    @{ id = "anthropic/claude-opus-4.6";                   name = "Claude Opus 4.6";          family = "anthropic" }
    @{ id = "anthropic/claude-sonnet-5";                   name = "Claude Sonnet 5";          family = "anthropic" }
    @{ id = "anthropic/claude-sonnet-4.6";                 name = "Claude Sonnet 4.6";        family = "anthropic" }
    @{ id = "openai/gpt-5.5";                              name = "GPT-5.5";                  family = "openai" }
    @{ id = "openai/gpt-5.5-pro";                          name = "GPT-5.5 Pro";              family = "openai" }
    @{ id = "openai/gpt-5.4";                              name = "GPT-5.4";                  family = "openai" }
    @{ id = "openai/gpt-5.4-mini";                         name = "GPT-5.4 Mini";             family = "openai" }
    @{ id = "openai/gpt-5-nano";                           name = "GPT-5 Nano";               family = "openai" }
    @{ id = "openai/gpt-5.2";                              name = "GPT-5.2";                  family = "openai" }
    @{ id = "openai/gpt-5.3-codex";                        name = "GPT-5.3 Codex Spark";      family = "openai" }
    @{ id = "openai/o4-mini";                              name = "o4-mini";                  family = "openai" }
    @{ id = "google/gemini-3.1-pro-preview";               name = "Gemini 3.1 Pro";           family = "gemini" }
    @{ id = "google/gemini-3.5-flash";                     name = "Gemini 3.5 Flash";         family = "gemini" }
    @{ id = "google/gemini-3-flash-preview";               name = "Gemini 3 Flash";           family = "gemini" }
    @{ id = "moonshotai/kimi-k2.6";                        name = "Kimi K2.6";                family = "kimi" }
    @{ id = "x-ai/grok-build-0.1";                         name = "Grok Build 0.1";           family = "grok" }
    @{ id = "qwen/qwen3.7-max";                            name = "Qwen3.7 Max";              family = "qwen" }
    @{ id = "qwen/qwen3.7-plus";                           name = "Qwen3.7 Plus";             family = "qwen" }
    @{ id = "xiaomi/mimo-v2.5";                            name = "MiMo-V2.5";                family = "mimo" }
    @{ id = "cohere/north-mini-code:free";                 name = "North Mini Code Free";     family = "cohere" }
    @{ id = "nvidia/nemotron-3-ultra-550b-a55b:free";      name = "Nemotron 3 Ultra Free";    family = "nvidia" }
)

# Models that don't return usage data — use local tiktoken proxy
$usageNullModels = @{ "openai/o4-mini" = $true; "openai/gpt-5-nano" = $true }

# Initialize tiktoken fallback for usage-null models
$useTiktoken = $usageNullModels.Count -gt 0

$totalCalls = $models.Count * $samples.Count
$callNum = 0
$results = @()
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$rawCsvPath = "$OutDir/experiment-s5-expansion-raw.csv"
$firstExport = $true

Write-Host "=== S5 Tokenizer Efficiency Expansion ==="
Write-Host "$($models.Count) new models × $($samples.Count) samples = $totalCalls calls"
Write-Host "Untested models not on OpenRouter: DeepSeek V4 Flash Max, V4 Pro Max, V4 Flash Free, Big Pickle"
Write-Host ""

foreach ($model in $models) {
    foreach ($st in @("code", "prose", "blended")) {
        $callNum++
        $text = Get-Content -Raw $samples[$st].path
        $wc = $samples[$st].words
        $maxTok = if ($usageNullModels[$model.id]) { 100 } else { 20 }

        Write-Host "[$callNum/$totalCalls] $($model.name) / $st..."

        $body = @{
            model       = $model.id
            messages    = @(@{ role = "user"; content = $text })
            max_tokens  = $maxTok
            temperature = 0
        } | ConvertTo-Json -Compress

        $start = Get-Date
        try {
            $resp = Invoke-RestMethod -Uri $baseUrl -Method Post -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 120
            $elapsed = (Get-Date) - $start

            $promptTokens = $resp.usage.prompt_tokens
            $outputTokens = $resp.usage.completion_tokens

            # Handle models with null usage (o4-mini)
            if ($null -eq $promptTokens -and $usageNullModels[$model.id]) {
                $sampleContent = Get-Content -Raw $samples[$st].path
                $promptTokens = [int]($sampleContent | python -c "import sys,tiktoken; print(len(tiktoken.get_encoding('o200k_base').encode(sys.stdin.read())))" 2>&1 | Select-Object -Last 1)
                $outputTokens = if ($resp.choices[0].message.content) { ($resp.choices[0].message.content -split '\s+').Count } else { 0 }
                Write-Host "  tiktoken proxy: prompt=$promptTokens"
            }

            $e = if ($promptTokens -gt 0) { [math]::Round($promptTokens / $wc, 2) } else { "N/A" }
            $tps = if ($outputTokens -gt 0 -and $elapsed.TotalSeconds -gt 0) { [math]::Round($outputTokens / $elapsed.TotalSeconds, 1) } else { "N/A" }

            Write-Host "  prompt=$promptTokens output=$outputTokens E=$e ${elapsed}s"

            $results += [PSCustomObject]@{
                trial_id        = "$($model.id):$st"
                model_id        = $model.id
                model_name      = $model.name
                family          = $model.family
                sample_type     = $st
                word_count      = $wc
                prompt_tokens   = $promptTokens
                output_tokens   = $outputTokens
                tokens_per_word = $e
                cost            = "N/A"
                tokens_per_sec  = $tps
                status          = "success"
                error           = $null
                elapsed_ms      = [math]::Round($elapsed.TotalMilliseconds)
                max_tokens      = $maxTok
                temperature     = 0
            }
        }
        catch {
            $err = $_.Exception.Message.Substring(0, [math]::Min(200, $_.Exception.Message.Length))
            Write-Host "  ERROR: $err"
            $results += [PSCustomObject]@{
                trial_id        = "$($model.id):$st"
                model_id        = $model.id
                model_name      = $model.name
                family          = $model.family
                sample_type     = $st
                word_count      = $wc
                prompt_tokens   = $null
                output_tokens   = $null
                tokens_per_word = $null
                cost            = "N/A"
                tokens_per_sec  = "N/A"
                status          = "failed"
                error           = $err
                elapsed_ms      = [math]::Round(((Get-Date) - $start).TotalMilliseconds)
                max_tokens      = $maxTok
                temperature     = 0
            }
        }

        # Incremental save every 10 calls
        if ($callNum % 10 -eq 0) {
            if ($firstExport) {
                $results | Export-Csv -Path $rawCsvPath -NoTypeInformation -Force
                $firstExport = $false
            } else {
                $results | Export-Csv -Path $rawCsvPath -NoTypeInformation
            }
        }

        Start-Sleep -Milliseconds 300
    }
}

$stopwatch.Stop()

# Final save
$results | Export-Csv -Path $rawCsvPath -NoTypeInformation -Force
Write-Host "`n=== EXPERIMENT COMPLETE ==="
Write-Host "Total calls: $($results.Count)"
Write-Host "Success: $(($results | Where-Object { $_.status -eq 'success' }).Count)"
Write-Host "Failed: $(($results | Where-Object { $_.status -eq 'failed' }).Count)"
Write-Host "Elapsed: $([math]::Round($stopwatch.Elapsed.TotalSeconds))s"
Write-Host "Raw: $rawCsvPath"

# Generate summary
Write-Host "`n=== SUMMARY ==="
$summary = $results | Where-Object { $_.status -eq "success" } | Group-Object family | ForEach-Object {
    $family = $_.Name
    $_.Group | Group-Object model_name | ForEach-Object {
        $modelName = $_.Name
        $codeRow = $_.Group | Where-Object { $_.sample_type -eq "code" } | Select-Object -First 1
        $proseRow = $_.Group | Where-Object { $_.sample_type -eq "prose" } | Select-Object -First 1
        $blendedRow = $_.Group | Where-Object { $_.sample_type -eq "blended" } | Select-Object -First 1

        $eCode = if ($codeRow) { [double]$codeRow.tokens_per_word } else { $null }
        $eProse = if ($proseRow) { [double]$proseRow.tokens_per_word } else { $null }
        $eBlended = if ($blendedRow) { [double]$blendedRow.tokens_per_word } else { $null }

        $blend60 = if ($eCode -and $eProse) { [math]::Round(0.6 * $eCode + 0.4 * $eProse, 2) } else { $null }
        $blend333 = if ($eCode -and $eProse -and $eBlended) { [math]::Round(($eCode + $eProse + $eBlended) / 3, 2) } else { $null }

        [PSCustomObject]@{
            rank            = 0
            family          = $family
            model_id        = ($_.Group[0].model_id)
            model_name      = $modelName
            e_code          = $eCode
            e_prose         = $eProse
            e_blended       = $eBlended
            blend_60_40     = $blend60
            blend_33_33_33  = $blend333
        }
    }
} | Sort-Object { if ($_.blend_60_40) { [double]$_.blend_60_40 } else { 999 } }

$i = 1
$summary | ForEach-Object { $_.rank = $i; $i++ }
$summary | Format-Table rank, model_name, family, e_code, e_prose, blend_60_40 -AutoSize

$summaryPath = "$OutDir/experiment-s5-expansion-summary.csv"
$summary | Export-Csv -Path $summaryPath -NoTypeInformation -Force
Write-Host "Summary: $summaryPath"
