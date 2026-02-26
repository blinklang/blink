[< All Decisions](../DECISIONS.md)

# AI-First Review Pass — Process Decision

### Rationale

Pact is AI-first, but the 5-expert panel gives equal vote weight. The AI/ML expert frequently dissents in 4-1 splits, often arguing "thin training data" or "LLMs will fumble this." Inflating vote weight would let "LLMs haven't seen this" override genuinely good designs — designing for AI learnability is fundamentally different from designing for today's training data coverage. Instead, a structural second-pass review evaluates every decision against AI-first criteria after voting concludes.

### Process Change

- **Equal vote weight preserved** — 5 experts, majority wins, no changes to voting
- **AI-First Review pass added** after vote tally (Step 8.5 in deliberation workflow)
- **5 criteria** evaluated pass/fail on the winning decision:
  1. **Learnability** — Can AI learn this from spec + examples without relying on other languages' training data?
  2. **Consistency** — Follows existing Pact patterns, or introduces a special case?
  3. **Generability** — Can AI reliably generate correct code using this feature?
  4. **Debuggability** — When AI gets this wrong, are error messages clear enough to self-correct?
  5. **Token Efficiency** — Does this minimize token count for common patterns?
- **2+ failures trigger reconsideration** — not a veto, but forces the panel to re-examine with AI-first concerns explicitly on the table
- **0-1 failures** — decision stands, proceed to spec writing

### AI/ML Expert Profile Update

The AI/ML expert's personality was reframed from "statistical thinker valuing training data representation" to evaluating through the 5 criteria above. This ensures the expert argues from principled AI-first design rather than "this pattern exists in training corpora."

