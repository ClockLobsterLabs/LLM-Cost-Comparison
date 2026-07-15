# appraise-model.ps1 — Per-model appraisal harness (3-in-1: tokenizer E + thinking tokens + speed).
#
# Measures ONE model across three dimensions and writes a single dated CSV to
# data/appraise/<slug>-<YYYY-MM-DD>.csv. Invoked once per model appraisal by the
# Appraise-Model skill (see SKILL.md → "Per-Model Appraisal Pipeline").
#
# Dimensions:
#   1. Tokenizer efficiency (E) — code/prose/blended fixed samples, max_tokens=20, temp=0.
#      Matches the Session 5 protocol (experiment-runner.ps1) exactly so values are
#      directly comparable to existing models.json tokenizer_efficiency entries.
#   2. Thinking / reasoning tokens — only when -Reasoning is set. One prose call at
#      reasoning_effort=xhigh; reads completion_tokens_details.reasoning_tokens and
#      derives thinking_token_ratio = reasoning / completion (matches run-max-test.ps1).
#   3. Token speed — max_tokens sweep [16,500,1000,2000,5000] on a fixed counting
#      prompt; records elapsed_ms + tokens_per_sec. Schema-compatible with
#      speed-benchmark-results.csv. (Fills the gap of the never-committed speed harness.)
#
# Cost enrichment is inline (formula from enrich-costs.ps1): pricing fetched from
# GET openrouter.ai/api/v1/models, cost = prompt_tokens*prompt_price + completion_tokens*completion_price.
#
# Usage:
#   pwsh scripts/appraise-model.ps1 -ModelId "z-ai/glm-5.3" -ModelName "GLM 5.3" -Family "glm" -Slug "glm-5-3"
#   pwsh scripts/appraise-model.ps1 -ModelId "deepseek/deepseek-v5-flash" -ModelName "DeepSeek V5 Flash Max" -Family "deepseek" -Slug "deepseek-v5-flash-max" -Reasoning

param(
    [Parameter(Mandatory = $true)][string]$ModelId,     # OpenRouter id, e.g. "z-ai/glm-5.3"
    [Parameter(Mandatory = $true)][string]$ModelName,   # Display name, e.g. "GLM 5.3"
    [Parameter(Mandatory = $true)][string]$Family,      # Lowercase family, e.g. "glm"
    [Parameter(Mandatory = $true)][string]$Slug,        # Canonical kebab slug, e.g. "glm-5-3"
    [switch]$Reasoning,                                 # Set if model supports reasoning_effort (adds thinking-token measurement)
    [string]$Date = (Get-Date -Format "yyyy-MM-dd")     # Date stamp for the output filename
)

. "$PSScriptRoot/../experiment-config.ps1"
$apiKey  = $script:OPENROUTER_API_KEY
$baseUrl = "https://openrouter.ai/api/v1/chat/completions"
$dataDir = "$PSScriptRoot/../data"
$outDir  = "$dataDir/appraise"
$samplesPath = "$dataDir/samples"

# Standardized fixed samples — identical to experiment-runner.ps1 / Session 5.
$Samples = @{
    code    = @{ path = "$samplesPath/code-sample.txt";    words = 306 }
    prose   = @{ path = "$samplesPath/prose-sample.txt";   words = 235 }
    blended = @{ path = "$samplesPath/blended-sample.txt"; words = 250 }
}

$headers = @{
    "Authorization" = "Bearer $apiKey"
    "Content-Type"  = "application/json"
    "HTTP-Referer"  = "https://github.com/ClockLobsterLabs/LLM-Cost-Comparison"
}

# ---------------------------------------------------------------------------
# Fetch live pricing for cost enrichment (enrich-costs.ps1 pattern)
# ---------------------------------------------------------------------------
Write-Host "Fetching OpenRouter pricing..."
$orModels = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/models" -Headers @{ "Authorization" = "Bearer $apiKey" }
$pricing = $null
$modelMatch = $orModels.data | Where-Object { $_.id -eq $ModelId } | Select-Object -First 1
if ($modelMatch) {
    $pricing = @{
        prompt     = [double]$modelMatch.pricing.prompt
        completion = [double]$modelMatch.pricing.completion
    }
    Write-Host "  Pricing for $ModelId : prompt=`$$($pricing.prompt) completion=`$$($pricing.completion) / 1k tok"
} else {
    Write-Host "  WARNING: $ModelId not found in OpenRouter catalog — cost will be N/A"
}

function Get-Cost {
    param($PromptTokens, $CompletionTokens)
    if ($null -eq $pricing -or -not $PromptTokens -or -not $CompletionTokens) { return "N/A" }
    $c = ([double]$PromptTokens * $pricing.prompt + [double]$CompletionTokens * $pricing.completion)
    return [math]::Round($c, 8)
}

