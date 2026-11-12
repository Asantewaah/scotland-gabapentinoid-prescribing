# 01c_lookups.R
# Download the lookups needed to link GP practices to place and deprivation:
#   - GP Practices and List Sizes (quarterly, 2015 onwards): practice code,
#     data zone, health board, registered list size (our population denominator)
#   - SIMD 2020v2 by data zone: deprivation quintile (1 = most deprived)
# Files are small; already-downloaded files are skipped.

source("analysis/00_packages.R")

api     <- "https://www.opendata.nhs.scot/api/3/action/"
out_dir <- here::here("data", "raw", "lookups")
gp_dir  <- file.path(out_dir, "gp-practices")
dir.create(gp_dir, recursive = TRUE, showWarnings = FALSE)

get_pkg <- function(id) {
  request(paste0(api, "package_show")) |>
    req_url_query(id = id) |>
    req_retry(max_tries = 4) |>
    req_perform() |>
    resp_body_json()
}

download_once <- function(url, path) {
  if (!file.exists(path)) {
    request(url) |> req_retry(max_tries = 4) |> req_perform(path = path)
    Sys.sleep(0.3)
  }
  invisible(path)
}

# ---- GP practices and list sizes ---------------------------------------------

gp_pkg <- get_pkg("gp-practice-contact-details-and-list-sizes")
gp_res <- tibble(
  name = map_chr(gp_pkg$result$resources, \(r) r$name %||% NA_character_),
  url  = map_chr(gp_pkg$result$resources, \(r) r$url %||% NA_character_)
) |>
  filter(str_detect(url, "\\.csv$"))

message(nrow(gp_res), " GP practice files")
walk(gp_res$url, \(u) download_once(u, file.path(gp_dir, basename(u))))

# ---- SIMD 2020v2 --------------------------------------------------------------

simd_pkg <- get_pkg("scottish-index-of-multiple-deprivation")
simd_res <- keep(simd_pkg$result$resources, \(r) identical(r$name, "SIMD 2020v2"))
stopifnot("SIMD 2020v2 resource not found" = length(simd_res) == 1)
download_once(simd_res[[1]]$url, file.path(out_dir, "simd2020v2.csv"))

message("Lookups saved to ", out_dir)
