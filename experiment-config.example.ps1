# LLM Cost Comparison — Local Experiment Configuration
# =============================================================================
# Copy this file to experiment-config.ps1 (gitignored) and set your key.
#
#   cp experiment-config.example.ps1 experiment-config.ps1
#   # Then set OPENROUTER_API_KEY in your shell before running experiments.
#
# The experiment runner will fail fast if OPENROUTER_API_KEY is not set.
# Never commit a real API key to the repo.

# The actual key is read from $env:OPENROUTER_API_KEY at runtime.
# Set it in your profile or session before invoking any experiment script.
