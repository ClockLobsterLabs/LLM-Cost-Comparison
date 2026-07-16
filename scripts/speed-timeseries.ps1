# speed-timeseries.ps1 — 24-hour token speed time-of-day experiment.
#
# Measures 5 models (China-based: DeepSeek V4 Flash, GLM 5.2, MiniMax M3;
# US-based: Claude Sonnet 5, o4-mini) every hour on the hour for N rounds,
# recording tokens/sec to detect time-of-day speed patterns.
#
# The hypothesis: China-based models may slow during Chinese peak hours,
# while US models may slow during US peak hours. Developers can use this to
# plan work schedules when switching between model ecosystems.
#
# Features:
#   - Resumable: loads existing CSV, skips completed (hour, model) pairs.
#   - Flush-per-row: writes each measurement immediately (survives interrupts).
#   - Ctrl+C graceful exit: traps SIGINT, prints summary, preserves data.
#   - Dry-run mode: validates config without calling the API.
#
# Output: data/speed-timeseries/speed-timeseries-<YYYY-MM-DD>.csv
#
# Usage:
#   pwsh scripts/speed-timeseries.ps1                    # full 24-hour run
#   pwsh scripts/speed-timeseries.ps1 -Rounds 3         # 3-round test
#   pwsh scripts/speed-timeseries.ps1 -DryRun           # validate without API calls
#   pwsh scripts/speed-timeseries.ps1 -Prompt "Count from 1 to 500"
#   pwsh scripts/speed-timeseries.ps1 -MaxTokens 1000

param(
    [int]$Rounds = 24,                                     # number of hourly rounds (default 24)
    [int]$MaxTokens = 3300,                               # max_tokens per API call
    [string]$Prompt = "Write the numbers from 1 to 200, comma-separated.",
    [string]$OutputDir = "$PSScriptRoot/../data/speed-timeseries",
    [switch]$DryRun,                                       # print plan without calling API
    [switch]$StartNow                                       # skip initial wait; start measuring immediately
)

# ---------------------------------------------------------------------------
# Model roster — 5 models representing China vs US provider ecosystems.
# ---------------------------------------------------------------------------
$Models = @(
    @{ model_id = "deepseek/deepseek-v4-flash";  model_name = "DeepSeek V4 Flash"; slug = "deepseek-v4-flash";  region = "China" }
    @{ model_id = "z-ai/glm-5.2";                model_name = "GLM 5.2";           slug = "glm-5-2";           region = "China" }
    @{ model_id = "minimax/minimax-m3";           model_name = "MiniMax M3";        slug = "minimax-m3";         region = "China" }
    @{ model_id = "anthropic/claude-sonnet-5";    model_name = "Claude Sonnet 5";   slug = "claude-sonnet-5";     region = "US"    }
    @{ model_id = "openai/o4-mini";               model_name = "o4-mini";           slug = "o4-mini";            region = "US"    }
)

# ---------------------------------------------------------------------------
# Bootstrap — load config, create output dir, determine run date.
# ---------------------------------------------------------------------------
. "$PSScriptRoot/../experiment-config.ps1"
$apiKey  = $script:OPENROUTER_API_KEY
$baseUrl = "https://openrouter.ai/api/v1/chat/completions"

$runDate  = Get-Date -Format "yyyy-MM-dd"
$csvName  = "speed-timeseries-$runDate.csv"
$csvPath  = Join-Path $OutputDir $csvName

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ---------------------------------------------------------------------------
# Fetch live pricing from OpenRouter (for cost enrichment).
# ---------------------------------------------------------------------------
$pricing = @{}  # keyed by model_id
if (-not $DryRun) {
    Write-Host "Fetching OpenRouter pricing..."
    try {
        $orModels = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/models" -Headers @{ "Authorization" = "Bearer $apiKey" }
        foreach ($m in $Models) {
            $match = $orModels.data | Where-Object { $_.id -eq $m.model_id } | Select-Object -First 1
            if ($match) {
                $pricing[$m.model_id] = @{
                    prompt     = [double]$match.pricing.prompt
                    completion = [double]$match.pricing.completion
                }
            }
        }
        $priced = $pricing.Count
        Write-Host "  Priced $priced / $($Models.Count) models"
    } catch {
        Write-Host "  WARNING: Could not fetch pricing ($($_.Exception.Message))"
        Write-Host "  Cost values will be N/A"
    }
}

function Get-Cost {
    param([string]$ModelId, [int]$PromptTokens, [int]$CompletionTokens)
    $p = $pricing[$ModelId]
    if (-not $p -or -not $PromptTokens -or -not $CompletionTokens) { return "N/A" }
    return [math]::Round($PromptTokens * $p.prompt + $CompletionTokens * $p.completion, 8)
}

# ---------------------------------------------------------------------------
# Resume support — load existing CSV and build completed-pair set.
# ---------------------------------------------------------------------------
$completed = @{}  # key = "$hour|$model_id"

$csvHeader = "run_date,hour_pst,hour_utc,model_id,model_name,slug,region,max_tokens,prompt_tokens,output_tokens,elapsed_ms,tokens_per_sec,cost,status,error,measured_at"

