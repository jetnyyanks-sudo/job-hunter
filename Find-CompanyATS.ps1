<#
.SYNOPSIS
    Identifies which ATS platform a company uses based on their careers page.
.DESCRIPTION
    Give it a company's careers URL and it will tell you which ATS they use
    so you know which section of config.json to add them to.
.EXAMPLE
    .\Find-CompanyATS.ps1 -Url "https://boards.greenhouse.io/hashicorp"
    .\Find-CompanyATS.ps1 -Url "https://careers.microsoft.com"
    .\Find-CompanyATS.ps1 -CompanyName "Datadog"
#>

[CmdletBinding()]
param(
    [Parameter(ParameterSetName = "Url")]
    [string]$Url,

    [Parameter(ParameterSetName = "Name")]
    [string]$CompanyName
)

function Detect-ATSFromUrl {
    param([string]$CareersUrl)

    $result = @{
        Platform = "Unknown"
        Slug     = ""
        Config   = ""
    }

    # Check URL patterns first
    if ($CareersUrl -match 'boards\.greenhouse\.io/(\w+)') {
        $result.Platform = "Greenhouse"
        $result.Slug = $Matches[1]
        $result.Config = "`"greenhouse`": [`"$($Matches[1])`"]"
        return $result
    }
    if ($CareersUrl -match 'jobs\.lever\.co/(\w+)') {
        $result.Platform = "Lever"
        $result.Slug = $Matches[1]
        $result.Config = "`"lever`": [`"$($Matches[1])`"]"
        return $result
    }
    if ($CareersUrl -match 'jobs\.ashbyhq\.com/(\w+)') {
        $result.Platform = "Ashby"
        $result.Slug = $Matches[1]
        $result.Config = "`"ashby`": [`"$($Matches[1])`"]"
        return $result
    }
    if ($CareersUrl -match 'jobs\.smartrecruiters\.com/(\w+)') {
        $result.Platform = "SmartRecruiters"
        $result.Slug = $Matches[1]
        $result.Config = "`"smartrecruiters`": [`"$($Matches[1])`"]"
        return $result
    }
    if ($CareersUrl -match '\.myworkday(site|jobs)\.com' -or $CareersUrl -match 'workday\.com') {
        $result.Platform = "Workday"
        $result.Config = "`"workday`": [{`"name`": `"CompanyName`", `"url`": `"$CareersUrl`"}]"
        return $result
    }
    if ($CareersUrl -match 'icims\.com') {
        $result.Platform = "iCIMS"
        $result.Config = "`"icims`": [{`"name`": `"CompanyName`", `"url`": `"$CareersUrl`"}]"
        return $result
    }

    # If URL doesn't match known patterns, fetch the page and check for clues
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        $response = Invoke-WebRequest -Uri $CareersUrl -Headers $headers -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop

        # Check final URL after redirects
        $finalUrl = $response.BaseResponse.ResponseUri.ToString()
        if ($finalUrl -ne $CareersUrl) {
            Write-Host "  Redirected to: $finalUrl" -ForegroundColor DarkGray
            return Detect-ATSFromUrl -CareersUrl $finalUrl
        }

        $content = $response.Content

        # Check page source for ATS signatures
        if ($content -match 'greenhouse') {
            $result.Platform = "Greenhouse"
            if ($content -match 'boards-api\.greenhouse\.io/v1/boards/(\w+)') {
                $result.Slug = $Matches[1]
                $result.Config = "`"greenhouse`": [`"$($Matches[1])`"]"
            }
        }
        elseif ($content -match 'lever\.co') {
            $result.Platform = "Lever"
            if ($content -match 'api\.lever\.co/v0/postings/(\w+)') {
                $result.Slug = $Matches[1]
                $result.Config = "`"lever`": [`"$($Matches[1])`"]"
            }
        }
        elseif ($content -match 'ashbyhq') {
            $result.Platform = "Ashby"
            if ($content -match 'ashbyhq\.com/(\w+)') {
                $result.Slug = $Matches[1]
                $result.Config = "`"ashby`": [`"$($Matches[1])`"]"
            }
        }
        elseif ($content -match 'smartrecruiters') {
            $result.Platform = "SmartRecruiters"
        }
        elseif ($content -match 'workday|myworkday') {
            $result.Platform = "Workday"
            $result.Config = "`"workday`": [{`"name`": `"CompanyName`", `"url`": `"$CareersUrl`"}]"
        }
        elseif ($content -match 'icims') {
            $result.Platform = "iCIMS"
            $result.Config = "`"icims`": [{`"name`": `"CompanyName`", `"url`": `"$CareersUrl`"}]"
        }
    }
    catch {
        Write-Warning "Could not fetch URL: $_"
    }

    return $result
}

