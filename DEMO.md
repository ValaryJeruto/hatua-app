# Hatua: 3-minute demo

## Setup for the script below

- **Interface:** English at the start.
- **Demo goal:** loaded in **Kiswahili** on the day of the demo (see the checklist), so the coach replies in Kiswahili. It shows 🔥 4 and has 3 past check-ins.
- **Live goal to type:** *Save 5,000 shillings for a laptop by December*. It matches the built-in "saving" template, so it still works if the AI is down.
- **AI calls:** the whole script uses about 3–4 (plan, coach reply, adapting).

> ⚠️ **Gemini free-tier limits: about 5 requests per minute AND only 20 per day** for `gemini-2.5-flash`. One full rehearsal uses about 4, so **rehearse at most 2–3 times with the AI on demo day**, and practise the rest with the AI off (see the backup path). Better still, use a key with billing enabled, or a separate fresh key, just for the demo. You can see your usage at https://aistudio.google.com/.

## The script

### 0:00–0:20 · Hook (20s)
> "Most young people I know have a big goal: a first job, a skill, saving for a laptop. The dream isn't the problem. *Starting* is, and keeping going after a bad week. Most apps just pile up undone tasks. Hatua is a coach that meets you where you are, one small step at a time, in English or Kiswahili."

*On screen: the home page, EN.*

### 0:20–1:00 · Plan a goal live (40s)
1. Type **Save 5,000 shillings for a laptop by December**, and for why: **To learn coding at home**.
2. Set **15** min/day and **English**, then click **Plan it**.
> "I tell Hatua my goal, why it matters and how much time I really have. Jac sends that to Gemini through a typed AI function. It must return milestones and steps, nothing else, and every step has to fit in 15 minutes."
3. When the plan appears, scroll briefly. *(If you see "📴 Offline plan", say: "No internet? Hatua still gives a starter plan.")*

### 1:00–1:30 · Tick a step (30s)
1. Open the demo goal, **Pata kazi yangu ya kwanza mtandaoni…**. The **Today** tab shows just 1–3 steps.
> "Today only shows the next few steps, so you're never overwhelmed. This learner has shown up 4 days in a row."
2. Tick the first step. The badge goes from **🔥 4-day streak** to **🔥 5-day streak**.
> "One tick and the streak grows. Small wins, every day."

### 1:30–2:20 · Hard day in Kiswahili: the coach adapts (50s)
1. Click **SW** in the header, and the whole interface switches.
> "Hatua speaks Kiswahili too, the whole interface, not just the AI."
2. Open the **Ripoti** tab, pick **😞 Ngumu**, and type **Nimechoka sana leo, sina nguvu**. Click **Hifadhi**.
3. The coach card shows *Inafikiri…*, then a warm reply in Kiswahili, then **"Nimezifanya hatua zako zinazofuata kuwa ndogo kwa leo 💛"**.
> "On a hard day, most apps make you feel worse. Hatua listens, replies kindly, and quietly makes tomorrow's steps smaller."
4. Open **Leo**. The steps now carry the **Imerahisishwa kwa leo** tag.
> "Same goal, gentler steps. And it's the user's choice: one tap on Tendua brings the old plan back."

### 2:20–2:40 · Progress (20s)
1. Open **Maendeleo**.
> "Progress, milestone by milestone, the streak, and how often they checked in this week. Proof that small steps add up."

### 2:40–3:00 · Impact close (20s)
> "Hatua is built for young people in Kenya, including POD learners, who have the ambition but need a patient coach in their own language. It never gives medical, legal or financial advice, and the Kenya Red Cross line, 1199, is on every screen. It's one Jac codebase: graph data, typed AI functions and a React interface, together. Hatua: one small step at a time. Asante!"

## Backup path (AI or internet down)

Hatua runs on your laptop. Only the AI calls need the internet, so the app itself won't go down.

| If… | Do this | Say |
|---|---|---|
| Planning fails | Use the saving goal from the script. It matches a built-in template, so you'll get a plan with the **📴 Offline plan** note. | "Even without internet, Hatua gives a ready-made starter plan." |
| The coach is down | The check-in still saves and shows the kind default reply (*"Asante kwa kuripoti. Hatua moja ndogo leo inatosha."*). The steps won't shrink. | "The coach always answers kindly. When the AI is back, it also makes the steps smaller." |
| The demo goal is missing or used up | Open **http://localhost:8000/?demo=1** and click **Load demo** in the footer. | — |
| You hit the rate limit (`429` / `RateLimitError` in the terminal) | If it says *PerMinute*, wait 60 seconds. If it says *PerDay*, the AI is out until tomorrow, so continue with the backup lines above. | — |
| Everything fails | Show the screenshots in `docs/screenshots/` and talk through them. | — |

**To reset the demo between rehearsals:** open the demo goal, click **Delete goal**, then **Yes, delete**. Then open `/?demo=1` and click **Load demo** again.

## Pre-demo checklist

- [ ] **Key set:** `.env` contains `GEMINI_API_KEY=…`.
- [ ] **Server running:** `jac run main.jac` in your terminal, and http://localhost:8000 loads.
- [ ] **One test plan works,** at least 2 minutes before you go on, so the per-minute limit has reset by demo time. Don't burn the daily 20 on rehearsals.
- [ ] **Old test goals deleted:** every "(UI test)" or "Stage 3 test" goal.
- [ ] **Demo goal loaded TODAY in Kiswahili:** click **SW**, open `/?demo=1`, click **Pakia mfano**, then switch back to **EN**. (Load it on the day itself; the 4-day streak counts back from that day.)
- [ ] **Demo goal shows 🔥 4,** with no check-in for today yet.
- [ ] **Interface back on EN,** with no goal open and the new-goal form empty.
- [ ] **Browser zoom 125–150%** so the back row can read it.
- [ ] **Phone view ready** in a second tab with DevTools device mode (Ctrl+Shift+M, around 390px wide), in case they ask about mobile.
- [ ] Notifications off, other tabs closed, laptop charging.

## Likely judge questions

**Why Jac?**
One language for the whole app. The data is a graph of nodes (Goal → Milestone → Step), every `def:pub` function is automatically an API endpoint, AI calls are typed functions with `by llm()`, and the React interface lives in the same codebase through jac-client. That let one person build a full-stack AI app in a hackathon.

**How is the AI kept safe?**
Every prompt forbids medical, legal and financial advice. The coach is told to respond with care to signs of crisis and to point to Kenya Red Cross on 1199, which is also on every screen. Outputs are typed, so the model can't return free-form text where a plan is expected. Hard days only ever make steps *smaller*, and the user can undo that.

**Does it work offline?**
The app runs locally, and all data is stored on the device. If the AI can't be reached, goals about jobs, saving, fitness or learning get a hand-written starter plan in English or Kiswahili, check-ins still save, and the coach sends a kind default message. Nothing crashes, and nothing is lost.

**What's next?**
User accounts, so each person has their own goals; reminders by SMS or WhatsApp, since many users rely on feature phones and data bundles; more Kenyan languages (Sheng, Dholuo, Kikuyu); and partnering with programmes like POD to support learners between sessions.

**Who does it help?**
Young people in Kenya with big goals and limited time, money or support, such as job seekers, learners in programmes like POD, and anyone who has given up on a plan after a bad week. Hatua coaches in their language and adjusts to how they actually feel.
