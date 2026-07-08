function Get-LeverJobs {
    <#
    .SYNOPSIS
        Scrapes jobs from Lever postings API for specified companies.
    .DESCRIPTION
        Uses the public Lever postings API (no auth required).
        API: https://api.lever.co/v0/postings/{company}
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
        Write-Verbose "Fetching Lever jobs for: $company"
        $url = "https://api.lever.co/v0/postings/$company"

        try {
            $jobs = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop

            foreach ($job in $jobs) {
                # Check if title matches any of our filters
                $titleMatch = $false
                foreach ($filter in $TitleFilters) {
                    if ($job.text -match $filter) {
                        $titleMatch = $true
                        break
                    }
                }

                if (-not $titleMatch) { continue }

                # Extract location
                $location = if ($job.categories.location) { $job.categories.location } else { "Not specified" }

                # Build description from lists
                $description = ""
                if ($job.lists) {
                    foreach ($list in $job.lists) {
                        $description += "$($list.text): "
                        if ($list.content) {
                            $description += ($list.content -replace '<[^>]+>', ' ' -replace '\s+', ' ')
                        }
                        $description += " | "
                    }
                }
                if ($job.additional) {
                    $description += ($job.additional -replace '<[^>]+>', ' ' -replace '\s+', ' ')
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

                if ($description.Length -gt 2000) {
                    $description = $description.Substring(0, 2000)
                }

                $allJobs += [PSCustomObject]@{
                    Source      = "Lever"
                    Company     = $company
                    Title       = $job.text
                    Location    = $location
                    Url         = $job.hostedUrl
                    PostedDate  = if ($job.createdAt) { [DateTimeOffset]::FromUnixTimeMilliseconds($job.createdAt).DateTime } else { Get-Date }
                    Description = $description
                    Salary      = $salary
                    JobId       = "lever_${company}_$($job.id)"
                }
            }

            Write-Verbose "  Found $($allJobs.Count) matching jobs at $company"
        }
        catch {
            Write-Warning "Failed to fetch Lever jobs for $company : $_"
        }

        Start-Sleep -Milliseconds 500
    }

    return $allJobs
}
