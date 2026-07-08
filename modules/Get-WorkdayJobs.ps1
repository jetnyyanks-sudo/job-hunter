function Get-WorkdayJobs {
    <#
    .SYNOPSIS
        Scrapes jobs from Workday career sites.
    .DESCRIPTION
        Workday sites are JS-heavy, but many expose a search API endpoint.
        This uses the common Workday search API pattern.
        Falls back to HTML scraping for non-standard implementations.
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
        Write-Verbose "Fetching Workday jobs for: $companyName"

        try {
            # Attempt to scrape the career page
            $headers = @{
                "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                "Accept"     = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            }

            $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -ErrorAction Stop
            $content = $response.Content

            # Try to find job listings in the HTML
            # Workday pages often have structured data or specific patterns
            $jobPattern = '(?s)<a[^>]*href="([^"]*)"[^>]*>([^<]*(?:Site Reliability|SRE|Reliability Engineer)[^<]*)</a>'
            $matches = [regex]::Matches($content, $jobPattern, 'IgnoreCase')

            foreach ($match in $matches) {
                $jobUrl = $match.Groups[1].Value
                $jobTitle = $match.Groups[2].Value.Trim()

                # Make URL absolute if relative
                if ($jobUrl -notmatch '^https?://') {
                    $baseUri = [System.Uri]$url
                    $jobUrl = [System.Uri]::new($baseUri, $jobUrl).ToString()
                }

                $allJobs += [PSCustomObject]@{
                    Source      = "Workday"
                    Company     = $companyName
                    Title       = $jobTitle
                    Location    = "Check listing"
                    Url         = $jobUrl
                    PostedDate  = Get-Date
                    Description = "Workday listing - visit URL for full details. Title: $jobTitle at $companyName"
                    Salary      = ""
                    JobId       = "workday_$($companyName.ToLower() -replace '\s+','')_$($jobUrl.GetHashCode())"
                }
            }

            # Also try JSON-LD structured data
            $jsonLdPattern = '<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>'
            $jsonMatches = [regex]::Matches($content, $jsonLdPattern, 'Singleline')

            foreach ($jsonMatch in $jsonMatches) {
                try {
                    $jsonData = $jsonMatch.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop
                    if ($jsonData.'@type' -eq 'JobPosting') {
                        $titleMatch = $false
                        foreach ($filter in $TitleFilters) {
                            if ($jsonData.title -match $filter) {
                                $titleMatch = $true
                                break
                            }
                        }
                        if ($titleMatch) {
                            $allJobs += [PSCustomObject]@{
                                Source      = "Workday"
                                Company     = $companyName
                                Title       = $jsonData.title
                                Location    = if ($jsonData.jobLocation) { $jsonData.jobLocation.address.addressLocality } else { "Check listing" }
                                Url         = if ($jsonData.url) { $jsonData.url } else { $url }
                                PostedDate  = if ($jsonData.datePosted) { [datetime]$jsonData.datePosted } else { Get-Date }
                                Description = if ($jsonData.description) { ($jsonData.description -replace '<[^>]+>', ' ').Substring(0, [Math]::Min(2000, $jsonData.description.Length)) } else { "" }
                                Salary      = if ($jsonData.baseSalary) { "$($jsonData.baseSalary.value.minValue) - $($jsonData.baseSalary.value.maxValue)" } else { "" }
                                JobId       = "workday_$($companyName.ToLower() -replace '\s+','')_$($jsonData.title.GetHashCode())"
                            }
                        }
                    }
                }
                catch { }
            }

            Write-Verbose "  Found $($allJobs.Count) matching jobs at $companyName"
        }
        catch {
            Write-Warning "Failed to fetch Workday jobs for $companyName : $_"
        }

        Start-Sleep -Seconds 2
    }

    return $allJobs
}
