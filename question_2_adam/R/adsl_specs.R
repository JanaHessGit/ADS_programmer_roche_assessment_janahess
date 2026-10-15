# =============================================================================
# Program : R/adsl_specs.R
# Purpose : Study-specific derivation rules for ADSL that are shared between
#           the production program (create_adsl.R) and the tests
#           (tests/testthat/test-adsl.R), so that both use exactly the same
#           definitions.
# =============================================================================

# -----------------------------------------------------------------------------
# AGEGR9 / AGEGR9N - age groups based on DM.AGE
#   "<18"     -> 1
#   "18 - 50" -> 2   (18 and 50 inclusive)
#   ">50"     -> 3
# Subjects with missing AGE get missing AGEGR9 / AGEGR9N (no category is
# defined for missing age in the specification).
# Used with admiral::derive_vars_cat(); conditions are evaluated in order and
# the first condition that is TRUE determines the category.
# -----------------------------------------------------------------------------
agegr9_lookup <- admiral::exprs(
  ~condition,            ~AGEGR9,   ~AGEGR9N,
  AGE < 18,              "<18",     1,
  between(AGE, 18, 50),  "18 - 50", 2,
  AGE > 50,              ">50",     3
)

# -----------------------------------------------------------------------------
# Valid dose (specification NOTE for TRTSDTM):
#   EX.EXDOSE > 0, or EX.EXDOSE = 0 and EX.EXTRT contains "PLACEBO".
# Stored as an expression so it can be injected (!!) into admiral filters.
# -----------------------------------------------------------------------------
valid_dose_cond <- rlang::expr(
  EXDOSE > 0 | (EXDOSE == 0 & stringr::str_detect(EXTRT, "PLACEBO"))
)
