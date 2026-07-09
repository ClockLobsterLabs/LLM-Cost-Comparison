$existing = Import-Csv "$PSScriptRoot/../data/experiment-session5-summary.csv"
$expansion = Import-Csv "$PSScriptRoot/../data/experiment-s5-expansion-summary.csv"

$tierMap = @{
    "DeepSeek V4 Pro" = "taskrunner"; "Claude Fable 5" = "complex"; "Claude Opus 4.8" = "complex"
    "Claude Opus 4.7" = "complex"; "Claude Opus 4.6" = "complex"; "Claude Sonnet 5" = "daily"
    "Claude Sonnet 4.6" = "daily"; "GPT-5.5" = "complex"; "GPT-5.5 Pro" = "complex"
    "GPT-5.4" = "daily"; "GPT-5.4 Mini" = "taskrunner"; "GPT-5.2" = "daily"
    "GPT-5.3 Codex Spark" = "daily"; "o4-mini" = "taskrunner"
    "Gemini 3.1 Pro" = "daily"; "Gemini 3.5 Flash" = "daily"; "Gemini 3 Flash" = "taskrunner"
    "Kimi K2.6" = "taskrunner"; "Grok Build 0.1" = "budget_taskrunner"
    "Qwen3.7 Max" = "taskrunner"; "Qwen3.7 Plus" = "budget_taskrunner"
    "MiMo-V2.5" = "free"; "North Mini Code Free" = "free"
    "Nemotron 3 Ultra Free" = "free"; "GPT-5 Nano" = "budget_taskrunner"
    "Perplexity Sonar Pro Search" = "daily"; "Perplexity Sonar Pro" = "daily"
    "GPT-5.4 Nano" = "budget_taskrunner"; "Phi-4" = "budget_taskrunner"; "o3-mini" = "taskrunner"
    "Kimi K2.7 Code" = "taskrunner"; "Llama 3.3 70B" = "budget_taskrunner"
    "Llama 4 Maverick" = "budget_taskrunner"; "GLM 5.2" = "taskrunner"; "Codestral" = "budget_taskrunner"
    "Mistral Large 3" = "budget_taskrunner"; "DeepSeek Chat V3" = "budget_taskrunner"
    "DeepSeek R1" = "taskrunner"; "DeepSeek V4 Flash" = "budget_taskrunner"
    "DeepSeek V3.2" = "budget_taskrunner"; "MiniMax M3" = "budget_taskrunner"
    "Amazon Nova Pro" = "taskrunner"; "Command A" = "daily"
    "Gemini 2.5 Pro" = "daily"; "Claude Haiku 4.5" = "taskrunner"
    "Amazon Nova Premier" = "daily"; "Grok 4.5" = "taskrunner"
    "Jamba Large 1.7" = "free"
}

$combined = $existing + $expansion
if (-not ($combined | Where-Object { $_.model_name -eq "Jamba Large 1.7" })) {
    $combined += [PSCustomObject]@{rank=0;family="ai21";model_id="ai21/jamba-large-1.7";model_name="Jamba Large 1.7";e_code=2.82;e_prose=1.22;e_blended=1.90;blend_60_40=2.18;blend_33_33_33=1.98}
}

$sorted = $combined | Sort-Object { if ($_.blend_60_40) { [double]$_.blend_60_40 } else { 999 } }
$output = @(); $i = 1
foreach ($m in $sorted) {
    $tier = if ($tierMap.ContainsKey($m.model_name)) { $tierMap[$m.model_name] } else { "unknown" }
    $output += [PSCustomObject]@{rank=$i;family=$m.family;model_id=$m.model_id;model_name=$m.model_name;tier=$tier;e_code=$m.e_code;e_prose=$m.e_prose;e_blended=$m.e_blended;blend_60_40=$m.blend_60_40;blend_33_33_33=$m.blend_33_33_33}
    $i++
}

$output | Export-Csv "$PSScriptRoot/../data/experiment-s5-all-summary.csv" -NoTypeInformation -Force
Write-Host "=== S5 TOKENIZER EFFICIENCY — FULL RANKING ==="
foreach ($m in $output) {
    Write-Host ("{0,2}. [{1,-20}] {2,-25} code={3} prose={4} 60:40={5}" -f $m.rank, $m.tier, $m.model_name, $m.e_code, $m.e_prose, $m.blend_60_40)
}
Write-Host "`nTotal: $($output.Count) models | Not testable: DeepSeek V4 Flash Max, V4 Pro Max, V4 Flash Free, Big Pickle"
