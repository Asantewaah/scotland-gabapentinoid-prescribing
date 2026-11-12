# 02_clean.R
# Combine the 127 monthly drug-level files, check the drugs behind each BNF code,
# link GP practices to health board and SIMD quintile, add registered-population
# denominators, and write small monthly series for the analysis.
#
# Run after 01_download.R and 01c_lookups.R.

source("analysis/00_packages.R")

raw_dir <- here::here("data", "raw")
out_dir <- here::here("data", "processed")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

drugs <- readr::read_csv(file.path(raw_dir, "drug-level", "_drug_list.csv"), col_types = "ccc")

# ---- 1. Prescribing: read and harmonise ------------------------------------------
# Early files use HBT2014, later files HBT; later files add DMDCode and PrescribedType.

files <- list.files(file.path(raw_dir, "drug-level"), pattern = "^pitc_\\d{6}\\.csv$", full.names = TRUE)
message(length(files), " monthly files")

rx_raw <- map(files, \(f) readr::read_csv(f, col_types = readr::cols(.default = "c"), progress = FALSE)) |>
  list_rbind()
if (!"HBT" %in% names(rx_raw))     rx_raw$HBT <- NA_character_
if (!"HBT2014" %in% names(rx_raw)) rx_raw$HBT2014 <- NA_character_

rx <- rx_raw |>
  transmute(
    month       = lubridate::ym(PaidDateMonth),
    hbt         = coalesce(HBT, HBT2014),
    gp_practice = GPPractice,
    bnf_code    = BNFItemCode,
    bnf_desc    = BNFItemDescription,
    bnf_prefix  = str_sub(BNFItemCode, 1, 9),
    items       = as.numeric(NumberOfPaidItems),
    quantity    = as.numeric(PaidQuantity),
    cost        = as.numeric(GrossIngredientCost)
  ) |>
  left_join(select(drugs, drug, bnf_prefix), by = "bnf_prefix")

stopifnot("Some rows did not match a drug prefix" = !anyNA(rx$drug))

# Duloxetine 20mg and 40mg are urinary incontinence doses: exclude
rx <- rx |>
  filter(!(drug == "duloxetine" & str_detect(bnf_desc, "(?<![0-9])(20|40) ?MG")))

# Coding check: items per drug and code by year, to catch codes that move over time
code_check <- rx |>
  count(drug, bnf_prefix, year = lubridate::year(month), wt = items, name = "items") |>
  tidyr::pivot_wider(names_from = year, values_from = items, values_fill = 0)
readr::write_csv(code_check, file.path(out_dir, "bnf_code_check.csv"))
message("\nItems per drug and BNF code by year (look for codes appearing or vanishing):")
print(code_check, width = Inf)
stopifnot("Expected one row set per month" = n_distinct(rx$month) == length(files))

# ---- 2. Check the drug names behind each code ---------------------------------------

desc_check <- rx |>
  count(drug, bnf_desc, wt = items, name = "items", sort = TRUE)
readr::write_csv(desc_check, file.path(out_dir, "bnf_descriptions_check.csv"))

message("\nTop products per drug (check these are the right medicines):")
desc_check |>
  group_by(drug) |>
  slice_max(items, n = 4) |>
  ungroup() |>
  print(n = 20)

# ---- 3. GP practice lookup ----------------------------------------------------------

gp_files <- list.files(file.path(raw_dir, "lookups", "gp-practices"), pattern = "\\.csv$", full.names = TRUE)

gp <- map(gp_files, \(f) {
  readr::read_csv(f, col_types = readr::cols(.default = "c"), progress = FALSE) |>
    janitor::clean_names() |>
    rename_with(\(n) "data_zone", .cols = matches("^data_?zone")) |>
    mutate(quarter = lubridate::ymd(str_match(basename(f), "(\\d{8})")[, 2]))
}) |>
  list_rbind() |>
  transmute(practice_code, quarter, hb, data_zone,
            list_size_raw = practice_list_size,
            list_size = suppressWarnings(as.numeric(practice_list_size))) |>
  distinct(practice_code, quarter, .keep_all = TRUE)

bad_sizes <- gp |> filter(is.na(list_size)) |> count(list_size_raw, sort = TRUE)
if (nrow(bad_sizes) > 0) {
  message(sum(bad_sizes$n), " practice-quarters have a non-numeric list size (treated as missing):")
  print(bad_sizes, n = 10)
}
gp <- select(gp, -list_size_raw)

# Health boards: map pre-2019 codes to current codes so each practice has one board
hb_recode <- c(S08000018 = "S08000029", S08000027 = "S08000030",
               S08000021 = "S08000031", S08000023 = "S08000032")
