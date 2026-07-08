---
inclusion: manual
---

# Job Scoring Instructions

When the user asks to "score my pending jobs" or "score jobs", follow this workflow:

## 1. Read the candidate's resume and pending jobs

First, read `resume.md` to understand the candidate's full experience, skills, certifications, and career history. Use this as the primary reference for scoring — it's more detailed than the profile summary in config.json.

Then read `data/pending_scoring.json`. It contains a `profile` object (high-level preferences) and a `jobs` array.

## 2. Score each job 1-100

For each job, evaluate against the candidate's resume and profile using these weighted criteria:

- **Title/Level Match (25%)**: Is the title SRE/Reliability/Platform and is the level Principal, Staff, or Senior? Match against the candidate's current and target seniority.
- **Skills Match (30%)**: How well do the job requirements align with the specific tools, technologies, and experience on the resume? Look for: Dynatrace, Terraform, PagerDuty, Azure DevOps, PowerShell, observability, monitoring, IaC, incident management, and any other skills from the resume.
- **Salary Fit (20%)**: Always use the salary listed in the job posting if available. If the scraped description includes a salary range, use that exact figure. Only estimate if no salary information is found anywhere in the job data. If listed salary is below $180,000, score this criteria as 0 and note it as a concern in the reason.
- **Remote/Location (15%)**: Is it remote-friendly or US-based?
- **Company/Growth (10%)**: Reputable company with good engineering culture, 50-10,000 employees?

## 3. Bucket the results

- **Apply Today**: Score >= 85
- **Worth Looking**: Score 70-84
- **Skip**: Score < 70

## 4. Write results

Save scored results to `data/scored_results.json` with this structure per job:
```json
{
  "job_id": "...",
  "score": 88,
  "reason": "2-3 sentence explanation",
  "skills_matched": "Terraform, Observability, IaC",
  "salary_estimate": "$190,000-$220,000",
  "bucket": "apply_today"
}
```

After writing scored results, **delete `data/pending_scoring.json`** to clear the queue so the next week's scrapes start fresh.

## 5. Generate report and email

After scoring:
- Read `modules/Export-HtmlReport.ps1` and generate an HTML report to `reports/report_YYYY-MM-DD.html`
- Prepare and send an email notification via Gmail MCP that includes:
  - **Apply Today** jobs (score 85+) with full details: title, company, location, score, reasoning, salary estimate, and clickable application link
  - **Worth Looking** jobs (score 70-84) as a condensed list with title, company, score, and clickable link
- The email goes to the Gmail address in config.json

## 6. Present summary

Show the user a summary table of Apply Today and Worth Looking jobs with scores, then send the email automatically unless they say otherwise.
