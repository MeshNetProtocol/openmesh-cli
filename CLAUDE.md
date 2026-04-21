# CLAUDE.md

Project instructions for AI assistants working in this codebase.

---

## Part 1: Core Coding Principles

Universal guidelines to reduce common LLM coding mistakes. **Tradeoff:** These bias toward caution over speed.

### 1.1 Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 1.2 Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 1.3 Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

**The test:** Every changed line should trace directly to the user's request.

### 1.4 Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

## Part 2: Project-Specific Protocols

### 2.1 Context Management Protocol

**Requirement:** Monitor context usage to maintain conversation quality.

#### Display Context Usage

At the **END** of each response (when task is complete), display:

```
📊 Context: [current_tokens]/[max_tokens] ([percentage]%)
```

**Note:** Only display at conversation end, not at start or middle of responses.

#### High Context Warning

When context usage exceeds **50%** of maximum, display warning:

```
⚠️ Context: [current_tokens]/[max_tokens] ([percentage]%) - Consider starting a new conversation to maintain performance
```

**System behavior:** The system automatically compresses prior messages as it approaches context limits. This is handled automatically and cannot be manually triggered.

---

### 2.2 File Operations Protocol

Rules to prevent "Write failed" errors:

1. **Always use relative paths** - No absolute paths like `/Users/wesley/...`. All paths must be relative to project root (e.g., `docs/phase1/filename.md`).

2. **Never pre-create with `touch`** - Don't use `touch` to create empty files before writing. Directly call `write_to_file` with relative path.
   - **Reason:** Pre-creating with `touch` makes AI think it's an existing file, triggering write protection if no `read` operation precedes the write.

3. **Follow Read-Before-Write flow:**
   - If target file exists: must call `read_file` first to confirm content
   - If target file is new: directly call `write` tool

4. **Auto-create directories** - Ensure write operations automatically create missing parent directories (`mkdir -p` behavior).

5. **UTF-8 encoding** - All filenames and content must use UTF-8 encoding, especially paths containing Chinese characters.

---

### 2.3 UI/UX Design System Protocol

**Requirement:** Use ui-ux-pro-max-skill system for all UI/UX work.

#### Activation Triggers

Auto-activates when working on:
- Landing pages, dashboards, or web applications
- UI components, forms, or layouts
- Design system implementation
- Frontend styling or visual design

#### Mandatory Workflow

**Step 1: Generate Design System First**

Before writing any UI code, generate complete design system:

```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "[product description]" --design-system -p "[Project Name]"
```

**Step 2: Persist to Files**

Save design system for hierarchical retrieval:

```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "[product description]" --design-system --persist -p "[Project Name]"
```

This creates:
- `design-system/MASTER.md` - Global source of truth (colors, typography, spacing, components)
- `design-system/pages/[page-name].md` - Page-specific overrides (optional)

**Step 3: Read Before Implementing**

Always read design system files before generating code:
- First check if `design-system/pages/[page-name].md` exists for specific page
- If page file exists, its rules override Master file
- If not, use `design-system/MASTER.md` exclusively

#### Pre-Delivery Checklist

Before marking any UI task complete, verify:

- [ ] No emojis as icons - Use SVG icons (Heroicons/Lucide) only
- [ ] `cursor-pointer` on all clickable elements
- [ ] Hover states with smooth transitions (150-300ms)
- [ ] Text contrast minimum 4.5:1 for light mode
- [ ] Focus states visible for keyboard navigation
- [ ] `prefers-reduced-motion` respected in animations
- [ ] Responsive breakpoints tested: 375px, 768px, 1024px, 1440px

#### Anti-Patterns to Avoid

- Never use emojis as UI icons (❌ 🎨 📱)
- Never use AI purple/pink gradients unless in design system
- Never skip hover states or transitions
- Never use bright neon colors without design system approval
- Never implement dark mode unless specified in design system

#### Stack Guidelines

Default to **HTML + Tailwind CSS** unless user specifies:
- React ecosystem: React, Next.js, shadcn/ui
- Vue ecosystem: Vue, Nuxt.js, Nuxt UI
- Other: Svelte, Astro, Angular, Laravel

#### Reasoning Engine

System includes 161 industry-specific reasoning rules covering:
- Tech & SaaS, Finance, Healthcare, E-commerce
- Services, Creative, Lifestyle, Emerging Tech

Each rule provides:
- Recommended landing page pattern
- Style priority (from 67 available styles)
- Color mood (from 161 palettes)
- Typography pairing (from 57 combinations)
- Key effects and anti-patterns

---

### 2.4 Tool Integration

#### gstack Skills

Use `/browse` from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools.

**Available skills:**
- Planning: `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/autoplan`
- Design: `/design-consultation`, `/design-shotgun`, `/design-html`, `/design-review`
- Development: `/review`, `/ship`, `/land-and-deploy`, `/investigate`, `/document-release`
- Testing: `/qa`, `/qa-only`, `/canary`, `/benchmark`, `/health`
- DevEx: `/plan-devex-review`, `/devex-review`
- Security: `/cso`, `/careful`, `/freeze`, `/guard`, `/unfreeze`
- Browser: `/browse`, `/connect-chrome`, `/open-gstack-browser`, `/setup-browser-cookies`, `/pair-agent`
- Utilities: `/retro`, `/codex`, `/gstack-upgrade`, `/learn`, `/checkpoint`

---

## Part 3: Quick Reference

### Common Commands

```bash
# Generate UI design system
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "[description]" --design-system -p "[Project]"

# Persist design system
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "[description]" --design-system --persist -p "[Project]"

# Domain-specific search
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "[query]" --domain [style|typography|chart]

# Stack-specific guidelines
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "[query]" --stack [react|html-tailwind|vue]
```

### Key Constraints Checklist

Before completing any task, verify:

- [ ] **Simplicity:** Could this be simpler? No unnecessary abstractions?
- [ ] **Surgical:** Only changed what was requested? No unrelated improvements?
- [ ] **File paths:** Using relative paths only?
- [ ] **Context:** Displayed context usage at end of response?
- [ ] **UI work:** Generated and followed design system? Passed pre-delivery checklist?

### Protocol Violations

These are **critical failures** that must be avoided:

1. **Context overflow** - Not monitoring or compacting context when >50%
2. **Write failures** - Using absolute paths or pre-creating files with `touch`
3. **UI inconsistency** - Implementing UI without generating design system first
4. **Over-engineering** - Adding features, abstractions, or error handling beyond requirements

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
