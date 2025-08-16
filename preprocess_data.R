library(dplyr)
library(haven)
library(sf)
library(giscoR)
library(forcats)

# 1. Read raw ESS data and filter for Hungary
ess_data <- read_sav("data/raw_data/ESS9e03_1.sav") %>%
  filter(cntry == "HU")

# 2. Convert labelled region to character
ess_data$region <- as_factor(ess_data$region)

# 3. Select and rename variables
df_sel <- ess_data %>%
  transmute(
    region       = as.character(region),
    ppltrst,
    happy,
    eduyrs,
    sclact,
    polintr_rev = 5 - polintr,
    health_rev  = 6 - health
  )

# 3b. Harmonize region names to match NUTS3$NUTS_NAME
region_map <- c(
  "Borsod-Abauj-Zemplen" = "Borsod-Abaúj-Zemplén",
  "Fejer"                = "Fejér",
  "Gyor-Moson-Sopron"    = "Győr-Moson-Sopron",
  "Hajdu-Bihar"          = "Hajdú-Bihar",
  "Jasz-Nagykun-Szolnok" = "Jász-Nagykun-Szolnok",
  "Komarom-Esztergom"    = "Komárom-Esztergom",
  "Nograd"               = "Nógrád",
  "Veszprem"             = "Veszprém"
)

df_sel <- df_sel %>%
  mutate(region = ifelse(region %in% names(region_map),
                         region_map[region],
                         region))

# 4. Save processed individual-level data
saveRDS(df_sel, file = "data/df_sel.Rds")

# 5. Load NUTS3 geometries and reproject
nuts3 <- gisco_get_nuts(
  nuts_level = 3,
  year       = 2016,
  resolution = "20",
  country    = "Hungary"
) %>%
  st_transform(4326)

# 6. Save spatial data
saveRDS(nuts3, file = "data/nuts3.Rds")

# 7. Calculate regional averages
regional_avg <- df_sel %>%
  group_by(region) %>%
  summarise(
    ppltrst_avg   = mean(ppltrst, na.rm = TRUE),
    happy_avg     = mean(happy, na.rm = TRUE),
    eduyrs_avg    = mean(eduyrs, na.rm = TRUE),
    sclact_avg    = mean(sclact, na.rm = TRUE),
    polintr_rev_avg = mean(polintr_rev, na.rm = TRUE),
    health_rev_avg  = mean(health_rev, na.rm = TRUE)
  )



cat("Data preprocessing completed successfully!\n")
cat("Files saved:\n")
cat("- data/df_sel.Rds (individual-level data)\n")
cat("- data/nuts3.Rds (spatial geometries only)\n")



