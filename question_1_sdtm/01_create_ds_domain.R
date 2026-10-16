# =============================================================================
# Program     : 01_create_ds_domain.R
# Purpose     : Create the SDTM DS (Disposition) domain from the raw
#               disposition CRF data pharmaverseraw::ds_raw using {sdtm.oak}.
# Input       : pharmaverseraw::ds_raw  - raw Subject Disposition eCRF data
#               pharmaversesdtm::dm     - SDTM DM (USUBJID, RFXSTDTC)
#               metadata/sdtm_ct.csv    - study controlled terminology (CT)
# Output      : output/ds.rds, output/ds.csv - SDTM DS domain
# Spec        : Subject Disposition aCRF (pharmaverseraw) and SDTMIG v3.4 DS
#
# Mapping rules (from the annotated CRF):
#   * IT.DSTERM  -> DSTERM, IT.DSDECOD -> DSDECOD  if OTHERSP is null
#   * OTHERSP    -> DSTERM and DSDECOD             if OTHERSP is not null
#   * DSCAT = if OTHERSP is not null -> "OTHER EVENT",
#             if OTHERSP is null:
#               if IT.DSDECOD = "Randomized" -> "PROTOCOL MILESTONE",
#               else -> "DISPOSITION EVENT"
#   * DSDTCOL + DSTMCOL -> DSDTC   (ISO 8601 date/time of collection)
#   * IT.DSSTDAT        -> DSSTDTC (ISO 8601 start date; the aCRF calls the
#                                   field IT.DSSDAT, the data IT.DSSTDAT)
# Not annotated on the aCRF (SDTMIG / pharmaverse conventions) but 
# indicated in the question:
#   * INSTANCE -> VISIT / VISITNUM via study CT (as in the pharmaverse VS
#     example) 
#   * USUBJID from DM (DM.SITEID-DM.SUBJID = PATNUM)
#   * DSSEQ  : unique sequence number per subject, chronological by DSSTDTC
#   * DSSTDY : study day of DSSTDTC relative to DM.RFXSTDTC (no day 0)
#
# How to run  : from the repository root, with log file (see README.md):
#                 logrx::axecute("question_1_sdtm/01_create_ds_domain.R",
#                                log_name = "01_create_ds_domain.log",
#                                log_path = "question_1_sdtm")
#               Tests (after running the program):
#                 testthat::test_dir("question_1_sdtm/tests/testthat")
#
# =============================================================================

library(sdtm.oak)
library(dplyr, warn.conflicts = FALSE)
library(stringr)
library(pharmaverseraw)
library(pharmaversesdtm)


