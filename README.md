# What changed when the rules changed?

A causal look at gabapentinoid prescribing in Scotland. In April 2019 pregabalin and gabapentin were reclassified as Class C controlled drugs. This project asks whether that changed prescribing in Scotland, and whether it changed it equally across communities.

Entry for The Data Lab Community's Data Visualisation Competition 2026/27 (theme: Scotland's health). Focus area from Scotland's Population Health Framework: **providing equitable access to health and care**, with a secondary link to **building a prevention-focused system**.

> **Status:** prototype. The live page currently runs on simulated data while the analysis is built.

**Live page:** https://asantewaah.github.io/scotland-gabapentinoid-prescribing/

## Approach

- **Design:** interrupted time series (segmented regression with seasonality) on monthly prescribing, with the change at April 2019.
- **Counterfactual:** the pre-2019 trend projected forward with 95% prediction intervals; the effect is observed minus expected.
- **Equity lens:** the same analysis by SIMD quintile and by NHS health board.
- **Robustness:** a control series (a similar medicine that was not reclassified), placebo change dates, and sensitivity to the start window.

## Repository layout

```
analysis/   R: data download, cleaning, ITS models, robustness checks, exports
explore/    Python: exploratory charts while finding the story (not shipped)
images/     Python: static images (social card, thumbnail, fallback PNG)
data/
  raw/        downloaded source files (git-ignored)
  processed/  cleaned intermediate files
site/       the live scrollytelling page (HTML, CSS, D3), deployed to GitHub Pages
  data/       small CSV/JSON files the page reads
```

Languages hand off through files: R and Python write CSV or JSON, and the page reads them. R and Python never call each other.

## Running it locally

**The page**

```bash
python -m http.server 8000 --directory site
# open http://localhost:8000
```

**R analysis**

```r
source("analysis/00_packages.R")   # installs what is missing
```

**Python**

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r explore/requirements.txt
```

## Theme

The page opens in a light editorial theme. The button in the top-right corner switches to a dark theme, and the choice is remembered in the browser. All colours are CSS variables in `site/css/style.css`, so the charts follow the theme.

## Data

Public Health Scotland, *Prescriptions in the Community*, Scottish Health and Social Care Open Data (opendata.nhs.scot). Contains public sector information licensed under the UK Open Government Licence v3.0.

## Key references

- Lopez Bernal, J., Cummins, S. and Gasparrini, A. (2017) Interrupted time series regression for the evaluation of public health interventions: a tutorial. *International Journal of Epidemiology*, 46(1), 348-355. doi:10.1093/ije/dyw098
- Lopez Bernal, J., Cummins, S. and Gasparrini, A. (2018) The use of controls in interrupted time series studies of public health interventions. *International Journal of Epidemiology*, 47(6), 2082-2093. doi:10.1093/ije/dyy135
- The Misuse of Drugs Act 1971 (Amendment) Order 2018 (SI 2018/1356), in force 1 April 2019.

## Author

Juliet Asantewaa Sarpong, PhD student in statistics (causal inference), University of Edinburgh.
