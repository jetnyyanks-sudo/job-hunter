function Get-RipplingJobs {
    <#
    .SYNOPSIS
        Scrapes jobs from Rippling ATS boards for specified companies.
    .DESCRIPTION
        Uses the public Rippling ATS API (no auth required).
        API: https://ats.rippling.com/api/v2/board/{board_id}/jobs
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
        Write-Verbose "Fetching Rippling jobs for: $company"
        $url = "https://ats.rippling.com/api/v2/board/$company/jobs"

        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
            $jobs = if ($response.jobs) { $response.jobs } elseif ($response -is [array]) { $response } else { @() }

            foreach ($job in $jobs) {
                $title = if ($job.title) { $job.title } elseif ($job.name) { $job.name } else { "" }

                # Check if title matches any of our filters
                $titleMatch = $false
                foreach ($filter in $TitleFilters) {
                    if ($title -match $filter) {
                        $titleMatch = $true
                        break
                    }
                }
                if (-not $titleMatch) { continue }

                # Extract location
                $location = "Not specified"
                if ($job.location) { $location = $job.location }
                elseif ($job.city -and $job.state) { $location = "$($job.city), $($job.state)" }
                if ($job.remote -or $job.workplaceType -eq 'REMOTE') { $location = "Remote - $location" }

                # Extract description
                $description = ""
                if ($job.description) {
                    $description = ($job.description -replace '<[^>]+>', ' ' -replace '\s+', ' ')
                    $description = $description.Substring(0, [Math]::Min(2000, $description.Length))
                }

                # Extract salary
                $salary = ""
                if ($job.compensation) { $salary = $job.compensation }
                elseif ($description -match '\$[\d,]+\s*[-\u2013\u2014]\s*\$[\d,]+') { $salary = $Matches[0] }

                $jobUrl = "https://ats.rippling.com/$company/jobs/$($job.id)"
                if ($job.url) { $jobUrl = $job.url }

                $allJobs += [PSCustomObject]@{
                    Source      = "Rippling"
                    Company     = $company
                    Title       = $title
                    Location    = $location
                    Url         = $jobUrl
                    PostedDate  = if ($job.createdAt) { try { [datetime]$job.createdAt } catch { Get-Date } } else { Get-Date }
                    Description = $description
                    Salary      = $salary
                    JobId       = "rippling_${company}_$($job.id)"
                }
            }

            Write-Verbose "  Found $($allJobs.Count) matching jobs at $company"
        }
        catch {
            Write-Warning "Failed to fetch Rippling jobs for $company : $($_.Exception.Message.Substring(0, [Math]::Min(100, $_.Exception.Message.Length)))"
        }

        Start-Sleep -Milliseconds 500
    }

    return $allJobs
}
