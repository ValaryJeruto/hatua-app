import "./styles.css";
import os;
import from datetime { date, timedelta }

# ================= BACKEND (runs on the server) =================
# Graph shape:  root --> Goal --> Milestone --> Step
#                        Goal --> CheckIn

node Goal {
    has title: str,
        why: str = "",
        minutes_per_day: int = 15,
        language: str = "en",
        is_demo: bool = False;
}

node Milestone {
    has title: str;
}

node Step {
    has text: str,
        done: bool = False,
        done_on: str = "",
        original_text: str = "";
}

node CheckIn {
    has mood: str,
        note: str = "",
        day: str = "",
        coach_reply: str = "",
        adapted: bool = False;
}

# ---- views sent to the browser ----

obj StepView {
    has id: str,
        text: str,
        done: bool;
}

obj MilestoneView {
    has id: str,
        title: str,
        steps: list[StepView];
}

obj TodayStep {
    has id: str,
        text: str,
        done: bool,
        milestone_title: str,
        original_text: str = "";
}

obj CheckInView {
    has id: str,
        mood: str,
        note: str,
        day: str,
        is_today: bool,
        coach_reply: str = "",
        adapted: bool = False;
}

obj CheckInResult {
    has checkin: CheckInView,
        coach_reply: str,
        adapted: bool,
        new_steps: list[TodayStep],
        error: str = "";
}

obj MilestoneProgress {
    has id: str,
        title: str,
        done: int,
        total: int,
        percent: int;
}

obj ProgressView {
    has percent: int,
        done: int,
        total: int,
        streak: int,
        checkins_this_week: int,
        milestones: list[MilestoneProgress];
}

obj PlanResult {
    has ok: bool,
        error: str = "",
        offline: bool = False,
        milestones: list[MilestoneView] = [];
}

# ---- AI: the shape the LLM must fill in ----

obj MilestonePlan {
    has title: str,
        steps: list[str];
}
sem MilestonePlan.title = "A short, encouraging milestone name (max 8 words).";
sem MilestonePlan.steps = "3 to 5 small, concrete actions for this milestone, in order. Each starts with a verb and is doable in one sitting within the daily time budget.";

def plan_goal(goal: str, why: str, minutes_per_day: int, language: str) -> list[MilestonePlan] by llm(temperature=0.4);
sem plan_goal = """You are Hatua, a warm, practical self-help goal coach.
Break the user's big goal into 3 to 5 milestones, in the order they should be done.
Give each milestone 3 to 5 tiny daily steps. Every step must fit in minutes_per_day minutes.
Write ALL text in the requested language: 'en' = English, 'sw' = Kiswahili (simple, everyday Kiswahili).
Never give medical, legal or financial advice. If the goal touches health, keep steps to
everyday habits and include a step to talk to a qualified professional.""";
sem plan_goal.goal = "The user's big goal, in their own words.";
sem plan_goal.why = "Why this goal matters to the user (may be empty).";
sem plan_goal.minutes_per_day = "How many minutes per day the user can spend.";
sem plan_goal.language = "Language code for the output: 'en' or 'sw'.";

def coach_message(goal: str, mood: str, note: str, streak: int, language: str) -> str by llm(temperature=0.6);
sem coach_message = """You are Hatua, a warm, practical goal coach. Reply in 2-3 short sentences in the requested language ('en' English, 'sw' simple everyday Kiswahili). Acknowledge the feeling, mention the streak if it's above 0, and end with one tiny next action. Never give medical, legal or financial advice. If the note suggests the person is in crisis or thinking of harming themselves, respond with care, encourage them to talk to someone they trust, and mention they can call Kenya Red Cross on 1199.""";
sem coach_message.goal = "The user's big goal.";
sem coach_message.mood = "How today felt: 'good', 'okay' or 'hard'.";
sem coach_message.note = "The user's one-line note about today (may be empty).";
sem coach_message.streak = "Consecutive days with at least one step done.";
sem coach_message.language = "Language code for the reply: 'en' or 'sw'.";

def adapt_steps(
    goal: str, milestone: str, steps: list[str], mood: str, note: str,
    minutes_per_day: int, language: str
) -> list[str] by llm(temperature=0.4);
sem adapt_steps = """Rewrite each step to be smaller and gentler, doable in about half the daily time. Return exactly one rewritten step per input step, same order, same language. Each starts with a verb.""";
sem adapt_steps.steps = "The steps to rewrite, in order.";
sem adapt_steps.minutes_per_day = "The user's usual daily time budget in minutes.";
sem adapt_steps.language = "Language code: 'en' or 'sw'.";

# ---- private helpers (not exposed as endpoints) ----

"""Load KEY=VALUE lines from ./.env into os.environ (jac run does not do this)."""
def:priv load_env -> None {
    path = os.path.join(os.getcwd(), ".env");
    if not os.path.exists(path) { return; }
    with open(path) as f {
        for raw in f {
            line = raw.strip();
            if not line or line.startswith("#") or "=" not in line { continue; }
            if line.startswith("export ") { line = line[7:].strip(); }
            parts = line.split("=", 1);
            key = parts[0].strip();
            val = parts[1].strip().strip('"').strip("'");
            if key and key not in os.environ { os.environ[key] = val; }
        }
    }
}

def:priv find_goal(goal_id: str) -> Goal | None {
    for g in [root-->][?:Goal] {
        if jid(g) == goal_id { return g; }
    }
    return None;
}

def:priv find_milestone(milestone_id: str) -> Milestone | None {
    for g in [root-->][?:Goal] {
        for m in [g-->][?:Milestone] {
            if jid(m) == milestone_id { return m; }
        }
    }
    return None;
}

def:priv find_step(step_id: str) -> Step | None {
    for g in [root-->][?:Goal] {
        for m in [g-->][?:Milestone] {
            for s in [m-->][?:Step] {
                if jid(s) == step_id { return s; }
            }
        }
    }
    return None;
}

def:priv build_plan(g: Goal) -> list[MilestoneView] {
    views: list[MilestoneView] = [];
    for m in [g-->][?:Milestone] {
        steps: list[StepView] = [
            StepView(id=jid(s), text=s.text, done=s.done) for s in [m-->][?:Step]
        ];
        views.append(MilestoneView(id=jid(m), title=m.title, steps=steps));
    }
    return views;
}

def:priv checkin_view(c: CheckIn) -> CheckInView {
    return CheckInView(
        id=jid(c),
        mood=c.mood,
        note=c.note,
        day=c.day,
        is_today=c.day == date.today().isoformat(),
        coach_reply=c.coach_reply,
        adapted=c.adapted
    );
}

def:priv fallback_reply(language: str) -> str {
    if language == "sw" {
        return "Asante kwa kuripoti. Hatua moja ndogo leo inatosha.";
    }
    return "Thanks for checking in. One small step today is enough.";
}

"""True when unfinished steps exist but nothing was ticked today or yesterday."""
def:priv is_stalled(goal: Goal) -> bool {
    recent: list[str] = [
        date.today().isoformat(), (date.today() - timedelta(days=1)).isoformat()
    ];
    has_unfinished = False;
    for m in [goal-->][?:Milestone] {
        for s in [m-->][?:Step] {
            if s.done and s.done_on in recent { return False; }
            if not s.done { has_unfinished = True; }
        }
    }
    return has_unfinished;
}