# ---------------------------------------------------------------------------
# Shared API call helper
# ---------------------------------------------------------------------------
function Invoke-Call {
    param($Messages, $MaxTokens, $ReasoningEffort, $WordCount)

    $body = @{ model = $ModelId; messages = $Messages; max_tokens = $MaxTokens; temperature = 0 }
    if ($ReasoningEffort) { $body.reasoning_effort = $ReasoningEffort }
    $jsonBody = $body | ConvertTo-Json -Compress -Depth 5

    $start = Get-Date
    try {
        $resp = Invoke-RestMethod -Uri $baseUrl -Method Post -Headers $headers -Body $jsonBody -ContentType "application/json" -TimeoutSec 120
        $elapsed = (Get-Date) - $start
        $pt = $resp.usage.prompt_tokens
        $ct = $resp.usage.completion_tokens
        $rt = if ($resp.usage.completion_tokens_details) { [int]$resp.usage.completion_tokens_details.reasoning_tokens } else { 0 }
        return @{
            status = "success"; error = ""
            prompt_tokens = $pt; completion_tokens = $ct; reasoning_tokens = $rt
            elapsed_ms = [math]::Round($elapsed.TotalMilliseconds)
            tokens_per_word = if ($WordCount -and $pt) { [math]::Round($pt / $WordCount, 2) } else { $null }
            cost = (Get-Cost $pt $ct)
        }
    } catch {
        $elapsed = (Get-Date) - $start
        $msg = $_.Exception.Message
        $status = "error"
        if ($msg -match "404") { $status = "not_found" }
        elseif ($msg -match "timeout|timed out") { $status = "timeout" }
        elseif ($msg -match "guardrail|blocked|429") { $status = "blocked" }
        return @{
            status = $status; error = ($msg.Substring(0, [math]::Min(200, $msg.Length)))
            prompt_tokens = $null; completion_tokens = $null; reasoning_tokens = $null
            elapsed_ms = [math]::Round($elapsed.TotalMilliseconds); tokens_per_word = $null; cost = "N/A"
        }
    }
}

$rows = [System.Collections.Generic.List[PSObject]]::new()
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$callNum = 0

# Speed sweep uses the same fixed counting prompt as close-gaps-exp3-exp4.ps1 (Exp 4).
$speedPrompt = "Write the numbers from 1 to 200, comma-separated."
$speedSettings = @(16, 500, 1000, 2000, 5000)

# Count total calls for the progress display.
$totalCalls = $Samples.Count + $speedSettings.Count + $(if ($Reasoning) { 1 } else { 0 })
Write-Host ""
Write-Host "=== Appraise $ModelName ($ModelId) — $totalCalls calls ==="
Write-Host "  Tokenizer E: $($Samples.Count) samples | Speed: $($speedSettings.Count) settings$(if ($Reasoning) { " | Thinking: 1 call (xhigh)" })"
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Tokenizer efficiency (E) — code / prose / blended, max_tokens=20
# ---------------------------------------------------------------------------
foreach ($st in @("code", "prose", "blended")) {
    $callNum++
    $text = Get-Content -Raw $Samples[$st].path
    $wc   = $Samples[$st].words
    $r = Invoke-Call -Messages @(@{ role = "user"; content = $text }) -MaxTokens 20 -ReasoningEffort $null -WordCount $wc
    $rows.Add([PSCustomObject]@{
        model_id=$ModelId; model_name=$ModelName; family=$Family; slug=$Slug; date=$Date
        measurement="tokenizer_E"; sample_type=$st; reasoning_effort="none"
        max_tokens=20; prompt_tokens=$r.prompt_tokens; output_tokens=$r.completion_tokens
        reasoning_tokens=$r.reasoning_tokens; elapsed_ms=$r.elapsed_ms
        tokens_per_sec=$null; tokens_per_word=$r.tokens_per_word; blend_60_40=$null
        cost=$r.cost; status=$r.status; error=$r.error
    })
    Write-Host ("  [{0}/{1}] E/{2} -> {3}  prompt={4}  E={5}" -f $callNum, $totalCalls, $st, $r.status, $r.prompt_tokens, $r.tokens_per_word)
    Start-Sleep -Milliseconds 200
}

