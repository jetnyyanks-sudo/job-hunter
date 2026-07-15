<#
.SYNOPSIS
    Job Hunter - Automated SRE Job Scraper & Scorer
.DESCRIPTION
    Scrapes multiple ATS platforms for SRE/Reliability Engineer roles,
    scores them against your profile using an LLM, and notifies you
    of high-match opportunities.
.NOTES
    Author: Job Hunter Automation
    Run daily via Task Scheduler for best results.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Resolve script root reliably
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ConfigPath -or $ConfigPath -eq "\config.json") {
    $ConfigPath = "$scriptRoot\config.json"
}

# Start logging to file
$logsDir = "$scriptRoot\logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
$logFile = "$logsDir\run_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
Start-Transcript -Path $logFile -Append | Out-Null

# ============================================================
# LOAD MODULES
# ============================================================
Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  🎯 JOB HUNTER — Automated SRE Job Scraper" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "════════════════════════════════════════════════════════════`n" -ForegroundColor DarkCyan

$modulesPath = "$scriptRoot\modules"
. "$modulesPath\Get-GreenhouseJobs.ps1"
. "$modulesPath\Get-LeverJobs.ps1"
. "$modulesPath\Get-AshbyJobs.ps1"
. "$modulesPath\Get-SmartRecruiterJobs.ps1"
. "$modulesPath\Get-WorkdayJobs.ps1"
. "$modulesPath\Get-ICIMSJobs.ps1"
. "$modulesPath\Get-RipplingJobs.ps1"
. "$modulesPath\Get-WorkableJobs.ps1"
. "$modulesPath\Get-JobBoardJobs.ps1"
. "$modulesPath\Get-CareerPageJobs.ps1"
. "$modulesPath\JobDatabase.ps1"

# ============================================================
# LOAD CONFIG
# ============================================================
Write-Host "📋 Loading configuration..." -ForegroundColor Yellow
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found: $ConfigPath"
    exit 1
}
$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

# ============================================================
# INITIALIZE DATABASE
# ============================================================
Write-Host "💾 Initializing database..." -ForegroundColor Yellow
$dbPath = "$scriptRoot\data\jobs.db"
$database = Initialize-JobDatabase -DatabasePath $dbPath

# Prune old records (keeps dedup index, removes full records older than 90 days)
Invoke-DatabaseCleanup -Database $database -RetentionDays 90

# ============================================================
# SCRAPE ALL SOURCES
# ============================================================
Write-Host "`n🔍 Scraping job boards...`n" -ForegroundColor Green

$allJobs = @()
$titleFilters = $config.title_filters
$isVerbose = $VerbosePreference -eq "Continue"
$scrapeStart = Get-Date

# --- Greenhouse ---
if ($config.companies.greenhouse -and $config.companies.greenhouse.Count -gt 0) {
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 🌿 Greenhouse ($($config.companies.greenhouse.Count) companies)..." -ForegroundColor White
    $ghJobs = Get-GreenhouseJobs -Companies $config.companies.greenhouse -TitleFilters $titleFilters -Verbose:$isVerbose
    $allJobs += $ghJobs
    Write-Host "     Found: $($ghJobs.Count) matching jobs" -ForegroundColor Gray
}

# --- Lever ---
if ($config.companies.lever -and $config.companies.lever.Count -gt 0) {
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 🔧 Lever ($($config.companies.lever.Count) companies)..." -ForegroundColor White
    $leverJobs = Get-LeverJobs -Companies $config.companies.lever -TitleFilters $titleFilters -Verbose:$isVerbose
    $allJobs += $leverJobs
    Write-Host "     Found: $($leverJobs.Count) matching jobs" -ForegroundColor Gray
}

# --- Ashby ---
if ($config.companies.ashby -and $config.companies.ashby.Count -gt 0) {
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 📋 Ashby ($($config.companies.ashby.Count) companies)..." -ForegroundColor White
    $ashbyJobs = Get-AshbyJobs -Companies $config.companies.ashby -TitleFilters $titleFilters -Verbose:$isVerbose
    $allJobs += $ashbyJobs
    Write-Host "     Found: $($ashbyJobs.Count) matching jobs" -ForegroundColor Gray
}

# --- SmartRecruiters ---
if ($config.companies.smartrecruiters -and $config.companies.smartrecruiters.Count -gt 0) {
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 🧠 SmartRecruiters ($($config.companies.smartrecruiters.Count) companies)..." -ForegroundColor White
    $srJobs = Get-SmartRecruiterJobs -Companies $config.companies.smartrecruiters -TitleFilters $titleFilters -Verbose:$isVerbose
    $allJobs += $srJobs
    Write-Host "     Found: $($srJobs.Count) matching jobs" -ForegroundColor Gray
}

# --- Workday ---
if ($config.companies.workday -and $config.companies.workday.Count -gt 0) {
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 💼 Workday ($($config.companies.workday.Count) companies)..." -ForegroundColor White
    $wdJobs = Get-WorkdayJobs -Companies $config.companies.workday -TitleFilters $titleFilters -Verbose:$isVerbose
    $allJobs += $wdJobs
    Write-Host "     Found: $($wdJobs.Count) matching jobs" -ForegroundColor Gray
}

# --- iCIMS ---
if ($config.companies.icims -and $config.companies.icims.Count -gt 0) {
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 🏢 iCIMS ($($config.companies.icims.Count) companies)..." -ForegroundColor White
    $icimsJobs = Get-ICIMSJobs -Companies $config.companies.icims -TitleFilters $titleFilters -Verbose:$isVerbose
    $allJobs += $icimsJobs
    Write-Host "     Found: $($icimsJobs.Count) matching jobs" -ForegroundColor Gray
}

# --- Rippling ---
if ($config.companies.rippling -and $config.companies.rippling.Count -gt 0) {
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 🔗 Rippling ($($config.companies.rippling.Count) companies)..." -ForegroundColor White
    $ripJobs = Get-RipplingJobs -Companies $config.companies.rippling -TitleFilters $titleFilters -Verbose:$isVerbose
    $allJobs += $ripJobs
    Write-Host "     Found: $($ripJobs.Count) matching jobs" -ForegroundColor Gray
}

# --- Workable ---
if ($config.companies.workable -and $config.companies.workable.Count -gt 0) {
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 📝 Workable ($($config.companies.workable.Count) companies)..." -ForegroundColor White
    $wkJobs = Get-WorkableJobs -Companies $config.companies.workable -TitleFilters $titleFilters -Verbose:$isVerbose
    $allJobs += $wkJobs
    Write-Host "     Found: $($wkJobs.Count) matching jobs" -ForegroundColor Gray
}

# --- Job Board APIs (RemoteOK, Jobicy) ---
Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 📡 Job Boards (RemoteOK, Jobicy)..." -ForegroundColor White
$jbJobs = Get-JobBoardJobs -TitleFilters $titleFilters -Verbose:$isVerbose
$allJobs += $jbJobs
Write-Host "     Found: $($jbJobs.Count) matching jobs" -ForegroundColor Gray

# --- Generic Career Pages ---
$careerPagesPath = "$scriptRoot\career_pages.json"
if (Test-Path $careerPagesPath) {
    $careerPages = (Get-Content -Path $careerPagesPath -Raw | ConvertFrom-Json).companies
    if ($careerPages -and $careerPages.Count -gt 0) {
        Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 🌐 Career Pages ($($careerPages.Count) companies)..." -ForegroundColor White
        $cpJobs = Get-CareerPageJobs -Companies $careerPages -TitleFilters $titleFilters -Verbose:$isVerbose
        $allJobs += $cpJobs
        Write-Host "     Found: $($cpJobs.Count) matching jobs" -ForegroundColor Gray
    }
}

Write-Host "`n  📊 Total matching jobs found: $($allJobs.Count)" -ForegroundColor Cyan