"""Shrink the next 1-3 unfinished steps with the AI (one call per milestone).
Returns how many steps changed; failures are added to errors as codes."""
def:priv adapt_next_steps(goal: Goal, mood: str, note: str, errors: list[str]) -> int {
    left = 3;
    changed = 0;
    for m in [goal-->][?:Milestone] {
        if left <= 0 { break; }
        batch: list[Step] = [];
        for s in [m-->][?:Step] {
            if not s.done and len(batch) < left { batch.append(s); }
        }
        if len(batch) == 0 { continue; }
        left -= len(batch);
        new_texts: list[str] = [];
        try {
            new_texts = adapt_steps(
                goal.title, m.title, [s.text for s in batch], mood, note,
                goal.minutes_per_day, goal.language
            );
        } except Exception as e {
            print(f"[add_checkin] adapt_steps failed: {e}");
            errors.append("adapt_failed");
            break;
        }
        if len(new_texts) != len(batch) {
            print(f"[add_checkin] adapt_steps returned {len(new_texts)} steps for {len(batch)}; skipped.");
            continue;
        }
        for i in range(len(batch)) {
            text = new_texts[i].strip();
            if not text { continue; }
            if not batch[i].original_text { batch[i].original_text = batch[i].text; }
            batch[i].text = text;
            changed += 1;
        }
    }
    return changed;
}

# ---- built-in plans (used offline and for the demo; no AI needed) ----
# Each milestone is [title, step, step, ...].

glob TEMPLATES: dict[str, dict[str, list[list[str]]]] = {
    "job": {
        "en": [
            ["Know what you are aiming for",
             "Write down 3 job titles you would like to apply for",
             "Read 3 job adverts and list the skills that keep coming up",
             "Pick one skill from your list to show off first"],
            ["Get your CV and profile ready",
             "Write a short summary of who you are and what you can do",
             "List your projects, studies and volunteer work on your CV",
             "Create or update your LinkedIn profile with a clear photo",
             "Ask a friend or mentor to read your CV and give feedback"],
            ["Build proof of your skills",
             "Choose one small project to build or improve",
             "Spend 15 minutes working on your project",
             "Share your project online with a short description"],
            ["Apply and follow up",
             "Find 2 openings that match your skills",
             "Write a short, personal message for one application",
             "Send one application today",
             "Practise answering 'Tell me about yourself' out loud"]
        ],
        "sw": [
            ["Jua unacholenga",
             "Andika majina 3 ya kazi ungependa kuomba",
             "Soma matangazo 3 ya kazi na uorodheshe ujuzi unaojirudia",
             "Chagua ujuzi mmoja kutoka kwenye orodha yako uanze nao"],
            ["Andaa CV na wasifu wako",
             "Andika maelezo mafupi kuhusu wewe na unachoweza kufanya",
             "Orodhesha miradi, masomo na kazi za kujitolea kwenye CV yako",
             "Fungua au sasisha wasifu wako wa LinkedIn ukiwa na picha nzuri",
             "Muombe rafiki au mshauri asome CV yako akupe maoni"],
            ["Onyesha ujuzi wako",
             "Chagua mradi mmoja mdogo wa kujenga au kuboresha",
             "Tumia dakika 15 kufanya kazi kwenye mradi wako",
             "Shiriki mradi wako mtandaoni pamoja na maelezo mafupi"],
            ["Omba kazi na ufuatilie",
             "Tafuta nafasi 2 za kazi zinazolingana na ujuzi wako",
             "Andika ujumbe mfupi wa kibinafsi kwa ombi moja",
             "Tuma ombi moja la kazi leo",
             "Jizoeze kujibu swali 'Niambie kuhusu wewe' kwa sauti"]
        ]
    },
    "money": {
        "en": [
            ["See where your money goes",
             "Write down everything you spend today",
             "Sort this week's spending into needs and wants",
             "Pick one 'want' you can cut back on this week"],
            ["Set a small saving goal",
             "Choose an amount you can save each week, even a small one",
             "Write down what you are saving for and why",
             "Set aside a separate place for your savings"],
            ["Make saving a habit",
             "Put your weekly amount aside on the same day each week",
             "Check your savings total and write it down",
             "Tell a friend about your goal so they can cheer you on",
             "Celebrate one week of saving in a free way"]
        ],
        "sw": [
            ["Jua pesa zako zinaenda wapi",
             "Andika kila kitu unachotumia leo",
             "Gawa matumizi ya wiki hii kuwa mahitaji na matakwa",
             "Chagua kitu kimoja usichohitaji sana upunguze wiki hii"],
            ["Weka lengo dogo la akiba",
             "Chagua kiasi unachoweza kuweka akiba kila wiki, hata kidogo",
             "Andika unachowekea akiba na sababu yake",
             "Tenga mahali maalum pa kuweka akiba yako"],
            ["Fanya akiba kuwa tabia",
             "Weka kiasi chako cha wiki kando siku ile ile kila wiki",
             "Angalia jumla ya akiba yako na uiandike",
             "Mwambie rafiki kuhusu lengo lako ili akutie moyo",
             "Sherehekea wiki moja ya kuweka akiba bila kutumia pesa"]
        ]
    },
    "fitness": {
        "en": [
            ["Start gently",
             "Walk for 10 minutes at an easy pace",
             "Do 5 minutes of gentle stretching",
             "Choose a regular time of day for your exercise",
             "If you have a health condition, talk to a health worker before you start"],
            ["Build the habit",
             "Walk or jog for 15 minutes",
             "Write down how you felt after moving today",
             "Add one minute to your walk or jog",
             "Invite a friend to exercise with you once this week"],
            ["Keep going",
             "Plan your exercise days for next week",
             "Try a new simple activity, like dancing or skipping",
             "Look back at your progress and celebrate it"]
        ],
        "sw": [
            ["Anza polepole",
             "Tembea kwa dakika 10 kwa mwendo wa kawaida",
             "Fanya mazoezi mepesi ya kunyoosha mwili kwa dakika 5",
             "Chagua muda maalum wa siku wa kufanya mazoezi",
             "Kama una tatizo la kiafya, ongea na mhudumu wa afya kabla ya kuanza"],
            ["Jenga tabia",
             "Tembea au kimbia polepole kwa dakika 15",
             "Andika ulivyojisikia baada ya mazoezi ya leo",
             "Ongeza dakika moja kwenye matembezi au mbio zako",
             "Mwalike rafiki mfanye mazoezi pamoja mara moja wiki hii"],
            ["Endelea mbele",
             "Panga siku zako za mazoezi za wiki ijayo",
             "Jaribu zoezi jipya rahisi, kama kucheza muziki au kuruka kamba",
             "Angalia maendeleo yako na ujipongeze"]
        ]
    },
    "skill": {
        "en": [
            ["Choose your path",
             "Write down the skill you want to learn and why",
             "Find one free course, video series or book for it",
             "Block 15 minutes in your day for learning"],
            ["Learn a little every day",
             "Spend 15 minutes on the first lesson",
             "Write 3 things you learned today in your own words",
             "Practise what you learned with a tiny exercise",
             "Ask one question in an online community or to a friend"],
            ["Use what you know",
             "Pick a small project that uses your new skill",
             "Work on your project for 15 minutes",
             "Show your project to someone and ask for feedback"]
        ],
        "sw": [
            ["Chagua njia yako",
             "Andika ujuzi unaotaka kujifunza na sababu yake",
             "Tafuta kozi moja ya bure, video au kitabu kuhusu ujuzi huo",
             "Tenga dakika 15 kila siku kwa ajili ya kujifunza"],
            ["Jifunze kidogo kila siku",
             "Tumia dakika 15 kwenye somo la kwanza",
             "Andika mambo 3 uliyojifunza leo kwa maneno yako mwenyewe",
             "Fanya zoezi dogo ukitumia ulichojifunza",
             "Uliza swali moja kwenye jumuiya ya mtandaoni au kwa rafiki"],
            ["Tumia unachojua",
             "Chagua mradi mdogo unaotumia ujuzi wako mpya",
             "Fanya kazi kwenye mradi wako kwa dakika 15",
             "Mwonyeshe mtu mradi wako na umwombe maoni"]
        ]
    }
};

