. "$PSScriptRoot/experiment-config.ps1"

$Samples = @{
    code    = @{ path = "$PSScriptRoot/data/samples/code-sample.txt";    words = 306 }
    prose   = @{ path = "$PSScriptRoot/data/samples/prose-sample.txt";   words = 235 }
    blended = @{ path = "$PSScriptRoot/data/samples/blended-sample.txt"; words = 250 }
}

$Models = @(
    @{ id = "deepseek/deepseek-chat-v4-flash";           name = "DeepSeek V4 Flash";       family = "deepseek"     }
    @{ id = "anthropic/claude-haiku-4.5";                name = "Claude Haiku 4.5";        family = "anthropic"    }
    @{ id = "openai/gpt-5.4-nano";                       name = "GPT-5.4 Nano";            family = "openai"       }
    @{ id = "z-ai/glm-5.2";                              name = "GLM 5.2";                 family = "glm"          }
    @{ id = "moonshotai/kimi-k2.5-code";                 name = "Kimi K2.7 Code";          family = "kimi"         }
    @{ id = "x-ai/grok-4.5";                             name = "Grok 4.5";                family = "grok"         }
    @{ id = "minimax/minimax-m2.5";                      name = "MiniMax M3";              family = "minimax"      }
    @{ id = "deepseek/deepseek-r1";                      name = "DeepSeek R1";             family = "deepseek"     }
    @{ id = "deepseek/deepseek-chat-v3.2";               name = "DeepSeek V3.2";           family = "deepseek"     }
    @{ id = "deepseek/deepseek-chat-v3";                 name = "DeepSeek Chat V3";        family = "deepseek"     }
    @{ id = "google/gemini-2.5-pro-preview-05-06";       name = "Gemini 2.5 Pro";          family = "gemini"       }
    @{ id = "meta-llama/llama-3.3-70b-instruct";         name = "Llama 3.3 70B";           family = "meta"         }
    @{ id = "meta-llama/llama-4-maverick-17b-128e";      name = "Llama 4 Maverick";        family = "meta"         }
    @{ id = "microsoft/phi-4";                           name = "Phi-4";                   family = "microsoft"    }
    @{ id = "amazon/nova-pro-v1";                        name = "Amazon Nova Pro";         family = "amazon"       }
    @{ id = "perplexity/sonar-pro";                      name = "Perplexity Sonar Pro";    family = "perplexity"   }
    @{ id = "perplexity/sonar-pro-search";               name = "Perplexity Sonar Pro Search"; family = "perplexity" }
    @{ id = "amazon/nova-premier-v1";                    name = "Amazon Nova Premier";     family = "amazon"       }
    @{ id = "openai/o3-mini";                            name = "o3-mini";                 family = "openai"       }
    @{ id = "mistralai/mistral-large-2512";              name = "Mistral Large 3";         family = "mistral"      }
    @{ id = "mistralai/codestral-2508";                  name = "Codestral";               family = "mistral"      }
    @{ id = "cohere/command-a";                          name = "Command A";               family = "cohere"       }
    @{ id = "ai21/jamba-large-1.7";                      name = "Jamba Large 1.7";         family = "ai21"         }
)

$Uri = "https://openrouter.ai/api/v1/chat/completions"
$Headers = @{ Authorization = "Bearer $script:OPENROUTER_API_KEY"; "Content-Type" = "application/json" }

$TotalCalls = $Models.Count * $Samples.Count
$TotalCost = 0
$Results = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
$CompletedCount = 0
$FailedCount = 0
$Lock = [System.Threading.Mutex]::new()

Write-Host "Tokenizer Efficiency Experiment — Session 5"
Write-Host "  $($Models.Count) models × $($Samples.Count) samples = $TotalCalls calls"
Write-Host "  max_tokens=20, temperature=0"
Write-Host ""

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Invoke-Measurement {
    param($Model, $SampleType, $Text, $WordCount)

    $body = @{
        model       = $Model.id
        messages    = @(@{ role = "user"; content = $Text })
        max_tokens  = 20
        temperature = 0
    } | ConvertTo-Json -Compress

    $start = Get-Date
    try {
        $resp = Invoke-RestMethod -Uri $Uri -Method Post -Headers $Headers -Body $body -ContentType "application/json" -TimeoutSec 60
        $elapsed = (Get-Date) - $start
        $promptTokens = $resp.usage.prompt_tokens
        $outputTokens = $resp.usage.completion_tokens
        $cost = "N/A"
        $speed = "N/A"

        # Extract generation speed if available
        if ($resp.usage.completion_tokens -and $resp.usage.completion_tokens -gt 0) {
            $tps = $resp.usage.completion_tokens / $elapsed.TotalSeconds
            $speed = [math]::Round($tps, 1)
        }

        $e = if ($promptTokens -and $promptTokens -gt 0) { [math]::Round($promptTokens / $WordCount, 2) } else { "N/A" }

        return @{
            status         = "success"
            prompt_tokens  = $promptTokens
            output_tokens  = $outputTokens
            cost           = $cost
            speed          = $speed
            tokens_per_word = $e
            elapsed_ms     = [math]::Round($elapsed.TotalMilliseconds)
        }
    }
    catch {
        $elapsed = (Get-Date) - $start
        $errMsg = $_.Exception.Message
        $status = "failed"
        if ($errMsg -match "404" -or $errMsg -match "guardrail" -or $errMsg -match "blocked") { $status = "blocked" }
        if ($errMsg -match "timeout" -or $errMsg -match "timed out") { $status = "timeout" }
        return @{
            status         = $status
            error          = $errMsg.Substring(0, [math]::Min(200, $errMsg.Length))
            prompt_tokens  = $null
            output_tokens  = $null
            tokens_per_word = $null
            cost           = "N/A"
            speed          = "N/A"
            elapsed_ms     = [math]::Round($elapsed.TotalMilliseconds)
        }
    }
}

