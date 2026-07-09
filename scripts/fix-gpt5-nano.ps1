. "$PSScriptRoot/../experiment-config.ps1"
$headers = @{"Authorization"="Bearer $script:OPENROUTER_API_KEY";"Content-Type"="application/json";"HTTP-Referer"="https://github.com/ClockLobsterLabs/LLM-Cost-Comparison"}

$paths = @{code="$PSScriptRoot/../data/samples/code-sample.txt";prose="$PSScriptRoot/../data/samples/prose-sample.txt";blended="$PSScriptRoot/../data/samples/blended-sample.txt"}
$words = @{code=306;prose=235;blended=250}

$newRows = @()
foreach ($st in @("code","prose","blended")) {
    $text = Get-Content -Raw $paths[$st]
    $body = @{model="openai/gpt-5-nano";messages=@(@{role="user";content=$text});max_tokens=100;temperature=0}|ConvertTo-Json -Compress
    $resp = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/chat/completions" -Method Post -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 30
    $pt = $resp.usage.prompt_tokens
    $ot = $resp.usage.completion_tokens
    $e = [math]::Round($pt/$words[$st],2)
    Write-Host ("{0}: prompt={1} output={2} E={3}" -f $st, $pt, $ot, $e)
    $newRows += [PSCustomObject]@{
        trial_id="$("openai/gpt-5-nano"):$st"
        model_id="openai/gpt-5-nano"
        model_name="GPT-5 Nano"
        family="openai"
        sample_type=$st
        word_count=$words[$st]
        prompt_tokens=$pt
        output_tokens=$ot
        tokens_per_word=$e
        cost="N/A"
        tokens_per_sec="N/A"
        status="success"
        error=$null
        elapsed_ms=0
        max_tokens=100
        temperature=0
    }
    Start-Sleep -Milliseconds 500
}

$csv = Import-Csv "$PSScriptRoot/../data/experiment-s5-expansion-raw.csv"
$filtered = $csv | Where-Object { $_.model_id -ne "openai/gpt-5-nano" }
$merged = $filtered + $newRows
$merged | Export-Csv "$PSScriptRoot/../data/experiment-s5-expansion-raw.csv" -NoTypeInformation -Force
Write-Host "Updated CSV: $($merged.Count) rows (removed 3 old GPT-5 Nano rows, added 3 new)"
