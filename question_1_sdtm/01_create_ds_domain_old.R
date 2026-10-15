
# =============================================================================
# Program     : 01_create_ds_domain.R
# Purpose     : Create the SDTM DS (Disposition) domain from the raw
#               disposition CRF data pharmaverseraw::ds_raw using {sdtm.oak}.
# Input       : pharmaverseraw::ds_raw  - raw Subject Disposition eCRF data
#               pharmaversesdtm::dm     - SDTM DM (reference dates for DSSTDY)
#               metadata/sdtm_ct.csv    - study controlled terminology (CT)
# Output      : output/ds.rds, output/ds.csv - SDTM DS domain
#               (log: run with logrx, see "How to run" below)
# Spec        : Subject Disposition aCRF (pharmaverseraw) and SDTMIG v3.4 DS
#
# Mapping rules (from the annotated CRF):
#   * IT.DSDECOD -> DSDECOD and IT.DSTERM -> DSTERM, when OTHERSP is null
#   * OTHERSP    -> DSDECOD and DSTERM,              when OTHERSP is not null
#   * DSCAT = "PROTOCOL MILESTONE" if IT.DSDECOD = "Randomized",
#             "OTHER EVENT"        if OTHERSP is not null,
#             "DISPOSITION EVENT"  otherwise
#   * DSDTCOL + DSTMCOL -> DSDTC   (ISO 8601 date/time of collection)
#   * IT.DSSTDAT        -> DSSTDTC (ISO 8601 start date of the event)
#   * INSTANCE          -> VISIT / VISITNUM (follows the pharmaverse VS example)
#   * DSSTDY derived from DSSTDTC relative to DM.RFXSTDTC
#   * DSSEQ  derived per subject in chronological order
#
# How to run (from the repository root):
#   logrx::axecute("question_1_sdtm/01_create_ds_domain.R",
#                  log_name = "01_create_ds_domain.log",
#                  log_path = "question_1_sdtm")
#   (alternative without logrx:
#    Rscript question_1_sdtm/01_create_ds_domain.R > question_1_sdtm/01_create_ds_domain.log 2>&1)
#
# R packages  : sdtm.oak, pharmaverseraw, pharmaversesdtm, dplyr, stringr
#
#
# How to run and create logfile (from the repository root):
#   logrx::axecute("question_1_sdtm/01_create_ds_domain.R",
#                  log_name = "output/01_create_ds_domain.log",
#                  log_path = "question_1_sdtm")
# =============================================================================

library(sdtm.oak)
library(pharmaverseraw)
library(pharmaversesdtm)
library(dplyr)
library(stringr)
library(logrx)

