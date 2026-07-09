function Get-CareerPageJobs {
    <#
    .SYNOPSIS
        Generic career page scraper that works with any company website.
    .DESCRIPTION
        Fetches company career/jobs pages by URL in parallel (5 at a time),
        searches for job links matching title filters, and extracts job titles + URLs.
        Uses HttpClient with hard 5-second timeout to prevent hanging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Companies,

        [Parameter(Mandatory)]
        [string[]]$TitleFilters
    )

    $totalCount = $Companies.Count
    $allJobs = $Companies | ForEach-Object -ThrottleLimit 5 -Parallel {
        $companyConfig = $_
        $companyName = $companyConfig.name
        $url = $companyConfig.url
        $TitleFilters = $using:TitleFilters
        $jobs = @()

        try {
            # Use HttpClient with hard timeout (Invoke-WebRequest can hang)
            $handler = [System.Net.Http.HttpClientHandler]::new()
            $handler.AllowAutoRedirect = $true
            $handler.MaxAutomaticRedirections = 5
            $client = [System.Net.Http.HttpClient]::new($handler)
            $client.Timeout = [TimeSpan]::FromSeconds(5)
            $client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            $client.DefaultRequestHeaders.Add("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")

            $responseMsg = $client.GetAsync($url).GetAwaiter().GetResult()
            if (-not $responseMsg.IsSuccessStatusCode) {
                Write-Host "     [$companyName] HTTP $($responseMsg.StatusCode)" -ForegroundColor Red
                $client.Dispose()
                return
            }
            $content = $responseMsg.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $client.Dispose()

            # Strategy 1: Find job links by matching title keywords in anchor text
            foreach ($filter in $TitleFilters) {
                $pattern = '(?s)<a[^>]*href="([^"]+)"[^>]*>([^<]*' + [regex]::Escape($filter) + '[^<]*)</a>'
                $linkMatches = [regex]::Matches($content, $pattern, 'IgnoreCase')
                foreach ($m in $linkMatches) {
                    $jobUrl = $m.Groups[1].Value
                    $jobTitle = ($m.Groups[2].Value -replace '\s+', ' ').Trim()

                    if ($jobUrl -notmatch '^https?://') {
                        try { $jobUrl = [System.Uri]::new([System.Uri]$url, $jobUrl).ToString() } catch { continue }
                    }
                    if ($jobUrl -match '^(javascript|mailto|#|tel:)') { continue }
                    if ($jobs | Where-Object { $_.Url -eq $jobUrl }) { continue }

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
            }

            # Strategy 2: Check JSON-LD structured data
            $jsonLdPattern = '(?s)<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>'
            $jsonMatches = [regex]::Matches($content, $jsonLdPattern, 'Singleline')
            foreach ($jsonMatch in $jsonMatches) {
                try {
                    $jsonData = $jsonMatch.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop
                    $postings = @()
                    if ($jsonData.'@type' -eq 'JobPosting') { $postings += $jsonData }
                    elseif ($jsonData.'@graph') { $postings += $jsonData.'@graph' | Where-Object { $_.'@type' -eq 'JobPosting' } }

                    foreach ($posting in $postings) {
                        $titleMatch = $false
                        foreach ($filter in $TitleFilters) {
                            if ($posting.title -match $filter) { $titleMatch = $true; break }
                        }
                        if (-not $titleMatch) { continue }
                        if ($jobs | Where-Object { $_.Title -eq $posting.title -and $_.Company -eq $companyName }) { continue }

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

                        $jobUrl = if ($posting.url) { $posting.url } else { $url }

                        $jobs += [PSCustomObject]@{
                            Source      = "CareerPage"
                            Company     = $companyName
                            Title       = $posting.title
                            Location    = $location
                            Url         = $jobUrl
                            PostedDate  = if ($posting.datePosted) { try { [datetime]$posting.datePosted } catch { Get-Date } } else { Get-Date }
                            Description = if ($posting.description) { ($posting.description -replace '<[^>]+>', ' ' -replace '\s+', ' ').Substring(0, [Math]::Min(2000, $posting.description.Length)) } else { "" }
                            Salary      = $salary
                            JobId       = "careerpage_$($companyName.ToLower() -replace '[^a-z0-9]','')_$($posting.title.GetHashCode())"
                        }
                    }
                } catch { }
            }

            $count = $jobs.Count
            Write-Host "     [$companyName] $count found" -ForegroundColor $(if ($count -gt 0) { "Green" } else { "DarkGray" })
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg.Length -gt 60) { $msg = $msg.Substring(0, 60) + "..." }
            Write-Host "     [$companyName] FAIL: $msg" -ForegroundColor Red
        }

        $jobs
    }

    $results = @($allJobs | Where-Object { $_ -ne $null -and $_.PSObject.Properties.Name -contains 'JobId' })
    Write-Host "     Career Pages total: $($results.Count) jobs" -ForegroundColor Cyan
    return $results
}
