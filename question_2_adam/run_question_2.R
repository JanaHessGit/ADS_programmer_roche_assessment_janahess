# =============================================================================
# Program : run_question_2.R
# Purpose : 1. Run create_adsl.R with {logrx} and write a log file documenting
#              that the program runs without errors or warnings.
#           2. Run the tests in tests/testthat and save the results.
# Usage   : From the repository root:
#             source("question_2_adam/run_question_2.R")
#           or in a terminal:
#             Rscript question_2_adam/run_question_2.R
# Output  : question_2_adam/create_adsl.log        (program log)
#           question_2_adam/tests/test_results.txt (test results)
#           question_2_adam/output/adsl.rds, adsl.csv (via create_adsl.R)
# =============================================================================

prog_dir <- "question_2_adam"
log_name <- "create_adsl.log"

# -----------------------------------------------------------------------------
# 1. Run the ADSL program with a log file
# -----------------------------------------------------------------------------
logrx::axecute(
  file     = file.path(prog_dir, "create_adsl.R"),
  log_name = log_name,
  log_path = prog_dir
)

# Show the error and warning sections of the log in the console
log_lines <- readLines(file.path(prog_dir, log_name))
start <- grep("^Errors:", log_lines)
cat(log_lines[start:(start + 4)], sep = "\n")

# -----------------------------------------------------------------------------
# 2. Run the tests on the new output and save the results
# -----------------------------------------------------------------------------
test_results <- testthat::test_dir(
  file.path(prog_dir, "tests", "testthat"),
  reporter         = "summary",
  stop_on_failure  = FALSE
)

results_df <- as.data.frame(test_results)
writeLines(
  c(
    paste("Test run:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste("R version:", R.version.string),
    "",
    sprintf("%-75s %6s %6s %6s %6s",
            "Test", "passed", "failed", "skip", "error"),
    sprintf("%-75s %6d %6d %6s %6s",
            substr(results_df$test, 1, 75), results_df$passed,
            results_df$failed, results_df$skipped, results_df$error),
    "",
    sprintf("TOTAL: %d passed, %d failed, %d tests skipped, %d errors",
            sum(results_df$passed), sum(results_df$failed),
            sum(results_df$skipped), sum(results_df$error))
  ),
  file.path(prog_dir, "tests", "test_results.txt")
)

if (sum(results_df$failed) > 0 || any(results_df$error)) {
  stop("Some tests failed - see question_2_adam/tests/test_results.txt")
}
message("All tests passed - see question_2_adam/tests/test_results.txt")