# Word starts that pick a template (English + Kiswahili). Checked in this order.
glob TEMPLATE_KEYWORDS: list[list[str]] = [
    ["job", "job", "jobs", "career", "employ", "hire", "hiring", "intern", "interview",
     "cv", "resume", "freelanc", "kazi", "ajira", "kuajiriwa", "mahojiano"],
    ["money", "sav", "money", "budget", "debt", "akiba", "pesa", "fedha", "bajeti"],
    ["fitness", "fit", "exercis", "workout", "gym", "run", "jog", "walk", "5k",
     "marathon", "stretch", "mazoezi", "kimbia", "kukimbia", "tembea", "kutembea", "mbio"],
    ["skill", "learn", "study", "skill", "course", "code", "coding", "program", "languag",
     "practi", "jifunz", "kujifunz", "soma", "kusoma", "ujuzi", "kozi", "lugha"]
];

# ---- demo goal (seed_demo) ----

glob DEMO_TEXT: dict[str, dict[str, str]] = {
    "en": {
        "title": "Get my first online job as a web developer",
        "why": "I want to earn my own income and build a career in tech.",
        "note_good": "Wrote down 3 job titles I like",
        "reply_good": "Lovely work, that's two days in a row! Keep the momentum: read one more job advert tomorrow.",
        "note_okay": "Busy day, but I read some job adverts",
        "reply_okay": "An okay day still counts, and you're on a 3-day streak. Tomorrow, just pick one skill to focus on.",
        "note_hard": "Tired after a long day, felt like giving up",
        "reply_hard": "Hard days happen, and you still showed up for 4 days in a row. Tomorrow, spend just 10 minutes on your CV summary."
    },
    "sw": {
        "title": "Pata kazi yangu ya kwanza mtandaoni kama msanidi wa tovuti",
        "why": "Nataka kupata kipato changu na kujenga taaluma katika teknolojia.",
        "note_good": "Nimeandika majina 3 ya kazi ninazopenda",
        "reply_good": "Kazi nzuri, siku mbili mfululizo! Endelea hivyo: soma tangazo moja zaidi la kazi kesho.",
        "note_okay": "Siku ilikuwa na shughuli nyingi, lakini nilisoma matangazo ya kazi",
        "reply_okay": "Siku ya kawaida bado ina thamani, na uko kwenye mfululizo wa siku 3. Kesho, chagua tu ujuzi mmoja wa kuzingatia.",
        "note_hard": "Nimechoka baada ya siku ndefu, nilihisi kukata tamaa",
        "reply_hard": "Siku ngumu hutokea, na bado umejitokeza siku 4 mfululizo. Kesho, tumia dakika 10 tu kwenye maelezo ya CV yako."
    }
};

"""Which built-in template fits this text ('' if none). Matches word starts."""
def:priv match_template(text: str) -> str {
    words: list[str] = text.lower().replace(",", " ").replace(".", " ").split();
    for row in TEMPLATE_KEYWORDS {
        kind = row[0];
        for kw in row[1:] {
            for w in words {
                if w.startswith(kw) { return kind; }
            }
        }
    }
    return "";
}

"""A built-in template as MilestonePlans, in 'en' or 'sw'."""
def:priv template_plan(kind: str, language: str) -> list[MilestonePlan] {
    by_lang = TEMPLATES.get(kind, TEMPLATES["skill"]);
    rows: list[list[str]] = by_lang.get(language, by_lang["en"]);
    return [MilestonePlan(title=row[0], steps=row[1:]) for row in rows];
}

"""Save milestones and steps under a goal."""
def:priv save_plan(goal: Goal, plans: list[MilestonePlan]) {
    for mp in plans {
        m = goal ++> Milestone(title=mp.title);
        for text in mp.steps {
            m ++> Step(text=text);
        }
    }
}

# ---- public endpoints (def:pub = HTTP API) ----

"""Create a goal (no AI yet)."""
def:pub create_goal(
    title: str, why: str = "", minutes_per_day: int = 15, language: str = "en"
) -> Goal {
    goal = root ++> Goal(
        title=title, why=why, minutes_per_day=minutes_per_day, language=language
    );
    return goal;
}

"""List all goals."""
def:pub get_goals -> list[Goal] {
    return [root-->][?:Goal];
}

"""Ask the AI to plan a goal and save its milestones and steps in the graph."""
def:pub plan_it(goal_id: str) -> PlanResult {
    load_env();
    goal = find_goal(goal_id);
    if goal is None {
        return PlanResult(ok=False, error="goal_not_found");
    }
    # Already planned? Just return the saved plan (no duplicate milestones).
    if len([goal-->][?:Milestone]) > 0 {
        return PlanResult(ok=True, milestones=build_plan(goal));
    }
    plans: list[MilestonePlan] = [];
    try {
        plans = plan_goal(
            goal.title, goal.why, goal.minutes_per_day, goal.language
        );
    } except Exception as e {
        print(f"[plan_it] AI call failed: {e}");
        # Offline fallback: a ready-made plan when the goal matches a template.
        kind = match_template(goal.title + " " + goal.why);
        if kind {
            save_plan(goal, template_plan(kind, goal.language));
            return PlanResult(ok=True, offline=True, milestones=build_plan(goal));
        }
        return PlanResult(ok=False, error="plan_failed");
    }
    if len(plans) == 0 {
        return PlanResult(ok=False, error="plan_empty");
    }
    save_plan(goal, plans);
    return PlanResult(ok=True, milestones=build_plan(goal));
}

"""Add a milestone to a goal by hand."""
def:pub add_milestone(goal_id: str, title: str) -> MilestoneView | None {
    goal = find_goal(goal_id);
    if goal is None { return None; }
    m = goal ++> Milestone(title=title);
    return MilestoneView(id=jid(m), title=m.title, steps=[]);
}

"""Add a step to a milestone by hand."""
def:pub add_step(milestone_id: str, text: str) -> StepView | None {
    m = find_milestone(milestone_id);
    if m is None { return None; }
    s = m ++> Step(text=text);
    return StepView(id=jid(s), text=s.text, done=s.done);
}

"""Tick or untick a step. done_on remembers the day it was done."""
def:pub toggle_step(step_id: str) -> StepView | None {
    s = find_step(step_id);
    if s is None { return None; }
    s.done = not s.done;
    s.done_on = date.today().isoformat() if s.done else "";
    return StepView(id=jid(s), text=s.text, done=s.done);
}

"""Get a goal's milestones and steps."""
def:pub get_plan(goal_id: str) -> list[MilestoneView] {
    goal = find_goal(goal_id);
    if goal is None { return []; }
    return build_plan(goal);
}

