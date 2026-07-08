function Get-ICIMSJobs {
    <#
    .SYNOPSIS
        Scrapes jobs from iCIMS career portals.
    .DESCRIPTION
        iCIMS portals are HTML-based. This scrapes the search results page
        and extracts job listings matching our filters.
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
        $url = $companyConfig.url
        Write-Verbose "Fetching iCIMS jobs for: $companyName"

        try {
            $headers = @{
                "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                "Accept"     = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            }

            $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -ErrorAction Stop
            $content = $response.Content

            # iCIMS typically has job cards with links and titles
            # Common patterns: class="iCIMS_JobsTable" or similar
            $jobPattern = '(?s)<a[^>]*href="([^"]*jobs[^"]*)"[^>]*class="[^"]*title[^"]*"[^>]*>([^<]+)</a>'
            $matches = [regex]::Matches($content, $jobPattern, 'IgnoreCase')

            # Fallback pattern - more generic link extraction
            if ($matches.Count -eq 0) {
                $jobPattern = '(?s)<a[^>]*href="([^"]*(?:/job/|/jobs/)[^"]*)"[^>]*>([^<]+)</a>'
                $matches = [regex]::Matches($content, $jobPattern, 'IgnoreCase')
            }

            # Another fallback - look for any links containing our keywords
            if ($matches.Count -eq 0) {
                $jobPattern = '(?s)<a[^>]*href="([^"]*)"[^>]*>\s*([^<]*(?:Site Reliability|SRE|Reliability Engineer)[^<]*)\s*</a>'
                $matches = [regex]::Matches($content, $jobPattern, 'IgnoreCase')
            }

            foreach ($match in $matches) {
                $jobUrl = $match.Groups[1].Value
                $jobTitle = $match.Groups[2].Value.Trim()

                # Filter by title
                $titleMatch = $false
                foreach ($filter in $TitleFilters) {
                    if ($jobTitle -match $filter) {
                        $titleMatch = $true
                        break
                    }
                }

                if (-not $titleMatch) { continue }

                # Make URL absolute if relative
                if ($jobUrl -notmatch '^https?://') {
                    $baseUri = [System.Uri]$url
                    $jobUrl = [System.Uri]::new($baseUri, $jobUrl).ToString()
                }

                $allJobs += [PSCustomObject]@{
                    Source      = "iCIMS"
                    Company     = $companyName
                    Title       = $jobTitle
                    Location    = "Check listing"
                    Url         = $jobUrl
                    PostedDate  = Get-Date
                    Description = "iCIMS listing - visit URL for full details. Title: $jobTitle at $companyName"
                    Salary      = ""
                    JobId       = "icims_$($companyName.ToLower() -replace '\s+','')_$($jobUrl.GetHashCode())"
                }
            }

            Write-Verbose "  Found $($allJobs.Count) matching jobs at $companyName"
        }
        catch {
            Write-Warning "Failed to fetch iCIMS jobs for $companyName : $_"
        }

        Start-Sleep -Seconds 2
    }

    return $allJobs
}