# Paths are relative to the repository root
prog_dir <- "question_1_sdtm"
out_dir  <- file.path(prog_dir, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# -----------------------------------------------------------------------------
# 1. Read input data
# -----------------------------------------------------------------------------
ds_raw <- pharmaverseraw::ds_raw
dm <- pharmaversesdtm::dm

# Load controlled terminology specifications
study_ct <- read.csv(file.path("metadata", "sdtm_ct.csv"), stringsAsFactors = FALSE)

# Quick look at the raw data
message("ds_raw: ", nrow(ds_raw), " records, ", n_distinct(ds_raw$PATNUM), " subjects")

# -----------------------------------------------------------------------------
# 2. Create the oak ID variables
#    (oak_id, raw_source, patient_number) - they link every SDTM record back to
#    its raw record and are used as join keys by all sdtm.oak mapping functions.
# -----------------------------------------------------------------------------
ds_raw <- ds_raw %>% 
  generate_oak_id_vars(pat_var = "PATNUM", raw_src = "ds_raw")


# -----------------------------------------------------------------------------
# 3. Map the topic and qualifier variables
# -----------------------------------------------------------------------------
ds <-
  # --- DSTERM ----------------------------------------------------------------
  # IF OTHERSP is NA map from IT.DSTERM else map from OTHERSP as described in the aCRF
  assign_no_ct(
    raw_dat = condition_add(ds_raw, is.na(OTHERSP)),
    raw_var = "IT.DSTERM",
    tgt_var = "DSTERM",
    id_vars = oak_id_vars()
  ) %>%
  assign_no_ct(
    raw_dat = condition_add(ds_raw, !is.na(OTHERSP)),
    raw_var = "OTHERSP",
    tgt_var = "DSTERM",
    id_vars = oak_id_vars()
  ) %>%

  # --- DSDECOD ---------------------------------------------------------------
  # IF OTHERSP is NA map from IT.DSDECOD else map from OTHERSP as described in the aCRF
  # Standardised term: IT.DSDECOD mapped to the incomplete codelist (C66727).
  # Note: "Randomized" is a protocol milestone and is not part of C66727, so
  # sdtm.oak keeps it as the (upper-cased) collected value "RANDOMIZED".
  # For other events, DSDECOD = OTHERSP (free text, no CT applies).
  assign_ct(
    raw_dat  = condition_add(ds_raw, is.na(OTHERSP)),
    raw_var  = "IT.DSDECOD",
    tgt_var  = "DSDECOD",
    ct_spec  = study_ct,
    ct_clst  = "C66727",
    id_vars  = oak_id_vars()
  ) %>%
  assign_no_ct(
    raw_dat = condition_add(ds_raw, !is.na(OTHERSP)),
    raw_var = "OTHERSP",
    tgt_var = "DSDECOD",
    id_vars = oak_id_vars()
  ) %>%

  # --- VISIT / VISITNUM ------------------------------------------------------
  # map VISIT and VISITNUM from INSTANCE and look up terminology in study_ct
  assign_ct(
    raw_dat = ds_raw,
    raw_var = "INSTANCE",
    tgt_var = "VISIT",
    ct_spec = study_ct,
    ct_clst = "VISIT",
    id_vars = oak_id_vars()
  ) %>%
  assign_ct(
    raw_dat = ds_raw,
    raw_var = "INSTANCE",
    tgt_var = "VISITNUM",
    ct_spec = study_ct,
    ct_clst = "VISITNUM",
    id_vars = oak_id_vars()
  ) %>%

  # --- DSDTC: date/time of collection ----------------------------------------
  # DSDTCOL is "mm-dd-yyyy", DSTMCOL is "HH:MM" (missing for most records,
  # in which case DSDTC holds the date only).
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = c("DSDTCOL", "DSTMCOL"),
    tgt_var = "DSDTC",
    raw_fmt = c("m-d-y", "H:M"),
    id_vars = oak_id_vars()
  ) %>%
  # --- DSSTDTC: start date of the disposition event ---------------------------
  # Map the IT.DSSTDAT to DSSTDTC ISO8601 format as described in the ACRF
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = "IT.DSSTDAT",
    tgt_var = "DSSTDTC",
    raw_fmt = "m-d-y",
    id_vars = oak_id_vars()
  )


# Note: assign_ct() reports "Randomized", "Completed", "Study Terminated by Sponsor", "Screen Failure", and "Lost to Follow-Up"
# and as unmapped because the study CT's collected values differ in wording/case. The upper-cased raw values equal
# the C66727 submission values (verified by the check in section 6).




# -----------------------------------------------------------------------------
# 4. Derive DSCAT, identifiers and clean up text variables
# -----------------------------------------------------------------------------
# Raw variables needed for DSCAT and the identifiers, joined via oak IDs
raw_keys <- ds_raw %>%
  select(all_of(oak_id_vars()), STUDY, PATNUM, IT.DSDECOD, OTHERSP, INSTANCE)

# VISITNUM fallback for visits not in the study CT:
#   * "Unscheduled x.y" -> x.y (the number is part of the visit name)
#   * "Ambul Ecg Removal" differs from the CT value "Ambul ECG Removal" only in
#     case, so a case-insensitive lookup in the CT is used.
visitnum_ct <- study_ct %>%
  filter(codelist_code == "VISITNUM") %>%
  transmute(INSTANCE_UP = toupper(collected_value),
            VISITNUM_CT = as.numeric(term_value)) %>%
  distinct(INSTANCE_UP, .keep_all = TRUE)


