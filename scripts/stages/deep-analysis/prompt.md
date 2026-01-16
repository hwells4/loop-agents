# Deep Analysis Agent

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Session: ${SESSION_NAME}
Iteration: ${ITERATION}

${CONTEXT}

---

First read ALL of the AGENTS.md file, CLAUDE.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project.

Then, once you've done an extremely thorough and meticulous job at all that and deeply understood the entire existing system and what it does, its purpose, and how it is implemented and how all the pieces connect with each other, I need you to hyper-intensively investigate and study and ruminate on these questions as they pertain to this project:

Are there any other gross inefficiencies in the core system? places in the code base where 1) changes would actually move the needle in terms of overall latency/responsiveness and throughput; 2) such that our changes would be provably isomorphic in terms of functionality so that we would know for sure that it wouldn't change the resulting outputs given the same inputs; 3) where you have a clear vision to an obviously better approach in terms of algorithms or data structures (note that for this, you can include in your contemplations lesser-known data structures and more esoteric/sophisticated/mathematical algorithms as well as ways to recast the problem(s) so that another paradigm is exposed, such as the list shown below (Note: Before proposing any optimization, establish baseline metrics (p50/p95/p99 latency, throughput, peak memory) and capture CPU/allocation/I/O profiles to identify actual hotspots):

- N+1 query/fetch pattern elimination
- zero-copy / buffer reuse / scatter-gather I/O
- serialization format costs (parse/encode overhead)
- bounded queues + backpressure (prevent memory blowup and tail latency)
- sharding / striped locks to reduce contention
- memoization with cache invalidation strategies
- dynamic programming techniques
- convex optimization theory
- lazy evaluation / deferred computation
- iterator/generator patterns to avoid materializing large collections
- streaming/chunked processing for memory-bounded work
- pre-computation and lookup tables
- index-based lookup vs linear scan recognition
- binary search (on data and on answer space)
- two-pointer and sliding window techniques
- prefix sums / cumulative aggregates
- topological sort and DAG-awareness for dependency graphs
- cycle detection
- union-find for dynamic connectivity
- graph traversal (BFS/DFS) with early termination
- Dijkstra's / A* for weighted shortest paths
- priority queues / heaps
- tries for prefix operations
- bloom filters for probabilistic membership
- interval/segment trees for range queries
- spatial indexing (k-d trees, quadtrees, R-trees)
- persistent/immutable data structures
- copy-on-write semantics
- object/connection pooling
- cache eviction policy selection (LRU/LFU/ARC)
- batch-aware algorithm selection
- async I/O batching and coalescing
- lock-free structures for high-contention scenarios
- work-stealing for recursive parallelism
- memory layout optimization (SoA vs AoS, cache locality)
- short-circuiting and early termination
- string interning for repeated values
- amortized analysis reasoning

taking into consideration these general guides where applicable:

DP APPLICABILITY CHECKS:
- Overlapping subproblems? → memoize with stable state key
- Optimal partitioning/batching? → prefix sums + interval DP
- Dependency graph with repeated traversal? → single-pass topological DP

CONVEX OPTIMIZATION CHECKS:
- Brute-forcing exact allocation/scheduling? → LP / min-cost flow with deterministic tie-breaking
- Continuous parameter fitting with explicit loss? → regularized least squares / QP
- Large decomposable convex objective? → ADMM / proximal methods

Also note that if there are well-written third party libraries you know of that would work well, we can include them in the project).

METHODOLOGY REQUIREMENTS:

A) Baseline first: Run the test suite and a representative workload; record p50/p95/p99 latency, throughput, and peak memory with exact commands.

B) Profile before proposing: Capture CPU + allocation + I/O profiles; identify the top 3–5 hotspots by % time before suggesting changes.

C) Equivalence oracle: Define explicit golden outputs + invariants. For large input spaces, add property-based or metamorphic tests.

D) Isomorphism proof per change: Every proposed diff must include a short proof sketch explaining why outputs cannot change (including ordering, tie-breaking, floating-point behavior, and RNG seeds).

E) Opportunity matrix: Rank candidates by (Impact × Confidence) / Effort before implementing; focus only on items likely to move p95+ or throughput meaningfully.

F) Minimal diffs: One performance lever per change. No unrelated refactors. Include rollback guidance if any risk exists.

G) Regression guardrails: Add benchmark thresholds or monitoring hooks to prevent future regressions.

Use ultrathink.

---

## Engine Integration

### Check for Inputs

```bash
# Read initial inputs (from --input CLI flag)
jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | while read file; do
  echo "=== Input: $file ==="
  cat "$file"
done
```

### Write Output

Save your optimization plan to `docs/PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__OPUS.md` (or `*_GPT.md` if running as Codex).

### Update Progress

Append a summary of your findings to `${PROGRESS}`.

### Write Status

When complete, write to `${STATUS}`:

```json
{
  "decision": "stop",
  "reason": "Deep analysis complete",
  "summary": "Comprehensive codebase analysis with optimization plan created",
  "work": {"items_completed": ["deep-analysis"], "files_touched": []},
  "errors": []
}
```