# ============================================================
# FILTER DUPLICATES
# ============================================================
Write-Host "`n🔄 Checking for duplicates..." -ForegroundColor Yellow
$newJobs = @()
foreach ($job in $allJobs) {
    if (-not (Test-JobSeen -Database $database -JobId $job.JobId)) {
        $newJobs += $job
    }
}
Write-Host "  ✨ New jobs to process: $($newJobs.Count)" -ForegroundColor Green

if ($newJobs.Count -eq 0) {
    Write-Host "`n✅ No new jobs found. All caught up!" -ForegroundColor Green
    exit 0
}

# ============================================================
# FILTER BY LEVEL (exclude junior/entry)
# ============================================================
$filteredJobs = @()
foreach ($job in $newJobs) {
    $excluded = $false
    foreach ($excludeKeyword in $config.exclude_keywords) {
        if ($job.Title -match $excludeKeyword) {
            $excluded = $true
            break
        }
    }
    if (-not $excluded) {
        $filteredJobs += $job
    }
}
Write-Host "  🎯 After level filter: $($filteredJobs.Count) jobs" -ForegroundColor Green

# ============================================================
# SAVE UNSCORED JOBS (scoring happens in Kiro)
# ============================================================
Write-Host "`n💾 Saving $($filteredJobs.Count) new jobs for scoring in Kiro..." -ForegroundColor Yellow

foreach ($job in $filteredJobs) {
    Save-Job -Database $database -Job $job -Score $null
}

# Also save to a pending file for Kiro to pick up (append to existing if present)
$pendingPath = "$scriptRoot\data\pending_scoring.json"
$existingJobs = @()
if (Test-Path $pendingPath) {
    try {
        $existing = Get-Content -Path $pendingPath -Raw | ConvertFrom-Json
        if ($existing.jobs) { $existingJobs = @($existing.jobs) }
    }
    catch { }
}

$newJobEntries = @($filteredJobs | ForEach-Object {
    @{
        JobId       = $_.JobId
        Source      = $_.Source
        Company     = $_.Company
        Title       = $_.Title
        Location    = $_.Location
        Url         = $_.Url
        Description = $_.Description
        Salary      = $_.Salary
    }
})

$allPendingJobs = $existingJobs + $newJobEntries

$pendingData = @{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    resume_file  = "resume.md"
    profile      = $config.profile
    jobs         = $allPendingJobs
}
$pendingData | ConvertTo-Json -Depth 5 | Set-Content -Path $pendingPath -Encoding UTF8
Write-Host "  Saved to: $pendingPath ($($allPendingJobs.Count) total pending, $($newJobEntries.Count) new today)" -ForegroundColor Gray
Write-Host "  Open Kiro and ask: 'score my pending jobs'" -ForegroundColor Green

# ============================================================
# RESULTS SUMMARY
# ============================================================
Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  📊 SCRAPE SUMMARY" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  Total found:      $($allJobs.Count)" -ForegroundColor White
Write-Host "  New listings:     $($newJobs.Count)" -ForegroundColor White
Write-Host "  After filters:    $($filteredJobs.Count)" -ForegroundColor White
Write-Host "  Pending scoring:  $($filteredJobs.Count)" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════════`n" -ForegroundColor DarkCyan

Write-Host "✅ Job Hunter scrape complete! $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Green
Write-Host "   Next step: open Kiro and ask 'score my pending jobs'`n" -ForegroundColor DarkGray
Write-Host "   Log saved: $logFile" -ForegroundColor DarkGray

Stop-Transcript | Out-Null