if (Test-Path $csvPath) {
    Write-Host "Resuming from $csvPath ..."
    $existing = Import-Csv $csvPath
    foreach ($row in $existing) {
        $key = "$($row.hour_pst)|$($row.model_id)"
        $completed[$key] = $true
    }
    $skipCount = $existing.Count
    Write-Host "  Found $skipCount existing rows — will skip completed pairs"
} else {
    # Write header to new file.
    $csvHeader | Set-Content -Path $csvPath -Encoding UTF8
}

# ---------------------------------------------------------------------------
# API call helper — mirrors Invoke-Call from appraise-model.ps1.
# ---------------------------------------------------------------------------
$headers = @{
    "Authorization" = "Bearer $apiKey"
    "Content-Type"  = "application/json"
    "HTTP-Referer"  = "https://github.com/ClockLobsterLabs/LLM-Cost-Comparison"
}

function Invoke-SpeedCall {
    param([string]$ModelId)

    $body = @{
        model       = $ModelId
        messages    = @(@{ role = "user"; content = $Prompt })
        max_tokens  = $MaxTokens
        temperature = 0
    } | ConvertTo-Json -Compress -Depth 5

    $start = Get-Date
    try {
        $resp = Invoke-RestMethod -Uri $baseUrl -Method Post -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 120
        $elapsed = (Get-Date) - $start
        $pt = $resp.usage.prompt_tokens
        $ct = $resp.usage.completion_tokens
        return @{
            status           = "success"
            error            = ""
            prompt_tokens    = $pt
            completion_tokens = $ct
            elapsed_ms       = [math]::Round($elapsed.TotalMilliseconds)
        }
    } catch {
        $elapsed = (Get-Date) - $start
        $msg = $_.Exception.Message
        $status = "error"
        if ($msg -match "404")                { $status = "not_found" }
        elseif ($msg -match "timeout|timed out") { $status = "timeout" }
        elseif ($msg -match "guardrail|blocked|429") { $status = "blocked" }
        return @{
            status            = $status
            error             = $msg.Substring(0, [math]::Min(200, $msg.Length))
            prompt_tokens     = $null
            completion_tokens = $null
            elapsed_ms        = [math]::Round($elapsed.TotalMilliseconds)
        }
    }
}

# ---------------------------------------------------------------------------
# Ctrl+C graceful exit handler.
# ---------------------------------------------------------------------------
$script:Interrupted = $false
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    # This doesn't fire on Ctrl+C in all hosts, so we also trap below.
}

function Handle-Interrupt {
    $script:Interrupted = $true
    Write-Host ""
    Write-Host "*** INTERRUPT — flushing data and exiting ***" -ForegroundColor Yellow
}

# Graceful Ctrl+C — rely on the try/finally block to flush data on exit.

# ---------------------------------------------------------------------------
# Main loop — N rounds, one per hour.
# ---------------------------------------------------------------------------
$Stopwatch  = [System.Diagnostics.Stopwatch]::StartNew()
$totalCalls = $Rounds * $Models.Count
$doneCalls  = $completed.Count
$successCount = ($doneCalls)  # approximate; we'll recount from CSV at the end

