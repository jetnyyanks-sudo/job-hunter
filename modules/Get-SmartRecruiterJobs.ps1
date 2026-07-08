function Get-SmartRecruiterJobs {
    <#
    .SYNOPSIS
        Scrapes jobs from SmartRecruiters public API for specified companies.
    .DESCRIPTION
        Uses the public SmartRecruiters API (no auth required).
        API: https://api.smartrecruiters.com/v1/companies/{company}/postings
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Companies,

        [Parameter(Mandatory)]
        [string[]]$TitleFilters
    )

    $allJobs = @()

    foreach ($company in $Companies) {
        Write-Verbose "Fetching SmartRecruiters jobs for: $company"

        $offset = 0
        $limit = 100
        $hasMore = $true

        while ($hasMore) {
            $url = "https://api.smartrecruiters.com/v1/companies/$company/postings?offset=$offset&limit=$limit"

            try {
                $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
                $jobs = $response.content

                if (-not $jobs -or $jobs.Count -eq 0) {
                    $hasMore = $false
                    break
                }

                foreach ($job in $jobs) {
                    # Check if title matches any of our filters
                    $titleMatch = $false
                    foreach ($filter in $TitleFilters) {
                        if ($job.name -match $filter) {
                            $titleMatch = $true
                            break
                        }
                    }

                    if (-not $titleMatch) { continue }

                    # Extract location
                    $location = "Not specified"
                    if ($job.location) {
                        $parts = @()
                        if ($job.location.city) { $parts += $job.location.city }
                        if ($job.location.region) { $parts += $job.location.region }
                        if ($job.location.country) { $parts += $job.location.country }
                        $location = $parts -join ", "
                        if ($job.location.remote) { $location = "Remote - $location" }
                    }

                    # Get description from job details
                    $description = ""
                    if ($job.jobAd -and $job.jobAd.sections) {
                        foreach ($section in $job.jobAd.sections) {
                            if ($section.text) {
                                $description += ($section.text -replace '<[^>]+>', ' ' -replace '\s+', ' ') + " | "
                            }
                        }
                    }

                    # Extract salary from full description before truncating
                    $salary = ""
                    if ($description -match '\$[\d,]+\s*[-–—]\s*\$[\d,]+') {
                        $salary = $Matches[0]
                    }
                    elseif ($description -match '\$[\d,]+\s+to\s+\$[\d,]+') {
                        $salary = $Matches[0]
                    }
                    elseif ($description -match '(?:base|salary|pay|compensation)\s*(?:range|:)\s*\$[\d,]+\s*[-–—]\s*\$[\d,]+') {
                        $salary = $Matches[0]
                    }

                    $description = if ($description.Length -gt 2000) { $description.Substring(0, 2000) } else { $description }

                    $allJobs += [PSCustomObject]@{
                        Source      = "SmartRecruiters"
                        Company     = $company
                        Title       = $job.name
                        Location    = $location
                        Url         = $job.ref
                        PostedDate  = if ($job.releasedDate) { [datetime]$job.releasedDate } else { Get-Date }
                        Description = $description
                        Salary      = $salary
                        JobId       = "smartrecruiters_${company}_$($job.id)"
                    }
                }

                $offset += $limit
                if ($response.totalFound -le $offset) { $hasMore = $false }
            }
            catch {
                Write-Warning "Failed to fetch SmartRecruiters jobs for $company : $_"
                $hasMore = $false
            }

            Start-Sleep -Milliseconds 500
        }

        Write-Verbose "  Found $($allJobs.Count) matching jobs at $company"
    }

    return $allJobs
}
