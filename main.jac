import "./styles.css";
import from datetime { date }

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
        done_on: str = "";
}

node CheckIn {
    has mood: str,
        note: str = "",
        day: str = "";
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

# ---- private helpers (not exposed as endpoints) ----

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
        plan_error: str = "";

    async can with entry {
        goals = await get_goals();
    }

    async def run_plan(goal_id: str) {
        planning = True;
        plan_error = "";
        try {
            result = await plan_it(goal_id);
            if result.ok {
                plan = result.milestones;
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
        plan = await get_plan(jid(g));
    }

    async def add_new_milestone {
        if milestone_title.strip() and selected_goal {
            m = await add_milestone(selected_goal, milestone_title.strip());
            if m is not None { plan = await get_plan(selected_goal); }
            milestone_title = "";
        }
    }

    async def add_new_step(milestone_id: str) {
        text = step_inputs.get(milestone_id, "").strip();
        if text {
            s = await add_step(milestone_id, text);
            if s is not None { plan = await get_plan(selected_goal); }
            step_inputs = {**step_inputs, str(milestone_id): ""};
        }
    }

    async def tick(step_id: str) {
        updated = await toggle_step(step_id);
        if updated is not None { plan = await get_plan(selected_goal); }
    }

    # ---- Right panel: the selected goal's plan ----
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
        plan_panel =
            <section className="panel">
                <h2>{selected_title}</h2>
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