"""The next 1-3 unfinished steps, in plan order."""
def:pub get_today(goal_id: str) -> list[TodayStep] {
    goal = find_goal(goal_id);
    if goal is None { return []; }
    result: list[TodayStep] = [];
    for m in [goal-->][?:Milestone] {
        for s in [m-->][?:Step] {
            if not s.done {
                result.append(
                    TodayStep(
                        id=jid(s),
                        text=s.text,
                        done=s.done,
                        milestone_title=m.title,
                        original_text=s.original_text
                    )
                );
                if len(result) >= 3 { return result; }
            }
        }
    }
    return result;
}

"""Consecutive days with at least one ticked step, ending today (or yesterday)."""
def:pub get_streak(goal_id: str) -> int {
    goal = find_goal(goal_id);
    if goal is None { return 0; }
    days: set[str] = set();
    for m in [goal-->][?:Milestone] {
        for s in [m-->][?:Step] {
            if s.done and s.done_on { days.add(s.done_on); }
        }
    }
    day = date.today();
    if day.isoformat() not in days { day = day - timedelta(days=1); }
    count = 0;
    while day.isoformat() in days {
        count += 1;
        day = day - timedelta(days=1);
    }
    return count;
}

"""Save today's check-in (one per goal per day), then ask the AI coach for a reply.
On a hard day, or after 2 days without a ticked step, shrink the next steps (once per day)."""
def:pub add_checkin(goal_id: str, mood: str, note: str = "") -> CheckInResult | None {
    goal = find_goal(goal_id);
    if goal is None or mood not in ["good", "okay", "hard"] { return None; }
    today = date.today().isoformat();
    c: CheckIn | None = None;
    for existing in [goal-->][?:CheckIn] {
        if existing.day == today { c = existing; }
    }
    if c is None {
        c = goal ++> CheckIn(mood=mood, note=note.strip(), day=today);
    } else {
        c.mood = mood;
        c.note = note.strip();
    }

    load_env();
    errors: list[str] = [];
    reply = "";
    try {
        reply = coach_message(
            goal.title, mood, c.note, get_streak(goal_id), goal.language
        ).strip();
    } except Exception as e {
        print(f"[add_checkin] coach_message failed: {e}");
        errors.append("coach_offline");
    }
    if not reply { reply = fallback_reply(goal.language); }
    c.coach_reply = reply;

    adapted_now = False;
    if not c.adapted and (mood == "hard" or is_stalled(goal)) {
        if adapt_next_steps(goal, mood, c.note, errors) > 0 {
            c.adapted = True;
            adapted_now = True;
        }
    }
    return CheckInResult(
        checkin=checkin_view(c),
        coach_reply=reply,
        adapted=adapted_now,
        new_steps=get_today(goal_id) if adapted_now else [],
        error=" ".join(errors)
    );
}

"""Undo adapting: put the original text back on unfinished steps. Returns how many."""
def:pub restore_steps(goal_id: str) -> int {
    goal = find_goal(goal_id);
    if goal is None { return 0; }
    count = 0;
    for m in [goal-->][?:Milestone] {
        for s in [m-->][?:Step] {
            if not s.done and s.original_text {
                s.text = s.original_text;
                s.original_text = "";
                count += 1;
            }
        }
    }
    return count;
}

"""The last 7 check-ins, newest first."""
def:pub get_checkins(goal_id: str) -> list[CheckInView] {
    goal = find_goal(goal_id);
    if goal is None { return []; }
    by_day: dict[str, CheckIn] = {};
    for c in [goal-->][?:CheckIn] {
        by_day[c.day] = c;
    }
    days: list[str] = sorted(by_day.keys(), reverse=True)[:7];
    return [checkin_view(by_day[d]) for d in days];
}

"""Overall and per-milestone progress, streak and check-ins in the last 7 days."""
def:pub get_progress(goal_id: str) -> ProgressView {
    empty = ProgressView(
        percent=0, done=0, total=0, streak=0, checkins_this_week=0, milestones=[]
    );
    goal = find_goal(goal_id);
    if goal is None { return empty; }
    rows: list[MilestoneProgress] = [];
    done = 0;
    total = 0;
    for m in [goal-->][?:Milestone] {
        steps = [m-->][?:Step];
        m_done = len([s for s in steps if s.done]);
        rows.append(
            MilestoneProgress(
                id=jid(m),
                title=m.title,
                done=m_done,
                total=len(steps),
                percent=round(m_done * 100 / len(steps)) if len(steps) > 0 else 0
            )
        );
        done += m_done;
        total += len(steps);
    }
    week_start = (date.today() - timedelta(days=6)).isoformat();
    week = len([c for c in [goal-->][?:CheckIn] if c.day >= week_start]);
    return ProgressView(
        percent=round(done * 100 / total) if total > 0 else 0,
        done=done,
        total=total,
        streak=get_streak(goal_id),
        checkins_this_week=week,
        milestones=rows
    );
}

"""Delete a goal with all its milestones, steps and check-ins. Returns nodes removed."""
def:pub delete_goal(goal_id: str) -> int {
    goal = find_goal(goal_id);
    if goal is None { return 0; }
    removed = 0;
    for m in [goal-->][?:Milestone] {
        for s in [m-->][?:Step] {
            del s;
            removed += 1;
        }
        del m;
        removed += 1;
    }
    for c in [goal-->][?:CheckIn] {
        del c;
        removed += 1;
    }
    del goal;
    return removed + 1;
}

"""Delete a single step."""
def:pub delete_step(step_id: str) -> bool {
    s = find_step(step_id);
    if s is None { return False; }
    del s;
    return True;
}


"""Create the demo goal (no AI): a full plan, 4 days of ticks and 3 past check-ins.
Only one demo goal ever exists; calling again returns the existing one's id."""
def:pub seed_demo(language: str = "en") -> str {
    for g in [root-->][?:Goal] {
        if g.is_demo { return jid(g); }
    }
    lang = "sw" if language == "sw" else "en";
    text = DEMO_TEXT[lang];
    goal = root ++> Goal(
        title=text["title"], why=text["why"], minutes_per_day=15,
        language=lang, is_demo=True
    );
    save_plan(goal, template_plan("job", lang));

    # Tick the first 4 steps, one per day from 4 days ago to yesterday -> streak 4.
    today = date.today();
    days_ago = 4;
    for m in [goal-->][?:Milestone] {
        for s in [m-->][?:Step] {
            if days_ago > 0 {
                s.done = True;
                s.done_on = (today - timedelta(days=days_ago)).isoformat();
                days_ago -= 1;
            }
        }
    }

    # Three past check-ins with short coach replies.
    for (mood, ago) in [("good", 3), ("okay", 2), ("hard", 1)] {
        goal ++> CheckIn(
            mood=mood,
            note=text["note_" + mood],
            day=(today - timedelta(days=ago)).isoformat(),
            coach_reply=text["reply_" + mood]
        );
    }
    return jid(goal);
}


# ================= FRONTEND (runs in the browser) =================

