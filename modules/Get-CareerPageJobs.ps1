function Get-CareerPageJobs {
    <#
    .SYNOPSIS
        Generic career page scraper that works with any company website.
    .DESCRIPTION
        Fetches company career/jobs pages by URL, searches for job links matching
        title filters, and extracts job titles + URLs. Works regardless of ATS platform.
        This is a broad-net supplement to the ATS-specific API scrapers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Companies,

        [Parameter(Mandatory)]
        [string[]]$TitleFilters
    )

    $allJobs = @()

    $headers = @{
        "User-Agent"      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        "Accept"          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        "Accept-Language" = "en-US,en;q=0.9"
    }

    foreach ($companyConfig in $Companies) {
        $companyName = $companyConfig.name
        $url = $companyConfig.url
        Write-Verbose "Fetching career page for: $companyName ($url)"
        Write-Host "     [$($Companies.IndexOf($companyConfig) + 1)/$($Companies.Count)] $companyName..." -ForegroundColor DarkGray -NoNewline

        try {
            $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 5 -ErrorAction Stop
            $content = $response.Content

            # Strategy 1: Find job links by matching title keywords in anchor text
            $jobLinks = @()
            foreach ($filter in $TitleFilters) {
                # Match links containing our keywords in the anchor text
                $pattern = '(?s)<a[^>]*href="([^"]+)"[^>]*>([^<]*' + [regex]::Escape($filter) + '[^<]*)</a>'
                $matches = [regex]::Matches($content, $pattern, 'IgnoreCase')
                foreach ($match in $matches) {
                    $jobLinks += @{
                        Url   = $match.Groups[1].Value
                        Title = ($match.Groups[2].Value -replace '\s+', ' ').Trim()
                    }
                }

                # Also check for title text in nearby elements (span, div, h3 inside links)
                $pattern2 = '(?s)<a[^>]*href="([^"]+)"[^>]*>.*?(' + [regex]::Escape($filter) + '[^<]{0,80}).*?</a>'
                $matches2 = [regex]::Matches($content, $pattern2, 'IgnoreCase')
                foreach ($match in $matches2) {
                    $rawTitle = ($match.Groups[2].Value -replace '<[^>]+>', '' -replace '\s+', ' ').Trim()
                    if ($rawTitle.Length -gt 5) {
                        $jobLinks += @{
                            Url   = $match.Groups[1].Value
                            Title = $rawTitle
                        }
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

                    # Handle single JobPosting
                    $postings = @()
                    if ($jsonData.'@type' -eq 'JobPosting') {
                        $postings += $jsonData
                    }
                    # Handle arrays or ItemList
                    elseif ($jsonData.'@graph') {
                        $postings += $jsonData.'@graph' | Where-Object { $_.'@type' -eq 'JobPosting' }
                    }
                    elseif ($jsonData -is [array]) {
                        $postings += $jsonData | Where-Object { $_.'@type' -eq 'JobPosting' }
                    }

                    foreach ($posting in $postings) {
                        $titleMatch = $false
                        foreach ($filter in $TitleFilters) {
                            if ($posting.title -match $filter) {
                                $titleMatch = $true
                                break
                            }
                        }
                        if (-not $titleMatch) { continue }

                        $location = "Check listing"
                        if ($posting.jobLocation) {
                            if ($posting.jobLocation.address) {
                                $addr = $posting.jobLocation.address
                                $parts = @()
                                if ($addr.addressLocality) { $parts += $addr.addressLocality }
                                if ($addr.addressRegion) { $parts += $addr.addressRegion }
                                if ($addr.addressCountry) { $parts += $addr.addressCountry }
                                $location = $parts -join ", "
                            }
                            elseif ($posting.jobLocation.name) {
                                $location = $posting.jobLocation.name
                            }
                        }
                        if ($posting.jobLocationType -eq 'TELECOMMUTE') { $location = "Remote - $location" }

                        $salary = ""
                        if ($posting.baseSalary -and $posting.baseSalary.value) {
                            $sal = $posting.baseSalary.value
                            if ($sal.minValue -and $sal.maxValue) {
                                $salary = "`$$($sal.minValue) - `$$($sal.maxValue)"
                            }
                            elseif ($sal.value) {
                                $salary = "`$$($sal.value)"
                            }
                        }

                        $description = ""
                        if ($posting.description) {
                            $description = ($posting.description -replace '<[^>]+>', ' ' -replace '\s+', ' ')
                            # Extract salary from description if not in structured data
                            if (-not $salary -and $description -match '\$[\d,]+\s*[-–—]\s*\$[\d,]+') {
                                $salary = $Matches[0]
                            }
                            $description = $description.Substring(0, [Math]::Min(2000, $description.Length))
                        }

                        $jobUrl = if ($posting.url) { $posting.url } else { $url }

                        $allJobs += [PSCustomObject]@{
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
                }
                catch { }
            }

            # Strategy 3: Process the HTML link matches
            # Deduplicate by URL
            $seenUrls = @{}
            foreach ($link in $jobLinks) {
                $jobUrl = $link.Url
                $jobTitle = $link.Title

                # Skip if already found via JSON-LD
                if ($allJobs | Where-Object { $_.Title -eq $jobTitle -and $_.Company -eq $companyName }) { continue }

                # Make URL absolute if relative
                if ($jobUrl -notmatch '^https?://') {
                    try {
                        $baseUri = [System.Uri]$url
                        $jobUrl = [System.Uri]::new($baseUri, $jobUrl).ToString()
                    }
                    catch { continue }
                }

                # Skip duplicates
                if ($seenUrls.ContainsKey($jobUrl)) { continue }
                $seenUrls[$jobUrl] = $true

                # Skip non-job links (anchors, javascript, mailto, etc.)
                if ($jobUrl -match '^(javascript|mailto|#|tel:)') { continue }

                $allJobs += [PSCustomObject]@{
                    Source      = "CareerPage"
                    Company     = $companyName
                    Title       = $jobTitle
                    Location    = "Check listing"
                    Url         = $jobUrl
                    PostedDate  = Get-Date
                    Description = "Career page listing - visit URL for full details. Title: $jobTitle at $companyName"
                    Salary      = ""
                    JobId       = "careerpage_$($companyName.ToLower() -replace '[^a-z0-9]','')_$($jobUrl.GetHashCode())"
                }
            }

            Write-Verbose "  Found $($allJobs.Count) matching jobs at $companyName"
            $foundThisCompany = ($allJobs | Where-Object { $_.Company -eq $companyName }).Count
            Write-Host " $foundThisCompany found" -ForegroundColor $(if ($foundThisCompany -gt 0) { "Green" } else { "DarkGray" })
        }
        catch {
            Write-Host " FAIL" -ForegroundColor Red
            Write-Warning "Failed to fetch career page for $companyName : $($_.Exception.Message.Substring(0, [Math]::Min(100, $_.Exception.Message.Length)))"
        }

        # Be polite - 2s between companies (HTML scraping)
        Start-Sleep -Seconds 2
    }

    return $allJobs
}
