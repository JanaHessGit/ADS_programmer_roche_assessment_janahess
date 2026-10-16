# =============================================================================
# Program : R/tlg_functions.R
# Purpose : Helper functions shared by the TLG programs
#           (02_create_visualizations.R) and the
#           tests (tests/testthat/test-tlg.R). Keeping the calculations in
#           functions makes them testable on small dummy data.
# =============================================================================

#' Severity levels in their natural order, derived from the data
#'
#' Orders the distinct values of AESEV by their numeric code ASEVN
#' (1 = MILD, 2 = MODERATE, 3 = SEVERE in this study).
get_severity_levels <- function(adae) {
  stopifnot(all(c("AESEV", "ASEVN") %in% names(adae)))
  lvls <- adae |>
    dplyr::filter(!is.na(.data$AESEV)) |>
    dplyr::distinct(.data$AESEV, .data$ASEVN) |>
    dplyr::arrange(.data$ASEVN)
  # each severity text must have exactly one numeric code and vice versa
  if (anyDuplicated(lvls$AESEV) || anyDuplicated(lvls$ASEVN)) {
    stop("AESEV and ASEVN are not a one-to-one mapping")
  }
  as.character(lvls$AESEV)
}

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
#' @param conf_level Confidence level for Clopper-Pearson 95% CI
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
        \(k, total) stats::binom.test(k, total,, conf.level = conf_level)$conf.int
      ),
      ci_low = purrr::map_dbl(.data$ci, 1),
      ci_high = purrr::map_dbl(.data$ci, 2)
    ) %>%
    dplyr::select(-"ci")
}
