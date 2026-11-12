# Install the R packages used in this project (only those that are missing).

pkgs <- c(
  "tidyverse",  # wrangling and plotting
  "httr2",      # Public Health Scotland open data (CKAN) API
  "jsonlite",   # API responses and JSON exports for the site
  "janitor",    # clean column names across years
  "lubridate",  # dates
  "sandwich",   # Newey-West (HAC) standard errors
  "lmtest",     # coeftest() with robust SEs
  "nlme",       # gls() with AR(1) errors, as an alternative
  "here"        # project-relative paths
)

missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) install.packages(missing)

invisible(lapply(pkgs, library, character.only = TRUE))
message("All packages loaded.")
