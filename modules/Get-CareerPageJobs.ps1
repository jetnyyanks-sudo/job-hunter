function Get-CareerPageJobs {
    <#
    .SYNOPSIS
        Generic career page scraper that works with any company website.
    .DESCRIPTION
        Fetches company career/jobs pages by URL, searches for job links matching
        title filters, and extracts job titles + URLs. Works regardless of ATS platform.
        Uses parallel processing (PS 7+) to scrape 5 companies simultaneously.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Companies,

        [Parameter(Mandatory)]
        [string[]]$TitleFilters
    )

    $headers = @{
        "User-Agent"      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        "Accept"          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        "Accept-Language" = "en-US,en;q=0.9"
    }

    $allJobs = $Companies | ForEach-Object -ThrottleLimit 5 -Parallel {
        $companyConfig = $_
        $companyName = $companyConfig.name
        $url = $companyConfig.url
        $TitleFilters = $using:TitleFilters
        $headers = $using:headers
        $jobs = @()

        try {
            $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 5 -ErrorAction Stop
            $content = $response.Content

            # Strategy 1: Find job links by matching title keywords in anchor text
            foreach ($filter in $TitleFilters) {
                $pattern = '(?s)<a[^>]*href="([^"]+)"[^>]*>([^<]*' + [regex]::Escape($filter) + '[^<]*)</a>'
                $matches = [regex]::Matches($content, $pattern, 'IgnoreCase')
                foreach ($match in $matches) {
                    $jobUrl = $match.Groups[1].Value
                    $jobTitle = ($match.Groups[2].Value -replace '\s+', ' ').Trim()

                    if ($jobUrl -notmatch '^https?://') {
                        try {
                            $baseUri = [System.Uri]$url
                            $jobUrl = [System.Uri]::new($baseUri, $jobUrl).ToString()
                        } catch { continue }
                    }
                    if ($jobUrl -match '^(javascript|mailto|#|tel:)') { continue }

                    $jobs += [PSCustomObject]@{
                        Source      = "CareerPage"
                        Company     = $companyName
                        Title       = $jobTitle
                        Location    = "Check listing"
                        Url         = $jobUrl
                        PostedDate  = Get-Date
                        Description = "Career page listing: $jobTitle at $companyName"
                        Salary      = ""
                        JobId       = "careerpage_$($companyName.ToLower() -replace '[^a-z0-9]','')_$($jobUrl.GetHashCode())"
                    }
                }

                # Also check nested elements
                $pattern2 = '(?s)<a[^>]*href="([^"]+)"[^>]*>.*?(' + [regex]::Escape($filter) + '[^<]{0,80}).*?</a>'
                $matches2 = [regex]::Matches($content, $pattern2, 'IgnoreCase')
                foreach ($match in $matches2) {
                    $rawTitle = ($match.Groups[2].Value -replace '<[^>]+>', '' -replace '\s+', ' ').Trim()
                    if ($rawTitle.Length -le 5) { continue }
                    $jobUrl = $match.Groups[1].Value
                    if ($jobUrl -notmatch '^https?://') {
                        try {
                            $baseUri = [System.Uri]$url
                            $jobUrl = [System.Uri]::new($baseUri, $jobUrl).ToString()
                        } catch { continue }
                    }
                    if ($jobUrl -match '^(javascript|mailto|#|tel:)') { continue }
                    # Skip if already found
                    if ($jobs | Where-Object { $_.Url -eq $jobUrl }) { continue }

                    $jobs += [PSCustomObject]@{
                        Source      = "CareerPage"
                        Company     = $companyName
                        Title       = $rawTitle
                        Location    = "Check listing"
                        Url         = $jobUrl
                        PostedDate  = Get-Date
                        Description = "Career page listing: $rawTitle at $companyName"
                        Salary      = ""
                        JobId       = "careerpage_$($companyName.ToLower() -replace '[^a-z0-9]','')_$($jobUrl.GetHashCode())"
                    }
                }
            }

            # Strategy 2: Check JSON-LD structured data
            $jsonLdPattern = '(?s)<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>'
            $jsonMatches = [regex]::Matches($content, $jsonLdPattern, 'Singleline')
            foreach ($jsonMatch in $jsonMatches) {
                try {
                    $jsonRaw = $jsonMatch.Groups[1].Value
                    $jsonData = $jsonRaw | ConvertFrom-Json -ErrorAction Stop

                    $postings = @()
                    if ($jsonData.'@type' -eq 'JobPosting') { $postings += $jsonData }
                    elseif ($jsonData.'@graph') { $postings += $jsonData.'@graph' | Where-Object { $_.'@type' -eq 'JobPosting' } }
                    elseif ($jsonData -is [array]) { $postings += $jsonData | Where-Object { $_.'@type' -eq 'JobPosting' } }

                    foreach ($posting in $postings) {
                        $titleMatch = $false
                        foreach ($filter in $TitleFilters) {
                            if ($posting.title -match $filter) { $titleMatch = $true; break }
                        }
                        if (-not $titleMatch) { continue }

                        $location = "Check listing"
                        if ($posting.jobLocation -and $posting.jobLocation.address) {
                            $addr = $posting.jobLocation.address
                            $parts = @()
                            if ($addr.addressLocality) { $parts += $addr.addressLocality }
                            if ($addr.addressRegion) { $parts += $addr.addressRegion }
                            $location = $parts -join ", "
                        }
                        if ($posting.jobLocationType -eq 'TELECOMMUTE') { $location = "Remote - $location" }

                        $salary = ""
                        if ($posting.baseSalary -and $posting.baseSalary.value) {
                            $sal = $posting.baseSalary.value
                            if ($sal.minValue -and $sal.maxValue) { $salary = "`$$($sal.minValue) - `$$($sal.maxValue)" }
                        }

                        $description = ""
                        if ($posting.description) {
                            $description = ($posting.description -replace '<[^>]+>', ' ' -replace '\s+', ' ')
                            if (-not $salary -and $description -match '\$[\d,]+\s*[-\u2013\u2014]\s*\$[\d,]+') { $salary = $Matches[0] }
                            $description = $description.Substring(0, [Math]::Min(2000, $description.Length))
                        }

                        $jobUrl = if ($posting.url) { $posting.url } else { $url }

                        $jobs += [PSCustomObject]@{
                            Source      = "CareerPage"
                            Company     = $companyName
                            Title       = $posting.title
                            Location    = $location
                            Url         = $jobUrl
                            PostedDate  = if ($posting.datePosted) { try { [datetime]$posting.datePosted } catch { Get-Date } } else { Get-Date }
                            Description = $description
                            Salary      = $salary
                            JobId       = "careerpage_$($companyName.ToLower() -replace '[^a-z0-9]','')_$($posting.title.GetHashCode())"
                        }
                    }
                } catch { }
            }

            $count = $jobs.Count
            Write-Host "     [$($companyConfig.name)] $count found" -ForegroundColor $(if ($count -gt 0) { "Green" } else { "DarkGray" })
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg.Length -gt 80) { $msg = $msg.Substring(0, 80) + "..." }
            Write-Host "     [$companyName] FAIL: $msg" -ForegroundColor Red
        }

        # Output jobs from this parallel block
        $jobs
    }

    # Filter out nulls and return
    $results = @($allJobs | Where-Object { $_ -ne $null })
    return $results
}
