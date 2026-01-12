#!/bin/bash
# Tests for engine config loading - verify YAML → environment variable flow
# This ensures the engine correctly reads v3 termination config from loop.yaml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/yaml.sh"

#-------------------------------------------------------------------------------
# Test Helper Functions
#-------------------------------------------------------------------------------

# Simulate load_stage config parsing without running the engine
# This extracts config values the same way engine.sh does
_parse_loop_config() {
  local stage_dir=$1
  local config_file="$stage_dir/loop.yaml"

  if [ ! -f "$config_file" ]; then
    return 1
  fi

  local config=$(yaml_to_json "$config_file")

  # v3 schema: read termination block
  local term_type=$(json_get "$config" ".termination.type" "")
  if [ -n "$term_type" ]; then
    case "$term_type" in
      queue) STAGE_COMPLETION="beads-empty" ;;
      judgment) STAGE_COMPLETION="plateau" ;;
      fixed) STAGE_COMPLETION="fixed-n" ;;
      *) STAGE_COMPLETION="$term_type" ;;
    esac
    STAGE_MIN_ITERATIONS=$(json_get "$config" ".termination.min_iterations" "1")
    STAGE_CONSENSUS=$(json_get "$config" ".termination.consensus" "2")
    STAGE_TERM_TYPE="$term_type"
  else
    # v2 legacy
    STAGE_COMPLETION=$(json_get "$config" ".completion" "fixed-n")
    STAGE_MIN_ITERATIONS=$(json_get "$config" ".min_iterations" "1")
    STAGE_CONSENSUS="2"
    STAGE_TERM_TYPE=""
  fi

  # Export for tests
  export MIN_ITERATIONS="$STAGE_MIN_ITERATIONS"
  export CONSENSUS="$STAGE_CONSENSUS"
}

#-------------------------------------------------------------------------------
# Work Stage Config Tests
#-------------------------------------------------------------------------------

test_work_stage_loads_queue_termination() {
  _parse_loop_config "$SCRIPT_DIR/stages/work"

  assert_eq "queue" "$STAGE_TERM_TYPE" "work stage has termination.type=queue"
  assert_eq "beads-empty" "$STAGE_COMPLETION" "queue maps to beads-empty completion"
}

#-------------------------------------------------------------------------------
# Improve-Plan Stage Config Tests
#-------------------------------------------------------------------------------

test_improve_plan_loads_judgment_termination() {
  _parse_loop_config "$SCRIPT_DIR/stages/improve-plan"

  assert_eq "judgment" "$STAGE_TERM_TYPE" "improve-plan has termination.type=judgment"
  assert_eq "plateau" "$STAGE_COMPLETION" "judgment maps to plateau completion"
}

test_improve_plan_loads_consensus() {
  _parse_loop_config "$SCRIPT_DIR/stages/improve-plan"

  # Check the actual config value (should be 2 for improve-plan)
  local config=$(yaml_to_json "$SCRIPT_DIR/stages/improve-plan/loop.yaml")
  local consensus=$(json_get "$config" ".termination.consensus" "")

  assert_eq "2" "$consensus" "improve-plan has consensus=2 in config"
  assert_eq "2" "$CONSENSUS" "CONSENSUS env var matches config"
}

test_improve_plan_loads_min_iterations() {
  _parse_loop_config "$SCRIPT_DIR/stages/improve-plan"

  local config=$(yaml_to_json "$SCRIPT_DIR/stages/improve-plan/loop.yaml")
  local min_iter=$(json_get "$config" ".termination.min_iterations" "")

  assert_eq "2" "$min_iter" "improve-plan has min_iterations=2 in config"
  assert_eq "2" "$MIN_ITERATIONS" "MIN_ITERATIONS env var matches config"
}

#-------------------------------------------------------------------------------
# Elegance Stage Config Tests
#-------------------------------------------------------------------------------

test_elegance_loads_judgment_termination() {
  _parse_loop_config "$SCRIPT_DIR/stages/elegance"

  assert_eq "judgment" "$STAGE_TERM_TYPE" "elegance has termination.type=judgment"
  assert_eq "plateau" "$STAGE_COMPLETION" "judgment maps to plateau completion"
}

test_elegance_loads_consensus() {
  _parse_loop_config "$SCRIPT_DIR/stages/elegance"

  local config=$(yaml_to_json "$SCRIPT_DIR/stages/elegance/loop.yaml")
  local consensus=$(json_get "$config" ".termination.consensus" "")

  # elegance should have consensus configured
  assert_neq "" "$consensus" "elegance has consensus configured"
  assert_eq "$consensus" "$CONSENSUS" "CONSENSUS env var matches config"
}

#-------------------------------------------------------------------------------
# Idea-Wizard Stage Config Tests
#-------------------------------------------------------------------------------

test_idea_wizard_loads_fixed_termination() {
  _parse_loop_config "$SCRIPT_DIR/stages/idea-wizard"

  assert_eq "fixed" "$STAGE_TERM_TYPE" "idea-wizard has termination.type=fixed"
  assert_eq "fixed-n" "$STAGE_COMPLETION" "fixed maps to fixed-n completion"
}

#-------------------------------------------------------------------------------
# Refine-Beads Stage Config Tests
#-------------------------------------------------------------------------------

test_refine_beads_loads_judgment_termination() {
  _parse_loop_config "$SCRIPT_DIR/stages/refine-beads"

  assert_eq "judgment" "$STAGE_TERM_TYPE" "refine-beads has termination.type=judgment"
  assert_eq "plateau" "$STAGE_COMPLETION" "judgment maps to plateau completion"
}

#-------------------------------------------------------------------------------
# Environment Variable Export Tests
#-------------------------------------------------------------------------------

test_config_exports_min_iterations() {
  # Unset any existing value
  unset MIN_ITERATIONS

  _parse_loop_config "$SCRIPT_DIR/stages/improve-plan"

  # Should be exported
  assert_neq "" "$MIN_ITERATIONS" "MIN_ITERATIONS is exported"
}

test_config_exports_consensus() {
  # Unset any existing value
  unset CONSENSUS

  _parse_loop_config "$SCRIPT_DIR/stages/improve-plan"

  # Should be exported
  assert_neq "" "$CONSENSUS" "CONSENSUS is exported"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Engine Config Loading Tests (v3 YAML → Env)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

run_test "work: loads queue termination" test_work_stage_loads_queue_termination
run_test "improve-plan: loads judgment termination" test_improve_plan_loads_judgment_termination
run_test "improve-plan: loads consensus from config" test_improve_plan_loads_consensus
run_test "improve-plan: loads min_iterations from config" test_improve_plan_loads_min_iterations
run_test "elegance: loads judgment termination" test_elegance_loads_judgment_termination
run_test "elegance: loads consensus from config" test_elegance_loads_consensus
run_test "idea-wizard: loads fixed termination" test_idea_wizard_loads_fixed_termination
run_test "refine-beads: loads judgment termination" test_refine_beads_loads_judgment_termination
run_test "config exports MIN_ITERATIONS" test_config_exports_min_iterations
run_test "config exports CONSENSUS" test_config_exports_consensus

test_summary
