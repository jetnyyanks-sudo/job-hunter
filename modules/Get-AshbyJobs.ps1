function Get-AshbyJobs {
    <#
    .SYNOPSIS
        Scrapes jobs from Ashby job board API for specified companies.
    .DESCRIPTION
        Uses the public Ashby posting API.
        API: https://api.ashbyhq.com/posting-api/job-board/{company}
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
        Write-Verbose "Fetching Ashby jobs for: $company"
        $url = "https://api.ashbyhq.com/posting-api/job-board/$company"

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
                $location = if ($job.location) { $job.location } else { "Not specified" }
                if ($job.isRemote) { $location = "Remote - $location" }

                # Get job details for description (may fail silently on some boards)
                $description = ""
                $detailUrl = "https://api.ashbyhq.com/posting-api/job-board/$company/posting/$($job.id)"
                try {
                    $detail = Invoke-RestMethod -Uri $detailUrl -Method Get -ErrorAction SilentlyContinue
                    if ($detail -and $detail.descriptionHtml) {
                        $description = ($detail.descriptionHtml -replace '<[^>]+>', ' ' -replace '\s+', ' ')
                        $description = $description.Substring(0, [Math]::Min(2000, $description.Length))
                    }
                    else {
                        $description = $job.title
                    }
                }
                catch {
                    $description = $job.title
                }

                # Extract salary
                $salary = ""
                if ($job.compensation) {
                    $salary = $job.compensation
                }
                elseif ($description -match '\$[\d,]+\s*[-–]\s*\$[\d,]+') {
                    $salary = $Matches[0]
                }

                $jobUrl = "https://jobs.ashbyhq.com/$company/$($job.id)"

                $allJobs += [PSCustomObject]@{
                    Source      = "Ashby"
                    Company     = $company
                    Title       = $job.title
                    Location    = $location
                    Url         = $jobUrl
                    PostedDate  = if ($job.publishedAt) { [datetime]$job.publishedAt } else { Get-Date }
                    Description = $description
                    Salary      = $salary
                    JobId       = "ashby_${company}_$($job.id)"
                }

                Start-Sleep -Milliseconds 300
            }

            Write-Verbose "  Found $($allJobs.Count) matching jobs at $company"
        }
        catch {
            Write-Warning "Failed to fetch Ashby jobs for $company : $($_.Exception.Message.Substring(0, [Math]::Min(100, $_.Exception.Message.Length)))"
        }

        Start-Sleep -Milliseconds 500
    }

    return $allJobs
}