# Main execution
if ($Url) {
    Write-Host "`n🔍 Detecting ATS for: $Url`n" -ForegroundColor Cyan
    $result = Detect-ATSFromUrl -CareersUrl $Url

    Write-Host "  Platform:  $($result.Platform)" -ForegroundColor Green
    if ($result.Slug) { Write-Host "  Slug:      $($result.Slug)" -ForegroundColor White }
    if ($result.Config) {
        Write-Host "`n  Add to config.json:" -ForegroundColor Yellow
        Write-Host "  $($result.Config)" -ForegroundColor Gray
    }
}
elseif ($CompanyName) {
    Write-Host "`n🔍 Trying common ATS patterns for: $CompanyName`n" -ForegroundColor Cyan
    $slug = $CompanyName.ToLower() -replace '\s+', ''

    $attempts = @(
        @{ Platform = "Greenhouse"; Url = "https://boards-api.greenhouse.io/v1/boards/$slug/jobs" }
        @{ Platform = "Lever"; Url = "https://api.lever.co/v0/postings/$slug" }
        @{ Platform = "Ashby"; Url = "https://api.ashbyhq.com/posting-api/job-board/$slug" }
        @{ Platform = "SmartRecruiters"; Url = "https://api.smartrecruiters.com/v1/companies/$slug/postings" }
    )

    foreach ($attempt in $attempts) {
        Write-Host "  Trying $($attempt.Platform)..." -ForegroundColor Gray -NoNewline
        try {
            $response = Invoke-RestMethod -Uri $attempt.Url -Method Get -ErrorAction Stop -TimeoutSec 5
            Write-Host " ✅ FOUND!" -ForegroundColor Green
            Write-Host "`n  Platform: $($attempt.Platform)" -ForegroundColor Green
            Write-Host "  Slug: $slug" -ForegroundColor White
            Write-Host "  API URL: $($attempt.Url)" -ForegroundColor DarkGray

            if ($attempt.Platform -eq "Greenhouse") {
                Write-Host "  Jobs found: $($response.jobs.Count)" -ForegroundColor Cyan
            }
            elseif ($attempt.Platform -eq "Lever") {
                Write-Host "  Jobs found: $($response.Count)" -ForegroundColor Cyan
            }

            Write-Host "`n  Add to config.json:" -ForegroundColor Yellow
            Write-Host "  `"$($attempt.Platform.ToLower())`": [`"$slug`"]" -ForegroundColor Gray
            return
        }
        catch {
            Write-Host " ❌" -ForegroundColor Red
        }
    }

    Write-Host "`n  Could not auto-detect. Try providing the careers page URL directly:" -ForegroundColor Yellow
    Write-Host "  .\Find-CompanyATS.ps1 -Url `"https://careers.$($CompanyName.ToLower()).com`"" -ForegroundColor Gray
}
else {
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\Find-CompanyATS.ps1 -Url `"https://careers.company.com`"" -ForegroundColor White
    Write-Host "  .\Find-CompanyATS.ps1 -CompanyName `"Datadog`"" -ForegroundColor White
}

Write-Host ""
