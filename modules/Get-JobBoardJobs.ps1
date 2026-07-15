function Get-JobBoardJobs {
    <#
    .SYNOPSIS
        Fetches jobs from free public job board APIs (RemoteOK, Jobicy).
    .DESCRIPTION
        Aggregates remote job listings from public APIs that require no auth.
        These catch jobs from companies that don't use the major ATS platforms.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$TitleFilters
    )

    $allJobs = @()

    # --- RemoteOK ---
    Write-Verbose "Fetching from RemoteOK..."
    $remoteOkTags = @("sre", "devops", "infrastructure")
    foreach ($tag in $remoteOkTags) {
        try {
            $response = Invoke-RestMethod -Uri "https://remoteok.com/api?tag=$tag" -TimeoutSec 8 -ErrorAction Stop
            # First element is metadata, skip it
            $jobs = $response | Where-Object { $_.id }

            foreach ($job in $jobs) {
                $title = if ($job.position) { $job.position } else { "" }

                $titleMatch = $false
                foreach ($filter in $TitleFilters) {
                    if ($title -match $filter) { $titleMatch = $true; break }
                }
                if (-not $titleMatch) { continue }

                $jobId = "remoteok_$($job.id)"
                if ($allJobs | Where-Object { $_.JobId -eq $jobId }) { continue }

                $salary = ""
                if ($job.salary_min -and $job.salary_max) { $salary = "`$$($job.salary_min) - `$$($job.salary_max)" }

                $allJobs += [PSCustomObject]@{
                    Source      = "RemoteOK"
                    Company     = if ($job.company) { $job.company } else { "Unknown" }
                    Title       = $title
                    Location    = if ($job.location) { $job.location } else { "Remote" }
                    Url         = if ($job.url) { $job.url } else { "https://remoteok.com/l/$($job.id)" }
                    PostedDate  = if ($job.date) { try { [datetime]$job.date } catch { Get-Date } } else { Get-Date }
                    Description = if ($job.description) { ($job.description -replace '<[^>]+>', ' ' -replace '\s+', ' ').Substring(0, [Math]::Min(2000, $job.description.Length)) } else { $title }
                    Salary      = $salary
                    JobId       = $jobId
                }
            }
        }
        catch {
            Write-Warning "RemoteOK ($tag) failed: $($_.Exception.Message.Substring(0, [Math]::Min(80, $_.Exception.Message.Length)))"
        }
        Start-Sleep -Milliseconds 500
    }

    # --- Jobicy ---
    Write-Verbose "Fetching from Jobicy..."
    $jobicyTags = @("sre", "devops", "cloud-engineer")
    foreach ($tag in $jobicyTags) {
        try {
            $response = Invoke-RestMethod -Uri "https://jobicy.com/api/v2/remote-jobs?count=50&tag=$tag&geo=usa" -TimeoutSec 8 -ErrorAction Stop
            $jobs = if ($response.jobs) { $response.jobs } else { @() }

            foreach ($job in $jobs) {
                $title = if ($job.jobTitle) { $job.jobTitle } else { "" }

                $titleMatch = $false
                foreach ($filter in $TitleFilters) {
                    if ($title -match $filter) { $titleMatch = $true; break }
                }
                if (-not $titleMatch) { continue }

                $jobId = "jobicy_$($job.id)"
                if ($allJobs | Where-Object { $_.JobId -eq $jobId }) { continue }

                $salary = ""
                if ($job.annualSalaryMin -and $job.annualSalaryMax) { $salary = "`$$($job.annualSalaryMin) - `$$($job.annualSalaryMax)" }

                $allJobs += [PSCustomObject]@{
                    Source      = "Jobicy"
                    Company     = if ($job.companyName) { $job.companyName } else { "Unknown" }
                    Title       = $title
                    Location    = if ($job.jobGeo) { $job.jobGeo } else { "Remote" }
                    Url         = if ($job.url) { $job.url } else { "" }
                    PostedDate  = if ($job.pubDate) { try { [datetime]$job.pubDate } catch { Get-Date } } else { Get-Date }
                    Description = if ($job.jobDescription) { ($job.jobDescription -replace '<[^>]+>', ' ' -replace '\s+', ' ').Substring(0, [Math]::Min(2000, $job.jobDescription.Length)) } else { $title }
                    Salary      = $salary
                    JobId       = $jobId
                }
            }
        }
        catch {
            Write-Warning "Jobicy ($tag) failed: $($_.Exception.Message.Substring(0, [Math]::Min(80, $_.Exception.Message.Length)))"
        }
        Start-Sleep -Milliseconds 500
    }

    return $allJobs
}
