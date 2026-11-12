# 01_download.R
# Pull monthly drug-level prescribing from Public Health Scotland's open data
# ("Prescriptions in the Community", by GP practice and BNF item), keeping only
# the medicines we study. Each month is saved to data/raw/drug-level/ so the
# script can be stopped and restarted: months already saved are skipped.
#
# Strategy: ask the PHS API to filter by drug on the server (datastore SQL).
# If that fails for a month, download that month's full CSV to a temp file,
# filter it locally, and delete the temp file, so gigabytes never pile up.

source("analysis/00_packages.R")

# ---- Settings ----------------------------------------------------------------

api        <- "https://www.opendata.nhs.scot/api/3/action/"
dataset_id <- "prescriptions-in-the-community"
first_month <- "201601"   # three years before the April 2019 change
out_dir    <- here::here("data", "raw", "drug-level")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# BNF chemical-substance prefixes (first 9 characters of BNFItemCode).
# Verified against PHS data (Nov 2026). 02_clean.R prints the products found for each.
# Duloxetine needs two codes: in early files generic duloxetine sat under 0704020AA
# and moved to 0403040Y0 over 2016-2018. 02_clean.R drops the 20mg and 40mg
# strengths (urinary incontinence doses).
drugs <- tibble::tribble(
  ~drug,           ~bnf_prefix,  ~role,
  "gabapentin",    "0408010G0",  "reclassified",
  "pregabalin",    "0408010AE",  "reclassified",
  "amitriptyline", "0403010B0",  "possible substitute (not reclassified)",
  "duloxetine",    "0403040Y0",  "possible substitute (not reclassified)",
  "duloxetine",    "0704020AA",  "possible substitute (not reclassified)"
)

# ---- List the monthly files ---------------------------------------------------

pkg <- request(paste0(api, "package_show")) |>
  req_url_query(id = dataset_id) |>
  req_retry(max_tries = 4) |>
  req_perform() |>
  resp_body_json()

resources <- tibble(
  id   = map_chr(pkg$result$resources, \(r) r$id %||% NA_character_),
  name = map_chr(pkg$result$resources, \(r) r$name %||% NA_character_),
  url  = map_chr(pkg$result$resources, \(r) r$url %||% NA_character_)
) |>
  mutate(
    file  = basename(url),
    month = str_match(file, "pitc_?(\\d{6})")[, 2]
  ) |>
  # Keep the GP practice (prescriber) files only. From 2019 PHS also publishes
  # dispenser-location files (disp_pitc...), which we do not want here.
  filter(
    !is.na(month), month >= first_month,
    !str_detect(file, "^disp_"),
    str_detect(name, regex("prescrib", ignore_case = TRUE))
  ) |>
  arrange(month)

dupes <- count(resources, month) |> filter(n > 1)
if (nrow(dupes) > 0) {
  print(filter(resources, month %in% dupes$month) |> select(month, name, file))
  stop("More than one prescriber file for some months; check the list above.")
}

message(nrow(resources), " monthly files from ", min(resources$month), " to ", max(resources$month))

# ---- Fetch one month ----------------------------------------------------------

where_clause <- paste0("\"BNFItemCode\" LIKE '", drugs$bnf_prefix, "%'", collapse = " OR ")

fetch_sql <- function(resource_id, page_size = 30000) {
  pages <- list()
  offset <- 0
  repeat {
    sql <- sprintf('SELECT * FROM "%s" WHERE %s LIMIT %d OFFSET %d',
                   resource_id, where_clause, page_size, offset)
    resp <- request(paste0(api, "datastore_search_sql")) |>
      req_url_query(sql = sql) |>
      req_retry(max_tries = 4) |>
      req_perform() |>
      resp_body_json(simplifyVector = TRUE)
    recs <- resp$result$records
    if (is.null(recs) || NROW(recs) == 0) break
    pages[[length(pages) + 1]] <- mutate(as_tibble(recs), across(everything(), as.character))
    if (NROW(recs) < page_size) break
    offset <- offset + page_size
  }
  bind_rows(pages)
}

fetch_csv <- function(url) {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  request(url) |> req_retry(max_tries = 4) |> req_perform(path = tmp)
  x <- readr::read_csv(tmp, col_types = readr::cols(.default = "c"), progress = FALSE)
  code_col <- grep("^BNFItemCode$", names(x), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(code_col)) stop("No BNFItemCode column in ", url)
  filter(x, str_sub(.data[[code_col]], 1, 9) %in% drugs$bnf_prefix)
}

# ---- Loop over months -----------------------------------------------------------

for (i in seq_len(nrow(resources))) {
  m <- resources$month[i]
  out_file <- file.path(out_dir, paste0("pitc_", m, ".csv"))
  if (file.exists(out_file)) next

  x <- tryCatch(fetch_sql(resources$id[i]), error = function(e) {
    message("  ", m, ": SQL filter failed (", conditionMessage(e), "), downloading full file instead")
    fetch_csv(resources$url[i])
  })

  x <- select(x, -any_of(c("_id", "_full_text")))
  readr::write_csv(x, out_file)
  message(m, ": ", nrow(x), " rows")
  Sys.sleep(0.5)  # be polite to the API
}

readr::write_csv(drugs, here::here("data", "raw", "drug-level", "_drug_list.csv"))
message("Done. Files in ", out_dir)
