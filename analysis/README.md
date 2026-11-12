# Analysis (R)

Planned scripts, run in order. Each step gets its own branch and pull request.

| Script | Does | Writes |
| --- | --- | --- |
| `00_packages.R` | Installs and loads packages | |
| `01_download.R` | Pulls monthly Prescriptions in the Community data for pregabalin, gabapentin and a control medicine | `data/raw/` |
| `02_clean.R` | Harmonises column names across years, aggregates to month by health board and SIMD quintile, adds population denominators | `data/processed/` |
| `03_its.R` | Segmented regression with seasonality; level and slope change at April 2019; counterfactual with 95% prediction intervals | `data/processed/its_results.csv` |
| `04_robustness.R` | Control series, placebo dates, start-window sensitivity, AR(1) and Newey-West comparisons | `data/processed/robustness.csv` |
| `05_export.R` | Small, tidy files for the page | `site/data/*.csv` |

## Model

For month *t* with change at *T0* (April 2019):

```
y_t = b0 + b1*t + b2*post_t + b3*(t - T0)*post_t + seasonal terms + e_t
```

`b2` is the immediate level change and `b3` the change in slope. Standard errors allow for autocorrelation (Newey-West), with an AR(1) model as a check.