hb_names <- tibble::tribble(
  ~hb,          ~hb_name,
  "S08000015",  "Ayrshire and Arran",
  "S08000016",  "Borders",
  "S08000017",  "Dumfries and Galloway",
  "S08000019",  "Forth Valley",
  "S08000020",  "Grampian",
  "S08000022",  "Highland",
  "S08000024",  "Lothian",
  "S08000025",  "Orkney",
  "S08000026",  "Shetland",
  "S08000028",  "Western Isles",
  "S08000029",  "Fife",
  "S08000030",  "Tayside",
  "S08000031",  "Greater Glasgow and Clyde",
  "S08000032",  "Lanarkshire"
)

simd <- readr::read_csv(file.path(raw_dir, "lookups", "simd2020v2.csv"),
                        col_types = readr::cols(.default = "c")) |>
  transmute(data_zone = DataZone, simd_quintile = as.integer(SIMD2020V2CountryQuintile))

# Each practice gets its most recent board and data zone (current boundaries)
practices <- gp |>
  filter(!is.na(data_zone) | !is.na(hb)) |>
  group_by(practice_code) |>
  slice_max(quarter, n = 1, with_ties = FALSE) |>
  ungroup() |>
  mutate(hb = recode(hb, !!!hb_recode)) |>
  select(practice_code, hb, data_zone) |>
  left_join(simd, by = "data_zone") |>
  left_join(hb_names, by = "hb")

readr::write_csv(practices, file.path(out_dir, "practices_lookup.csv"))

# ---- 4. Registered-population denominators (monthly) -----------------------------
# Each month uses the most recent quarterly list size on or before it.

quarters <- sort(unique(gp$quarter))
month_quarter <- tibble(month = sort(unique(rx$month))) |>
  mutate(quarter = map(month, \(m) max(quarters[quarters <= m])) |> list_c())

denom <- month_quarter |>
  left_join(select(gp, practice_code, quarter, list_size), by = "quarter", relationship = "many-to-many") |>
  left_join(select(practices, practice_code, hb_name, simd_quintile), by = "practice_code")

# ---- 5. Link prescribing to practices -------------------------------------------------

rx <- rx |> left_join(select(practices, practice_code, hb_name, simd_quintile),
                      by = c("gp_practice" = "practice_code"))

match_summary <- rx |>
  summarise(
    items_total   = sum(items),
    pct_with_simd = 100 * sum(items[!is.na(simd_quintile)]) / items_total,
    pct_with_hb   = 100 * sum(items[!is.na(hb_name)]) / items_total
  )
message(sprintf("\nItems linked to a practice SIMD quintile: %.1f%%; to a health board: %.1f%%",
                match_summary$pct_with_simd, match_summary$pct_with_hb))

# ---- 6. Monthly series -------------------------------------------------------------------

rate <- function(df) mutate(df, items_per_1000 = 1000 * items / population)

national <- rx |>
  group_by(month, drug) |>
  summarise(items = sum(items), quantity = sum(quantity), cost = sum(cost), .groups = "drop") |>
  left_join(denom |> group_by(month) |> summarise(population = sum(list_size, na.rm = TRUE)), by = "month") |>
  rate()

by_simd <- rx |>
  filter(!is.na(simd_quintile)) |>
  group_by(month, drug, simd_quintile) |>
  summarise(items = sum(items), quantity = sum(quantity), .groups = "drop") |>
  left_join(denom |> filter(!is.na(simd_quintile)) |>
              group_by(month, simd_quintile) |> summarise(population = sum(list_size, na.rm = TRUE), .groups = "drop"),
            by = c("month", "simd_quintile")) |>
  rate()

by_board <- rx |>
  filter(!is.na(hb_name)) |>
  group_by(month, drug, hb_name) |>
  summarise(items = sum(items), quantity = sum(quantity), .groups = "drop") |>
  left_join(denom |> filter(!is.na(hb_name)) |>
              group_by(month, hb_name) |> summarise(population = sum(list_size, na.rm = TRUE), .groups = "drop"),
            by = c("month", "hb_name")) |>
  rate()

readr::write_csv(national, file.path(out_dir, "rx_national.csv"))
readr::write_csv(by_simd,  file.path(out_dir, "rx_by_simd.csv"))
readr::write_csv(by_board, file.path(out_dir, "rx_by_board.csv"))

message("\nNational items per 1,000 registered patients, first and last month:")
national |>
  filter(month %in% range(month)) |>
  select(month, drug, items, items_per_1000) |>
  print()

message("Saved processed series to ", out_dir)
