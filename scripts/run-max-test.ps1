. "$PSScriptRoot/../experiment-config.ps1"
$key = $script:OPENROUTER_API_KEY
$samplesPath = "$PSScriptRoot/../data/samples"

$samples = @{
    code = Get-Content "$samplesPath/code-sample.txt" -Raw
    prose = Get-Content "$samplesPath/prose-sample.txt" -Raw
    blended = Get-Content "$samplesPath/blended-sample.txt" -Raw
}

$wordCounts = @{ code = 306; prose = 235; blended = 250 }

$models = @(
    @{ id = "deepseek/deepseek-v4-flash"; name = "DeepSeek V4 Flash Max" },
    @{ id = "deepseek/deepseek-v4-pro"; name = "DeepSeek V4 Pro Max" }
)

$results = @()
foreach ($m in $models) {
    foreach ($st in $samples.Keys) {
        $body = @{
            model = $m.id
            messages = @(@{ role = "user"; content = $samples[$st] })
            max_tokens = 20
            temperature = 0
            reasoning_effort = "xhigh"
        } | ConvertTo-Json

        $resp = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers @{
            "Authorization" = "Bearer $key"
            "HTTP-Referer" = "https://clocklobsterlabs.com"
        }
        
        $u = $resp.usage
        $pt = $u.prompt_tokens
        $ct = $u.completion_tokens
        $rt = if ($u.completion_tokens_details) { $u.completion_tokens_details.reasoning_tokens } else { 0 }
        $tokensPerWord = [math]::Round($pt / $wordCounts[$st], 2)

        Write-Host "$($m.name) | $st | prompt=$pt | completion=$ct | reasoning=$rt | E=$tokensPerWord"

        $results += [PSCustomObject]@{
            model_id = $m.id
            model_name = $m.name
            family = if ($m.name -match "Flash") { "deepseek" } else { "deepseek" }
            sample_type = $st
            word_count = $wordCounts[$st]
            prompt_tokens = $pt
            completion_tokens = $ct
            reasoning_tokens = $rt
            tokens_per_word = $tokensPerWord
            max_tokens = 20
            temperature = 0
            reasoning_effort = "xhigh"
            status = "success"
        }
        Start-Sleep -Seconds 2
    }
}

$results | Export-Csv "$PSScriptRoot/../data/experiment-s5-max-variants-raw.csv" -NoTypeInformation -Force

Write-Host "`n=== SUMMARY ==="
$summary = $results | Group-Object model_name | ForEach-Object {
    $name = $_.Name
    $code = ($_.Group | Where-Object { $_.sample_type -eq "code" }).tokens_per_word
    $prose = ($_.Group | Where-Object { $_.sample_type -eq "prose" }).tokens_per_word
    $blended = ($_.Group | Where-Object { $_.sample_type -eq "blended" }).tokens_per_word
    Write-Host "$name | code=$code | prose=$prose | blended=$blended | 60:40=$([math]::Round(0.6*$code + 0.4*$prose, 2))"
}

Write-Host "`nDone. Saved to data/experiment-s5-max-variants-raw.csv"
