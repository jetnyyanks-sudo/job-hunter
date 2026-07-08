function Invoke-LLMScoring {
    <#
    .SYNOPSIS
        Scores a job listing against the user's profile using an LLM.
    .DESCRIPTION
        Sends the job description and user profile to an LLM API (OpenAI-compatible)
        and returns a score from 1-100 with explanation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Job,

        [Parameter(Mandatory)]
        [PSCustomObject]$Profile,

        [Parameter(Mandatory)]
        [hashtable]$ScoringConfig
    )

    $prompt = @"
You are a job matching expert. Score how well this job matches the candidate's profile.

CANDIDATE PROFILE:
- Current Title: $($Profile.title)
- Level: $($Profile.level)
- Acceptable Levels: $($Profile.acceptable_levels -join ', ')
- Core Skills: $($Profile.skills -join ', ')
- Minimum Salary: `$$($Profile.minimum_salary)/year
- Summary: $($Profile.summary)

JOB LISTING:
- Title: $($Job.Title)
- Company: $($Job.Company)
- Location: $($Job.Location)
- Salary Listed: $($Job.Salary)
- Source: $($Job.Source)
- Description: $($Job.Description)

SCORING CRITERIA (weight these factors):
1. TITLE/LEVEL MATCH (25%): Does the title align with SRE/Reliability and is the level appropriate (Principal, Staff, or Senior)?
2. SKILLS MATCH (30%): Does it mention Dynatrace, Terraform, PagerDuty, Azure DevOps, PowerShell, observability, monitoring, IaC?
3. SALARY FIT (20%): If salary is listed, is it >= `$180,000? If not listed, estimate based on title/company/level.
4. REMOTE/LOCATION (15%): Is it remote-friendly or US-based?
5. COMPANY/GROWTH (10%): Is this a reputable company with good engineering culture?

RESPOND IN EXACTLY THIS FORMAT (no markdown, no extra text):
SCORE: [number 1-100]
REASON: [2-3 sentence explanation of the score]
SKILLS_MATCHED: [comma-separated list of matching skills found in the job]
SALARY_ESTIMATE: [your estimate if not listed, or the listed salary]
"@

    try {
        $body = @{
            model       = $ScoringConfig.model
            messages    = @(
                @{ role = "system"; content = "You are a precise job matching assistant. Always respond in the exact format requested." }
                @{ role = "user"; content = $prompt }
            )
            temperature = 0.3
            max_tokens  = 300
        } | ConvertTo-Json -Depth 5

        $headers = @{
            "Authorization" = "Bearer $($ScoringConfig.api_key)"
            "Content-Type"  = "application/json"
        }

        $response = Invoke-RestMethod -Uri $ScoringConfig.base_url -Method Post -Headers $headers -Body $body -ErrorAction Stop

        $content = $response.choices[0].message.content

        # Parse the response
        $score = 0
        $reason = ""
        $skillsMatched = ""
        $salaryEstimate = ""

        if ($content -match 'SCORE:\s*(\d+)') { $score = [int]$Matches[1] }
        if ($content -match 'REASON:\s*(.+?)(?:\r?\n|$)') { $reason = $Matches[1].Trim() }
        if ($content -match 'SKILLS_MATCHED:\s*(.+?)(?:\r?\n|$)') { $skillsMatched = $Matches[1].Trim() }
        if ($content -match 'SALARY_ESTIMATE:\s*(.+?)(?:\r?\n|$)') { $salaryEstimate = $Matches[1].Trim() }

        return [PSCustomObject]@{
            Score          = $score
            Reason         = $reason
            SkillsMatched  = $skillsMatched
            SalaryEstimate = $salaryEstimate
            RawResponse    = $content
        }
    }
    catch {
        Write-Warning "LLM scoring failed for $($Job.Title) at $($Job.Company): $_"
        return [PSCustomObject]@{
            Score          = 0
            Reason         = "Scoring failed: $_"
            SkillsMatched  = ""
            SalaryEstimate = ""
            RawResponse    = ""
        }
    }
}