# ---------------------------------------------------------------------------
# 2. Thinking / reasoning tokens — prose sample, reasoning_effort=xhigh
# ---------------------------------------------------------------------------
$thinkRatio = 0
if ($Reasoning) {
    $callNum++
    $text = Get-Content -Raw $Samples["prose"].path
    $wc   = $Samples["prose"].words
    $r = Invoke-Call -Messages @(@{ role = "user"; content = $text }) -MaxTokens 20 -ReasoningEffort "xhigh" -WordCount $wc
    if ($r.status -eq "success" -and $r.completion_tokens -gt 0) {
        $thinkRatio = [math]::Round($r.reasoning_tokens / $r.completion_tokens, 2)
    }
    $rows.Add([PSCustomObject]@{
        model_id=$ModelId; model_name=$ModelName; family=$Family; slug=$Slug; date=$Date
        measurement="thinking_tokens"; sample_type="prose"; reasoning_effort="xhigh"
        max_tokens=20; prompt_tokens=$r.prompt_tokens; output_tokens=$r.completion_tokens
        reasoning_tokens=$r.reasoning_tokens; elapsed_ms=$r.elapsed_ms
        tokens_per_sec=$null; tokens_per_word=$r.tokens_per_word; blend_60_40=$null
        cost=$r.cost; status=$r.status; error=$r.error
    })
    Write-Host ("  [{0}/{1}] THINK/xhigh -> {2}  reasoning={3}  ratio={4}" -f $callNum, $totalCalls, $r.status, $r.reasoning_tokens, $thinkRatio)
    Start-Sleep -Milliseconds 200
}

# ---------------------------------------------------------------------------
# 3. Token speed — max_tokens sweep
# ---------------------------------------------------------------------------
foreach ($mt in $speedSettings) {
    $callNum++
    $r = Invoke-Call -Messages @(@{ role = "user"; content = $speedPrompt }) -MaxTokens $mt -ReasoningEffort $null -WordCount 0
    $tps = if ($r.status -eq "success" -and $r.completion_tokens -and $r.elapsed_ms -gt 0) {
        [math]::Round($r.completion_tokens / ($r.elapsed_ms / 1000), 1)
    } else { $null }
    $rows.Add([PSCustomObject]@{
        model_id=$ModelId; model_name=$ModelName; family=$Family; slug=$Slug; date=$Date
        measurement="speed"; sample_type="numbers"; reasoning_effort="none"
        max_tokens=$mt; prompt_tokens=$r.prompt_tokens; output_tokens=$r.completion_tokens
        reasoning_tokens=$r.reasoning_tokens; elapsed_ms=$r.elapsed_ms
        tokens_per_sec=$tps; tokens_per_word=$null; blend_60_40=$null
        cost=$r.cost; status=$r.status; error=$r.error
    })
    Write-Host ("  [{0}/{1}] SPEED/max={2} -> {3}  out={4}  tps={5}" -f $callNum, $totalCalls, $mt, $r.status, $r.completion_tokens, $tps)
    Start-Sleep -Milliseconds 200
}

$Stopwatch.Stop()

# ---------------------------------------------------------------------------
# Write output CSV + print summary
# ---------------------------------------------------------------------------
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = "$outDir/$Slug-$Date.csv"
$rows | Export-Csv -Path $outPath -NoTypeInformation -Force

# Derive headline E blend (60:40 code:prose) and a representative speed (1000-tok setting).
$eCode = ($rows | Where-Object { $_.measurement -eq "tokenizer_E" -and $_.sample_type -eq "code" -and $_.status -eq "success" } | Select-Object -First 1).tokens_per_word
$eProse = ($rows | Where-Object { $_.measurement -eq "tokenizer_E" -and $_.sample_type -eq "prose" -and $_.status -eq "success" } | Select-Object -First 1).tokens_per_word
$blend60 = if ($eCode -and $eProse) { [math]::Round(0.6 * [double]$eCode + 0.4 * [double]$eProse, 2) } else { $null }
$speed1000 = ($rows | Where-Object { $_.measurement -eq "speed" -and $_.max_tokens -eq 1000 -and $_.status -eq "success" } | Select-Object -First 1).tokens_per_sec
$okCount = ($rows | Where-Object { $_.status -eq "success" }).Count
$totalCost = ($rows | Where-Object { $_.cost -ne "N/A" } | ForEach-Object { [double]$_.cost } | Measure-Object -Sum).Sum

Write-Host ""
Write-Host "=== Appraisal complete ==="
Write-Host "  Calls: $okCount/$($rows.Count) success in $([math]::Round($Stopwatch.Elapsed.TotalSeconds))s"
Write-Host "  Estimated cost: `$$([math]::Round($totalCost, 5))"
Write-Host ""
Write-Host "  Headline metrics:"
Write-Host "    tokenizer_efficiency (blend 60:40): $blend60"
Write-Host "    thinking_token_ratio:               $thinkRatio"
Write-Host "    speed_tok_per_s (max_tokens=1000):   $speed1000"
Write-Host ""
Write-Host "  Raw CSV: $outPath"
Write-Host ""
Write-Host "  Next (skill steps): research SWE-bench Verified/Pro, update models.json,"
Write-Host "  build comparison table, generate News post, commit + push both repos."
