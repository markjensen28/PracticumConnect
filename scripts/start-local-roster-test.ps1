$ErrorActionPreference = 'Stop'
$env:APP_ORIGIN = 'http://localhost:52740'
$env:SCHOOL_EMAIL_FROM = 'onboarding@resend.dev'
$key = Read-Host 'Enter your Resend sending key for this session' -AsSecureString
$env:RESEND_API_KEY = [System.Net.NetworkCredential]::new('', $key).Password
try {
    if (-not $env:RESEND_API_KEY) { throw 'A Resend sending key is required.' }
    node (Join-Path $PSScriptRoot '../tools/approval_server.mjs')
} finally {
    Remove-Item Env:RESEND_API_KEY -ErrorAction SilentlyContinue
}