# Every piece of interface text, in English and Kiswahili. Look up with t(key).
glob T: dict[str, dict[str, str]] = {
    "en": {
        "tagline": "one step at a time",
        "ui_language": "Interface language",
        "new_goal": "New goal",
        "ph_title": "Big goal, e.g. Run a 5K by December",
        "ph_why": "Why does it matter to you?",
        "min_day": "min / day",
        "goal_language": "Plan language",
        "lang_en": "English",
        "lang_sw": "Kiswahili",
        "plan_it": "Plan it",
        "planning": "Planning…",
        "my_goals": "My goals",
        "no_goals": "No goals yet. Write your first big goal above 🌱",
        "goal_meta": "{m} min/day",
        "pick_goal": "Create a goal and press Plan it, or pick one from My goals.",
        "planning_msg": "Hatua is breaking \"{title}\" into small steps…",
        "streak_n": "🔥 {n}-day streak",
        "streak_0": "Start your streak today",
        "tab_today": "Today",
        "tab_plan": "Plan",
        "tab_checkin": "Check-in",
        "tab_progress": "Progress",
        "next_steps": "Your next small steps:",
        "adapted_tag": "Adapted for today",
        "original": "Original: ",
        "all_done": "All steps done — amazing!",
        "no_steps": "No steps yet. Open the Plan tab to plan this goal.",
        "go_plan": "Go to Plan",
        "try_again": "Try again",
        "no_milestones": "No milestones yet. Let Hatua plan it, or add your own below.",
        "plan_ai": "Plan it with AI",
        "ph_step": "Add a step",
        "ph_milestone": "Add your own milestone",
        "add": "Add",
        "adding": "…",
        "delete_step": "Delete step",
        "how_today": "How did today go?",
        "mood_good": "😀 Good",
        "mood_okay": "😐 Okay",
        "mood_hard": "😞 Hard",
        "ph_note": "One line about your day (optional)",
        "save": "Save",
        "saving": "Saving…",
        "thinking": "Thinking…",
        "adapted_msg": "I made your next steps smaller for today 💛",
        "undo": "Undo",
        "undoing": "Undoing…",
        "restored": "Restored {n} step(s) to the original plan.",
        "nothing_restore": "Nothing to restore.",
        "last7": "Last 7 check-ins",
        "no_checkins": "No check-ins yet. How are you feeling today?",
        "today": "Today",
        "overall": "of all steps done",
        "steps_of": "{d} of {t} steps",
        "streak_label": "Day streak",
        "week_checkins": "Check-ins this week",
        "no_progress": "No steps yet. Plan your goal to see your progress here.",
        "delete_goal": "Delete goal",
        "confirm_delete": "Delete \"{title}\" with all its steps and check-ins? This can't be undone.",
        "yes_delete": "Yes, delete",
        "deleting": "Deleting…",
        "cancel": "Cancel",
        "footer": "Need support? Call Kenya Red Cross on 1199.",
        "err_server": "Could not reach the server. Is jac run still running?",
        "err_save_goal": "Could not save the goal. Please try again.",
        "err_save": "Could not save. Please try again.",
        "err_plan_failed": "The AI coach could not make a plan right now. Check your internet connection and GEMINI_API_KEY, then try again.",
        "err_plan_empty": "The AI returned an empty plan. Try rewording your goal.",
        "err_goal_not_found": "Goal not found.",
        "err_coach_offline": "The AI coach is offline right now.",
        "err_adapt_failed": "Could not make your steps smaller right now.",
        "err_load_goals": "Could not load your goals. Check that jac run is running, then refresh the page.",
        "err_open_goal": "Could not open this goal. Please try again.",
        "err_demo": "Could not load the demo. Please try again.",
        "err_action": "That didn't work. Check your connection and try again.",
        "load_demo": "Load demo",
        "loading_demo": "Loading demo…",
        "offline_plan": "Offline plan: a ready-made starter plan. You can edit it, or try the AI again later.",
        "dismiss": "Dismiss"
    },
    "sw": {
        "tagline": "hatua moja baada ya nyingine",
        "ui_language": "Lugha ya programu",
        "new_goal": "Lengo jipya",
        "ph_title": "Lengo kubwa, mf. Kukimbia km 5 kufikia Desemba",
        "ph_why": "Kwa nini lengo hili ni muhimu kwako?",
        "min_day": "dak / siku",
        "goal_language": "Lugha ya mpango",
        "lang_en": "Kiingereza",
        "lang_sw": "Kiswahili",
        "plan_it": "Panga",
        "planning": "Inapanga…",
        "my_goals": "Malengo yangu",
        "no_goals": "Bado huna lengo. Andika lengo lako la kwanza hapo juu 🌱",
        "goal_meta": "dak {m}/siku",
        "pick_goal": "Andika lengo kisha bonyeza Panga, au chagua moja kwenye Malengo yangu.",
        "planning_msg": "Hatua inagawa \"{title}\" katika hatua ndogo…",
        "streak_n": "🔥 Siku {n} mfululizo",
        "streak_0": "Anza mfululizo wako leo",
        "tab_today": "Leo",
        "tab_plan": "Mpango",
        "tab_checkin": "Ripoti",
        "tab_progress": "Maendeleo",
        "next_steps": "Hatua zako ndogo zinazofuata:",
        "adapted_tag": "Imerahisishwa kwa leo",
        "original": "Awali: ",
        "all_done": "Hatua zote zimekamilika — hongera sana!",
        "no_steps": "Bado hakuna hatua. Fungua Mpango ili kupanga lengo hili.",
        "go_plan": "Nenda kwenye Mpango",
        "try_again": "Jaribu tena",
        "no_milestones": "Bado hakuna hatua kuu. Acha Hatua ipange, au ongeza zako hapa chini.",
        "plan_ai": "Panga kwa AI",
        "ph_step": "Ongeza hatua",
        "ph_milestone": "Ongeza hatua kuu yako mwenyewe",
        "add": "Ongeza",
        "adding": "…",
        "delete_step": "Futa hatua",
        "how_today": "Leo imekuwaje?",
        "mood_good": "😀 Vizuri",
        "mood_okay": "😐 Kawaida",
        "mood_hard": "😞 Ngumu",
        "ph_note": "Sentensi moja kuhusu siku yako (si lazima)",
        "save": "Hifadhi",
        "saving": "Inahifadhi…",
        "thinking": "Inafikiri…",
        "adapted_msg": "Nimezifanya hatua zako zinazofuata kuwa ndogo kwa leo 💛",
        "undo": "Tendua",
        "undoing": "Inatendua…",
        "restored": "Hatua {n} zimerudishwa kama zilivyokuwa.",
        "nothing_restore": "Hakuna cha kurudisha.",
        "last7": "Ripoti 7 za mwisho",
        "no_checkins": "Bado hakuna ripoti. Unajisikiaje leo?",
        "today": "Leo",
        "overall": "ya hatua zote imekamilika",
        "steps_of": "Hatua {d} kati ya {t}",
        "streak_label": "Siku mfululizo",
        "week_checkins": "Ripoti wiki hii",
        "no_progress": "Bado hakuna hatua. Panga lengo lako uone maendeleo yako hapa.",
        "delete_goal": "Futa lengo",
        "confirm_delete": "Ufute \"{title}\" pamoja na hatua na ripoti zake zote? Huwezi kurudisha.",
        "yes_delete": "Ndiyo, futa",
        "deleting": "Inafuta…",
        "cancel": "Ghairi",
        "footer": "Unahitaji msaada? Piga simu Kenya Red Cross kupitia 1199.",
        "err_server": "Imeshindwa kufikia seva. Je, jac run bado inaendelea?",
        "err_save_goal": "Imeshindwa kuhifadhi lengo. Tafadhali jaribu tena.",
        "err_save": "Imeshindwa kuhifadhi. Tafadhali jaribu tena.",
        "err_plan_failed": "Kocha wa AI hakuweza kutengeneza mpango sasa hivi. Angalia mtandao wako na GEMINI_API_KEY, kisha ujaribu tena.",
        "err_plan_empty": "AI imerudisha mpango mtupu. Jaribu kuandika lengo lako kwa njia nyingine.",
        "err_goal_not_found": "Lengo halikupatikana.",
        "err_coach_offline": "Kocha wa AI hapatikani kwa sasa.",
        "err_adapt_failed": "Imeshindwa kurahisisha hatua zako kwa sasa.",
        "err_load_goals": "Imeshindwa kupakia malengo yako. Hakikisha jac run inaendelea, kisha upakie ukurasa upya.",
        "err_open_goal": "Imeshindwa kufungua lengo hili. Tafadhali jaribu tena.",
        "err_demo": "Imeshindwa kupakia mfano. Tafadhali jaribu tena.",
        "err_action": "Haikufanikiwa. Angalia mtandao wako kisha ujaribu tena.",
        "load_demo": "Pakia mfano",
        "loading_demo": "Inapakia mfano…",
        "offline_plan": "Mpango wa nje ya mtandao: mpango wa kuanzia ulioandaliwa tayari. Unaweza kuubadilisha, au ujaribu AI tena baadaye.",
        "dismiss": "Funga"
    }
};

