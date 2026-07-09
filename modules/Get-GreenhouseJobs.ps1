function Get-GreenhouseJobs {
    <#
    .SYNOPSIS
        Scrapes jobs from Greenhouse boards API for specified companies.
    .DESCRIPTION
        Uses the public Greenhouse boards API (no auth required) to fetch job listings.
        API: https://boards-api.greenhouse.io/v1/boards/{company}/jobs
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
        Write-Verbose "Fetching Greenhouse jobs for: $company"
        $url = "https://boards-api.greenhouse.io/v1/boards/$company/jobs?content=true"

        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
            $jobs = $response.jobs

            foreach ($job in $jobs) {
                # Check if title matches any of our filters
                $titleMatch = $false
                foreach ($filter in $TitleFilters) {
                    if ($job.title -match $filter) {
                        $titleMatch = $true
                        break
                    }
                }

                if (-not $titleMatch) { continue }

                # Extract location
                $location = if ($job.location) { $job.location.name } else { "Not specified" }

                # Safely extract description (clean HTML first, then extract salary from full text)
                $description = ""
                $salary = ""
                if ($job.content) {
                    $fullText = ($job.content -replace '<[^>]+>', ' ' -replace '\s+', ' ')

                    # Extract salary from full cleaned text before truncating
                    if ($fullText -match '\$[\d,]+\s*[-–—]\s*\$[\d,]+') {
                        $salary = $Matches[0]
                    }
                    elseif ($fullText -match '\$[\d,]+\s+to\s+\$[\d,]+') {
                        $salary = $Matches[0]
                    }
                    elseif ($fullText -match '(?:base|salary|pay|compensation)\s*(?:range|:)\s*\$[\d,]+\s*[-–—]\s*\$[\d,]+') {
                        $salary = $Matches[0]
                    }

                    # Truncate for storage
                    $description = $fullText.Substring(0, [Math]::Min(2000, $fullText.Length))
                }

                $allJobs += [PSCustomObject]@{
                    Source      = "Greenhouse"
                    Company     = $company
                    Title       = $job.title
                    Location    = $location
                    Url         = $job.absolute_url
                    PostedDate  = if ($job.updated_at) { [datetime]$job.updated_at } else { Get-Date }
                    Description = $description
                    Salary      = $salary
                    JobId       = "greenhouse_${company}_$($job.id)"
                }
            }

            Write-Verbose "  Found $($allJobs.Count) matching jobs at $company"
        }
        catch {
            Write-Warning "Failed to fetch Greenhouse jobs for $company : $($_.Exception.Message.Substring(0, [Math]::Min(100, $_.Exception.Message.Length)))"
        }

        # Be polite - don't hammer the API
        Start-Sleep -Milliseconds 500
    }

    return $allJobs
}
