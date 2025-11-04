# Meeting Classification Review

## Purpose
Review and improve meeting classification rules based on actual calendar data.

## Classification Results (Sorted by Confidence - Lowest First)

### Unknown (Confidence: 50%) - NEEDS RULES

1. **weekly kpi start**
   - Current: unknown / unknown / unknown
   - Suggested: ???
   - Jeff's Input:

---

### Low Confidence (75%) - Likely Wrong Guesses

2. **Gone - Weekly Sync**
   - Current: ipmedia_1on1 / IPMedia / Gone
   - Suggested: Team meeting or company meeting?
   - Jeff's Input:

3. **Gone Standup**
   - Current: ipmedia_1on1 / IPMedia / Gone
   - Suggested: Team standup?
   - Jeff's Input:

4. **HR + Recruitment Weekly**
   - Current: ipmedia_1on1 / IPMedia / HR
   - Suggested: Team meeting?
   - Jeff's Input:

5. **Headquarters Meeting**
   - Current: ipmedia_1on1 / IPMedia / Headquarters
   - Suggested: Company-wide meeting?
   - Jeff's Input:

6. **Interage - DEV Coworking**
   - Current: ipmedia_1on1 / IPMedia / Interage
   - Suggested: ???
   - Jeff's Input:

7. **Internal Meeting - November 2025**
   - Current: ipmedia_1on1 / IPMedia / Internal
   - Suggested: Company meeting?
   - Jeff's Input:

8. **Jeff / Ron Weekly Meeting**
   - Current: ipmedia_1on1 / IPMedia / Ron
   - Suggested: This looks correct - 1on1 with Ron
   - Jeff's Input:

9. **Jeff and DBoy**
   - Current: ipmedia_1on1 / IPMedia / DBoy
   - Suggested: This looks correct - 1on1 with DBoy
   - Jeff's Input:

10. **MP BI Meeting**
    - Current: ipmedia_1on1 / IPMedia / MP
    - Suggested: Team meeting (BI team)?
    - Jeff's Input:

11. **MP Product Team Meeting**
    - Current: ipmedia_1on1 / IPMedia / MP
    - Suggested: Team meeting (Product team)?
    - Jeff's Input:

12. **MeuMatch Product Discussion**
    - Current: ipmedia_1on1 / IPMedia / MeuMatch
    - Suggested: Product/project meeting?
    - Jeff's Input:

13. **Mkt Headquarter**
    - Current: ipmedia_1on1 / IPMedia / Mkt
    - Suggested: Marketing team or company meeting?
    - Jeff's Input:

14. **Ops Team Weekly**
    - Current: ipmedia_1on1 / IPMedia / Ops
    - Suggested: Team meeting (Ops team)?
    - Jeff's Input:

15. **Overview - Novembro 2025**
    - Current: ipmedia_1on1 / IPMedia / Overview
    - Suggested: Company overview meeting?
    - Jeff's Input:

16. **PD - Best Meeting Ever**
    - Current: ipmedia_1on1 / IPMedia / PD
    - Suggested: PD company meeting (already have pattern for "pd weekly")?
    - Jeff's Input:

17. **Reunião de KPI - Aberta**
    - Current: ipmedia_1on1 / IPMedia / Reunião
    - Suggested: KPI review meeting (company/team)?
    - Jeff's Input:

18. **Slackbot Weekly**
    - Current: ipmedia_1on1 / IPMedia / Slackbot
    - Suggested: ???
    - Jeff's Input:

19. **Social Media and Press - Headquarters**
    - Current: ipmedia_1on1 / IPMedia / Social
    - Suggested: Marketing/PR team meeting?
    - Jeff's Input:

20. **Thais Guapyassu e Deila Gabriela Santos Coelho**
    - Current: ipmedia_1on1 / IPMedia / Thais
    - Suggested: This looks correct - 1on1 with Thais (multiple participants in meeting)
    - Jeff's Input:

21. **Vlad & Jeff moving forward on projects**
    - Current: ipmedia_1on1 / IPMedia / Vlad
    - Suggested: This looks correct - 1on1 with Vlad
    - Jeff's Input:

22. **Weekly Meeting Excelsior**
    - Current: ipmedia_1on1 / IPMedia / Excelsior
    - Suggested: Excelsior company meeting (like "Weekly Meeting TP")?
    - Jeff's Input:

23. **Weekly Meeting TP**
    - Current: ipmedia_1on1 / IPMedia / TP
    - Suggested: Should match TP company meeting pattern (already exists but not matching)
    - Jeff's Input:

24. **Weekly RH <> SUPORTE**
    - Current: ipmedia_1on1 / IPMedia / RH
    - Suggested: HR/Support team meeting?
    - Jeff's Input:

25. **[SEO] Meu Patrocinio & Chili - Biweekly**
    - Current: ipmedia_1on1 / IPMedia / Meu
    - Suggested: SEO/marketing meeting?
    - Jeff's Input:

---

### High Confidence (88-90%) - Likely Correct

26. **MassTraffic Weekly**
    - Current: co_mt_meeting / MT / MassTraffic
    - Status: ✅ Correctly classified as MT company meeting

27-44. **All "1on1 [Name] Jeff" meetings**
    - Status: ✅ All correctly classified as IPMedia 1-on-1s with correct participant names

---

## Notes

- The classifier is good at recognizing explicit "1on1" patterns (90% confidence)
- It correctly identified "MassTraffic Weekly" as MT company meeting (88% confidence)
- Many team/company meetings are being misclassified as 1-on-1s because they have a capitalized word
- Need to add patterns for: team meetings, standup, KPI meetings, headquarters, etc.
