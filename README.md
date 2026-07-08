# Job Hunter - Automated SRE Job Scraper

A PowerShell + Kiro automation that scrapes ATS platforms and career pages for SRE roles, then uses Kiro to score and notify you of high-match opportunities.

**Zero API fees. Scoring and email powered by your Kiro Pro subscription.**

## How It Works

The system runs in two phases:

### Phase 1: Scrape (automated, runs on schedule)

```
Task Scheduler (daily 7 AM)
    → Run-JobHunter.ps1
    → Scrapes 7 sources (6 ATS APIs + generic career pages)
    → Filters by title/level keywords
    → Deduplicates against previously seen jobs
    → Appends new jobs to data/pending_scoring.json
    → Auto-prunes database records older than 90 days
```

### Phase 2: Score + Notify (in Kiro, on your schedule)

```
You open Kiro (daily, weekly, whenever)
    → Ask: "score my pending jobs"
    → Kiro reads resume.md + pending_scoring.json
    → Scores each job 1-100 against your full resume
    → Buckets: Apply Today (85+), Worth Looking (70-84), Skip (<70)
    → Sends email via Gmail MCP with both buckets (links included)
    → Clears the pending queue
```

Pending jobs accumulate across runs — score daily or let them pile up for a weekly review.

## Prerequisites

- **PowerShell 5.1+** (Windows built-in)
- **Node.js** (for the GitHub MCP server via `npx`)
- **Kiro Pro** with these MCP servers connected:

| MCP Server | Purpose | Config Location |
|------------|---------|-----------------|
| Google Workspace | Send scoring emails via Gmail | User-level (`~/.kiro/settings/mcp.json`) |
| GitHub | Push code, manage repo | Workspace-level (`.kiro/settings/mcp.json`) |

The Google Workspace MCP is configured at the user level (applies globally). The GitHub MCP is workspace-specific and uses the `GITHUB_JOBHUNTER_PAT` env var for auth.

## Quick Start

### 1. Environment Variables

```powershell
# Required for email notifications
[Environment]::SetEnvironmentVariable("JOBHUNTER_GMAIL", "your-email@gmail.com", "User")

# Required for GitHub integration (optional, for pushing code)
[Environment]::SetEnvironmentVariable("GITHUB_JOBHUNTER_PAT", "ghp_your_token_here", "User")
```

### 2. Configure

Edit `config.json`:
- Adjust `profile` to match your background, skills, and salary minimum
- Adjust `title_filters` and `exclude_keywords`
- Add/remove companies from each ATS section

Edit `career_pages.json`:
- Add career page URLs for companies not on the 6 supported ATS platforms

Create `resume.md`:
- Add your resume in markdown format (used by Kiro for scoring context)

### 3. Run the scraper

```powershell
.\Run-JobHunter.ps1

# Verbose output for debugging
.\Run-JobHunter.ps1 -Verbose
```

### 4. Score in Kiro

Open this project in Kiro and say:

> "score my pending jobs"

Kiro will read the scraped jobs, score them against your resume, and send an email with Apply Today and Worth Looking results (with clickable application links).

### 5. Schedule the scraper

```powershell
$scriptPath = "C:\path\to\job-hunter\Run-JobHunter.ps1"  # Update this path
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NonInteractive -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At 7am
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName "JobHunter" -Action $action -Trigger $trigger -Settings $settings -Description "Daily SRE job scraper"
```

`-StartWhenAvailable` ensures the scrape runs when your machine powers on if it missed the 7 AM window.

## Supported Platforms

| Platform | Method | Auth Required | Config File |
|----------|--------|---------------|-------------|
| Greenhouse | JSON API | No | config.json |
| Lever | JSON API | No | config.json |
| Ashby | JSON API | No | config.json |
| SmartRecruiters | JSON API | No | config.json |
| Workday | HTML scraping | No | config.json |
| iCIMS | HTML scraping | No | config.json |
| Any career page | HTML + JSON-LD | No | career_pages.json |

## Scoring Criteria

When you ask Kiro to score jobs, it reads your `resume.md` and evaluates each job on 5 factors:

| Factor | Weight | What it checks |
|--------|--------|----------------|
| Title/Level Match | 25% | SRE/Reliability/Platform title at Principal/Staff/Senior level |
| Skills Match | 30% | Matches against your resume's specific tools and experience |
| Salary Fit | 20% | Uses listed salary if available; estimates only if not found |
| Remote/Location | 15% | Remote-friendly or US-based |
| Company Fit | 10% | Good engineering culture, 50-10k employees |

## Kiro Commands

| Command | What it does |
|---------|--------------|
| "score my pending jobs" | Score all accumulated jobs, send email with results |
| "send the pending job hunter email" | Resend the last scoring email |
| Click **Send Job Hunter Email** hook | Same as above, via the hook button |

## Adding Companies

### ATS-specific (API-based, most reliable)

Add the company slug to `config.json`:
```json
"greenhouse": ["hashicorp", "datadog", "newcompany"],
"lever": ["netflix", "figma", "anothercompany"]
```

For Workday/iCIMS, add an object with the search URL:
```json
"workday": [
  { "name": "CompanyName", "url": "https://company.wd5.myworkdaysite.com/search?q=sre" }
]
```

### Generic career pages (any ATS, broader coverage)

Add any company's careers search URL to `career_pages.json`:
```json
{ "name": "Stripe", "url": "https://stripe.com/jobs/search?query=site+reliability" }
```

This works regardless of what ATS the company uses. The scraper searches the page for links matching your title filters and extracts any JSON-LD structured job data.

### Detecting a company's ATS

```powershell
.\Find-CompanyATS.ps1 -Url "https://careers.company.com"
.\Find-CompanyATS.ps1 -CompanyName "Datadog"
```

If the ATS is supported (Greenhouse, Lever, Ashby, SmartRecruiters), add the slug to `config.json`. Otherwise, add the careers URL to `career_pages.json`.

## Email Setup

Email is sent through Gmail via Kiro's Google Workspace MCP. No SMTP credentials or app passwords needed.

Requirements:
1. Set the `JOBHUNTER_GMAIL` environment variable (see Quick Start)
2. Google Workspace MCP connected in Kiro

The email includes both **Apply Today** (full details + reasoning) and **Worth Looking** (condensed list), all with clickable application links.

## Data Retention

The job database auto-prunes on every run:
- **Job records**: deleted after 90 days (configurable in `Run-JobHunter.ps1`)
- **Dedup index**: kept forever — you'll never re-process the same job
- **Pending scoring**: accumulates daily until you score in Kiro, then clears

## File Structure

```
job-hunter/
├── Run-JobHunter.ps1           # Main scraper (runs on schedule)
├── Find-CompanyATS.ps1         # Utility: detect a company's ATS
├── Send-PendingEmail.ps1       # Shows pending email status
├── config.json                 # ATS company list + profile settings
├── career_pages.json           # Generic career page URLs (any ATS)
├── .gitignore
├── .kiro/
│   ├── hooks/
│   │   └── send-job-email.kiro.hook
│   ├── settings/
│   │   └── mcp.json            # GitHub MCP config
│   └── steering/
│       └── job-scoring.md      # Scoring instructions for Kiro
└── modules/
    ├── Get-GreenhouseJobs.ps1
    ├── Get-LeverJobs.ps1
    ├── Get-AshbyJobs.ps1
    ├── Get-SmartRecruiterJobs.ps1
    ├── Get-WorkdayJobs.ps1
    ├── Get-ICIMSJobs.ps1
    ├── Get-CareerPageJobs.ps1  # Generic scraper (any career page)
    ├── Export-HtmlReport.ps1
    ├── Send-JobNotification.ps1
    ├── Invoke-LLMScoring.ps1   # Legacy, not used
    └── JobDatabase.ps1

# Created at runtime (gitignored):
# data/jobs.json              - Job database
# data/pending_scoring.json   - Jobs awaiting scoring
# data/scored_results.json    - Scoring output
# reports/report_*.html       - HTML reports
# resume.md                   - Your resume (scoring context)
```

## Cost

**$0 extra.** Scraping is free (public APIs + HTML). Scoring and email use your existing Kiro Pro subscription.

## Development

Repo: [github.com/jetnyyanks-sudo/job-hunter](https://github.com/jetnyyanks-sudo/job-hunter)

```powershell
git clone https://github.com/jetnyyanks-sudo/job-hunter.git
```

The `.gitignore` excludes all personal data (resume, job database, reports, scored results).
