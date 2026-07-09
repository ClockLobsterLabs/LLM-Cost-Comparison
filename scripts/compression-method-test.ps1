# Compression Method Test — DeepSeek V4 Pro (Max mode: reasoning=xhigh)
# Phase A: Baseline tokenizer efficiency (max_tokens=20) — compare to Session 5
# Phase B: 6 conditions × 3 samples = 18 calls for compression comparison

. "$PSScriptRoot/../experiment-config.ps1"

$apiKey = $script:OPENROUTER_API_KEY
$modelId = "deepseek/deepseek-v4-pro"
$baseUrl = "https://openrouter.ai/api/v1/chat/completions"
$outDir = "$PSScriptRoot/../data/compression-test"
$null = New-Item -ItemType Directory -Path $outDir -Force

# Max mode reasoning config
$maxReasoning = @{ enabled = $true; effort = "xhigh" }

# --- Load samples ---
$samples = @{
    code    = @{ path = "$PSScriptRoot/../data/samples/code-sample.txt";    word_count = 306 }
    prose   = @{ path = "$PSScriptRoot/../data/samples/prose-sample.txt";   word_count = 235 }
    blended = @{ path = "$PSScriptRoot/../data/samples/blended-sample.txt"; word_count = 250 }
}

# --- System prompts ---
$conditions = @{
    baseline = "You are a helpful assistant. Complete the text naturally."
    smc      = "You are a Structured Markdown Compressor. Use tables, code blocks, lists. No prose fillers. No introductions or conclusions. Format carries information."
    json_env = "You are a JSON-Envelope responder. Each response is a single JSON object with minimal keys. No text outside JSON. Use short keys (t/c/k). Code in 'code' field."
    diff_only= "You are a Diff-Only responder. Output ONLY changed lines in unified diff format. No explanations. The diff is the explanation. Code unchanged."
    verb_noun= "You are a Constrained Grammar responder. Subject-verb-object only. No adjectives, adverbs, qualifiers, conjunctions. One statement per line. Fragments OK."
    word_del = "You are a Stop-Word Remover. Remove ALL determiners (a/an/the/this/that), qualifiers (very/quite/just/really), transitions (however/therefore/meanwhile), auxiliary verbs (is/was/have/been). Keep only content words. Code unchanged."
}

# --- Headers ---
$headers = @{
    "Authorization" = "Bearer $apiKey"
    "Content-Type"  = "application/json"
    "HTTP-Referer"  = "https://github.com/ClockLobsterLabs/LLM-Cost-Comparison"
}

# --- Results storage ---
$results = @()

# ========== PHASE A: Baseline tokenizer efficiency (max_tokens=20) ==========
Write-Host "=== PHASE A: Baseline tokenizer efficiency (max_tokens=20) ==="
foreach ($sampleName in $samples.Keys) {
    $sample = $samples[$sampleName]
    $promptText = Get-Content $sample.path -Raw
    Write-Host "  $sampleName..."

    $body = @{
        model     = $modelId
        reasoning = $maxReasoning
        messages  = @(
            @{ role = "system"; content = "You are a helpful assistant. Complete the text naturally." },
            @{ role = "user";   content = "Complete this text:`n`n$promptText" }
        )
        max_tokens = 20
        temperature = 0.0
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $baseUrl -Method Post -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 120
        $outputTokens = $response.usage.completion_tokens
        $promptTokens = $response.usage.prompt_tokens
        $content = $response.choices[0].message.content
        $outputWords = ($content -split '\s+' | Where-Object { $_ -ne '' }).Count
        $tokensPerWord = if ($outputWords -gt 0) { [math]::Round($outputTokens / $outputWords, 2) } else { $null }

        Write-Host "    Tokens: $outputTokens | Words: $outputWords | E: $tokensPerWord"

        $results += [PSCustomObject]@{
            phase      = "A-baseline"
            condition  = "baseline"
            sample     = $sampleName
            sample_words = $sample.word_count
            prompt_tokens = $promptTokens
            output_tokens = $outputTokens
            output_words  = $outputWords
            tokens_per_word = $tokensPerWord
            max_tokens = 20
            status     = "success"
        }
    } catch {
        Write-Host "    ERROR: $($_.Exception.Message)"
        $results += [PSCustomObject]@{ phase="A-baseline"; condition="baseline"; sample=$sampleName; status="error:$($_.Exception.Message)" }
    }
    Start-Sleep -Seconds 1
}

# ========== PHASE B: Compression method comparison (max_tokens=200) ==========
Write-Host "`n=== PHASE B: Compression comparison (max_tokens=200) ==="
$call = 0
$totalCalls = $samples.Keys.Count * $conditions.Keys.Count