# All paths are relative to the repository root
prog_dir <- "question_1_sdtm"
out_dir <- file.path(prog_dir, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# -----------------------------------------------------------------------------
# 1. Read input data
# -----------------------------------------------------------------------------
ds_raw <- pharmaverseraw::ds_raw
dm <- pharmaversesdtm::dm

# Study controlled terminology downloaded from GitHub link provided
# in the video assessment 
# (https://github.com/pharmaverse/examples/blob/main/metadata/sdtm_ct.csv).
study_ct <- read.csv(file.path(prog_dir, "metadata", "sdtm_ct.csv"), stringsAsFactors = FALSE)

message(
  "ds_raw: ", nrow(ds_raw), " records, ",
  n_distinct(ds_raw$PATNUM), " subjects"
)

# Data assumption used by the conditional mappings below: a record has either
# a coded reason (IT.DSTERM) or an "other" text (OTHERSP), never both.
stopifnot(
  "IT.DSTERM and OTHERSP are never both filled" =
    !any(!is.na(ds_raw$IT.DSTERM) & !is.na(ds_raw$OTHERSP))
)

# -----------------------------------------------------------------------------
# 2. Create the oak ID variables
#    (oak_id, raw_source, patient_number) - they link every SDTM record back to
#    its raw record and are used as join keys by all sdtm.oak mapping functions.
# -----------------------------------------------------------------------------
ds_raw <- ds_raw %>%
  generate_oak_id_vars(pat_var = "PATNUM", raw_src = "ds_raw")

# -----------------------------------------------------------------------------
# 3. Map the topic and qualifier variables with {sdtm.oak}
#    condition_add() restricts each mapping to the records the aCRF rule
#    applies to.
# -----------------------------------------------------------------------------
ds <-
  # --- DSTERM: from IT.DSTERM if OTHERSP is null, else from OTHERSP ----------
  # no controlled terminology as shown in SDTMIG DS domain table
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
  # --- DSDECOD: from IT.DSDECOD if OTHERSP is null, else from OTHERSP --------
  # IT.DSDECOD is mapped with the NCOMPLETE codelist (C66727).
  # Note: assign_ct() reports "Randomized", "Completed", "Screen Failure",
  # "Lost to Follow-Up" and "Study Terminated by Sponsor" as unmapped because
  # the study CT's collected values differ in wording or case. The upper-cased
  # raw values equal the C66727 submission values (checked in section 6).
  # "Randomized" is not part of C66727, it is a protocol milestone (PROTMLST).
  # For other events, DSDECOD = OTHERSP (free text, no CT).
  assign_ct(
    raw_dat = condition_add(ds_raw, is.na(OTHERSP)),
    raw_var = "IT.DSDECOD",
    tgt_var = "DSDECOD",
    ct_spec = study_ct,
    ct_clst = "C66727",
    id_vars = oak_id_vars()
  ) %>%
  assign_no_ct(
    raw_dat = condition_add(ds_raw, !is.na(OTHERSP)),
    raw_var = "OTHERSP",
    tgt_var = "DSDECOD",
    id_vars = oak_id_vars()
  ) %>%
  # --- DSCAT: fixed values per aCRF rule, checked against codelist C74558 ---
  hardcode_ct(
    raw_dat = condition_add(ds_raw, !is.na(OTHERSP)),
    raw_var = "OTHERSP",
    tgt_var = "DSCAT",
    tgt_val = "OTHER EVENT",
    ct_spec = study_ct,
    ct_clst = "C74558",
    id_vars = oak_id_vars()
  ) %>%
  hardcode_ct(
    raw_dat = condition_add(
      ds_raw, is.na(OTHERSP) & IT.DSDECOD == "Randomized"
    ),
    raw_var = "IT.DSDECOD",
    tgt_var = "DSCAT",
    tgt_val = "PROTOCOL MILESTONE",
    ct_spec = study_ct,
    ct_clst = "C74558",
    id_vars = oak_id_vars()
  ) %>%
  hardcode_ct(
    raw_dat = condition_add(
      ds_raw, is.na(OTHERSP) & IT.DSDECOD != "Randomized"
    ),
    raw_var = "IT.DSDECOD",
    tgt_var = "DSCAT",
    tgt_val = "DISPOSITION EVENT",
    ct_spec = study_ct,
    ct_clst = "C74558",
    id_vars = oak_id_vars()
  ) %>%
  # --- VISIT / VISITNUM: from INSTANCE via the study visit codelists --------
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
  # --- DSDTC: date/time of collection --------------------------------------
  # DSDTCOL is "mm-dd-yyyy", DSTMCOL is "HH:MM" (missing for most records,
  # in which case DSDTC holds the date only).
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = c("DSDTCOL", "DSTMCOL"),
    tgt_var = "DSDTC",
    raw_fmt = c("m-d-y", "H:M"),
    id_vars = oak_id_vars()
  ) %>%
  # --- DSSTDTC: start date of the disposition event ------------------------
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = "IT.DSSTDAT",
    tgt_var = "DSSTDTC",
    raw_fmt = "m-d-y",
    id_vars = oak_id_vars()
  )

# Raw dates that could not be parsed would silently become NA - stop instead
stopifnot(
  "All DSDTC values parsed"   = nrow(problems(ds$DSDTC)) == 0,
  "All DSSTDTC values parsed" = nrow(problems(ds$DSSTDTC)) == 0
)

# -----------------------------------------------------------------------------
# 4. Identifiers, VISITNUM fallback and text clean-up
# -----------------------------------------------------------------------------
# Raw variables needed below, joined to the mapped data via the oak IDs
raw_keys <- ds_raw %>%
  select(all_of(oak_id_vars()), STUDY, PATNUM, INSTANCE)

# USUBJID is taken from DM instead of hard-coding the study prefix:
# PATNUM in the raw data corresponds to DM.SITEID-DM.SUBJID
dm_ids <- dm %>%
  transmute(PATNUM = paste0(SITEID, "-", SUBJID), USUBJID)

# VISITNUM fallback for visits not in the study CT:
#   * "Ambul Ecg Removal" differs from the CT value "Ambul ECG Removal" only in
#     case, so a case-insensitive lookup in the CT is used
#   * "Unscheduled x.y" -> x.y (SDTMIG convention: number after the preceding
#     scheduled visit, already part of the visit name)
# In a production study these visits should be added to the study CT instead.
visitnum_ct <- study_ct %>%
  filter(codelist_code == "VISITNUM") %>%
  transmute(
    INSTANCE_UP = toupper(collected_value),
    VISITNUM_CT = as.numeric(term_value)
  ) %>%
  distinct(INSTANCE_UP, .keep_all = TRUE)

# Function to convert string to numeric without coercion warnings: only strings that are
# valid numbers (e.g. "13", "6.1") are converted, everything else becomes NA.
as_num_safe <- function(x) {
  out <- rep(NA_real_, length(x))
  is_num <- !is.na(x) & grepl("^[0-9]+(\\.[0-9]+)?$", x)
  out[is_num] <- as.numeric(x[is_num])
  out
}

