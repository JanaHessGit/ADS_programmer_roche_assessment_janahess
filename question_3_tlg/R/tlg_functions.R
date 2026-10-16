# =============================================================================
# Program : R/tlg_functions.R
# Purpose : Helper functions shared by the TLG programs
#           (02_create_visualizations.R) and the
#           tests (tests/testthat/test-tlg.R). Keeping the calculations in
#           functions makes them testable on small dummy data.
# =============================================================================

#' Severity levels in their natural order, derived from the data
#'
#' Returns the distinct values of `AESEV` ordered by their numeric code
#' `ASEVN`, so that severity is shown in its clinical order instead of
#' alphabetically (in this study: MILD = 1, MODERATE = 2, SEVERE = 3).
#' Deriving the order from the data avoids hard-coding the severity values.
#'
#' @param adae ADAE dataset with the variables `AESEV` (severity as text) and
#'   `ASEVN` (severity as number). Records with missing `AESEV` are ignored.
#'
#' @return Character vector of the distinct `AESEV` values, ordered by
#'   ascending `ASEVN`, e.g. `c("MILD", "MODERATE", "SEVERE")`.
#'
#' @details The function stops with an error if `AESEV` or `ASEVN` is missing
#'   from `adae`, or if the two variables are not a one-to-one mapping (one
#'   severity text with several codes, or one code with several texts), since
#'   then no unique order exists.
#'
#' @examples
#' get_severity_levels(pharmaverseadam::adae)
#' #> "MILD" "MODERATE" "SEVERE"
get_severity_levels <- function(adae) {
  stopifnot(all(c("AESEV", "ASEVN") %in% names(adae)))
  lvls <- adae %>%
    dplyr::filter(!is.na(.data$AESEV)) %>%
    dplyr::distinct(.data$AESEV, .data$ASEVN) %>%
    dplyr::arrange(.data$ASEVN)
  # each severity text must have exactly one numeric code and vice versa
  if (anyDuplicated(lvls$AESEV) || anyDuplicated(lvls$ASEVN)) {
    stop("AESEV and ASEVN are not a one-to-one mapping")
  }
  as.character(lvls$AESEV)
}


#' Number of AE records by treatment arm and severity
#'
#' Counts the adverse event records (events, not subjects) per treatment arm
#' (`ACTARM`) and severity (`AESEV`). Used as the data for Plot 1 (AE
#' severity distribution by treatment).
#'
#' @param adae ADAE dataset with the variables `ACTARM` and `AESEV`. Records
#'   with missing `AESEV` are not counted.
#' @param severity_levels Character vector of the severity values in the order
#'   they should be displayed. Default: derived from the data with
#'   [get_severity_levels()], which requires `ASEVN` in `adae`. Pass the
#'   levels explicitly to show severities that do not occur in the data
#'   (with n = 0) or if `ASEVN` is not available.
#'
#' @return Tibble with one row per treatment arm and severity:
#'   * `ACTARM` – treatment arm (character)
#'   * `AESEV` – severity (factor with levels `severity_levels`, so plots and
#'     legends follow the clinical order)
#'   * `n` – number of AE records
#'
#'   Arm/severity combinations without records are included with `n = 0`, so
#'   every arm has a row for every severity level.
#'
#' @details The function stops with an error if `ACTARM` or `AESEV` is
#'   missing from `adae`, or if `AESEV` contains a value that is not in
#'   `severity_levels` (it would otherwise silently become `NA`).
#'
#' @examples
#' count_ae_by_severity(pharmaverseadam::adae)
#'
#' # explicit levels, e.g. to show a severity without records
count_ae_by_severity <- function(adae,
                                 severity_levels = get_severity_levels(adae)) {
  stopifnot(all(c("ACTARM", "AESEV") %in% names(adae)))
  stopifnot(all(adae$AESEV %in% c(severity_levels, NA)))

  # .data pronoun: refer to dataset columns explicitly inside functions
  adae %>%
    dplyr::filter(!is.na(.data$AESEV)) %>%
    dplyr::mutate(
      ACTARM = factor(.data$ACTARM),
      AESEV  = factor(.data$AESEV, levels = severity_levels)
    ) %>%
    # .drop = FALSE keeps arm/severity combinations without records (n = 0)
    dplyr::count(.data$ACTARM, .data$AESEV, name = "n", .drop = FALSE) %>%
    dplyr::mutate(ACTARM = as.character(.data$ACTARM))
}


#' Top AE terms by subject incidence, with exact 95% confidence intervals
#'
#' Incidence = number of subjects with at least one record of the term divided
#' by the number of subjects in the denominator. 95% CIs are exact
#' Clopper-Pearson intervals (stats::binom.test).
#'
#' @param adae ADAE dataset with USUBJID and AETERM.
#' @param n_top Number of terms to return.
#' @param conf_level Confidence level of the Clopper-Pearson CI (default 0.95).
#' @param denominator Number of subjects used as denominator. Default: all
#'   subjects in `adae` (as in the assessment's sample output).
#' @return Tibble with AETERM, n, N, pct, ci_low, ci_high (proportions 0-1),
#'   sorted by descending n (ties sorted alphabetically).
top_ae_incidence <- function(adae, n_top = 10, conf_level = 0.95,
                             denominator = dplyr::n_distinct(adae$USUBJID)) {
  stopifnot(all(c("USUBJID", "AETERM") %in% names(adae)))
  stopifnot(denominator >= dplyr::n_distinct(adae$USUBJID))

  adae %>%
    dplyr::filter(!is.na(.data$AETERM)) %>%
    # a subject counts once per term, however many records it has
    dplyr::distinct(.data$USUBJID, .data$AETERM) %>%
    dplyr::count(.data$AETERM, name = "n") %>%
    dplyr::arrange(dplyr::desc(.data$n), .data$AETERM) %>%
    dplyr::slice_head(n = n_top) %>%
    dplyr::mutate(
      N = denominator,
      pct = .data$n / .data$N,
      # exact (Clopper-Pearson) CI; binom.test() takes one count at a
      # time, so it is run once per term and returns c(lower, upper)
      ci = purrr::map2(
        .data$n, .data$N,
        \(k, total) stats::binom.test(k, total, conf.level = conf_level)$conf.int
      ),
      ci_low = purrr::map_dbl(.data$ci, 1),
      ci_high = purrr::map_dbl(.data$ci, 2)
    ) %>%
    dplyr::select(-"ci")
}