foreach ($sampleName in $samples.Keys) {
    $sample = $samples[$sampleName]
    $promptText = Get-Content $sample.path -Raw

    foreach ($condName in $conditions.Keys) {
        $call++
        Write-Host "[$call/$totalCalls] $sampleName / $condName..."

        $body = @{
            model     = $modelId
            reasoning = $maxReasoning
            messages  = @(
                @{ role = "system"; content = $conditions[$condName] },
                @{ role = "user";   content = "Complete this text naturally:`n`n$promptText" }
            )
            max_tokens = 200
            temperature = 0.7
        } | ConvertTo-Json -Depth 5

        try {
            $response = Invoke-RestMethod -Uri $baseUrl -Method Post -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 120

            $outputTokens = $response.usage.completion_tokens
            $promptTokens = $response.usage.prompt_tokens
            $content = $response.choices[0].message.content
            $outputWords = ($content -split '\s+' | Where-Object { $_ -ne '' }).Count
            $tokensPerWord = if ($outputWords -gt 0) { [math]::Round($outputTokens / $outputWords, 2) } else { $null }

            # Save raw content
            $content | Out-File "$outDir/$condName`_$sampleName`_raw.txt" -Encoding utf8

            Write-Host "    Out tok: $outputTokens | Words: $outputWords | E: $tokensPerWord"

            $results += [PSCustomObject]@{
                phase      = "B-compression"
                condition  = $condName
                sample     = $sampleName
                sample_words = $sample.word_count
                prompt_tokens = $promptTokens
                output_tokens = $outputTokens
                output_words  = $outputWords
                tokens_per_word = $tokensPerWord
                max_tokens = 200
                status     = "success"
            }
        } catch {
            Write-Host "    ERROR: $($_.Exception.Message)"
            $results += [PSCustomObject]@{ phase="B-compression"; condition=$condName; sample=$sampleName; status="error:$($_.Exception.Message)" }
        }
        Start-Sleep -Seconds 1
    }
}

# --- Save all results ---
$csvPath = "$outDir/compression-method-results.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "`nResults saved to $csvPath"

# --- REPORT ---
Write-Host "`n`n========================================"
Write-Host "=== COMPRESSION METHOD TEST REPORT ==="
Write-Host "Model: DeepSeek V4 Pro (Max reasoning)"
Write-Host "========================================"

# Phase A summary
Write-Host "`n--- Phase A: Baseline Tokenizer Efficiency (max_tokens=20) ---"
Write-Host ("{0,-10} {1,-10} {2,-10} {3,-10} {4,-12}" -f "Sample", "Out Tok", "Out Words", "E (t/w)", "S5 Ref")
Write-Host ("{0,-10} {1,-10} {2,-10} {3,-10} {4,-12}" -f ("-"*10), ("-"*10), ("-"*10), ("-"*10), ("-"*12))
foreach ($r in $results | Where-Object { $_.phase -eq "A-baseline" -and $_.status -eq "success" }) {
    Write-Host ("{0,-10} {1,6}    {2,6}    {3,6}    {4,-12}" -f $r.sample, $r.output_tokens, $r.output_words, $r.tokens_per_word, "N/A")
}

# Phase B summary
Write-Host "`n--- Phase B: Compression Comparison (max_tokens=200) ---"
Write-Host ("{0,-12} {1,-10} {2,-10} {3,-10} {4,-10} {5,-10}" -f "Condition", "Sample", "Out Tok", "Out Words", "E (t/w)", "vs Base")
Write-Host ("{0,-12} {1,-10} {2,-10} {3,-10} {4,-10} {5,-10}" -f ("-"*12), ("-"*10), ("-"*10), ("-"*10), ("-"*10), ("-"*10))

$baselinesB = @{}
foreach ($r in $results | Where-Object { $_.phase -eq "B-compression" -and $_.condition -eq "baseline" -and $_.status -eq "success" }) {
    $baselinesB[$r.sample] = $r
}

foreach ($condName in $conditions.Keys) {
    foreach ($sampleName in $samples.Keys) {
        $r = $results | Where-Object { $_.phase -eq "B-compression" -and $_.condition -eq $condName -and $_.sample -eq $sampleName -and $_.status -eq "success" } | Select-Object -First 1
        if (-not $r) { continue }
        $vsBase = ""
        if ($condName -ne "baseline" -and $baselinesB.ContainsKey($sampleName) -and $baselinesB[$sampleName].output_tokens -gt 0) {
            $saved = [math]::Round(($baselinesB[$sampleName].output_tokens - $r.output_tokens) / $baselinesB[$sampleName].output_tokens * 100, 1)
            $vsBase = "$saved%"
        } elseif ($condName -eq "baseline") {
            $vsBase = "ref"
        }
        Write-Host ("{0,-12} {1,-10} {2,7}    {3,7}    {4,7}    {5,-10}" -f $condName, $sampleName, $r.output_tokens, $r.output_words, $r.tokens_per_word, $vsBase)
    }
}

# Overall stats
Write-Host "`n--- Overall Savings per Condition ---"
$baselineTotal = ($results | Where-Object { $_.phase -eq "B-compression" -and $_.condition -eq "baseline" -and $_.status -eq "success" } | Measure-Object output_tokens -Sum).Sum
if (-not $baselineTotal) { $baselineTotal = 0 }

foreach ($condName in $conditions.Keys) {
    if ($condName -eq "baseline") { continue }
    $condResults = $results | Where-Object { $_.phase -eq "B-compression" -and $_.condition -eq $condName -and $_.status -eq "success" }
    $condTotal = ($condResults | Measure-Object output_tokens -Sum).Sum
    if ($baselineTotal -gt 0 -and $condTotal -gt 0) {
        $pct = [math]::Round(($baselineTotal - $condTotal) / $baselineTotal * 100, 1)
        Write-Host "  $condName : $pct% fewer tokens than baseline"
    }
}
