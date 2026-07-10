function Get-WorkdayJobs {
    <#
    .SYNOPSIS
        Scrapes jobs from Workday career sites using their hidden JSON API.
    .DESCRIPTION
        Uses the undocumented Workday CXS API (POST endpoint, no auth required).
        URL pattern: https://{tenant}.{server}.myworkdayjobs.com/wday/cxs/{tenant}/{site}/jobs
        
        Config format in config.json:
        "workday": [
            { "name": "Company", "tenant": "company", "server": "wd1", "site": "External" }
        ]
        
        Or legacy format (will attempt to extract params from URL):
        "workday": [
            { "name": "Company", "url": "https://company.wd1.myworkdayjobs.com/en-US/External?q=SRE" }
        ]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Companies,

        [Parameter(Mandatory)]
        [string[]]$TitleFilters
    )

    $allJobs = @()

    foreach ($companyConfig in $Companies) {
        $companyName = $companyConfig.name
        Write-Verbose "Fetching Workday jobs for: $companyName"

        # Determine API params from config
        $tenant = $null
        $server = $null
        $site = $null

        if ($companyConfig.tenant -and $companyConfig.server -and $companyConfig.site) {
            # New format: explicit params
            $tenant = $companyConfig.tenant
            $server = $companyConfig.server
            $site = $companyConfig.site
        }
        elseif ($companyConfig.url) {
            # Legacy format: extract from URL
            # Pattern: https://{tenant}.{server}.myworkdayjobs.com/en-US/{site}?q=...
            # Or: https://{tenant}.{server}.myworkdayjobs.com/{site}/...
            $url = $companyConfig.url
            if ($url -match '([\w-]+)\.(wd\d+)\.myworkday(?:jobs|site)\.com') {
                $tenant = $Matches[1]
                $server = $Matches[2]
            }
            # Try to extract site from path
            if ($url -match 'myworkday(?:jobs|site)\.com/(?:en-US/)?(\w+)') {
                $site = $Matches[1]
            }
            if (-not $site) { $site = "External" }
        }

        if (-not $tenant -or -not $server) {
            Write-Warning "Could not determine Workday API params for $companyName - skipping"
            continue
        }

        $apiUrl = "https://$tenant.$server.myworkdayjobs.com/wday/cxs/$tenant/$site/jobs"

        # Search with each title filter
        $searchTerms = @("site reliability", "SRE", "platform engineer", "production engineer")

        foreach ($searchTerm in $searchTerms) {
            try {
                $body = @{
                    appliedFacets = @{}
                    limit         = 20
                    offset        = 0
                    searchText    = $searchTerm
                } | ConvertTo-Json

                $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 8 -ErrorAction Stop

                if (-not $response.jobPostings) { continue }

                foreach ($job in $response.jobPostings) {
                    # Check if title matches our filters
                    $titleMatch = $false
                    foreach ($filter in $TitleFilters) {
                        if ($job.title -match $filter) {
                            $titleMatch = $true
                            break
                        }
                    }
                    if (-not $titleMatch) { continue }

                    # Skip if already added (multiple search terms may match same job)
                    # Use externalPath directly for stable ID (GetHashCode varies across sessions in .NET Core)
                    $pathSlug = if ($job.externalPath) { $job.externalPath -replace '[^a-zA-Z0-9_-]', '' } else { $job.title -replace '[^a-zA-Z0-9]', '' }
                    $jobId = "workday_${tenant}_${pathSlug}"
                    if ($allJobs | Where-Object { $_.JobId -eq $jobId }) { continue }

                    # Extract location
                    $location = if ($job.locationsText) { $job.locationsText } else { "Check listing" }

                    # Build job URL
                    $jobUrl = "https://$tenant.$server.myworkdayjobs.com/en-US/$site$($job.externalPath)"

                    # Extract posted date
                    $postedDate = Get-Date
                    if ($job.postedOn) {
                        try { $postedDate = [datetime]$job.postedOn } catch { }
                    }

                    $allJobs += [PSCustomObject]@{
                        Source      = "Workday"
                        Company     = $companyName
                        Title       = $job.title
                        Location    = $location
                        Url         = $jobUrl
                        PostedDate  = $postedDate
                        Description = if ($job.descriptionText) { $job.descriptionText.Substring(0, [Math]::Min(2000, $job.descriptionText.Length)) } else { "$($job.title) at $companyName" }
                        Salary      = ""
                        JobId       = $jobId
                    }
                }
            }
            catch {
                Write-Verbose "Workday search '$searchTerm' failed for $companyName : $($_.Exception.Message.Substring(0, [Math]::Min(80, $_.Exception.Message.Length)))"
            }
        }

        Write-Verbose "  Found $($allJobs.Count) matching jobs at $companyName"
        Start-Sleep -Milliseconds 500
    }

    return $allJobs
}