Write-Host ""
Write-Host "================================================================"
Write-Host "  Speed Time-of-Day Experiment — $runDate"
Write-Host "  Models: $($Models.Count)  |  Rounds: $Rounds  |  Max tokens: $MaxTokens"
Write-Host "  Prompt: `"$Prompt`""
Write-Host "  Output: $csvPath"
if ($DryRun) { Write-Host "  MODE: DRY RUN — no API calls will be made" -ForegroundColor Cyan }
Write-Host "================================================================"
Write-Host ""

try {
    for ($round = 0; $round -lt $Rounds; $round++) {

        # --- Calculate sleep until next hour boundary on first round only. ---
        if ($round -eq 0 -and -not $DryRun -and -not $StartNow) {
            $now = Get-Date
            $nextHour = $now.AddHours(1).Date.AddHours($now.Hour + 1)
            $waitMs = ($nextHour - $now).TotalMilliseconds
            if ($waitMs -gt 5000) {  # only sleep if >5s until the top of the hour
                Write-Host "Waiting $([math]::Round($waitMs / 1000))s until next hour boundary ($($nextHour.ToString('HH:mm:ss'))) ..."
                Start-Sleep -Milliseconds $waitMs
            }
        } elseif ($round -gt 0 -and -not $DryRun) {
            # Sleep ~60 minutes between rounds (minus time spent measuring).
            $roundElapsed = $roundStopwatch.Elapsed.TotalMilliseconds
            $waitMs = 3600000 - $roundElapsed
            if ($waitMs -gt 1000) {
                Write-Host "Sleeping $([math]::Round($waitMs / 1000))s until next hour ..."
                Start-Sleep -Milliseconds $waitMs
            }
        }

        $roundStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $measureTime = Get-Date
        $hourPst = $measureTime.ToString("HH")
        $hourUtc = $measureTime.ToUniversalTime().ToString("HH")
        $measuredAt = $measureTime.ToString("yyyy-MM-dd HH:mm:ss")

        Write-Host ""
        Write-Host "--- Round $($round + 1)/$Rounds  |  PST=$hourPst  UTC=$hourUtc  |  $measuredAt ---" -ForegroundColor Cyan

        foreach ($m in $Models) {
            $pairKey = "$hourPst|$($m.model_id)"

            if ($completed.ContainsKey($pairKey)) {
                Write-Host "  SKIP $($m.model_name) (hour=$hourPst already measured)"
                continue
            }

            if ($DryRun) {
                Write-Host "  [DRY] $($m.model_name) ($($m.model_id)) — would measure at max_tokens=$MaxTokens"
                continue
            }

            $r = Invoke-SpeedCall -ModelId $m.model_id

            $tps = if ($r.status -eq "success" -and $r.completion_tokens -and $r.elapsed_ms -gt 0) {
                [math]::Round($r.completion_tokens / ($r.elapsed_ms / 1000), 1)
            } else { $null }

            $cost = Get-Cost -ModelId $m.model_id -PromptTokens $r.prompt_tokens -CompletionTokens $r.completion_tokens

            # Build and write row immediately.
            $row = [PSCustomObject]@{
                run_date        = $runDate
                hour_pst        = $hourPst
                hour_utc        = $hourUtc
                model_id        = $m.model_id
                model_name      = $m.model_name
                slug            = $m.slug
                region          = $m.region
                max_tokens      = $MaxTokens
                prompt_tokens   = $r.prompt_tokens
                output_tokens   = $r.completion_tokens
                elapsed_ms      = $r.elapsed_ms
                tokens_per_sec  = $tps
                cost            = $cost
                status          = $r.status
                error           = $r.error
                measured_at     = $measuredAt
            }

            $row | Export-Csv -Path $csvPath -NoTypeInformation -Append -Force
            $completed[$pairKey] = $true
            $doneCalls++

            $tpsStr = if ($tps) { "$tps tok/s" } else { "N/A" }
            $outStr = if ($r.completion_tokens) { $r.completion_tokens } else { "—" }
            Write-Host "  $($m.model_name): status=$($r.status)  out=$outStr  $tpsStr  elapsed=$($r.elapsed_ms)ms  cost=$cost"

            Start-Sleep -Milliseconds 200
        }

        $roundStopwatch.Stop()

        # Progress summary.
        $pctDone = [math]::Round(($doneCalls / $totalCalls) * 100)
        Write-Host "  Round done. Overall: $doneCalls/$totalCalls calls ($pctDone%) in $([math]::Round($Stopwatch.Elapsed.TotalSeconds))s"
    }
} finally {
    $Stopwatch.Stop()

    # ---------------------------------------------------------------------------
    # Summary on exit (normal or Ctrl+C).
    # ---------------------------------------------------------------------------
    Write-Host ""
    Write-Host "================================================================"
    Write-Host "  Experiment ended — $doneCalls / $totalCalls measurements recorded"
    Write-Host "  Total wall time: $([math]::Round($Stopwatch.Elapsed.TotalSeconds))s"
    Write-Host "  CSV: $csvPath"

    if (Test-Path $csvPath) {
        $finalRows = Import-Csv $csvPath
        $okRows = $finalRows | Where-Object { $_.status -eq "success" }
        $errRows = $finalRows | Where-Object { $_.status -ne "success" }
        Write-Host "  Success: $($okRows.Count)  |  Errors: $($errRows.Count)"

        if ($okRows.Count -gt 0) {
            $totalCost = ($okRows | ForEach-Object {
                if ($_.cost -ne "N/A" -and $_.cost -ne "") { [double]$_.cost } else { 0 }
            } | Measure-Object -Sum).Sum
            Write-Host "  Estimated cost: `$$([math]::Round($totalCost, 5))"

            # Quick per-model speed summary.
            Write-Host ""
            Write-Host "  Per-model speed summary:"
            foreach ($m in $Models) {
                $mRows = $okRows | Where-Object { $_.model_id -eq $m.model_id }
                if ($mRows.Count -gt 0) {
                    $avgTps = [math]::Round(($mRows | ForEach-Object { [double]$_.tokens_per_sec } | Measure-Object -Average).Average, 1)
                    $minTps = [math]::Round(($mRows | ForEach-Object { [double]$_.tokens_per_sec } | Measure-Object -Minimum).Minimum, 1)
                    $maxTps = [math]::Round(($mRows | ForEach-Object { [double]$_.tokens_per_sec } | Measure-Object -Maximum).Maximum, 1)
                    Write-Host "    $($m.model_name.padRight(22)) avg=$avgTps  min=$minTps  max=$maxTps  n=$($mRows.Count)"
                } else {
                    Write-Host "    $($m.model_name.padRight(22)) no successful measurements"
                }
            }
        }
    }

    Write-Host "================================================================"
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Validate: python scripts/validate-data.py $csvPath"
    Write-Host "  2. Commit:   ./scripts/commit-data.sh `"feat(data): speed timeseries $runDate — $($okRows.Count) measurements`""
    Write-Host ""
}