# Convert string to numeric without coercion warnings: only strings that are
# valid numbers (e.g. "13", "6.1") are converted, everything else becomes NA.
as_num_safe <- function(x) {
  out <- rep(NA_real_, length(x))
  is_num <- !is.na(x) & grepl("^[0-9]+(\\.[0-9]+)?$", x)
  out[is_num] <- as.numeric(x[is_num])
  out
}


ds <- ds %>%
  left_join(raw_keys, by = oak_id_vars()) %>%
  mutate(INSTANCE_UP = toupper(INSTANCE)) %>%
  # add VISITNUMS that could not be matched before since no matching value present in study_ct
  left_join(visitnum_ct, by = "INSTANCE_UP") %>%
  mutate(
    STUDYID  = STUDY,
    DOMAIN   = "DS",
    USUBJID  = paste0("01-", PATNUM),  # study prefix "01-" as in DM (CDISC pilot convention) and pharmaverse examples
    DSTERM   = toupper(DSTERM),
    DSDECOD  = toupper(DSDECOD),
    #as specified in aCRF
    DSCAT    = case_when(
      !is.na(OTHERSP)            ~ "OTHER EVENT",
      IT.DSDECOD == "Randomized" ~ "PROTOCOL MILESTONE",
      TRUE                       ~ "DISPOSITION EVENT"
    ),
    VISIT    = toupper(VISIT),
    # VISITNUM: (1) sdtm.oak CT mapping, (2) case-insensitive CT lookup for
    # spelling mismatches, (3) number from "Unscheduled x.y" visit names.
    VISITNUM = coalesce(
      as_num_safe(VISITNUM),
      VISITNUM_CT,
      as_num_safe(str_extract(INSTANCE, "(?<=Unscheduled )[0-9.]+"))
    )
  )




# -----------------------------------------------------------------------------
# 5. Derive DSSEQ and DSSTDY
# -----------------------------------------------------------------------------
ds <- ds %>%
  # Sequence number per subject, in chronological order of the event
  # (events on the same day keep the order in which they were collected).
  derive_seq(
    tgt_var  = "DSSEQ",
    rec_vars = c("USUBJID", "DSSTDTC")
  ) %>%
  # Study day relative to the first exposure date (DM.RFXSTDTC);
  # no day 0: day 1 = day of first dose.
  derive_study_day(
    sdtm_in       = .,
    dm_domain     = dm,
    tgdt          = "DSSTDTC",
    refdt         = "RFXSTDTC",
    study_day_var = "DSSTDY"
  ) %>%
  # ISO 8601 dates are stored as character in SDTM
  mutate(DSDTC = as.character(DSDTC), DSSTDTC = as.character(DSSTDTC)) %>%
  select(STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD, DSCAT,
         VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY) %>%
  arrange(USUBJID, DSSEQ)


# Variable labels (SDTMIG v3.4)
labels <- c(
  STUDYID  = "Study Identifier",
  DOMAIN   = "Domain Abbreviation",
  USUBJID  = "Unique Subject Identifier",
  DSSEQ    = "Sequence Number",
  DSTERM   = "Reported Term for the Disposition Event",
  DSDECOD  = "Standardized Disposition Term",
  DSCAT    = "Category for Disposition Event",
  VISITNUM = "Visit Number",
  VISIT    = "Visit Name",
  DSDTC    = "Date/Time of Collection",
  DSSTDTC  = "Start Date/Time of Disposition Event",
  DSSTDY   = "Study Day of Start of Disposition Event"
)
for (v in names(labels)) attr(ds[[v]], "label") <- labels[[v]]


# Summary for the log
print(count(ds, DSCAT, DSDECOD), n = Inf)
dplyr::glimpse(ds)

# -----------------------------------------------------------------------------
# 6. Save the output
# -----------------------------------------------------------------------------
saveRDS(ds, file.path(out_dir, "ds.rds"))
write.csv(ds, file.path(out_dir, "ds.csv"), row.names = FALSE, na = "")

message("DS domain created: ", nrow(ds), " records, ",
        n_distinct(ds$USUBJID), " subjects")


