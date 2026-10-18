#!/usr/bin/env python3
"""Generate a large, realistic logpose journal for benchmarks.

Usage: gen_journal.py OUT_DIR [--years 2] [--seed 1]
Two years by default: a daily note per workday, sprint meetings and 1:1s for six projects,
~1,500 task files (most done and archived), topic notes and project pages.
"""
import argparse, datetime as dt, os, random

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--years", type=float, default=2)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--end", default="2026-10-15")
a = ap.parse_args()
R = random.Random(a.seed)
root = a.out
end = dt.date.fromisoformat(a.end)
start = end - dt.timedelta(days=int(365 * a.years))
PROJECTS = ["acme-api", "acme-web", "billing", "thesis", "infra", "mobile"]
PEOPLE = ["ana", "luis", "maria", "jorge", "sofia", "diego", "carla", "pablo"]
TAGS = ["perf", "ci", "bug", "security", "docs", "ux", "db", "api", "refactor", "ops"]
WORDS = ("cache queue retry index latency deploy schema migration endpoint token review "
         "rollout flaky test dashboard alert budget roadmap spike chart parser draft chapter").split()

def w(path, text):
    full = os.path.join(root, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(text)

def sentence(n=8):
    s = " ".join(R.choice(WORDS) for _ in range(n))
    return s[0].upper() + s[1:]

def item(done=None):
    box = "x" if (done if done is not None else R.random() < 0.6) else " "
    extra = ""
    if R.random() < 0.4:
        extra += " #" + R.choice(PROJECTS)
    if R.random() < 0.2:
        extra += " #" + R.choice(TAGS)
    if R.random() < 0.15:
        extra += " @" + R.choice(PEOPLE)
    return f"- [{box}] {sentence(R.randint(4, 9))}{extra}"

def sprint_of(d):
    anchor = dt.date(2026, 10, 15)
    return 43 + (d - anchor).days // 14

os.makedirs(root, exist_ok=True)
w(".logpose", "")
counts = {"daily": 0, "meetings": 0, "tasks": 0, "archived": 0, "notes": 0}
d = start
while d <= end:
    if d.weekday() < 5:
        iso = d.isoformat()
        body = [f"---\ncreated: {iso}T09:00\nmodified: {iso}T18:00\n---\n# {iso} daily notes\n",
                "## Yesterday\n", *[item(True) for _ in range(R.randint(2, 5))], "",
                "## Today\n", *[item() for _ in range(R.randint(3, 7))], "",
                "## Blockers\n", *(["- " + sentence(6)] if R.random() < 0.2 else []), "",
                "## Meetings\n", "", "## Notes\n", *[sentence(14) for _ in range(R.randint(1, 4))], ""]
        w(f"daily/daily-{iso}.md", "\n".join(body))
        counts["daily"] += 1
        # meetings: planning/review/retro on sprint boundaries, 1:1s weekly, ad-hoc sometimes
        types = []
        if d.weekday() == 3 and (d - dt.date(2026, 10, 15)).days % 14 == 0:
            types += ["planning"]
        if d.weekday() == 2 and (d - dt.date(2026, 10, 14)).days % 14 == 0:
            types += ["review", "retro"]
        if d.weekday() == 1:
            types += ["refinement"]
        if d.weekday() == 4:
            types += ["1on1"]
        if R.random() < 0.3:
            types += ["adhoc"]
        for t in types:
            p = R.choice(PROJECTS)
            title = {"planning": "Sprint planning", "review": "Sprint review", "retro": "Retro",
                     "refinement": "Refinement", "1on1": "1:1 " + R.choice(PEOPLE).title(),
                     "adhoc": sentence(3)}[t]
            slug = title.lower().replace(" ", "-").replace(":", "")
            att = ", ".join(R.sample(PEOPLE, 3))
            fm = (f'---\ntype: {t}\ndate: {iso}\nproject: {p}\ntitle: "{title}"\nattendees: [{att}]\n'
                  f"series: {p}/{t}\ncreated: {iso}T10:00\nmodified: {iso}T11:00\n---\n")
            body = ["## Notes\n", *["- " + sentence(10) for _ in range(R.randint(3, 8))], "",
                    "## Decisions\n", *["- " + sentence(8) for _ in range(R.randint(0, 3))], "",
                    "## Action items\n",
                    *[f"- [{'x' if R.random() < 0.7 else ' '}] {sentence(6)} @{R.choice(PEOPLE)} due:"
                      f"{(d + dt.timedelta(days=R.randint(1, 14))).isoformat()}" for _ in range(R.randint(1, 4))], ""]
            w(f"meetings/{p}/{iso} - {slug}.md", fm + "\n".join(body))
            counts["meetings"] += 1
    d += dt.timedelta(days=1)

# tasks: ~2 per workday over the period; old ones done and archived by sprint
for i in range(int(counts["daily"] * 1.5)):
    created = start + dt.timedelta(days=R.randint(0, (end - start).days))
    age = (end - created).days
    p = R.choice(PROJECTS)
    title = sentence(R.randint(3, 6))
    slug = f"{title.lower().replace(' ', '-')[:40]}-{i}"
    if age > 30 and R.random() < 0.95:
        status, folder = "done", f"tasks/archive/sprint-{sprint_of(created)}"
        counts["archived"] += 1
    else:
        status = R.choice(["backlog", "backlog", "todo", "in-progress", "follow-up", "done"])
        folder = "tasks"
    tags = ", ".join(R.sample(TAGS, R.randint(0, 2)))
    due = (created + dt.timedelta(days=R.randint(3, 30))).isoformat() if R.random() < 0.3 else ""
    blocked = "waiting on " + R.choice(PEOPLE) if status != "done" and R.random() < 0.1 else ""
    done = (created + dt.timedelta(days=R.randint(1, 20))).isoformat() if status == "done" else ""
    fm = (f'---\ntitle: "{title}"\nstatus: {status}\nproject: {p}\ntags: [{tags}]\ndue: {due}\n'
          f"blocked: {blocked}\ncreated: {created.isoformat()}T09:00\nmodified: {created.isoformat()}T09:00\n"
          f"started: \ndone: {done}\n---\n")
    body = ["## Context\n", sentence(20), "", *["- [ ] " + sentence(5) for _ in range(R.randint(0, 3))], "",
            "## Log\n", f"- {created.isoformat()} 09:00: created in Backlog", ""]
    w(f"{folder}/{slug}.md", fm + "\n".join(body))
    counts["tasks"] += 1

for i in range(60):
    p = R.choice(PROJECTS)
    title = sentence(3)
    w(f"notes/{title.lower().replace(' ', '-')}-{i}.md",
      f'---\ntitle: "{title}"\nproject: {p}\ntags: [{R.choice(TAGS)}]\n---\n## Notes\n\n' +
      "\n".join(sentence(15) for _ in range(R.randint(3, 12))) + "\n")
    counts["notes"] += 1
for p in PROJECTS:
    w(f"projects/{p}.md", f'---\ntitle: "{p.replace("-", " ").title()}"\ntype: project\nproject: {p}\n'
      f"description: {sentence(6)}\npaths: [~/work/{p}]\n---\n## Overview\n\n{sentence(20)}\n")
print(counts, "files:", sum(len(f) for _, _, f in os.walk(root)))
