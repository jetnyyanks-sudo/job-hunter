function Get-WorkableJobs {
    <#
    .SYNOPSIS
        Scrapes jobs from Workable job boards for specified companies.
    .DESCRIPTION
        Uses the public Workable widget/careers API (no auth required).
        API: https://apply.workable.com/api/v1/widget/accounts/{slug}
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
        Write-Verbose "Fetching Workable jobs for: $company"
        $url = "https://apply.workable.com/api/v1/widget/accounts/$company"

        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
            $jobs = if ($response.jobs) { $response.jobs } else { @() }

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
                $location = "Not specified"
                if ($job.location) {
                    $parts = @()
                    if ($job.location.city) { $parts += $job.location.city }
                    if ($job.location.region) { $parts += $job.location.region }
                    if ($job.location.country) { $parts += $job.location.country }
                    $location = $parts -join ", "
                }
                if ($job.remote -or $job.workplace -eq 'remote') { $location = "Remote - $location" }

                # Description from shortDescription or full
                $description = ""
                if ($job.description) {
                    $description = ($job.description -replace '<[^>]+>', ' ' -replace '\s+', ' ')
                    $description = $description.Substring(0, [Math]::Min(2000, $description.Length))
                }
                elseif ($job.shortDescription) {
                    $description = $job.shortDescription
                }

                # Salary
                $salary = ""
                if ($job.salary) { $salary = $job.salary }
                elseif ($description -match '\$[\d,]+\s*[-\u2013\u2014]\s*\$[\d,]+') { $salary = $Matches[0] }

                $jobUrl = "https://apply.workable.com/$company/j/$($job.shortcode)/"
                if ($job.url) { $jobUrl = $job.url }

                $allJobs += [PSCustomObject]@{
                    Source      = "Workable"
                    Company     = $company
                    Title       = $job.title
                    Location    = $location
                    Url         = $jobUrl
                    PostedDate  = if ($job.published_on) { try { [datetime]$job.published_on } catch { Get-Date } } else { Get-Date }
                    Description = $description
                    Salary      = $salary
                    JobId       = "workable_${company}_$($job.shortcode)"
                }
            }

            Write-Verbose "  Found $($allJobs.Count) matching jobs at $company"
        }
        catch {
            Write-Warning "Failed to fetch Workable jobs for $company : $($_.Exception.Message.Substring(0, [Math]::Min(100, $_.Exception.Message.Length)))"
        }

        Start-Sleep -Milliseconds 500
    }

    return $allJobs
}
