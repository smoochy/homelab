param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgsFromCaller
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PythonScript = Join-Path $ScriptDir "cloudflare_trusted_ips.py"
$EnvFile = if ($env:CLOUDFLARE_TRUSTED_IPS_ENV_FILE) {
    $env:CLOUDFLARE_TRUSTED_IPS_ENV_FILE
} else {
    Join-Path $ScriptDir ".env"
}

if (Get-Command uv -ErrorAction SilentlyContinue) {
    & uv run python $PythonScript --env-file $EnvFile @ArgsFromCaller
    exit $LASTEXITCODE
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    & python $PythonScript --env-file $EnvFile @ArgsFromCaller
    exit $LASTEXITCODE
}

Write-Error "missing required command: uv or python"
exit 1