glob PAGE_TITLE: str = "Hatua · one step at a time";
glob FAVICON: str = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Ctext y='.9em' font-size='90'%3E%F0%9F%8C%B1%3C/text%3E%3C/svg%3E";
glob LANG_KEY: str = "hatua_lang";

def:pub app -> JsxElement {
    has ui_lang: str = "en",
        goals: list[Goal] = [],
        plan: list[MilestoneView] = [],
        title: str = "",
        why: str = "",
        minutes: int = 15,
        language: str = "en",
        selected_goal: str = "",
        selected_title: str = "",
        milestone_title: str = "",
        step_inputs: dict[str, str] = {},
        planning: bool = False,
        plan_error: str = "",
        tab: str = "today",
        today: list[TodayStep] = [],
        streak: int = 0,
        progress: ProgressView | None = None,
        checkins: list[CheckInView] = [],
        mood: str = "",
        note: str = "",
        saving: bool = False,
        checkin_msg: str = "",
        coach_reply: str = "",
        coach_adapted: bool = False,
        coach_errors: list[str] = [],
        undo_msg: str = "",
        busy: str = "",
        confirm_delete: bool = False,
        show_goals: bool = False,
        app_error: str = "",
        plan_offline: bool = False,
        demo_param: bool = False;

    # ---- text helpers ----
    def t(key: str) -> str {
        words = T.get(ui_lang, T["en"]);
        return words.get(key, T["en"].get(key, key));
    }

    # Server sends short error codes; show them in the interface language.
    def err_text(code: str) -> str {
        return t("err_" + code) if ("err_" + code) in T["en"] else code;
    }

    def set_ui_lang(lang: str) {
        ui_lang = lang;
        language = lang;
        try {
            localStorage.setItem(LANG_KEY, lang);
        } except Exception {
            console.warn("[hatua] could not save language");
        }
    }

    async can with entry {
        document.title = PAGE_TITLE;
        link: any = document.querySelector("link[rel='icon']");
        if not link {
            link = document.createElement("link");
            link.rel = "icon";
            head: any = document.head;
            head.appendChild(link);
        }
        link.href = FAVICON;
        saved_lang = "en";
        try {
            if localStorage.getItem(LANG_KEY) == "sw" { saved_lang = "sw"; }
        } except Exception {
            console.warn("[hatua] could not read language");
        }
        ui_lang = saved_lang;
        language = saved_lang;
        try {
            params: any = new(URLSearchParams, window.location.search);  # jac:ignore[E1053,W1051]
            demo_param = params.get("demo") == "1";
        } except Exception {
            demo_param = False;
        }
        try {
            goals = await get_goals();
        } except Exception {
            app_error = "load_goals";
        }
    }

    # Reload everything that changes when a step is ticked, added or deleted.
    async def refresh(goal_id: str) {
        plan = await get_plan(goal_id);
        today = await get_today(goal_id);
        streak = await get_streak(goal_id);
        progress = await get_progress(goal_id);
    }

    async def load_checkins(goal_id: str) {
        loaded: list[CheckInView] = await get_checkins(goal_id);
        today_mood: str = "";
        today_note: str = "";
        for c in loaded {
            if c.is_today {
                today_mood = c.mood;
                today_note = c.note;
            }
        }
        checkins = loaded;
        mood = today_mood;
        note = today_note;
    }

    def reset_goal_view {
        plan_error = "";
        plan_offline = False;
        app_error = "";
        checkin_msg = "";
        coach_reply = "";
        coach_adapted = False;
        coach_errors = [];
        undo_msg = "";
        confirm_delete = False;
        show_goals = False;
    }

    async def run_plan(goal_id: str) {
        planning = True;
        plan_error = "";
        plan_offline = False;
        tab = "plan";
        try {
            result = await plan_it(goal_id);
            if result.ok {
                plan = result.milestones;
                plan_offline = result.offline;
                await refresh(goal_id);
            } else {
                plan_error = result.error;
            }
        } except Exception {
            plan_error = "server";
        }
        planning = False;
    }

    async def plan_new_goal {
        if planning or busy or not title.strip() { return; }
        planning = True;
        app_error = "";
        mins = minutes if minutes > 0 else 15;
        try {
            g = await create_goal(title.strip(), why.strip(), mins, language);
            goals = goals + [g];
            selected_goal = jid(g);
            selected_title = g.title;
            reset_goal_view();
            plan = [];
            today = [];
            streak = 0;
            progress = None;
            checkins = [];
            mood = "";
            note = "";
            title = "";
            why = "";
            await run_plan(jid(g));
        } except Exception {
            planning = False;
            app_error = "save_goal";
        }
    }

    async def open_goal(g: Goal) {
        if planning { return; }
        selected_goal = jid(g);
        selected_title = g.title;
        reset_goal_view();
        tab = "today";
        try {
            await refresh(jid(g));
            await load_checkins(jid(g));
        } except Exception {
            app_error = "open_goal";
        }
    }

    async def load_demo {
        if busy or planning { return; }
        busy = "demo";
        app_error = "";
        try {
            demo_id = await seed_demo(ui_lang);
            goals = await get_goals();
            for g in goals {
                if jid(g) == demo_id { await open_goal(g); }
            }
        } except Exception {
            app_error = "demo";
        }
        busy = "";
    }

    async def add_new_milestone {
        if busy or not milestone_title.strip() or not selected_goal { return; }
        busy = "milestone";
        try {
            m = await add_milestone(selected_goal, milestone_title.strip());
            if m is not None { await refresh(selected_goal); }
            milestone_title = "";
        } except Exception {
            app_error = "action";
        }
        busy = "";
    }

    async def add_new_step(milestone_id: str) {
        text = step_inputs.get(milestone_id, "").strip();
        if busy or not text { return; }
        busy = "step:" + milestone_id;
        try {
            s = await add_step(milestone_id, text);
            if s is not None { await refresh(selected_goal); }
            step_inputs = {**step_inputs, str(milestone_id): ""};
        } except Exception {
            app_error = "action";
        }
        busy = "";
    }

    async def tick(step_id: str) {
        if busy { return; }
        busy = "tick:" + step_id;
        try {
            updated = await toggle_step(step_id);
            if updated is not None { await refresh(selected_goal); }
        } except Exception {
            app_error = "action";
        }
        busy = "";
    }

    async def remove_step(step_id: str) {
        if busy { return; }
        busy = "del:" + step_id;
        try {
            await delete_step(step_id);
            await refresh(selected_goal);
        } except Exception {
            app_error = "action";
        }
        busy = "";
    }

    async def remove_goal {
        if busy or not selected_goal { return; }
        busy = "goal";
        try {
            await delete_goal(selected_goal);
            goals = [g for g in goals if jid(g) != selected_goal];
            selected_goal = "";
            selected_title = "";
            plan = [];
            today = [];
            progress = None;
            checkins = [];
            reset_goal_view();
        } except Exception {
            app_error = "action";
        }
        busy = "";
    }

    async def save_checkin {
        if not mood or saving or not selected_goal { return; }
        saving = True;
        checkin_msg = "";
        coach_reply = "";
        coach_adapted = False;
        coach_errors = [];
        undo_msg = "";
        try {
            result = await add_checkin(selected_goal, mood, note.strip());
            if result is not None {
                coach_reply = result.coach_reply;
                coach_adapted = result.adapted;
                coach_errors = [c for c in result.error.split(" ") if c];
                await load_checkins(selected_goal);
                await refresh(selected_goal);
            } else {
                checkin_msg = "save";
            }
        } except Exception {
            checkin_msg = "server";
        }
        saving = False;
    }

    async def undo_adapt {
        if busy or not selected_goal { return; }
        busy = "undo";
        try {
            restored = await restore_steps(selected_goal);
            await refresh(selected_goal);
            coach_adapted = False;
            undo_msg = (
                t("restored").replace("{n}", str(restored))
                if restored > 0 else t("nothing_restore")
            );
        } except Exception {
            undo_msg = t("err_server");
        }
        busy = "";
    }

    total_steps = sum([len(m.steps) for m in plan]);

    # ---- Plan tab ----
    plan_view =
        <div>
            {plan_offline and <p className="offline-note">📴 {t("offline_plan")}</p>}
            {plan_error and
                <div className="error">
                    <p>{err_text(plan_error)}</p>
                    <button className="btn small" onClick={lambda { run_plan(selected_goal); }}>
                        {t("try_again")}
                    </button>
                </div>}
            {(len(plan) == 0 and not plan_error) and
                <div className="empty-state">
                    <p>{t("no_milestones")}</p>
                    <button className="btn" onClick={lambda { run_plan(selected_goal); }}>
                        {t("plan_ai")}
                    </button>
                </div>}
            {[
                <div key={m.id} className="milestone">
                    <h3>{m.title}</h3>
                    {[
                        <div key={s.id} className={"step " + ("done" if s.done else "")}>
                            <label className="step-main">
                                <input
                                    type="checkbox"
                                    checked={s.done}
                                    disabled={busy != ""}
                                    onChange={lambda { tick(s.id); }}
                                />
                                <span>{s.text}</span>
                            </label>
                            <button
                                className="icon-btn"
                                title={t("delete_step")}
                                aria-label={t("delete_step")}
                                disabled={busy != ""}
                                onClick={lambda { remove_step(s.id); }}
                            >
                                {"…" if busy == "del:" + s.id else "✕"}
                            </button>
                        </div> for s in m.steps
                    ]}
                    <div className="row">
                        <input
                            className="input"
                            value={step_inputs.get(m.id, "")}
                            onChange={lambda (e: ChangeEvent) {
                                step_inputs = {**step_inputs, str(m.id): e.target.value};
                            }}
                            placeholder={t("ph_step")}
                        />
                        <button
                            className="btn small"
                            disabled={busy != "" or not step_inputs.get(m.id, "").strip()}
                            onClick={lambda { add_new_step(m.id); }}
                        >
                            {t("adding") if busy == "step:" + m.id else t("add")}
                        </button>
                    </div>
                </div> for m in plan
            ]}
            <div className="row">
                <input
                    className="input"
                    value={milestone_title}
                    onChange={lambda (e: ChangeEvent) { milestone_title = e.target.value; }}
                    placeholder={t("ph_milestone")}
                />
                <button
                    className="btn"
                    disabled={busy != "" or not milestone_title.strip()}
                    onClick={add_new_milestone}
                >
                    {t("adding") if busy == "milestone" else t("add")}
                </button>
            </div>
        </div>;

    # ---- Today tab ----
    if len(today) > 0 {
        today_view =
            <div>
                <p className="muted">{t("next_steps")}</p>
                {[
                    <label
                        key={ts.id}
                        className={"today-step " + ("busy" if busy == "tick:" + ts.id else "")}
                    >
                        <input
                            type="checkbox"
                            checked={ts.done}
                            disabled={busy != ""}
                            onChange={lambda { tick(ts.id); }}
                        />
                        <span className="today-text">
                            {ts.text}
                            <small className="muted">
                                {ts.milestone_title}
                                {ts.original_text and
                                    <span className="adapted-tag" title={t("original") + ts.original_text}>
                                        {t("adapted_tag")}
                                    </span>}
                            </small>
                        </span>
                    </label> for ts in today
                ]}
            </div>;
    } elif total_steps > 0 {
        today_view = <div className="empty-state all-done">{t("all_done")}</div>;
    } else {
        today_view =
            <div className="empty-state">
                <p>{t("no_steps")}</p>
                <button className="btn" onClick={lambda { tab = "plan"; }}>{t("go_plan")}</button>
            </div>;
    }

    # ---- Check-in tab ----
    checkin_view =
        <div>
            <p className="muted">{t("how_today")}</p>
            <div className="moods">
                {[
                    <button
                        key={k}
                        className={"mood " + ("active" if mood == k else "")}
                        onClick={lambda { mood = k; checkin_msg = ""; }}
                    >
                        {t("mood_" + k)}
                    </button> for k in ["good", "okay", "hard"]
                ]}
            </div>
            <div className="row">
                <input
                    className="input"
                    value={note}
                    maxLength={200}
                    onChange={lambda (e: ChangeEvent) { note = e.target.value; checkin_msg = ""; }}
                    placeholder={t("ph_note")}
                />
                <button className="btn" disabled={not mood or saving} onClick={save_checkin}>
                    {t("saving") if saving else t("save")}
                </button>
            </div>
            {checkin_msg and <p className="error">{err_text(checkin_msg)}</p>}
            {(saving or coach_reply) and
                <div className="coach-card">
                    <span className="coach-icon">🌱</span>
                    <div className="coach-body">
                        {saving and <p className="muted">{t("thinking")}</p>}
                        {(not saving and coach_reply) and <p>{coach_reply}</p>}
                        {(not saving and coach_adapted) and
                            <div className="coach-adapted">
                                <span>{t("adapted_msg")}</span>
                                <button className="btn-undo" disabled={busy != ""} onClick={undo_adapt}>
                                    {t("undoing") if busy == "undo" else t("undo")}
                                </button>
                            </div>}
                        {undo_msg and <p className="muted">{undo_msg}</p>}
                        {[
                            <p key={code} className="muted coach-error">{err_text(code)}</p>
                            for code in coach_errors
                        ]}
                    </div>
                </div>}
            <h3>{t("last7")}</h3>
            {len(checkins) == 0 and <p className="empty-state small">{t("no_checkins")}</p>}
            {[
                <div key={c.id} className="checkin">
                    <span className="checkin-day">{t("today") if c.is_today else c.day}</span>
                    <span>{t("mood_" + c.mood)}</span>
                    {c.note and <span className="muted checkin-note">{c.note}</span>}
                    {c.coach_reply and <span className="muted checkin-reply">🌱 {c.coach_reply}</span>}
                </div> for c in checkins
            ]}
        </div>;

    # ---- Progress tab ----
    if progress is None or progress.total == 0 {
        progress_view = <div className="empty-state"><p>{t("no_progress")}</p></div>;
    } else {
        progress_view =
            <div>
                <div className="progress-hero">
                    <span className="progress-big">{progress.percent}%</span>
                    <span className="muted">{t("overall")}</span>
                    <div className="bar big">
                        <div className="bar-fill" style={{"width": f"{progress.percent}%"}}></div>
                    </div>
                </div>
                <div className="stats">
                    <div className="stat">
                        <span className="stat-num">{progress.streak}</span>
                        <span className="muted">{t("streak_label")}</span>
                    </div>
                    <div className="stat">
                        <span className="stat-num">{progress.checkins_this_week}</span>
                        <span className="muted">{t("week_checkins")}</span>
                    </div>
                </div>
                {[
                    <div key={mp.id} className="milestone-progress">
                        <div className="mp-head">
                            <span className="mp-title">{mp.title}</span>
                            <span className="muted nowrap">
                                {t("steps_of").replace("{d}", str(mp.done)).replace("{t}", str(mp.total))}
                            </span>
                        </div>
                        <div className="bar">
                            <div
                                className="bar-fill"
                                style={{"width": f"{mp.percent}%"}}
                            ></div>
                        </div>
                    </div> for mp in progress.milestones
                ]}
            </div>;
    }

    # ---- Right panel: the selected goal ----
    if not selected_goal {
        goal_panel =
            <section className="panel empty">
                <span className="empty-icon">👣</span>
                <p>{t("pick_goal")}</p>
            </section>;
    } elif planning {
        goal_panel =
            <section className="panel empty">
                <div className="spinner"></div>
                <p>{t("planning_msg").replace("{title}", selected_title)}</p>
            </section>;
    } else {
        if tab == "plan" {
            tab_body = plan_view;
        } elif tab == "checkin" {
            tab_body = checkin_view;
        } elif tab == "progress" {
            tab_body = progress_view;
        } else {
            tab_body = today_view;
        }
        goal_panel =
            <section className="panel">
                <div className="goal-head">
                    <h2>{selected_title}</h2>
                    <span className={"streak " + ("on" if streak > 0 else "")}>
                        {t("streak_n").replace("{n}", str(streak)) if streak > 0 else t("streak_0")}
                    </span>
                </div>
                {confirm_delete and
                    <div className="confirm">
                        <p>{t("confirm_delete").replace("{title}", selected_title)}</p>
                        <div className="row">
                            <button className="btn danger" disabled={busy != ""} onClick={remove_goal}>
                                {t("deleting") if busy == "goal" else t("yes_delete")}
                            </button>
                            <button className="btn ghost" onClick={lambda { confirm_delete = False; }}>
                                {t("cancel")}
                            </button>
                        </div>
                    </div>}
                <div className="tabs" role="tablist">
                    {[
                        <button
                            key={k}
                            role="tab"
                            className={"tab " + ("active" if tab == k else "")}
                            onClick={lambda { tab = k; checkin_msg = ""; }}
                        >
                            {t("tab_" + k)}
                        </button> for k in ["today", "plan", "checkin", "progress"]
                    ]}
                </div>
                {tab_body}
                {not confirm_delete and
                    <div className="goal-actions">
                        <button className="link-btn danger-text" onClick={lambda { confirm_delete = True; }}>
                            {t("delete_goal")}
                        </button>
                    </div>}
            </section>;
    }

    goals_open = show_goals or not selected_goal;
    show_demo_link = len(goals) == 0 or demo_param;

    return
        <div className="container">
            <header className="header">
                <h1 className="brand">
                    <span className="logo" aria-hidden="true">🌱</span>
                    Hatua
                    <span className="tagline">· {t("tagline")}</span>
                </h1>
                <div className="lang-switch" role="group" aria-label={t("ui_language")}>
                    {[
                        <button
                            key={code}
                            className={"lang-btn " + ("active" if ui_lang == code else "")}
                            aria-pressed={ui_lang == code}
                            onClick={lambda { set_ui_lang(code); }}
                        >
                            {"EN" if code == "en" else "SW"}
                        </button> for code in ["en", "sw"]
                    ]}
                </div>
            </header>
            <button
                className="goals-toggle"
                aria-expanded={goals_open}
                onClick={lambda { show_goals = not show_goals; }}
            >
                {t("my_goals")} ({len(goals)}) {"▴" if goals_open else "▾"}
            </button>
            {app_error and
                <div className="error app-error" role="alert">
                    <p>{err_text(app_error)}</p>
                    <button className="icon-btn" aria-label={t("dismiss")} onClick={lambda { app_error = ""; }}>
                        ✕
                    </button>
                </div>}
            <div className="grid">
                <section className={"panel side " + ("open" if goals_open else "")}>
                    <h2>{t("new_goal")}</h2>
                    <input
                        className="input"
                        value={title}
                        onChange={lambda (e: ChangeEvent) { title = e.target.value; }}
                        placeholder={t("ph_title")}
                    />
                    <input
                        className="input"
                        value={why}
                        onChange={lambda (e: ChangeEvent) { why = e.target.value; }}
                        placeholder={t("ph_why")}
                    />
                    <div className="row">
                        <input
                            className="input minutes"
                            type="number"
                            min="5"
                            value={minutes}
                            onChange={lambda (e: ChangeEvent) { minutes = int(e.target.value or "0"); }}
                        />
                        <span className="muted nowrap">{t("min_day")}</span>
                        <select
                            className="input"
                            aria-label={t("goal_language")}
                            value={language}
                            onChange={lambda (e: ChangeEvent) { language = e.target.value; }}
                        >
                            <option value="en">{t("lang_en")}</option>
                            <option value="sw">{t("lang_sw")}</option>
                        </select>
                    </div>
                    <button
                        className="btn block"
                        disabled={planning or not title.strip()}
                        onClick={plan_new_goal}
                    >
                        {t("planning") if planning else t("plan_it")}
                    </button>
                    <h2>{t("my_goals")}</h2>
                    {len(goals) == 0 and <p className="empty-state small">{t("no_goals")}</p>}
                    {[
                        <button
                            key={jid(g)}
                            className={"item " + ("active" if jid(g) == selected_goal else "")}
                            onClick={lambda { open_goal(g); }}
                        >
                            <strong>{g.title}</strong>
                            <span className="muted">
                                {t("goal_meta").replace("{m}", str(g.minutes_per_day))} · {g.language}
                            </span>
                        </button> for g in goals
                    ]}
                </section>
                {goal_panel}
            </div>
            <footer className="footer">
                <p>{t("footer")}</p>
                {show_demo_link and
                    <button className="link-btn demo-link" disabled={busy != "" or planning} onClick={load_demo}>
                        {t("loading_demo") if busy == "demo" else t("load_demo")}
                    </button>}
            </footer>
        </div>;
}
