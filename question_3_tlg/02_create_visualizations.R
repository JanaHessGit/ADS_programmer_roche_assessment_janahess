# =============================================================================
# Program     : 02_create_visualizations.R
# Purpose     : Adverse event visualizations with {ggplot2}:
#               Plot 1 - AE severity distribution by treatment (stacked bars)
#               Plot 2 - Top 10 most frequent AEs with 95% Clopper-Pearson CIs
# Input       : pharmaverseadam::adae - Adverse Events Analysis Dataset
# Output      : question_3_tlg/output/ae_severity_by_treatment.png
#               question_3_tlg/output/top10_ae_incidence.png
#               question_3_tlg/output/ae_severity_by_treatment.csv  (plot data)
#               question_3_tlg/output/top10_ae_incidence.csv        (plot data)
#
# Specification and assumptions (matching the assessment's sample output):
#   * Plot 1: number of AE records (events) in ADAE by ACTARM and AESEV
#   * Plot 2: subject incidence of each AETERM (subjects with at least one
#     record of the term); denominator = all subjects in ADAE (n = 225), as in
#     the sample output; exact 95% Clopper-Pearson confidence intervals
#   * Both plots use all ADAE records (not only TEAEs), as in the sample output
#   * The plot data are saved as CSV so the numbers can be checked (QC)
#
# How to run  : from the repository root, with log file (see README.md):
#                 logrx::axecute("question_3_tlg/02_create_visualizations.R",
#                                log_name = "02_create_visualizations.log",
#                                log_path = "question_3_tlg")
#
# =============================================================================

library(ggplot2)
library(dplyr, warn.conflicts = FALSE)
library(pharmaverseadam)

prog_dir <- "question_3_tlg"
out_dir  <- file.path(prog_dir, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Helper functions: count_ae_by_severity(), top_ae_incidence()
source(file.path(prog_dir, "R", "tlg_functions.R"))

# -----------------------------------------------------------------------------
# 1. Input data
# -----------------------------------------------------------------------------
adae <- pharmaverseadam::adae

stopifnot(
  "No missing treatment arm" = !anyNA(adae$ACTARM),
  "No missing AE term"       = !anyNA(adae$AETERM)
)

# Common look: light theme, recessive grid, no minor gridlines
theme_tlg <- theme_minimal(base_size = 11) +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    plot.title         = element_text(face = "bold"),
    plot.title.position = "plot",
    legend.position    = "right"
  )

# -----------------------------------------------------------------------------
# 2. Plot 1 - AE severity distribution by treatment
# -----------------------------------------------------------------------------
severity_data <- count_ae_by_severity(adae)

print(severity_data)

plot_severity <- ggplot(severity_data, aes(x = ACTARM, y = n, fill = AESEV)) +
  geom_col(width = 0.6, colour = "white", linewidth = 0.5) +
  labs(
    title    = "AE severity distribution by treatment",
    x = "Treatment Arm",
    y = "Count of AEs",
    fill = "Severity/Intensity"
  ) +
  theme_tlg

ggsave(file.path(out_dir, "ae_severity_by_treatment.png"), plot_severity,
       width = 8, height = 5, dpi = 300, bg = "white")
write.csv(severity_data, file.path(out_dir, "ae_severity_by_treatment.csv"),
          row.names = FALSE)

# -----------------------------------------------------------------------------
# 3. Plot 2 - Top 10 most frequent AEs with 95% CI
# -----------------------------------------------------------------------------
top10 <- top_ae_incidence(adae, n_top = 10)
n_subjects <- unique(top10$N)

print(top10)

plot_top10 <- top10 %>%
  # most frequent term at the top
  mutate(AETERM = reorder(AETERM, pct)) %>%
  ggplot(aes(x = pct, y = AETERM)) +
  # horizontal error bars (geom_errorbarh() is deprecated in newer ggplot2)
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.3,
                orientation = "y", colour = "black", linewidth = 0.6) +
  geom_point(size = 2.5, colour = "black") +
  scale_x_continuous(
    labels = scales::label_percent(accuracy = 1),
    limits = c(0, NA), expand = expansion(mult = c(0, 0.05))
  ) +
  labs(
    title    = "Top 10 Most Frequent Adverse Events",
    subtitle = paste0("n = ", n_subjects,
                      " subjects; 95% Clopper-Pearson CIs"),
    x = "Percentage of Patients (%)",
    y = NULL
  ) +
  theme_tlg +
  theme(
    panel.grid.major.x = element_line(),
    panel.grid.major.y = element_blank()
  )

ggsave(file.path(out_dir, "top10_ae_incidence.png"), plot_top10,
       width = 8, height = 5, dpi = 300, bg = "white")
write.csv(top10, file.path(out_dir, "top10_ae_incidence.csv"),
          row.names = FALSE)

message("Plots saved to ", out_dir)
