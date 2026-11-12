# Analysis (R)

Two datasets, each with its own job:

- **Competition file** (required): dispensing by pharmacy and BNF chapter, Jan 2019 to May 2026. Sets the scene: nervous system (Chapter 4) prescribing by place and deprivation.
- **PHS drug-level open data** ("other publicly available data"): Prescriptions in the Community by GP practice and BNF item, from 2016. Carries the causal analysis of pregabalin and gabapentin around April 2019.

Scripts run in order. Each step gets its own branch and pull request.

| Script | Does | Writes |
| --- | --- | --- |
| `00_packages.R` | Installs and loads packages | |
| `01_download.R` | Pulls monthly drug-level data for gabapentin, pregabalin and comparison medicines, filtered on the server where possible; resumable | `data/raw/drug-level/` |
| `01b_competition_file.R` | Reads the three competition files; Chapter 4 share by health board and HSCP; pharmacy postcodes | `data/processed/competition_*.csv` |
| `02_clean.R` | Harmonises columns across years, checks BNF descriptions, aggregates by month, health board and SIMD quintile, adds population denominators | `data/processed/` |
| `03_its.R` | Segmented regression with seasonality; level and slope change at April 2019; counterfactual with 95% prediction intervals | `data/processed/its_results.csv` |
| `04_robustness.R` | Control series, placebo dates, start-window sensitivity, AR(1) and Newey-West comparisons | `data/processed/robustness.csv` |
| `05_export.R` | Small, tidy files for the page | `site/data/*.csv` |

## Before running

1. Copy the competition CSVs into `data/raw/competition/`.
2. `source("analysis/00_packages.R")`
3. `source("analysis/01_download.R")` (can take a while; safe to stop and restart)
4. `source("analysis/01b_competition_file.R")`

## Model

For month *t* with change at *T0* (April 2019):

```
y_t = b0 + b1*t + b2*post_t + b3*(t - T0)*post_t + seasonal terms + e_t
```

`b2` is the immediate level change and `b3` the change in slope. Standard errors allow for autocorrelation (Newey-West), with an AR(1) model as a check.

## Comparison medicines

Amitriptyline and duloxetine were not reclassified and are also used for nerve pain. They serve two purposes: a check for substitution (did prescribers switch to them?) and a comparison series. Because they may be substitutes, they are not a clean negative control; choosing one is part of `04_robustness.R`.
