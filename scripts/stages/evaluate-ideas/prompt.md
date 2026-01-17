# Evaluate the Other Model's Ideas

First, read your context file and get the other model's ideas:

```bash
cat ${CTX} | jq -r '.inputs.from_parallel.providers | to_entries[0].value.output'
```

Read that file now.

---

I asked another model the same thing and it came up with this list of ideas. You've now seen them.

Now, I want you to very carefully consider and evaluate each of them and then give me your candid evaluation and score them from 0 (worst) to 1000 (best) as an overall score that reflects how good and smart the idea is, how useful in practical, real-life scenarios it would be for humans and AI coding agents like yourself, how practical it would be to implement it all correctly, whether the utility/advantages of the new feature/idea would easily justify the increased complexity and tech debt, etc.

Use ultrathink.

---

When complete, write status:

```bash
cat > ${STATUS} << 'EOF'
{"decision": "stop", "reason": "Evaluation complete", "summary": "Scored ideas from other model"}
EOF
```
