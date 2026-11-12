# 01b_competition_file.R
# Read the three competition files (dispensing by pharmacy and BNF chapter,
# Jan 2019 to May 2026) and build the numbers for the opening section:
# nervous system (BNF Chapter 4) prescribing over time and by place.
#
# Before running: copy File_A_2019-21.csv, File_B_2022-24.csv and
# File_C_2025-26.csv into data/raw/competition/ (git-ignored).

source("analysis/00_packages.R")

in_dir  <- here::here("data", "raw", "competition")
out_dir <- here::here("data", "processed")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

files <- list.files(in_dir, pattern = "^File_[ABC].*\\.csv$", full.names = TRUE)
stopifnot("Copy the three competition CSVs into data/raw/competition/ first" = length(files) == 3)

comp <- map(files, \(f) readr::read_csv(
  f,
  col_types = readr::cols(
    PaidDateMonth = "c", DispLocationCode = "c", BNFChapter = "i",
    NumberOfPaidItems = "d", PaidQuantity = "d", GrossIngredientCost = "d",
    .default = "c"
  ),
  progress = FALSE
)) |>
  list_rbind() |>
  janitor::clean_names() |>
  mutate(month = lubridate::ym(paid_date_month))

message("Rows: ", nrow(comp), "; months ", min(comp$month), " to ", max(comp$month))

# Chapter 4 share of all medicine items (chapters 1 to 15), by month and health board
by_board <- comp |>
  filter(bnf_chapter %in% 1:15) |>
  group_by(month, hb_name) |>
  summarise(
    items_all = sum(number_of_paid_items),
    items_ch4 = sum(number_of_paid_items[bnf_chapter == 4]),
    .groups = "drop"
  ) |>
  mutate(ch4_share = items_ch4 / items_all)

# Same by HSCP (finer geography for the map)
by_hscp <- comp |>
  filter(bnf_chapter %in% 1:15) |>
  group_by(month, hb_name, hscp_name) |>
  summarise(
    items_all = sum(number_of_paid_items),
    items_ch4 = sum(number_of_paid_items[bnf_chapter == 4]),
    .groups = "drop"
  ) |>
  mutate(ch4_share = items_ch4 / items_all)

# Pharmacy list with postcodes, for linking to SIMD in 02_clean.R
pharmacies <- comp |>
  distinct(disp_location_code, disp_location_postcode, hscp_name, hb_name)

readr::write_csv(by_board,   file.path(out_dir, "competition_ch4_by_board.csv"))
readr::write_csv(by_hscp,    file.path(out_dir, "competition_ch4_by_hscp.csv"))
readr::write_csv(pharmacies, file.path(out_dir, "competition_pharmacies.csv"))
message("Saved competition summaries to ", out_dir)
