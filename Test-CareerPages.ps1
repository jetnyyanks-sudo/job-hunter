<#
.SYNOPSIS
    Validates all career page URLs in career_pages.json.
.DESCRIPTION
    Hits each URL and checks for HTTP 200 response. Reports failures so you
    can fix broken URLs before they waste time on daily scrape runs.
.EXAMPLE
    .\Test-CareerPages.ps1
    .\Test-CareerPages.ps1 -FixRedirects
#>

[CmdletBinding()]
param(
    [switch]$FixRedirects
)

$careerPagesPath = "$PSScriptRoot\career_pages.json"
if (-not (Test-Path $careerPagesPath)) {
    Write-Error "career_pages.json not found at: $careerPagesPath"
    exit 1
}

$data = Get-Content -Path $careerPagesPath -Raw | ConvertFrom-Json
$companies = $data.companies

Write-Host "`nValidating $($companies.Count) career page URLs...`n" -ForegroundColor Cyan

$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    "Accept"     = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
}

$results = @{
    ok      = @()
    failed  = @()
    redirect = @()
}

$i = 0
foreach ($company in $companies) {
    $i++
    $name = $company.name
    $url = $company.url
    Write-Host "  [$i/$($companies.Count)] $name... " -NoNewline

    try {
        $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
        $statusCode = $response.StatusCode

        if ($statusCode -eq 200) {
            # Check if page has meaningful content (not just a blank page or error)
            $contentLength = $response.Content.Length
            if ($contentLength -lt 500) {
                Write-Host "WARN (tiny page: $contentLength bytes)" -ForegroundColor Yellow
                $results.failed += [PSCustomObject]@{ Name = $name; Url = $url; Issue = "Page too small ($contentLength bytes)" }
            }
            else {
                Write-Host "OK ($contentLength bytes)" -ForegroundColor Green
                $results.ok += $name
            }
        }
        else {
            Write-Host "HTTP $statusCode" -ForegroundColor Yellow
            $results.failed += [PSCustomObject]@{ Name = $name; Url = $url; Issue = "HTTP $statusCode" }
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        # Handle redirects (3xx responses)
        if ($errorMsg -match '(301|302|303|307|308)' -or $errorMsg -match 'Maximum.*redirect') {
            try {
                # Follow the redirect to see where it goes
                $redirectResponse = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 5 -ErrorAction Stop
                $finalUrl = $url
                if ($redirectResponse.BaseResponse.ResponseUri) {
                    $finalUrl = $redirectResponse.BaseResponse.ResponseUri.ToString()
                }
                Write-Host "REDIRECT -> OK" -ForegroundColor Yellow
                $results.redirect += [PSCustomObject]@{ Name = $name; OriginalUrl = $url; FinalUrl = $finalUrl }
                $results.ok += $name
            }
            catch {
                Write-Host "REDIRECT -> FAIL" -ForegroundColor Red
                $results.failed += [PSCustomObject]@{ Name = $name; Url = $url; Issue = "Redirect failed: $($_.Exception.Message)" }
            }
        }
        # Handle Cloudflare challenges, bot detection
        elseif ($errorMsg -match '(403|406|429)' -or $errorMsg -match 'Forbidden') {
            Write-Host "BLOCKED (bot detection)" -ForegroundColor Yellow
            $results.failed += [PSCustomObject]@{ Name = $name; Url = $url; Issue = "Bot blocked (403/Cloudflare)" }
        }
        # Handle timeouts
        elseif ($errorMsg -match 'timed out') {
            Write-Host "TIMEOUT" -ForegroundColor Red
            $results.failed += [PSCustomObject]@{ Name = $name; Url = $url; Issue = "Timeout" }
        }
        # Handle DNS / connection failures
        elseif ($errorMsg -match '(404|410)' -or $errorMsg -match 'Not Found') {
            Write-Host "NOT FOUND (404)" -ForegroundColor Red
            $results.failed += [PSCustomObject]@{ Name = $name; Url = $url; Issue = "404 Not Found" }
        }
        else {
            Write-Host "ERROR: $errorMsg" -ForegroundColor Red
            $results.failed += [PSCustomObject]@{ Name = $name; Url = $url; Issue = $errorMsg }
        }
    }

    Start-Sleep -Milliseconds 500
}

# Summary
Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  VALIDATION RESULTS" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  OK:       $($results.ok.Count)" -ForegroundColor Green
Write-Host "  Redirect: $($results.redirect.Count)" -ForegroundColor Yellow
Write-Host "  Failed:   $($results.failed.Count)" -ForegroundColor Red
Write-Host "════════════════════════════════════════════════════════════`n" -ForegroundColor DarkCyan

if ($results.failed.Count -gt 0) {
    Write-Host "FAILED URLs (need fixing):" -ForegroundColor Red
    foreach ($fail in $results.failed) {
        Write-Host "  $($fail.Name): $($fail.Issue)" -ForegroundColor Red
        Write-Host "    $($fail.Url)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

if ($results.redirect.Count -gt 0) {
    Write-Host "REDIRECTED (working but URL could be updated):" -ForegroundColor Yellow
    foreach ($redir in $results.redirect) {
        Write-Host "  $($redir.Name)" -ForegroundColor Yellow
        Write-Host "    From: $($redir.OriginalUrl)" -ForegroundColor DarkGray
        Write-Host "    To:   $($redir.FinalUrl)" -ForegroundColor DarkGray
    }
    Write-Host ""
}
