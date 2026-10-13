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
        language: str = "en";
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

obj PlanResult {
    has ok: bool,
        error: str = "",
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
Returns how many steps changed; failures are added to errors."""
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
            errors.append("Could not make your steps smaller right now.");
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
        return PlanResult(ok=False, error="Goal not found.");
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
        return PlanResult(
            ok=False,
            error="The AI coach could not make a plan right now. Check your internet connection and GEMINI_API_KEY, then try again."
        );
    }
    if len(plans) == 0 {
        return PlanResult(
            ok=False, error="The AI returned an empty plan. Try rewording your goal."
        );
    }
    for mp in plans {
        m = goal ++> Milestone(title=mp.title);
        for text in mp.steps {
            m ++> Step(text=text);
        }
    }
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
        errors.append("The AI coach is offline right now.");
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


# ================= FRONTEND (runs in the browser) =================

def:pub app -> JsxElement {
    has goals: list[Goal] = [],
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
        checkins: list[CheckInView] = [],
        mood: str = "",
        note: str = "",
        saving: bool = False,
        checkin_msg: str = "",
        coach_reply: str = "",
        coach_adapted: bool = False,
        coach_error: str = "",
        undo_msg: str = "";

    async can with entry {
        goals = await get_goals();
    }

    # Reload everything that changes when a step is ticked.
    async def refresh(goal_id: str) {
        plan = await get_plan(goal_id);
        today = await get_today(goal_id);
        streak = await get_streak(goal_id);
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

    async def run_plan(goal_id: str) {
        planning = True;
        plan_error = "";
        tab = "plan";
        try {
            result = await plan_it(goal_id);
            if result.ok {
                plan = result.milestones;
                today = await get_today(goal_id);
                streak = await get_streak(goal_id);
            } else {
                plan_error = result.error;
            }
        } except Exception as e {
            plan_error = "Could not reach the server. Is jac run still running?";
        }
        planning = False;
    }

    async def plan_new_goal {
        if planning or not title.strip() { return; }
        mins = minutes if minutes > 0 else 15;
        try {
            g = await create_goal(title.strip(), why.strip(), mins, language);
            goals = goals + [g];
            selected_goal = jid(g);
            selected_title = g.title;
            plan = [];
            today = [];
            streak = 0;
            checkins = [];
            mood = "";
            note = "";
            checkin_msg = "";
            coach_reply = "";
            coach_adapted = False;
            coach_error = "";
            undo_msg = "";
            title = "";
            why = "";
            await run_plan(jid(g));
        } except Exception as e {
            plan_error = "Could not save the goal. Is jac run still running?";
        }
    }

    async def open_goal(g: Goal) {
        selected_goal = jid(g);
        selected_title = g.title;
        plan_error = "";
        checkin_msg = "";
        coach_reply = "";
        coach_adapted = False;
        coach_error = "";
        undo_msg = "";
        tab = "today";
        await refresh(jid(g));
        await load_checkins(jid(g));
    }

    async def add_new_milestone {
        if milestone_title.strip() and selected_goal {
            m = await add_milestone(selected_goal, milestone_title.strip());
            if m is not None { await refresh(selected_goal); }
            milestone_title = "";
        }
    }

    async def add_new_step(milestone_id: str) {
        text = step_inputs.get(milestone_id, "").strip();
        if text {
            s = await add_step(milestone_id, text);
            if s is not None { await refresh(selected_goal); }
            step_inputs = {**step_inputs, str(milestone_id): ""};
        }
    }

    async def tick(step_id: str) {
        updated = await toggle_step(step_id);
        if updated is not None { await refresh(selected_goal); }
    }

    async def save_checkin {
        if not mood or saving or not selected_goal { return; }
        saving = True;
        checkin_msg = "";
        coach_reply = "";
        coach_adapted = False;
        coach_error = "";
        undo_msg = "";
        try {
            result = await add_checkin(selected_goal, mood, note.strip());
            if result is not None {
                coach_reply = result.coach_reply;
                coach_adapted = result.adapted;
                coach_error = result.error;
                await load_checkins(selected_goal);
                if result.adapted { await refresh(selected_goal); }
            } else {
                checkin_msg = "Could not save. Please try again.";
            }
        } except Exception as e {
            checkin_msg = "Could not reach the server. Is jac run still running?";
        }
        saving = False;
    }

    async def undo_adapt {
        if not selected_goal { return; }
        try {
            restored = await restore_steps(selected_goal);
            await refresh(selected_goal);
            coach_adapted = False;
            undo_msg = (
                f"Restored {restored} step(s) to the original plan."
                if restored > 0 else "Nothing to restore."
            );
        } except Exception as e {
            undo_msg = "Could not reach the server. Is jac run still running?";
        }
    }

    mood_labels: dict[str, str] = {
        "good": "😀 Good", "okay": "😐 Okay", "hard": "😞 Hard"
    };
    total_steps = sum([len(m.steps) for m in plan]);

    # ---- Plan tab (unchanged Stage 2 view) ----
    plan_view =
        <div>
            {plan_error and
                <div className="error">
                    <p>{plan_error}</p>
                    <button className="btn small" onClick={lambda { run_plan(selected_goal); }}>
                        Try again
                    </button>
                </div>}
            {(len(plan) == 0 and not plan_error) and
                <div className="hint">
                    <p className="muted">No milestones yet.</p>
                    <button className="btn" onClick={lambda { run_plan(selected_goal); }}>
                        Plan it with AI
                    </button>
                </div>}
            {[
                <div key={m.id} className="milestone">
                    <h3>{m.title}</h3>
                    {[
                        <label key={s.id} className={"step " + ("done" if s.done else "")}>
                            <input
                                type="checkbox"
                                checked={s.done}
                                onChange={lambda (e: ChangeEvent) { tick(s.id); }}
                            />
                            <span>{s.text}</span>
                        </label> for s in m.steps
                    ]}
                    <div className="row">
                        <input
                            className="input"
                            value={step_inputs.get(m.id, "")}
                            onChange={lambda (e: ChangeEvent) {
                                step_inputs = {**step_inputs, str(m.id): e.target.value};
                            }}
                            placeholder="Add a step"
                        />
                        <button className="btn small" onClick={lambda { add_new_step(m.id); }}>
                            Add
                        </button>
                    </div>
                </div> for m in plan
            ]}
            <div className="row">
                <input
                    className="input"
                    value={milestone_title}
                    onChange={lambda (e: ChangeEvent) { milestone_title = e.target.value; }}
                    placeholder="Add your own milestone"
                />
                <button className="btn" onClick={add_new_milestone}>Add</button>
            </div>
        </div>;

    # ---- Today tab ----
    if len(today) > 0 {
        today_view =
            <div>
                <p className="muted">Your next small steps:</p>
                {[
                    <label key={t.id} className="today-step">
                        <input
                            type="checkbox"
                            checked={t.done}
                            onChange={lambda (e: ChangeEvent) { tick(t.id); }}
                        />
                        <span className="today-text">
                            {t.text}
                            <small className="muted">
                                {t.milestone_title}
                                {t.original_text and
                                    <span className="adapted-tag" title={"Original: " + t.original_text}>
                                        Adapted for today
                                    </span>}
                            </small>
                        </span>
                    </label> for t in today
                ]}
            </div>;
    } elif total_steps > 0 {
        today_view = <div className="hint all-done">All steps done — amazing!</div>;
    } else {
        today_view =
            <div className="hint">
                <p className="muted">No steps yet. Open the Plan tab to plan this goal.</p>
                <button className="btn" onClick={lambda { tab = "plan"; }}>Go to Plan</button>
            </div>;
    }

    # ---- Check-in tab ----
    checkin_view =
        <div>
            <p className="muted">How did today go?</p>
            <div className="moods">
                {[
                    <button
                        key={k}
                        className={"mood " + ("active" if mood == k else "")}
                        onClick={lambda { mood = k; checkin_msg = ""; }}
                    >
                        {mood_labels[k]}
                    </button> for k in ["good", "okay", "hard"]
                ]}
            </div>
            <div className="row">
                <input
                    className="input"
                    value={note}
                    maxLength={200}
                    onChange={lambda (e: ChangeEvent) { note = e.target.value; checkin_msg = ""; }}
                    placeholder="One line about your day (optional)"
                />
                <button className="btn" disabled={not mood or saving} onClick={save_checkin}>
                    {"Saving…" if saving else "Save"}
                </button>
            </div>
            {checkin_msg and <p className="error">{checkin_msg}</p>}
            {(saving or coach_reply) and
                <div className="coach-card">
                    <span className="coach-icon">🌱</span>
                    <div className="coach-body">
                        {saving and <p className="muted">Thinking…</p>}
                        {(not saving and coach_reply) and <p>{coach_reply}</p>}
                        {(not saving and coach_adapted) and
                            <div className="coach-adapted">
                                <span>I made your next steps smaller for today 💛</span>
                                <button className="btn-undo" onClick={undo_adapt}>Undo</button>
                            </div>}
                        {undo_msg and <p className="muted">{undo_msg}</p>}
                        {coach_error and <p className="muted coach-error">{coach_error}</p>}
                    </div>
                </div>}
            <h3>Last 7 check-ins</h3>
            {len(checkins) == 0 and <p className="muted">No check-ins yet.</p>}
            {[
                <div key={c.id} className="checkin">
                    <span className="checkin-day">{"Today" if c.is_today else c.day}</span>
                    <span>{mood_labels.get(c.mood, c.mood)}</span>
                    {c.note and <span className="muted checkin-note">{c.note}</span>}
                    {c.coach_reply and <span className="muted checkin-reply">🌱 {c.coach_reply}</span>}
                </div> for c in checkins
            ]}
        </div>;

    # ---- Right panel: the selected goal ----
    if not selected_goal {
        plan_panel =
            <section className="panel empty">
                Create a goal and press Plan it, or pick a goal on the left.
            </section>;
    } elif planning {
        plan_panel =
            <section className="panel empty">
                <div className="spinner"></div>
                <p>Hatua is breaking "{selected_title}" into small steps…</p>
            </section>;
    } else {
        if tab == "plan" {
            tab_body = plan_view;
        } elif tab == "checkin" {
            tab_body = checkin_view;
        } else {
            tab_body = today_view;
        }
        plan_panel =
            <section className="panel">
                <div className="goal-head">
                    <h2>{selected_title}</h2>
                    <span className={"streak " + ("on" if streak > 0 else "")}>
                        {f"🔥 {streak}-day streak" if streak > 0 else "Start your streak today"}
                    </span>
                </div>
                <div className="tabs">
                    <button
                        className={"tab " + ("active" if tab == "today" else "")}
                        onClick={lambda { tab = "today"; }}
                    >Today</button>
                    <button
                        className={"tab " + ("active" if tab == "plan" else "")}
                        onClick={lambda { tab = "plan"; }}
                    >Plan</button>
                    <button
                        className={"tab " + ("active" if tab == "checkin" else "")}
                        onClick={lambda { tab = "checkin"; checkin_msg = ""; }}
                    >Check-in</button>
                </div>
                {tab_body}
            </section>;
    }

    return
        <div className="container">
            <h1>Hatua <span className="muted">· one step at a time</span></h1>
            <div className="grid">
                <section className="panel">
                    <h2>New goal</h2>
                    <input
                        className="input"
                        value={title}
                        onChange={lambda (e: ChangeEvent) { title = e.target.value; }}
                        placeholder="Big goal, e.g. Run a 5K by December"
                    />
                    <input
                        className="input"
                        value={why}
                        onChange={lambda (e: ChangeEvent) { why = e.target.value; }}
                        placeholder="Why does it matter to you?"
                    />
                    <div className="row">
                        <input
                            className="input"
                            type="number"
                            min="5"
                            value={minutes}
                            onChange={lambda (e: ChangeEvent) { minutes = int(e.target.value or "0"); }}
                        />
                        <span className="muted nowrap">min / day</span>
                        <select
                            className="input"
                            value={language}
                            onChange={lambda (e: ChangeEvent) { language = e.target.value; }}
                        >
                            <option value="en">English</option>
                            <option value="sw">Kiswahili</option>
                        </select>
                    </div>
                    <button
                        className="btn"
                        disabled={planning or not title.strip()}
                        onClick={plan_new_goal}
                    >
                        {"Planning…" if planning else "Plan it"}
                    </button>
                    <h2>My goals</h2>
                    {[
                        <div
                            key={jid(g)}
                            className={"item " + ("active" if jid(g) == selected_goal else "")}
                            onClick={lambda { open_goal(g); }}
                        >
                            <strong>{g.title}</strong>
                            <span className="muted"> {g.minutes_per_day} min/day · {g.language}</span>
                        </div> for g in goals
                    ]}
                </section>
                {plan_panel}
            </div>
            <footer className="footer">
                Need support? Call Kenya Red Cross on 1199.
            </footer>
        </div>;
}