ds <- ds %>%
  left_join(raw_keys, by = oak_id_vars()) %>%
  left_join(dm_ids, by = "PATNUM") %>%
  mutate(INSTANCE_UP = toupper(INSTANCE)) %>%
  left_join(visitnum_ct, by = "INSTANCE_UP") %>%
  mutate(
    STUDYID = STUDY,
    DOMAIN = "DS",
    DSTERM = toupper(DSTERM),
    DSDECOD = toupper(DSDECOD),
    VISIT = toupper(VISIT),
    # VISITNUM: (1) sdtm.oak CT mapping, (2) case-insensitive CT lookup,
    # (3) only number from "Unscheduled x.y" visit names
    VISITNUM_FALLBACK = is.na(as_num_safe(VISITNUM)),
    VISITNUM = coalesce(
      as_num_safe(VISITNUM),
      VISITNUM_CT,
      as_num_safe(str_extract(INSTANCE, "(?<=Unscheduled )[0-9.]+"))
    )
  )

# Report visits that did not fit the study CT, for transparency in the log
visit_fallback <- ds %>%
  filter(VISITNUM_FALLBACK) %>%
  distinct(INSTANCE, VISITNUM)
if (nrow(visit_fallback) > 0) {
  message(
    "VISITNUM derived outside the study CT for: ",
    paste0(visit_fallback$INSTANCE, " -> ", visit_fallback$VISITNUM,
      collapse = "; "
    )
  )
}

# -----------------------------------------------------------------------------
# 5. Derive DSSEQ and DSSTDY
# -----------------------------------------------------------------------------
ds <- ds %>%
  # Unique sequence number per subject, in chronological order of the event
  # (events on the same day keep the order in which they were collected).
  derive_seq(
    tgt_var  = "DSSEQ",
    rec_vars = c("USUBJID", "DSSTDTC")
  ) %>%
  # Study day relative to the first exposure date (DM.RFXSTDTC, as in the
  # pharmaverse examples; identical to RFSTDTC in this study). No day 0:
  # day 1 = day of first dose.
  derive_study_day(
    sdtm_in       = .,
    dm_domain     = dm,
    tgdt          = "DSSTDTC",
    refdt         = "RFXSTDTC",
    study_day_var = "DSSTDY"
  ) %>%
  # ISO 8601 dates are stored as character in SDTM
  mutate(DSDTC = as.character(DSDTC), DSSTDTC = as.character(DSSTDTC)) %>%
  select(
    STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD, DSCAT,
    VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY
  ) %>%
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

# -----------------------------------------------------------------------------
# 6. Checks (the program stops with an error if any check fails)
# -----------------------------------------------------------------------------
required_vars <- c(
  "STUDYID", "DOMAIN", "USUBJID", "DSSEQ", "DSTERM",
  "DSDECOD", "DSCAT"
)
stopifnot(
  "One DS record per raw record"  = nrow(ds) == nrow(ds_raw),
  "Key USUBJID/DSSEQ is unique"   = !any(duplicated(ds[c("USUBJID", "DSSEQ")])),
  "Required variables populated"  = !anyNA(ds[required_vars]),
  "All subjects exist in DM"      = all(ds$USUBJID %in% dm$USUBJID),
  "All VISITNUM values mapped"    = !anyNA(ds$VISITNUM),
  "DSSTDTC are valid dates"       = !anyNA(as.Date(ds$DSSTDTC)),
  "DSDTC dates are valid dates"   = !anyNA(as.Date(substr(ds$DSDTC, 1, 10)))
)

# DSDECOD of disposition events must be in the NCOMPLETE codelist (C66727)
ncomplete <- study_ct$term_value[study_ct$codelist_code == "C66727"]
not_in_ct <- ds %>%
  filter(DSCAT == "DISPOSITION EVENT", !DSDECOD %in% ncomplete) %>%
  distinct(DSDECOD)
if (nrow(not_in_ct) > 0) {
  warning(
    "DSDECOD values not in C66727: ",
    paste(not_in_ct$DSDECOD, collapse = ", ")
  )
}

# Summaries for the log
print(count(ds, DSCAT, DSDECOD), n = Inf)
glimpse(ds)

# -----------------------------------------------------------------------------
# 7. Save the output
# -----------------------------------------------------------------------------
saveRDS(ds, file.path(out_dir, "ds.rds"))
write.csv(ds, file.path(out_dir, "ds.csv"), row.names = FALSE, na = "")

message(
  "DS domain created: ", nrow(ds), " records, ",
  n_distinct(ds$USUBJID), " subjects"
)