# Process in parallel batches of 5
$BatchSize = 5
$AllTasks = @()
$ModelIndex = 0
$SampleTypes = @("code", "prose", "blended")

foreach ($model in $Models) {
    foreach ($st in $SampleTypes) {
        $AllTasks += @{ model = $model; sampleType = $st }
    }
}

for ($i = 0; $i -lt $AllTasks.Count; $i += $BatchSize) {
    $batch = $AllTasks[$i..([math]::Min($i + $BatchSize - 1, $AllTasks.Count - 1))]
    $jobs = @()

    foreach ($task in $batch) {
        $text = Get-Content -Raw $Samples[$task.sampleType].path
        $wc = $Samples[$task.sampleType].words
        $m = $task.model
        $st = $task.sampleType

        $jobs += [pscustomobject]@{
            model      = $m
            sampleType = $st
            text       = $text
            wordCount  = $wc
        }
    }

    foreach ($job in $jobs) {
        $result = Invoke-Measurement -Model $job.model -SampleType $job.sampleType -Text $job.text -WordCount $job.wordCount

        $record = [pscustomobject]@{
            trial_id        = "$($job.model.id):$($job.sampleType)"
            model_id        = $job.model.id
            model_name      = $job.model.name
            family          = $job.model.family
            sample_type     = $job.sampleType
            word_count      = $job.wordCount
            prompt_tokens   = $result.prompt_tokens
            output_tokens   = $result.output_tokens
            tokens_per_word = $result.tokens_per_word
            cost            = $result.cost
            tokens_per_sec  = $result.speed
            status          = $result.status
            error           = $result.error
            elapsed_ms      = $result.elapsed_ms
            max_tokens      = 20
            temperature     = 0
        }

        $Results.Add($record)

        $Lock.WaitOne()
        $CompletedCount++
        $elapsedTotal = [math]::Round($Stopwatch.Elapsed.TotalSeconds)
        $statusIcon = switch ($result.status) { "success" { "[OK]" } "blocked" { "[BL]" } "timeout" { "[TO]" } default { "[ER]" } }
        Write-Host "  [$($CompletedCount)/$TotalCalls] $statusIcon $($job.model.name) / $($job.sampleType) -> $($result.status)"
        if ($result.status -eq "success") {
            Write-Host "         prompt=$($result.prompt_tokens) tok  E=$($result.tokens_per_word)  ${elapsedTotal}s elapsed"
        }
        elseif ($result.error) {
            Write-Host "         error: $($result.error)"
        }
        $Lock.ReleaseMutex()

        Start-Sleep -Milliseconds 200
    }
}

$Stopwatch.Stop()

Write-Host ""
Write-Host "=== Session Complete ==="
Write-Host "  Total calls: $CompletedCount"
Write-Host "  Elapsed: $([math]::Round($Stopwatch.Elapsed.TotalSeconds))s"
Write-Host ""

# Export raw results
$resultsArray = $Results.ToArray()
$resultsArray | Export-Csv -Path "$PSScriptRoot/data/experiment-session5-raw.csv" -NoTypeInformation
Write-Host "Raw results written to data/experiment-session5-raw.csv"

# Compute E summary
$summary = $resultsArray | Where-Object { $_.status -eq "success" } | Group-Object family | ForEach-Object {
    $family = $_.Name
    $models = $_.Group | Group-Object model_name | ForEach-Object {
        $modelName = $_.Name
        $codeRow = $_.Group | Where-Object { $_.sample_type -eq "code" } | Select-Object -First 1
        $proseRow = $_.Group | Where-Object { $_.sample_type -eq "prose" } | Select-Object -First 1
        $blendedRow = $_.Group | Where-Object { $_.sample_type -eq "blended" } | Select-Object -First 1

        $eCode = if ($codeRow) { $codeRow.tokens_per_word } else { $null }
        $eProse = if ($proseRow) { $proseRow.tokens_per_word } else { $null }
        $eBlended = if ($blendedRow) { $blendedRow.tokens_per_word } else { $null }

        $blend60 = if ($eCode -and $eProse) { [math]::Round(0.6 * [double]$eCode + 0.4 * [double]$eProse, 2) } else { $null }
        $blend333 = if ($eCode -and $eProse -and $eBlended) { [math]::Round(([double]$eCode + [double]$eProse + [double]$eBlended) / 3, 2) } else { $null }

        $modelId = if ($codeRow) { $codeRow.model_id } else { $_.Group[0].model_id }

        [pscustomobject]@{
            family          = $family
            model_id        = $modelId
            model_name      = $modelName
            e_code          = $eCode
            e_prose         = $eProse
            e_blended       = $eBlended
            blend_60_40     = $blend60
            blend_33_33_33  = $blend333
        }
    }
    $models
} | Sort-Object { if ($_.blend_60_40) { [double]$_.blend_60_40 } else { 999 } }

$summary | Export-Csv -Path "$PSScriptRoot/data/experiment-session5-summary.csv" -NoTypeInformation
$summary | Format-Table -AutoSize

Write-Host ""
Write-Host "Summary written to data/experiment-session5-summary.csv"
